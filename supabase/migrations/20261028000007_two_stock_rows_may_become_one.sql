-- Two stock rows may become one.
--
-- ── Why ──────────────────────────────────────────────────────────────────
--
-- Products can be merged. Stock rows cannot, and nothing could ever combine
-- them, so a duplicate consumable SPLITS THE COUNT for good. addConsumable's
-- own comment says what that costs: "8oz Gold Bag read 1,000 on one row and
-- 1,000 on the other, and neither was the shelf." MCR carries at least two
-- duplicate pairs today -- two 1.5-gallon filter rows and two 12-cup rows,
-- each a QuickBooks import beside the real one.
--
-- Creation-time duplicate detection already exists (findSimilarByName, advise
-- then confirm). This is the cure for the ones that got through.
--
-- ── What moves, and what deliberately does not ───────────────────────────
--
-- FIVE tables hold a consumable id, and 🔴 TWO OF THEM HAVE NO FOREIGN KEY, so
-- nothing in the database would ever catch a merge that forgot them:
--
--   products.source_consumable_id                      FK    MOVES
--   product_consumables.consumable_id                  FK    MOVES (folded)
--   consumable_inventory_purchased.consumable_...item  FK    MOVES
--   staged_line_items.consumable_id                    none  MOVES
--   consumable_inventory_history.consumable_id         none  STAYS
--
-- History STAYS on purpose. A count row is a dated statement about ONE shelf
-- location on one day; moving it would invent a history the survivor never
-- had. It is reached through the tombstone instead.
--
-- Receipts MOVE, and that is the difference from merge_product_groups. That
-- one cannot move an order line, because a posted line is immutable and
-- remapping it silently reprices an issued invoice. A receipt carries no such
-- guard, and moving it is what a merge MEANS: the stock arrived once, under
-- two names.
--
-- 🔴 BOM LINES ARE FOLDED, NOT JUST REPOINTED, AND THE FOLD IS MANDATORY.
-- product_consumables carries a unique INDEX on
-- (product_id, consumable_id, per_case) NULLS NOT DISTINCT --
-- `uq_product_consumables_item_basis`, an index and not a constraint, which is
-- why a query over pg_constraint does not see it. So a product drawing on BOTH
-- rows does not quietly end up with two lines: the repoint VIOLATES that index
-- and the whole merge aborts. Quantities are therefore summed within the same
-- per_case sense and the losing line removed BEFORE anything is repointed.
-- Tested on staging with real rows: a per-bag 1 and a per-bag 2 become one
-- line of 3, while a per-case line moves across on its own, because "one per
-- bag" and "one per case" are different statements and must not be added.
--
-- ── The count ────────────────────────────────────────────────────────────
--
-- Each row has its own physical count on its own date, and two counts taken on
-- different days are not additive -- adding them is how "neither was the
-- shelf" happens. So the merge takes an OPTIONAL fresh count, which is the only
-- honest number for a shelf that has just stopped being two shelves. Given, it
-- is written as a real count; omitted, the survivor keeps its own anchor and
-- the preview states what the stock will then read.
--
-- 🔴 A count cannot be written to consumable_inventory directly --
-- guard_consumable_inventory_baseline refuses it outright. The only way in is
-- an INSERT into consumable_inventory_history, whose trigger carries the value
-- onto the parent. That guard is why every consumable count in the app was
-- broken once already.
--
-- ── SECURITY DEFINER, unlike the product merge ───────────────────────────
--
-- This repoints rows in five tables whose RLS policies gate on different
-- permission keys (product.edit, inventory.edit, inventory.purchase). A
-- merge-capable operator may hold none of them, and 🔴 RLS refuses by returning
-- ZERO ROWS rather than an error, so an invoker-rights version would report a
-- clean merge having moved nothing. The function authorises itself instead:
-- one key, checked once, against a company the caller actually belongs to.

begin;

-- ── 1. The tombstone ─────────────────────────────────────────────────────
-- Mirrors products.canonical_product_id, which is the documented convention
-- here ("Its own id until merged"); merge_into_id is the older undocumented
-- one and is not copied.
alter table public.consumable_inventory
  add column if not exists canonical_consumable_id text
    references public.consumable_inventory(consumable_inventory_id);

