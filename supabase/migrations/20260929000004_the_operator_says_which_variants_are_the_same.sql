-- The operator says which variants are the same thing.
--
-- Merging two products paired their variants automatically on size AND channel
-- being identical. Two products that ARE the same thing often agree on neither.
-- Merging MCR's "2.2 Liter Pump Pot" (one variant, Wholesale, $66.25, linked to
-- its consumable) into the QuickBooks "2.2 Liter Pump Pot" (one variant, no
-- channel, no price, no consumable link) therefore merged ZERO variants and
-- retired the group anyway: product_merge_log holds a 'group' row for it at
-- 2026-09-25 08:29 with no matching 'variant' row. The selling variant was left
-- under a product marked invisible, and the surviving product could not reach
-- its own stock.
--
-- So the operator pairs them by hand. p_variant_plan is a list of
-- {kill, action, keep} with action in merge / move / archive. Omitted, the
-- automatic rule runs exactly as before, byte for byte -- every existing caller
-- keeps its behaviour.
--
-- WHY 'move' IS OFFERED BUT NEVER AUTOMATIC. It repoints group_id, and a
-- variant's name is rebuilt from its group by a row trigger, so moving one
-- renames it. Doing that behind somebody's back is why the automatic path
-- deliberately leaves unpaired variants where they are. Asked for, it is the
-- honest answer for a 12oz that exists on one side and not the other: it stays
-- sellable under the surviving name instead of only surfacing through rollup.
--
-- WHY THE SURVIVOR INHERITS source_consumable_id. A resold consumable deducts
-- through that column. The pump pot merge kept the QuickBooks variant, which has
-- none, so the survivor could not touch its own stock -- and somebody worked
-- around it by adding a product_consumables row pointing the consumable at
-- ITSELF. calculate_current_stock_consumables subtracts the BOM path and the
-- resale path independently, so that row double-deducts on the next sale. It is
-- the only such row in the database. Carrying the link over removes the reason
-- anyone would add another.
--
-- Both bodies below are pg_get_functiondef output from PROD with a script
-- applying the edits and printing the diff. merge_product_groups: 2 lines
-- removed. merge_product_preview: additive only.
--
-- 🔴 CREATE OR REPLACE with a DIFFERENT argument count creates an OVERLOAD, not
-- a replacement. Verified on prod: after the create, BOTH
-- merge_product_groups(uuid,uuid,text,text) and (uuid,uuid,text,text,jsonb)
-- existed. The old one would keep the old body, and a four-argument call --
-- which is exactly what the app sends -- becomes ambiguous the moment the fifth
-- has a default. PostgREST resolves by parameter NAME, so it would have had two
-- equally good candidates. The old signature is dropped below.

begin;

CREATE OR REPLACE FUNCTION public.merge_product_preview(p_keep_group uuid, p_kill_group uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  v_like int; v_adds int; v_lines int; v_units numeric; v_invoices int; v_disc int;
  v_retiring_variants jsonb; v_surviving_variants jsonb;
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

  -- Every variant on each side, so the operator can pair them BY HAND instead of
  -- discovering after the fact that nothing matched. The automatic rule pairs on
  -- size AND channel being identical, which is why merging a 2.2 Liter Pump Pot
  -- whose variant sits on Wholesale into a QuickBooks import whose variant has
  -- no channel at all merged ZERO variants and tombstoned the group anyway.
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', d.product_id,
           'product_name', d.product_name,
           'size', d.size,
           'size_name', (select s.size_name from public.size s where s.size_id = d.size),
           'channel', d.channel,
           'channel_name', (select c.channel from public.channel c where c.channel_id = d.channel),
           'price', d.price,
           'is_active', d.is_active,
           'source_consumable_id', d.source_consumable_id,
           'order_lines', (select count(*) from public.order_details od where od.product_id = d.product_id),
           'auto_match', (select k.product_id from public.products k
                           where k.group_id = p_keep_group
                             and k.size is not distinct from d.size
                             and k.channel is not distinct from d.channel
                             and k.canonical_product_id = k.product_id
                             and k.merge_into_id is null
                             and k.is_active
                           order by k.product_id limit 1)
         ) order by d.product_name), '[]'::jsonb) into v_retiring_variants
    from public.products d
   where d.group_id = p_kill_group
     and d.canonical_product_id = d.product_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', k.product_id,
           'product_name', k.product_name,
           'size', k.size,
           'size_name', (select s.size_name from public.size s where s.size_id = k.size),
           'channel', k.channel,
           'channel_name', (select c.channel from public.channel c where c.channel_id = k.channel),
           'price', k.price,
           'is_active', k.is_active,
           'source_consumable_id', k.source_consumable_id,
           'order_lines', (select count(*) from public.order_details od where od.product_id = k.product_id)
         ) order by k.product_name), '[]'::jsonb) into v_surviving_variants
    from public.products k
   where k.group_id = p_keep_group
     and k.canonical_product_id = k.product_id;

  return jsonb_build_object(
    'keeping', v_keep.group_name, 'retiring', v_kill.group_name,
    'keeping_type', v_keep.product_type, 'retiring_type', v_kill.product_type,
    'retiring_variants', v_retiring_variants,
    'surviving_variants', v_surviving_variants,
    'variants_merged', v_like, 'variants_added', v_adds,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'issued_invoices_affected_if_renamed', v_invoices);
