-- A merge is an admin act, and the key has to be the thing that says so.
--
-- WHAT WAS WRONG. 20260924000006 gated the product merge in the Next.js server
-- action and nowhere else. Verified on staging:
--
--     proacl = {postgres=X/postgres, authenticated=X/postgres, service_role=X/postgres}
--     has_function_privilege('authenticated','merge_product_groups(...)','EXECUTE') = t
--
-- The `revoke all ... from public, anon` in that migration revoked nothing that
-- mattered: Supabase's default ACL grants EXECUTE to `authenticated` by name, not
-- through PUBLIC. And the RLS on products, product_groups and product_merge_log is
-- tenant-scoped with no permission key in it. So every signed-in member of a tenant
-- — staff, sales_person, accounting_view, eight roles that do not hold the key —
-- could irreversibly retire any product with one POST to
-- /rest/v1/rpc/merge_product_groups, and then DELETE the product_merge_log row
-- proving they had. That is the identical hole 20260924000002 deleted the old
-- merge_products() for, rebuilt three migrations later.
--
-- customer.merge is the same story, older. It has existed as a key since the CRM
-- shipped and is enforced in ZERO places — no action, no RPC, no policy, no screen
-- reads it. The merge fires from an UPDATE of customers.merge_into_id, so one PATCH
-- to /rest/v1/customers merged two customers and MOVED their orders and
-- order_details. That one rewrites history rather than tombstoning it.
--
-- Owner's calls this session: product.merge goes to company_admin, facility_admin
-- and manager; it becomes plan-gated and is granted on all four plans; and
-- customer.merge is brought to the same three roles (it held five —
-- accounting_admin and sales_person lose it).
--
-- Every function body here was taken from pg_get_functiondef() on the live
-- database and patched in place. Nothing was retyped: rebuilding a body from
-- memory is what broke roast saving for two days this week.

begin;

-- ── The catalogue ───────────────────────────────────────────────────────
-- sort_order was omitted, so 'Merge products' defaulted to 0 and sorted ABOVE
-- 'View products' (10) in the one screen an admin opens to answer who can merge.
-- 45 puts it after 'Archive products' (40) and before 'View recipes' (50).
update public.permissions
   set is_plan_gated = true,
       sort_order    = 45
 where permission_id = 'product.merge';

-- Plan-gated now, so the rows have to exist or the key resolves to denied for
-- every plan. Granted on all four: consolidating your own duplicate catalogue is
-- not an upsell. The flag is the lever, not the restriction.
insert into public.plan_permissions (plan_id, permission_id, granted)
select p, 'product.merge', true
  from unnest(array['starter','pro','enterprise','enterprise_plus']) as p
on conflict (plan_id, permission_id) do update set granted = excluded.granted;

update public.permissions
   set is_plan_gated = true
 where permission_id = 'customer.merge';

insert into public.plan_permissions (plan_id, permission_id, granted)
select p, 'customer.merge', true
  from unnest(array['starter','pro','enterprise','enterprise_plus']) as p
on conflict (plan_id, permission_id) do update set granted = excluded.granted;

-- The three roles, for both merges. Written as grant-then-revoke rather than a
-- delete so the rows keep their history and the intent is legible in the table.
insert into public.role_permissions (role_id, permission_id, granted)
select r, k, true
  from unnest(array['company_admin','facility_admin','manager']) as r
 cross join unnest(array['product.merge','customer.merge']) as k
on conflict (role_id, permission_id) do update set granted = excluded.granted;

update public.role_permissions
   set granted = false
 where permission_id in ('product.merge','customer.merge')
   and role_id not in ('company_admin','facility_admin','manager');

-- ── An audit trail the audited party cannot edit ────────────────────────
-- product_merge_log shipped with one `for all` policy, and 20260924000002 issued
-- no revoke, so Supabase's default ACL left every signed-in user with UPDATE and
-- DELETE on it. A staff account that cannot merge could still erase the record
-- that a merge happened. config_audit_log is the house precedent: readable by the
-- tenant, written only by the function, editable by nobody.
drop policy if exists product_merge_log_tenant on public.product_merge_log;

create policy product_merge_log_select_own_company on public.product_merge_log
  for select to authenticated using (
    company_id is not null and company_id in (select public.auth_company_ids())
  );