comment on column public.consumable_inventory.canonical_consumable_id is
  'The stock row this one ROLLS UP to. Its own id until merged. A row whose '
  'canonical id is not itself has been merged away: its references have moved '
  'to the survivor and only its count history stays behind.';

update public.consumable_inventory
   set canonical_consumable_id = consumable_inventory_id
 where canonical_consumable_id is null;

create index if not exists consumable_inventory_canonical_idx
  on public.consumable_inventory (canonical_consumable_id)
  where canonical_consumable_id is distinct from consumable_inventory_id;

-- New rows answer the invariant themselves, so no reader has to write
-- coalesce(canonical, own) and no insert can forget.
create or replace function public.default_canonical_consumable()
returns trigger language plpgsql as $fn$
begin
  if new.canonical_consumable_id is null then
    new.canonical_consumable_id := new.consumable_inventory_id;
  end if;
  return new;
end $fn$;

drop trigger if exists aaa_default_canonical_consumable on public.consumable_inventory;
create trigger aaa_default_canonical_consumable
  before insert on public.consumable_inventory
  for each row execute function public.default_canonical_consumable();

-- ── 2. The permission ────────────────────────────────────────────────────
-- Shaped on inventory.archive, the closest existing act: the same three roles,
-- the same plans, slotted between archive (40) and purchase (50).
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values ('inventory.merge', 'Inventory', 'Merge inventory items',
        'Combine two duplicate stock items into one. Moves what the duplicate was used by and leaves its count history behind.',
        true, 45)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin', 'inventory.merge', true),
       ('facility_admin', 'inventory.merge', true),
       ('manager', 'inventory.merge', true),
       ('roastmaster', 'inventory.merge', false)