end; $function$;

CREATE OR REPLACE FUNCTION public.merge_product_groups(p_keep_group uuid, p_kill_group uuid, p_surviving_name text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_variant_plan jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  r record;
  v_merged int := 0; v_added int := 0; v_disc int := 0; v_lines int; v_units numeric;
  v_moved int := 0; v_archived int := 0; v_plan record; v_keep_src text;
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

  -- ── THE OPERATOR'S OWN PAIRING ─────────────────────────────────────────
  -- p_variant_plan is a list of {kill, action, keep}, action being 'merge',
  -- 'move' or 'archive'. It exists because the automatic rule below pairs on
  -- size AND channel being identical, and two products that ARE the same thing
  -- often do not agree on either: merging a 2.2 Liter Pump Pot whose variant
  -- sits on Wholesale into the QuickBooks import whose variant has no channel
  -- merged ZERO variants and retired the group anyway, so the selling variant
  -- was left under a product nobody can see.
  --
  -- 'move' repoints group_id, which the automatic path deliberately never does.
  -- That is safe ONLY because the operator asked: a variant's name is rebuilt
  -- from its group by a row trigger, so moving one renames it, and doing that
  -- behind somebody's back is why it was never automatic.
  if p_variant_plan is not null and jsonb_typeof(p_variant_plan) = 'array' then
    for v_plan in
      select (e ->> 'kill') as kill_id, coalesce(e ->> 'action', 'merge') as action,
             nullif(e ->> 'keep', '') as keep_id
        from jsonb_array_elements(p_variant_plan) e
    loop
      if v_plan.kill_id is null then continue; end if;
      -- A plan naming a variant of some OTHER product is not this merge's
      -- business, and honouring it would retire a row nobody was looking at.
      if not exists (select 1 from public.products x
                      where x.product_id = v_plan.kill_id and x.group_id = p_kill_group) then
        raise exception 'That variant does not belong to the product being retired.';
      end if;

      if v_plan.action = 'merge' then
        if v_plan.keep_id is null then
          raise exception 'Say which variant % merges into, or choose to move or archive it.', v_plan.kill_id;
        end if;
        if not exists (select 1 from public.products x
                        where x.product_id = v_plan.keep_id and x.group_id = p_keep_group) then
          raise exception 'That variant does not belong to the surviving product.';
        end if;
        perform public.merge_product_variant(v_plan.keep_id, v_plan.kill_id, 'via product merge (chosen)');
        v_merged := v_merged + 1;
      elsif v_plan.action = 'move' then
        update public.products set group_id = p_keep_group where product_id = v_plan.kill_id;
        v_moved := v_moved + 1;
      elsif v_plan.action = 'archive' then
        update public.products set is_active = false where product_id = v_plan.kill_id;
        v_archived := v_archived + 1;
      else
        raise exception 'Unknown choice "%" for a variant.', v_plan.action;
      end if;
    end loop;
  else

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
  end if;

  -- ── THE SURVIVOR HAS TO BE ABLE TO MOVE STOCK ──────────────────────────
  -- A resold consumable deducts through products.source_consumable_id. The pump
  -- pot merge kept the QuickBooks variant, which has none, so the surviving
  -- product could not touch its own stock -- and somebody "fixed" that by adding
  -- a BOM row pointing the consumable at itself, which double-deducts on the
  -- next sale. Carry the link over when exactly one side has it, rather than
  -- leaving a survivor that cannot sell what it is.
  select max(d.source_consumable_id) into v_keep_src
    from public.products d
   where d.group_id = p_kill_group and d.source_consumable_id is not null;
  if v_keep_src is not null then
    update public.products k
       set source_consumable_id = v_keep_src
     where k.group_id = p_keep_group
       and k.source_consumable_id is null
       and k.merge_into_id is null
       and k.is_active
       and not exists (select 1 from public.products x
                        where x.group_id = p_keep_group and x.source_consumable_id is not null);
  end if;

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
    'variants_merged', v_merged, 'variants_moved', v_moved,
    'variants_archived', v_archived, 'variants_added', v_added,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'surviving_name', coalesce(btrim(p_surviving_name), v_keep.group_name));