-- The merge functions are security invoker, so the insert happens as the caller
-- and still needs a policy — but only an insert, and only into their own tenant.
create policy product_merge_log_insert_own_company on public.product_merge_log
  for insert to authenticated with check (
    company_id is not null and company_id in (select public.auth_company_ids())
  );

revoke update, delete, truncate on public.product_merge_log from authenticated, anon;

comment on table public.product_merge_log is
  'Append-only record of every product merge. Inserted by merge_product_groups/merge_product_variant as the caller; readable by the tenant; no update or delete policy and no UPDATE/DELETE grant, by design.';

-- ── The gates ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.merge_product_preview(p_keep_group uuid, p_kill_group uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  v_like int; v_adds int; v_lines int; v_units numeric; v_invoices int; v_disc int;
begin
  select * into v_keep from public.product_groups where group_id = p_keep_group;
  if not found then raise exception 'the surviving product does not exist'; end if;
  select * into v_kill from public.product_groups where group_id = p_kill_group;
  if not found then raise exception 'the retiring product does not exist'; end if;

  -- Read-only, but it counts issued invoices and order volume across two
  -- products, so it is gated with the same key rather than left as a
  -- reachable reporting endpoint for any tenant member.
  if not public.auth_has_permission('product.merge', v_kill.company_id) then
    raise exception 'You do not have permission to merge products.'
      using errcode = 'insufficient_privilege';
  end if;

  -- These two counts previously omitted the filters the merge itself applies,
  -- so the numbers the operator confirmed were not the numbers that ran. They
  -- now mirror merge_product_groups exactly: distinct per kill row, and a
  -- survivor that is live and not already retired.
  select count(*) into v_like
    from (select distinct d.product_id
            from public.products d join public.products k
              on k.group_id = p_keep_group
             and k.size is not distinct from d.size
             and k.channel is not distinct from d.channel
             and k.canonical_product_id = k.product_id
             and k.merge_into_id is null
             and k.is_active
           where d.group_id = p_kill_group
             and d.canonical_product_id = d.product_id) x;

  select count(*) into v_adds
    from public.products d
   where d.group_id = p_kill_group
     and d.canonical_product_id = d.product_id
     and not exists (select 1 from public.products k
                      where k.group_id = p_keep_group
                        and k.size is not distinct from d.size
                        and k.channel is not distinct from d.channel
                        and k.canonical_product_id = k.product_id
                        and k.merge_into_id is null
                        and k.is_active);

  select count(*), coalesce(sum(od.quantity), 0) into v_lines, v_units
    from public.order_details od join public.products p on p.product_id = od.product_id
   where p.group_id = p_kill_group;

  -- Invoices that would print a different name if the operator renames.
  select count(distinct o.order_id) into v_invoices
    from public.order_details od
    join public.products p on p.product_id = od.product_id
    join public.orders o on o.order_id = od.order_id
   where p.group_id in (p_keep_group, p_kill_group)
     and (o.posted or o.invoice_number is not null);

  select count(*) into v_disc from public.customer_discount
   where scope = 'product' and scope_ref = p_kill_group::text
     and company_id = v_kill.company_id
     and is_active;

  return jsonb_build_object(
    'keeping', v_keep.group_name, 'retiring', v_kill.group_name,
    'variants_merged', v_like, 'variants_added', v_adds,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'issued_invoices_affected_if_renamed', v_invoices);
end; $function$;

CREATE OR REPLACE FUNCTION public.merge_product_variant(p_keep_id text, p_kill_id text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_keep    public.products%rowtype;
  v_kill    public.products%rowtype;
  v_lines   integer;
  v_units   numeric;
  v_moved   jsonb := '{}'::jsonb;
  v_n       integer;
begin
  if p_keep_id is null or p_kill_id is null then
    raise exception 'merge needs two products';
  end if;
  if p_keep_id = p_kill_id then
    raise exception 'a product cannot be merged into itself';
  end if;

  select * into v_keep from public.products where product_id = p_keep_id;
  if not found then raise exception 'the surviving product does not exist: %', p_keep_id; end if;
  select * into v_kill from public.products where product_id = p_kill_id;
  if not found then raise exception 'the retiring product does not exist: %', p_kill_id; end if;

  if v_keep.company_id is distinct from v_kill.company_id then
    raise exception 'refusing to merge across companies';
  end if;
  if v_kill.merge_into_id is not null then
    raise exception '% is already merged away', p_kill_id;
  end if;
  -- Merging INTO something retired would build a chain; follow it instead.
  if v_keep.merge_into_id is not null then
    raise exception '% is itself retired — merge into % instead', p_keep_id, v_keep.canonical_product_id;
  end if;

  -- Same gate as merge_product_groups, and needed independently: this function
  -- is separately EXECUTE-able by `authenticated` over PostgREST, so gating only
  -- the group-level entry point would leave the variant-level one wide open.
  if not public.auth_has_permission('product.merge', v_kill.company_id) then
    raise exception 'You do not have permission to merge products.'
      using errcode = 'insufficient_privilege';
  end if;

  -- What history stays behind, recorded before anything changes.
  select count(*), coalesce(sum(quantity), 0) into v_lines, v_units
    from public.order_details where product_id = p_kill_id;

  -- ── Forward-looking pointers follow the survivor ──────────────────────
  -- UNIQUE (customer_id, product_id, coffee_prep): a customer who holds a
  -- standing line for BOTH rows at the same prep would make a bare repoint
  -- raise 23505 and abort the whole merge. Fold the quantities together
  -- instead, then drop the loser's line.
  update public.standing_order_lines k
     set quantity = coalesce(k.quantity, 0) + coalesce((
           select sum(d.quantity) from public.standing_order_lines d
            where d.product_id = p_kill_id and d.customer_id = k.customer_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0)
   where k.product_id = p_keep_id
     and exists (select 1 from public.standing_order_lines d
                  where d.product_id = p_kill_id and d.customer_id = k.customer_id
                    and d.coffee_prep is not distinct from k.coffee_prep);
  delete from public.standing_order_lines d
   where d.product_id = p_kill_id
     and exists (select 1 from public.standing_order_lines k
                  where k.product_id = p_keep_id and k.customer_id = d.customer_id
                    and k.coffee_prep is not distinct from d.coffee_prep);
  update public.standing_order_lines set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('standing_order_lines', v_n);

  -- UNIQUE (vmi_checkin_id, product_id, coffee_prep). Same trap, same remedy:
  -- one check-in counting both rows is exactly what a duplicate product causes.
  -- Three figures, not one: observed, suggested and ordered are each counted
  -- per product, so each folds on its own.
  update public.vmi_checkin_items k
     set observed_qty  = coalesce(k.observed_qty, 0) + coalesce((
           select sum(d.observed_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0),
         suggested_qty = coalesce(k.suggested_qty, 0) + coalesce((
           select sum(d.suggested_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0),
         ordered_qty   = coalesce(k.ordered_qty, 0) + coalesce((
           select sum(d.ordered_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0)
   where k.product_id = p_keep_id
     and exists (select 1 from public.vmi_checkin_items d
                  where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
                    and d.coffee_prep is not distinct from k.coffee_prep);
  delete from public.vmi_checkin_items d
   where d.product_id = p_kill_id
     and exists (select 1 from public.vmi_checkin_items k
                  where k.product_id = p_keep_id and k.vmi_checkin_id = d.vmi_checkin_id
                    and k.coffee_prep is not distinct from d.coffee_prep);
  update public.vmi_checkin_items set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('vmi_checkin_items', v_n);

  update public.shopify_product_mappings set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shopify_product_mappings', v_n);

  update public.shop_config set shipping_product_id = p_keep_id where shipping_product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shop_config', v_n);

  update public.product_filter set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('product_filter', v_n);

  -- Polymorphic, no FK: nothing in the database would ever catch this.
  -- UNIQUE (customer_id, scope, coalesce(scope_ref,'__all__')) WHERE is_active.
  -- If the customer already has an ACTIVE rate on the survivor, keep that one
  -- and retire the loser's: two negotiated rates for one product have no
  -- honest merge, and inventing an answer is worse than keeping the rate that
  -- survives with the product.
  update public.customer_discount d
     set is_active = false,
         note = concat_ws(' ', d.note, '(superseded by the merged product''s own rate)')
   where d.scope = 'variant' and d.scope_ref = p_kill_id and d.company_id = v_kill.company_id
     and d.is_active
     and exists (select 1 from public.customer_discount k
                  where k.customer_id = d.customer_id and k.scope = 'variant'
                    and k.scope_ref = p_keep_id and k.is_active);
  update public.customer_discount
     set scope_ref = p_keep_id
   where scope = 'variant' and scope_ref = p_kill_id and company_id = v_kill.company_id
     and is_active;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('customer_discount', v_n);

  -- ── The survivor must be able to sell and consume ─────────────────────
  -- A survivor with no BOM consumes nothing. Copy (never move) so the loser
  -- keeps its own — its order lines are still read through it.
  if not exists (select 1 from public.product_consumables where product_id = p_keep_id)
     and exists (select 1 from public.product_consumables where product_id = p_kill_id) then
    insert into public.product_consumables (product_consumable_id, product_id, consumable_id, quantity, company_id, facility_id)
    select gen_random_uuid()::text, p_keep_id, pc.consumable_id, pc.quantity, pc.company_id, pc.facility_id
      from public.product_consumables pc
     where pc.product_id = p_kill_id
       -- Never give a resold product a BOM line for the consumable it IS:
       -- update_consumable_metrics subtracts the BOM path and the resold path
       -- independently, so that product would double-deduct on every order.
       and pc.consumable_id is distinct from v_keep.source_consumable_id;
    get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('bom_copied', v_n);
  end if;

  -- ── Retire ────────────────────────────────────────────────────────────
  update public.products
     set merge_into_id        = p_keep_id,
         canonical_product_id = v_keep.canonical_product_id,
         is_active            = false
   where product_id = p_kill_id;

  -- Anything already rolling up to the loser now rolls up to the survivor,
  -- so the graph never grows a second hop.
  update public.products
     set canonical_product_id = v_keep.canonical_product_id
   where canonical_product_id = p_kill_id and product_id <> p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('rechained', v_n);

  insert into public.product_merge_log (
    company_id, facility_id, merge_kind, kept_id, kept_name, retired_id, retired_name,
    order_lines_left, units_left, merged_by, notes)
  values (v_kill.company_id, v_kill.facility_id, 'variant', p_keep_id, v_keep.product_name,
          p_kill_id, v_kill.product_name, v_lines, v_units, auth.uid()::text, p_notes);

  return jsonb_build_object(
    'kept', p_keep_id, 'retired', p_kill_id,
    'order_lines_left_in_place', v_lines, 'units_left_in_place', v_units,
    'moved', v_moved);
end; $function$;

CREATE OR REPLACE FUNCTION public.merge_product_groups(p_keep_group uuid, p_kill_group uuid, p_surviving_name text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  r record;
  v_merged int := 0; v_added int := 0; v_disc int := 0; v_lines int; v_units numeric;
begin
  if p_keep_group is null or p_kill_group is null then
    raise exception 'a merge needs two products';
  end if;
  if p_keep_group = p_kill_group then
    raise exception 'a product cannot be merged into itself';
  end if;

  select * into v_keep from public.product_groups where group_id = p_keep_group;
  if not found then raise exception 'the surviving product does not exist'; end if;
  select * into v_kill from public.product_groups where group_id = p_kill_group;
  if not found then raise exception 'the retiring product does not exist'; end if;

  if v_keep.company_id is distinct from v_kill.company_id then
    raise exception 'refusing to merge products from different companies';
  end if;
  if v_kill.canonical_group_id is distinct from v_kill.group_id then
    raise exception 'that product has already been merged away';
  end if;
  if v_keep.canonical_group_id is distinct from v_keep.group_id then
    raise exception 'the surviving product is itself retired — merge into % instead', v_keep.canonical_group_id;
  end if;

  -- The gate. It lives HERE, not only in the Next.js action: `authenticated`
  -- holds EXECUTE on this function by Supabase's default ACL (the revoke in
  -- 20260924000006 named only public and anon, which grant nothing), and the
  -- RLS on products/product_groups is tenant-scoped with no key check. Without
  -- this line any signed-in member of the tenant — staff, sales_person,
  -- accounting_view — could retire a product with one POST to
  -- /rest/v1/rpc/merge_product_groups. That is the same hole 20260924000002
  -- deleted the old merge_products() for.
  if not public.auth_has_permission('product.merge', v_kill.company_id) then
    raise exception 'You do not have permission to merge products.'
      using errcode = 'insufficient_privilege';
  end if;

  select count(*), coalesce(sum(od.quantity), 0) into v_lines, v_units
    from public.order_details od join public.products p on p.product_id = od.product_id
   where p.group_id = p_kill_group;

  -- Like variants merge. Everything else stays put and rolls up through the
  -- group, because moving group_id would retype and rename it.
  for r in
    select distinct on (d.product_id)
           d.product_id as kill_id, k.product_id as keep_id
      from public.products d join public.products k
        on k.group_id = p_keep_group
       and k.size is not distinct from d.size
       and k.channel is not distinct from d.channel
       -- The survivor side was unfiltered. Two consequences, both silent:
       -- a keep group holding two rows at one size+channel yielded two pairs
       -- for one kill row, and the second merge_product_variant call aborted
       -- the whole transaction with 'is already merged away'; and a keep row
       -- that was archived or already retired swallowed a LIVE kill variant,
       -- taking that size off sale. Prod has 249 such archived slots at MCR,
       -- 66 and 59 at the two Social Hour tenants — this was never an MCR
       -- question.
       and k.canonical_product_id = k.product_id
       and k.merge_into_id is null
       and k.is_active
     where d.group_id = p_kill_group
       and d.canonical_product_id = d.product_id   -- skip any already merged
     order by d.product_id, k.product_id
  loop
    perform public.merge_product_variant(r.keep_id, r.kill_id, 'via product merge');
    v_merged := v_merged + 1;
  end loop;

  select count(*) into v_added from public.products
   where group_id = p_kill_group and canonical_product_id = product_id;

  -- Group-scoped discounts: no FK, so nothing else would ever catch this.
  -- customer_discount is UNIQUE (customer_id, scope, scope_ref) WHERE is_active,
  -- so a customer holding a negotiated rate on BOTH products made the bare
  -- repoint raise 23505 and abort the merge. 20260924000007 fixed exactly this
  -- for scope='variant' and did not touch scope='product'. Same resolution:
  -- the survivor's rate wins and the loser's retires, because two rates for one
  -- product have no honest merge and guessing is worse.
  update public.customer_discount d
     set is_active = false,
         note = concat_ws(' ', d.note, '(superseded by the merged product''s own rate)')
   where d.scope = 'product' and d.scope_ref = p_kill_group::text
     and d.company_id = v_kill.company_id and d.is_active
     and exists (select 1 from public.customer_discount k
                  where k.customer_id = d.customer_id and k.scope = 'product'
                    and k.scope_ref = p_keep_group::text and k.is_active);
  update public.customer_discount
     set scope_ref = p_keep_group::text
   where scope = 'product' and scope_ref = p_kill_group::text
     and company_id = v_kill.company_id
     and is_active;
  get diagnostics v_disc = row_count;

  -- Retire the group. canonical_group_id <> group_id IS the retired marker;
  -- is_visible keeps it out of the storefront.
  update public.product_groups
     set canonical_group_id = v_keep.canonical_group_id,
         is_visible         = false
   where group_id = p_kill_group;

  -- Anything already rolling up to it now rolls up to the survivor, so the
  -- graph never grows a second hop.
  update public.product_groups
     set canonical_group_id = v_keep.canonical_group_id
   where canonical_group_id = p_kill_group and group_id <> p_kill_group;

  -- The operator's name choice. Renaming restates issued invoices, which
  -- merge_product_preview counted for them.
  if p_surviving_name is not null and btrim(p_surviving_name) <> ''
     and btrim(p_surviving_name) <> v_keep.group_name then
    update public.product_groups set group_name = btrim(p_surviving_name)
     where group_id = p_keep_group;
    -- products.product_name is built from the group name by a row trigger that
    -- only fires on the child. Renaming the group alone left every variant, every
    -- order-picker option and every pack-run label reading the OLD name. This is
    -- the same no-op touch renameProductGroup() does in the app (products/actions.ts),
    -- copied rather than invented. build_product_name returns early for a resold
    -- consumable, so those rows are correctly untouched.
    update public.products set group_id = group_id where group_id = p_keep_group;
  end if;

  insert into public.product_merge_log (
    company_id, facility_id, merge_kind, kept_id, kept_name, retired_id, retired_name,
    order_lines_left, units_left, merged_by, notes)
  values (v_kill.company_id, v_kill.facility_id, 'group',
          p_keep_group::text, coalesce(btrim(p_surviving_name), v_keep.group_name),
          p_kill_group::text, v_kill.group_name,
          v_lines, v_units, auth.uid()::text, p_notes);

  return jsonb_build_object(
    'kept', p_keep_group, 'retired', p_kill_group,
    'variants_merged', v_merged, 'variants_added', v_added,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'surviving_name', coalesce(btrim(p_surviving_name), v_keep.group_name));
end; $function$;

CREATE OR REPLACE FUNCTION public.trg_do_customer_merge()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_keep_id text := NEW.merge_into_id;
    v_kill_id text := NEW.customer_id;
BEGIN
    -- Validate keep customer exists
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE customer_id = v_keep_id) THEN
        RAISE EXCEPTION 'Merge target customer not found: %', v_keep_id;
    END IF;

    -- customer.merge has existed as a permission key since the CRM shipped and
    -- has been enforced in exactly zero places: no server action, no RPC, no
    -- policy, no screen reads it. The merge is driven by an UPDATE of
    -- customers.merge_into_id, and the customers policy is tenant_company_access
    -- ALL with no key check — so any signed-in member could merge two customers,
    -- moving their orders and order_details, with one PATCH to /rest/v1/customers.
    -- Unlike the product merge this one REMAPS rather than tombstones, so it
    -- rewrites order history. The key now means something.
    IF NOT public.auth_has_permission('customer.merge', NEW.company_id) THEN
        RAISE EXCEPTION 'You do not have permission to merge customers.'
          USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Remap orders
    UPDATE public.orders
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap order_details
    UPDATE public.order_details
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap contacts
    UPDATE public.contacts
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap sales_notes
    UPDATE public.sales_notes
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap sales_tasks
    UPDATE public.sales_tasks
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Deactivate the kill customer
    UPDATE public.customers
    SET is_active = false
    WHERE customer_id = v_kill_id;

    RETURN NEW;
END;
$function$;

comment on function public.merge_product_groups(uuid, uuid, text, text) is
  'Merge two products. Like variants merge, the rest roll up through the group. Moves no order line and deletes no BOM. Requires product.merge, checked in-body because authenticated holds EXECUTE.';

-- ── Prove it ────────────────────────────────────────────────────────────
do $verify$
declare
  v_roles text; v_plans int; v_n int;
begin
  -- Every write path names the key.
  for v_n in
    select 1 from unnest(array[
      'merge_product_groups','merge_product_variant','merge_product_preview','trg_do_customer_merge'
    ]) as f
     where not exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = f
          and pg_get_functiondef(p.oid) ilike '%auth_has_permission%')
  loop
    raise exception 'a merge function still has no permission check';
  end loop;

  select string_agg(role_id, ', ' order by role_id) into v_roles
    from public.role_permissions where permission_id = 'product.merge' and granted;
  if v_roles is distinct from 'company_admin, facility_admin, manager' then
    raise exception 'product.merge roles are %, expected the three admins+manager', v_roles;
  end if;
  select string_agg(role_id, ', ' order by role_id) into v_roles
    from public.role_permissions where permission_id = 'customer.merge' and granted;
  if v_roles is distinct from 'company_admin, facility_admin, manager' then
    raise exception 'customer.merge roles are %, expected the same three', v_roles;
  end if;

  select count(*) into v_plans from public.plan_permissions
   where permission_id in ('product.merge','customer.merge') and granted;
  if v_plans <> 8 then raise exception 'expected 8 plan grants, found %', v_plans; end if;

  -- Nobody may edit the audit trail.
  if has_table_privilege('authenticated','public.product_merge_log','UPDATE')
     or has_table_privilege('authenticated','public.product_merge_log','DELETE') then
    raise exception 'authenticated can still edit the merge audit trail';
  end if;

  raise notice 'merge is gated: product.merge + customer.merge -> company_admin, facility_admin, manager; plan-gated on 4 plans; merge log append-only';
end $verify$;

commit;