on conflict (role_id, permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
values ('enterprise', 'inventory.merge', true),
       ('enterprise_plus', 'inventory.merge', true),
       ('pro', 'inventory.merge', true),
       ('starter', 'inventory.merge', false)
on conflict (plan_id, permission_id) do nothing;


-- ── 3. What the merge would do, said before it does it ───────────────────
create or replace function public.merge_consumables_preview(p_keep text, p_kill text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_keep public.consumable_inventory%rowtype;
  v_kill public.consumable_inventory%rowtype;
  v_products int; v_bom int; v_bom_folded int; v_purchases int; v_staged int; v_history int;
begin
  select * into v_keep from public.consumable_inventory where consumable_inventory_id = p_keep;
  if not found then raise exception 'the surviving stock item does not exist'; end if;
  select * into v_kill from public.consumable_inventory where consumable_inventory_id = p_kill;
  if not found then raise exception 'the duplicate stock item does not exist'; end if;

  -- Read-only, but it reports another tenant's purchase volume if left open,
  -- so it is gated with the same key as the merge itself.
  if v_keep.company_id not in (select auth_company_ids())
     or not public.auth_has_permission('inventory.merge', v_keep.company_id) then
    raise exception 'You do not have permission to merge stock items.'
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_products from public.products
   where source_consumable_id = p_kill;

  select count(*) into v_bom from public.product_consumables where consumable_id = p_kill;

  -- The ones that would land on a product ALREADY drawing on the survivor, in
  -- the same per_case sense. These are summed into that line rather than added
  -- beside it; see the header.
  select count(*) into v_bom_folded
    from public.product_consumables d
   where d.consumable_id = p_kill
     and exists (select 1 from public.product_consumables k
                  where k.product_id = d.product_id
                    and k.consumable_id = p_keep
                    and coalesce(k.per_case, false) = coalesce(d.per_case, false));

  select count(*) into v_purchases from public.consumable_inventory_purchased
   where consumable_inventory_item = p_kill;

  select count(*) into v_staged from public.staged_line_items where consumable_id = p_kill;
  select count(*) into v_history from public.consumable_inventory_history where consumable_id = p_kill;

  return jsonb_build_object(
    'keeping', v_keep.consumable_inventory_item,
    'retiring', v_kill.consumable_inventory_item,
    'keeping_stock', v_keep.in_stock,
    'retiring_stock', v_kill.in_stock,
    'keeping_counted_on', v_keep.last_inventory_date,
    'retiring_counted_on', v_kill.last_inventory_date,
    'keeping_supplier', (select s.supplier from public.supplier s where s.supplier_id = v_keep.supplier_id),
    'retiring_supplier', (select s.supplier from public.supplier s where s.supplier_id = v_kill.supplier_id),
    'products_moved', v_products,
    'bom_lines_moved', v_bom,
    'bom_lines_folded', v_bom_folded,
    'purchases_moved', v_purchases,
    'staged_lines_moved', v_staged,
    'count_history_left_behind', v_history,
    'already_merged', (v_kill.canonical_consumable_id is distinct from v_kill.consumable_inventory_id),
    'same_company', (v_keep.company_id = v_kill.company_id),
    'same_facility', (v_keep.facility_id is not distinct from v_kill.facility_id));
end $fn$;

-- ── 4. The merge ─────────────────────────────────────────────────────────
create or replace function public.merge_consumables(
  p_keep text,
  p_kill text,
  p_count numeric default null,
  p_counted_on date default null,
  p_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_keep public.consumable_inventory%rowtype;
  v_kill public.consumable_inventory%rowtype;
  v_products int := 0; v_bom int := 0; v_folded int := 0;
  v_purchases int := 0; v_staged int := 0;
begin
  if p_keep is null or p_kill is null then
    raise exception 'a merge needs two stock items';
  end if;
  if p_keep = p_kill then
    raise exception 'a stock item cannot be merged into itself';
  end if;

  select * into v_keep from public.consumable_inventory where consumable_inventory_id = p_keep;
  if not found then raise exception 'the surviving stock item does not exist'; end if;
  select * into v_kill from public.consumable_inventory where consumable_inventory_id = p_kill;
  if not found then raise exception 'the duplicate stock item does not exist'; end if;

  if v_keep.company_id is distinct from v_kill.company_id then
    raise exception 'refusing to merge stock items from different companies';
  end if;

  -- 🔴 SECURITY DEFINER: the caller's own membership is checked here, because
  -- nothing else will. A permission key alone would let a member of company A
  -- name two rows in company B.
  if v_keep.company_id not in (select auth_company_ids())
     or not public.auth_has_permission('inventory.merge', v_keep.company_id) then
    raise exception 'You do not have permission to merge stock items.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_kill.canonical_consumable_id is distinct from v_kill.consumable_inventory_id then
    raise exception '"%" has already been merged away.', v_kill.consumable_inventory_item;
  end if;
  if v_keep.canonical_consumable_id is distinct from v_keep.consumable_inventory_id then
    raise exception '"%" was itself merged away. Merge into the item it rolls up to instead.',
      v_keep.consumable_inventory_item;
  end if;

  -- Two facilities count two different shelves. Combining them would claim one
  -- building holds what two of them hold.
  if v_keep.facility_id is distinct from v_kill.facility_id then
    raise exception 'Those stock items are counted at different facilities, so they are not the same shelf.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- What the duplicate is sold as.
  update public.products set source_consumable_id = p_keep where source_consumable_id = p_kill;
  get diagnostics v_products = row_count;

  -- 🔴 FOLD FIRST, THEN REPOINT. A product drawing on both rows would otherwise
  -- end up with two lines naming one item and deduct twice on every sale.
  -- Folded within the same per_case sense: "one per bag" and "one per case"
  -- are different statements and must not be added together.
  -- 🔴 FOLD BEFORE REPOINT, or the repoint below violates
  -- uq_product_consumables_item_basis and the merge dies on a constraint the
  -- operator cannot read. Aggregated and matched by lateral rather than a
  -- plain UPDATE ... FROM so the arithmetic stays correct and the surviving
  -- line is chosen deterministically; the index means one group per
  -- (product, per_case) today, and the sum is then simply that group.
  with addends as (
    select d.product_id,
           coalesce(d.per_case, false) as per_case,
           sum(coalesce(d.quantity, 0)) as qty,
           array_agg(d.product_consumable_id) as kill_ids
      from public.product_consumables d
     where d.consumable_id = p_kill
     group by 1, 2
  ),
  matched as (
    select a.product_id, a.qty, a.kill_ids, k.product_consumable_id as keep_id
      from addends a
      join lateral (
        select k2.product_consumable_id
          from public.product_consumables k2
         where k2.product_id = a.product_id
           and k2.consumable_id = p_keep
           and coalesce(k2.per_case, false) = a.per_case
         order by k2.product_consumable_id
         limit 1
      ) k on true
  ),
  bumped as (
    update public.product_consumables k
       set quantity = coalesce(k.quantity, 0) + m.qty
      from matched m
     where k.product_consumable_id = m.keep_id
    returning 1
  )
  delete from public.product_consumables x
   where x.product_consumable_id in (select unnest(m.kill_ids) from matched m);
  get diagnostics v_folded = row_count;

  update public.product_consumables set consumable_id = p_keep where consumable_id = p_kill;
  get diagnostics v_bom = row_count;

  -- The stock that physically arrived, under whichever name.
  update public.consumable_inventory_purchased
     set consumable_inventory_item = p_keep
   where consumable_inventory_item = p_kill;
  get diagnostics v_purchases = row_count;

  -- No FK on this one, so nothing would have caught it.
  update public.staged_line_items set consumable_id = p_keep where consumable_id = p_kill;
  get diagnostics v_staged = row_count;

  -- consumable_inventory_history is deliberately NOT moved: see the header.

  update public.consumable_inventory
     set canonical_consumable_id = p_keep,
         is_active = false
   where consumable_inventory_id = p_kill;

  -- A fresh count, when the operator has one. 🔴 Written as a HISTORY row
  -- because guard_consumable_inventory_baseline refuses a direct edit to
  -- inventory_count / last_inventory_date; its trigger carries it to the parent.
  if p_count is not null then
    insert into public.consumable_inventory_history
      (history_id, consumable_id, facility_id, company_id, inventory_date, inventory_count, notes)
    values (gen_random_uuid()::text, p_keep, v_keep.facility_id, v_keep.company_id,
            coalesce(p_counted_on, current_date), p_count,
            coalesce(p_notes, 'Counted when ' || v_kill.consumable_inventory_item || ' was merged in'));
  end if;

  return jsonb_build_object(
    'keeping', v_keep.consumable_inventory_item,
    'retiring', v_kill.consumable_inventory_item,
    'products_moved', v_products,
    'bom_lines_moved', v_bom,
    'bom_lines_folded', v_folded,
    'purchases_moved', v_purchases,
    'staged_lines_moved', v_staged,
    'counted', (p_count is not null));
end $fn$;

revoke all on function public.merge_consumables_preview(text, text) from public;
revoke all on function public.merge_consumables(text, text, numeric, date, text) from public;
grant execute on function public.merge_consumables_preview(text, text) to authenticated;
grant execute on function public.merge_consumables(text, text, numeric, date, text) to authenticated;

do $$
declare
  n_col int; n_fn int; n_perm int; n_role int; n_plan int; ok_auth bool; n_untagged int;
begin
  select count(*) into n_col from information_schema.columns
   where table_schema='public' and table_name='consumable_inventory' and column_name='canonical_consumable_id';
  if n_col <> 1 then raise exception 'canonical_consumable_id was not added'; end if;

  select count(*) into n_untagged from public.consumable_inventory where canonical_consumable_id is null;
  if n_untagged > 0 then raise exception '% stock rows still have no canonical id', n_untagged; end if;

  select count(*) into n_fn from pg_proc
   where pronamespace='public'::regnamespace and proname in ('merge_consumables','merge_consumables_preview');
  if n_fn <> 2 then raise exception 'expected both merge functions, found %', n_fn; end if;

  ok_auth := has_function_privilege('authenticated',
    'public.merge_consumables(text, text, numeric, date, text)', 'execute');
  if not ok_auth then raise exception 'authenticated cannot execute merge_consumables'; end if;

  select count(*) into n_perm from public.permissions where permission_id='inventory.merge';
  select count(*) into n_role from public.role_permissions where permission_id='inventory.merge';
  select count(*) into n_plan from public.plan_permissions where permission_id='inventory.merge';
  if n_perm <> 1 or n_role < 4 or n_plan < 4 then
    raise exception 'inventory.merge did not ship its roles and plans (perm %, roles %, plans %)',
      n_perm, n_role, n_plan;
  end if;

  -- 🔴 Shape only. Staging holds neither of MCR's duplicate pairs, and an
  -- assertion only production could satisfy would break the rehearsal.
  raise notice 'merge_consumables is in place with inventory.merge and its roles and plans';
end $$;

commit;