end; $function$;

-- The overload the CREATE above left behind. Dropped, not replaced: leaving it
-- would keep the old body reachable AND make every four-argument call ambiguous.
drop function if exists public.merge_product_groups(uuid, uuid, text, text);

do $verify$
declare v_bad int;
begin
  -- Exactly ONE merge_product_groups, and it is the one that takes a plan.
  select count(*) into v_bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='merge_product_groups';
  if v_bad <> 1 then
    raise exception 'there are % merge_product_groups overloads; a four-argument call would be ambiguous', v_bad;
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.proname='merge_product_groups'
       and p.oid::regprocedure::text = 'merge_product_groups(uuid,uuid,text,text,jsonb)') then
    raise exception 'merge_product_groups did not gain its variant-plan argument';
  end if;

  -- merge_product_preview gates on auth_has_permission, which is false for the
  -- migration runner, so the shape is proved against the DATA it reads rather
  -- than by calling it. This is the pair that failed, asserted directly: under
  -- the automatic rule the pump pot's two variants do NOT pair, which is the
  -- whole reason the operator now gets to say so.
  if exists (select 1 from public.product_groups where group_id = '24d62787-7a86-5124-bd62-aee450f63145')
     and exists (select 1 from public.product_groups where group_id = '3527290c-db76-4fb8-9e2e-14698fe004f0') then
    select count(*) into v_bad
      from public.products d join public.products k
        on k.group_id = '24d62787-7a86-5124-bd62-aee450f63145'
       and k.size is not distinct from d.size
       and k.channel is not distinct from d.channel
       and k.canonical_product_id = k.product_id
       and k.merge_into_id is null
       and k.is_active
     where d.group_id = '3527290c-db76-4fb8-9e2e-14698fe004f0'
       and d.canonical_product_id = d.product_id;
    if v_bad <> 0 then
      raise exception 'expected the automatic rule to pair nothing for the pump pot; it paired %', v_bad;
    end if;

    -- And each side really does have a variant to offer, or there would be
    -- nothing for the operator to pair by hand either.
    select count(*) into v_bad from public.products
     where group_id = '3527290c-db76-4fb8-9e2e-14698fe004f0' and canonical_product_id = product_id;
    if v_bad = 0 then raise exception 'the retiring pump pot has no variant to pair'; end if;
    select count(*) into v_bad from public.products
     where group_id = '24d62787-7a86-5124-bd62-aee450f63145' and canonical_product_id = product_id;
    if v_bad = 0 then raise exception 'the surviving pump pot has no variant to pair into'; end if;
    raise notice 'pump pot: both sides carry a variant and the automatic rule pairs neither';
  end if;

  -- Nothing was merged by loading this migration.
  select count(*) into v_bad from public.product_merge_log
   where merged_at > now() - interval '1 minute';
  if v_bad > 0 then raise exception 'this migration merged % product(s); it must only define functions', v_bad; end if;
end;
$verify$;

commit;
