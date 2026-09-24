-- Merging two products (groups), and the permission that gates it.
--
-- 20260924000003 built the variant-level half. This is the one operators
-- actually reach for: "these two rows are the same product, make them one."
--
-- WHAT IT DOES
--   * A variant that exists in BOTH groups at the same size AND channel is a
--     like pair — the loser is retired into the survivor by
--     merge_product_variant.
--   * A variant that exists in only the retiring group is an ADD. It is NOT
--     moved: writing products.group_id fires products_inherit_group_type and
--     build_product_name, which would retype and rename it. It stays where it
--     is and rolls up through the retired GROUP's canonical_group_id.
--   * The retiring group is hidden and pointed at the survivor.
--   * Group-scoped customer discounts follow the survivor. scope='product'
--     stores the GROUP id in scope_ref, as text, with no foreign key — nothing
--     in the database would catch this being missed.
--
-- THE NAME. The operator may keep either name. Choosing the retiring group's
-- name RENAMES the survivor, and lib/shop/invoiceDispatch.ts:183 resolves an
-- invoice line's name LIVE from group_name — there is no snapshot on that
-- path. So an already-issued invoice re-rendered after the merge prints the
-- new name. That is a real restatement, it is the operator's call to make, and
-- merge_product_preview counts the affected invoices so the choice is made
-- with the number in front of them. Default is the survivor's own name, which
-- restates nothing.

begin;

-- ── The permission ──────────────────────────────────────────────────────
-- Every feature ships its role + plan rows, and the migration lands before any
-- frontend names the key: an unknown key resolves to denied for every role,
-- silently.
insert into public.permissions (permission_id, label, description, category, is_plan_gated)
values ('product.merge', 'Merge products',
        'Combine two duplicate products into one. Retires the loser and rolls its history up to the survivor.',
        'products', false)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
select r, 'product.merge', true
  from unnest(array['company_admin','facility_admin']) as r
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ── What a merge would do, before doing it ──────────────────────────────
create or replace function public.merge_product_preview(
  p_keep_group uuid,
  p_kill_group uuid
) returns jsonb
language plpgsql stable security invoker as $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  v_like int; v_adds int; v_lines int; v_units numeric; v_invoices int; v_disc int;
begin
  select * into v_keep from public.product_groups where group_id = p_keep_group;
  if not found then raise exception 'the surviving product does not exist'; end if;
  select * into v_kill from public.product_groups where group_id = p_kill_group;
  if not found then raise exception 'the retiring product does not exist'; end if;

  select count(*) into v_like
    from public.products k join public.products d
      on d.group_id = p_kill_group and k.group_id = p_keep_group
     and d.size is not distinct from k.size and d.channel is not distinct from k.channel;

  select count(*) into v_adds
    from public.products d where d.group_id = p_kill_group
     and not exists (select 1 from public.products k where k.group_id = p_keep_group
                      and k.size is not distinct from d.size and k.channel is not distinct from d.channel);

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
   where scope = 'product' and scope_ref = p_kill_group::text;

  return jsonb_build_object(
    'keeping', v_keep.group_name, 'retiring', v_kill.group_name,
    'variants_merged', v_like, 'variants_added', v_adds,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'issued_invoices_affected_if_renamed', v_invoices);
end; $function$;

comment on function public.merge_product_preview(uuid, uuid) is
  'What a merge would do, counted before it happens. issued_invoices_affected_if_renamed matters only if the operator keeps the RETIRING name — the invoice line name resolves live from group_name.';

-- ── The merge ───────────────────────────────────────────────────────────
create or replace function public.merge_product_groups(
  p_keep_group uuid,
  p_kill_group uuid,
  p_surviving_name text default null,
  p_notes text default null
) returns jsonb
language plpgsql security invoker as $function$
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

  select count(*), coalesce(sum(od.quantity), 0) into v_lines, v_units
    from public.order_details od join public.products p on p.product_id = od.product_id
   where p.group_id = p_kill_group;

  -- Like variants merge. Everything else stays put and rolls up through the
  -- group, because moving group_id would retype and rename it.
  for r in
    select d.product_id as kill_id, k.product_id as keep_id
      from public.products d join public.products k
        on k.group_id = p_keep_group
       and k.size is not distinct from d.size
       and k.channel is not distinct from d.channel
     where d.group_id = p_kill_group
       and d.canonical_product_id = d.product_id   -- skip any already merged
  loop
    perform public.merge_product_variant(r.keep_id, r.kill_id, 'via product merge');
    v_merged := v_merged + 1;
  end loop;

  select count(*) into v_added from public.products
   where group_id = p_kill_group and canonical_product_id = product_id;

  -- Group-scoped discounts: no FK, so nothing else would ever catch this.
  update public.customer_discount
     set scope_ref = p_keep_group::text
   where scope = 'product' and scope_ref = p_kill_group::text
     and company_id = v_kill.company_id;
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

comment on function public.merge_product_groups(uuid, uuid, text, text) is
  'Merge two products. Like variants merge, the rest roll up through the group. Moves no order line and deletes no BOM.';

revoke all on function public.merge_product_groups(uuid, uuid, text, text) from public, anon;
revoke all on function public.merge_product_preview(uuid, uuid) from public, anon;

do $$
declare v_roles text;
begin
  select string_agg(role_id, ', ' order by role_id) into v_roles
    from public.role_permissions where permission_id = 'product.merge' and granted;
  if v_roles is null then raise exception 'product.merge is granted to nobody'; end if;
  raise notice 'product.merge granted to: %', v_roles;
end $$;

commit;
