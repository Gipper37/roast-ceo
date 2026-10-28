-- A merge may not read another tenant, nor leave a phantom behind.
--
-- 20261028000007 shipped the consumable merge to STAGING ONLY. An adversarial
-- review of it before it reached production found five real defects, three of
-- which three independent reviewers reported separately. It is applied on
-- staging, so it is not edited: this corrects it.
--
-- ── 1. 🔴 CROSS-TENANT READ (the serious one) ────────────────────────────
--
-- merge_consumables_preview is SECURITY DEFINER, owned by a BYPASSRLS role, so
-- RLS does not apply inside it. It loaded BOTH rows and then checked only
-- p_keep's company. A tenant admin holding inventory.merge could pass any
-- consumable id belonging to ANOTHER roastery as p_kill and read back its name,
-- its on-hand quantity, the name of its supplier and five row counts. Returning
-- "same_company: false" in the same payload does not help; the values are
-- already in it. merge_consumables had the company-equality refusal; the
-- preview did not, and the preview is the one reachable with a single call.
--
-- Both functions now LOOK THE DUPLICATE UP WITHIN THE SURVIVOR'S COMPANY, so a
-- foreign row is never loaded at all. A comparison made afterwards would have
-- been one edit away from being lost again.
--
-- The two "does not exist" raises also fired BEFORE the permission check, which
-- answered "is this id real?" for any id in any tenant. The gate comes first now
-- and the message does not distinguish absent from somebody else's.
--
-- ── 2. No row lock, so two merges could point at each other ──────────────
--
-- The already-merged guards tested a plain SELECT's snapshot. Under READ
-- COMMITTED, A-into-B and B-into-A running together both passed, and the two
-- tombstone updates touch different rows so neither blocked the other. Both
-- rows are taken FOR UPDATE now.
--
-- ── 3. The retired row kept a phantom quantity ───────────────────────────
--
-- Its receipts and usage move to the survivor, but in_stock is derived from its
-- own count anchor, which did not move. So the duplicate went on reading as a
-- quantity nobody has -- the phantom half of the split count this feature
-- exists to end. It is now recorded as a real dated count of ZERO, through
-- consumable_inventory_history because guard_consumable_inventory_baseline
-- refuses a direct edit, with a note saying where its stock went.
--
-- 🔴 And updated_at is named in the tombstone UPDATE on purpose:
-- update_consumable_metrics is BEFORE UPDATE OF (..., updated_at), and
-- "UPDATE OF" fires on the columns in the SET list, not on what another trigger
-- assigns. Without it the recompute never ran.
--
-- ── 4. Restoring a merged-away row resurrected the duplicate ─────────────
--
-- Archive/Restore is a plain is_active flip and knew nothing about the
-- tombstone, so Restore put the duplicate back into every picker while its
-- references still pointed at the survivor -- the split count, recreated by a
-- button that looks harmless. Refused below, in the database, so no caller can
-- miss it.

begin;

