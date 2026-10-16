-- The merge plan stops offering sizes that are not on sale.
--
-- Owner, 2026-10-16, testing prod: *"unclear what we're doing here on the
-- merge. safeway maui blend only had one variant and its asking about two.
-- one of which does not exist on the safeway product. how canyou merge with
-- something that doesn't exist."*
--
-- He is right, and the cause is a ONE-SIDED FILTER in `merge_product_preview`.
-- The two halves of the plan did not ask the same question:
--
--   the SURVIVING product's variants (the `auto_match` lookup, and the
--     `surviving_variants` list the dropdowns are built from) filter
--     `canonical_product_id = product_id AND merge_into_id is null AND is_active`
--   the RETIRING product's variants filtered `canonical_product_id = product_id`
--     and NOTHING ELSE
--
-- So "WHAT HAPPENS TO EACH SIZE OF <product>" listed every row that product
-- had ever had: deactivated variants, and variants already merged away by an
-- earlier merge. His screenshot shows `8oz - retail` with no order lines
-- sitting beside `8oz - wholesale` with 276, on a product he knows has one
-- live size.
--
-- 🔴 WHY HIDING THEM IS RIGHT, rather than listing them as "take off sale".
-- The modal's own subtitle answers it: *"Sold history follows <product>
-- either way. This is about what stays on sale."* An inactive variant is
-- already not on sale, and its order history follows the group regardless of
-- anything chosen here, because the merge moves history by GROUP. So there is
-- no decision to take about it, and offering one invites an operator to map a
-- live size onto a dead row on a DESTRUCTIVE action.
--
-- This changes the PLAN only. `merge_products` itself is untouched: what it
-- moves, and the tombstone it leaves, are the same as before.
--
-- Body patched from `pg_get_functiondef`, not retyped. Two lines differ.

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
     and d.canonical_product_id = d.product_id
     -- 🔴 THE SAME FILTER THE SURVIVING SIDE USES. Without these two the
     -- plan listed every row the retiring product ever had, including
     -- deactivated variants and ones already merged away, and offered each
     -- one a mapping. See the note at the top of the migration.
     and d.merge_into_id is null
     and d.is_active;

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


do $verify$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc
   where oid = 'public.merge_product_preview(uuid,uuid)'::regprocedure;

  -- The retiring side now asks what the surviving side asks.
  if v_src not like '%and d.merge_into_id is null%' then
    raise exception 'the merge plan still lists variants that were merged away';
  end if;
  if v_src not like '%and d.is_active;%' then
    raise exception 'the merge plan still lists deactivated variants';
  end if;

  -- And the surviving side, which was always right, survived the replace.
  if v_src not like '%and k.merge_into_id is null%' or v_src not like '%and k.is_active%' then
    raise exception 'the surviving-variant filter is gone; the dropdowns would offer dead rows';
  end if;
  -- The parts that are not this change's.
  if v_src not like '%order_lines%' then
    raise exception 'the per-variant order line count is gone';
  end if;
  if v_src not like '%auto_match%' then
    raise exception 'the auto-match suggestion is gone';
  end if;
  if v_src not like '%the retiring product does not exist%' then
    raise exception 'the existence guards are gone';
  end if;

  raise notice 'the merge plan lists only sizes that are actually on sale';
end $verify$;

commit;