CREATE OR REPLACE FUNCTION public.merge_consumables_preview(p_keep text, p_kill text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_keep public.consumable_inventory%rowtype;
  v_kill public.consumable_inventory%rowtype;
  v_products int; v_bom int; v_bom_folded int; v_purchases int; v_staged int; v_history int;
begin
  select * into v_keep from public.consumable_inventory where consumable_inventory_id = p_keep;

  -- 🔴 THE CALLER'S COMPANY DECIDES WHAT CAN EVEN BE LOADED.
  --
  -- This is SECURITY DEFINER, owned by a BYPASSRLS role, so RLS does not apply
  -- inside it: whatever this function selects, it gets. The first version
  -- loaded BOTH rows and then checked only p_keep's company, so a tenant admin
  -- holding inventory.merge could pass any consumable id from ANOTHER tenant as
  -- p_kill and read back its name, its on-hand quantity, its supplier's name
  -- and five row counts. RLS would have refused every one of those reads.
  --
  -- Fixed by SCOPING THE QUERY rather than adding a comparison afterwards: the
  -- duplicate is looked up WITHIN the surviving row's company, so a foreign row
  -- is never loaded and there is nothing to leak by accident later.
  --
  -- 🔴 And the auth gate comes BEFORE any "does not exist", because those two
  -- raises told the caller whether an arbitrary id existed in any tenant.
  if v_keep.company_id is null
     or v_keep.company_id not in (select auth_company_ids())
     or not public.auth_has_permission('inventory.merge', v_keep.company_id) then
    raise exception 'You do not have permission to merge stock items.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_kill from public.consumable_inventory
   where consumable_inventory_id = p_kill
     and company_id = v_keep.company_id;
  if not found then
    raise exception 'That stock item is not one of yours.' using errcode = 'no_data_found';
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
end $function$;

CREATE OR REPLACE FUNCTION public.merge_consumables(p_keep text, p_kill text, p_count numeric DEFAULT NULL::numeric, p_counted_on date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- 🔴 LOCKED, not merely read. The already-merged guards below test whatever
  -- this select saw, and under READ COMMITTED two operators merging A into B
  -- and B into A at the same moment both passed them: the two tombstone
  -- updates touch different rows, so neither ever blocked the other, and the
  -- pair ended up pointing at each other. Taking the row locks here makes the
  -- second call wait and then fail its guard honestly.
  select * into v_keep from public.consumable_inventory
   where consumable_inventory_id = p_keep for update;

  -- 🔴 THE CALLER'S COMPANY DECIDES WHAT CAN EVEN BE LOADED.
  --
  -- This is SECURITY DEFINER, owned by a BYPASSRLS role, so RLS does not apply
  -- inside it: whatever this function selects, it gets. The first version
  -- loaded BOTH rows and then checked only p_keep's company, so a tenant admin
  -- holding inventory.merge could pass any consumable id from ANOTHER tenant as
  -- p_kill and read back its name, its on-hand quantity, its supplier's name
  -- and five row counts. RLS would have refused every one of those reads.
  --
  -- Fixed by SCOPING THE QUERY rather than adding a comparison afterwards: the
  -- duplicate is looked up WITHIN the surviving row's company, so a foreign row
  -- is never loaded and there is nothing to leak by accident later.
  --
  -- 🔴 And the auth gate comes BEFORE any "does not exist", because those two
  -- raises told the caller whether an arbitrary id existed in any tenant.
  if v_keep.company_id is null
     or v_keep.company_id not in (select auth_company_ids())
     or not public.auth_has_permission('inventory.merge', v_keep.company_id) then
    raise exception 'You do not have permission to merge stock items.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Scoped to the caller's company, same reason as the preview.
  select * into v_kill from public.consumable_inventory
   where consumable_inventory_id = p_kill
     and company_id = v_keep.company_id for update;
  if not found then
    raise exception 'That stock item is not one of yours.' using errcode = 'no_data_found';
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
         is_active = false,
         -- 🔴 updated_at IS LOAD-BEARING. update_consumable_metrics is a
         -- BEFORE UPDATE OF (..., updated_at) trigger, and "UPDATE OF" fires on
         -- the columns in the SET list, not on what another trigger assigns.
         -- Without naming one of its columns here the duplicate kept the
         -- in_stock it had before its receipts moved away.
         updated_at = now()
   where consumable_inventory_id = p_kill;

  -- 🔴 AND THE DUPLICATE NOW HOLDS NOTHING, so it must say so. Its receipts and
  -- its usage have moved to the survivor, but its own count ANCHOR is still
  -- whatever it was last counted at, and in_stock is derived from that anchor.
  -- Left alone the retired row reads as a quantity nobody has -- the phantom
  -- half of the split count this whole feature exists to end.
  -- Recorded as a real dated count of zero, through the only door
  -- guard_consumable_inventory_baseline leaves open, with a note saying why.
  insert into public.consumable_inventory_history
    (history_id, consumable_id, facility_id, company_id, inventory_date, inventory_count, notes)
  values (gen_random_uuid()::text, p_kill, v_kill.facility_id, v_kill.company_id,
          current_date, 0,
          'Merged into ' || v_keep.consumable_inventory_item || '; everything it held moved there');

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
end $function$;

-- ── 4. The guard ─────────────────────────────────────────────────────────
create or replace function public.guard_restoring_a_merged_consumable()
returns trigger language plpgsql as $fn$
begin
  if new.is_active and not coalesce(old.is_active, false)
     and new.canonical_consumable_id is distinct from new.consumable_inventory_id then
    raise exception
      'That item was merged into "%". Restoring it would put the duplicate back while everything it was used by still points at the other item. Merge is not undone by restoring.',
      coalesce((select c.consumable_inventory_item from public.consumable_inventory c
                 where c.consumable_inventory_id = new.canonical_consumable_id),
               'another item')
      using errcode = 'check_violation';
  end if;
  return new;
end $fn$;

drop trigger if exists aab_guard_restoring_a_merged_consumable on public.consumable_inventory;
create trigger aab_guard_restoring_a_merged_consumable
  before update of is_active on public.consumable_inventory
  for each row execute function public.guard_restoring_a_merged_consumable();

do $$
declare
  n_scoped int; n_locked int; n_zero int; n_guard int;
begin
  -- Each assertion names the defect it is standing in for, so re-introducing
  -- one fails here rather than in production.
  select count(*) into n_scoped from pg_proc
   where pronamespace='public'::regnamespace
     and proname in ('merge_consumables','merge_consumables_preview')
     and prosrc like '%and company_id = v_keep.company_id%';
  if n_scoped <> 2 then
    raise exception 'the duplicate is not looked up within the survivor''s company in both functions (%)', n_scoped;
  end if;

  select count(*) into n_locked from pg_proc
   where pronamespace='public'::regnamespace and proname='merge_consumables'
     and prosrc like '%for update%';
  if n_locked <> 1 then raise exception 'merge_consumables does not lock the rows it checks'; end if;

  select count(*) into n_zero from pg_proc
   where pronamespace='public'::regnamespace and proname='merge_consumables'
     and prosrc like '%everything it held moved there%';
  if n_zero <> 1 then raise exception 'the retired row is not counted to zero'; end if;

  select count(*) into n_guard from pg_trigger
   where tgrelid='public.consumable_inventory'::regclass
     and tgname='aab_guard_restoring_a_merged_consumable';
  if n_guard <> 1 then raise exception 'the restore guard is not installed'; end if;

  -- 🔴 Shape, not rows: staging holds no merged consumable and an assertion
  -- only production could satisfy would break the rehearsal.
  raise notice 'the merge is tenant-scoped, locked, leaves no phantom, and cannot be undone by Restore';
end $$;

commit;
