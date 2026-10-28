-- A merge may not drop a stock link without saying so.
--
-- ── What happened ────────────────────────────────────────────────────────
--
-- merge_product_groups carries the retiring product's source_consumable_id
-- over to the survivor, but only under this guard:
--
--     and not exists (select 1 from public.products x
--                      where x.group_id = p_keep_group
--                        and x.source_consumable_id is not null)
--
-- So when BOTH products are linked, the survivor keeps its own row and the
-- retiring product's is abandoned in silence. On MCR's 12-cup filters the
-- product being retired held the stock row with 5 on hand AND a supplier,
-- while the survivor held a QuickBooks import row with 1 and none. The
-- roaster caught it by eye -- "then don't retire it" -- and nothing in the app
-- would ever have mentioned it. 107 of his product groups carry a link, so
-- this was not a one-off.
--
-- ── What changes ─────────────────────────────────────────────────────────
--
-- merge_product_preview gains a `stock_link` object naming both sides and
-- saying which of five things will happen: none, kept, carried_over, same, or
-- conflict. The per-variant source_consumable_id was already in that payload,
-- which is exactly why this went unnoticed: the one case that loses
-- information looked identical to the four that do not.
--
-- merge_product_groups gains `p_source_consumable` and REFUSES a conflicting
-- merge that does not answer it, naming both stock items in the message. A
-- constraint is a choice, not a recovery: either answer can be right and only
-- the operator knows which, so guessing the likelier one is the one thing this
-- must not do. Nothing is deleted on either path -- the losing consumable
-- keeps its own stock and its own history.
--
-- 🔴 The no-conflict paths are byte-for-byte what they were. A merge where one
-- side or neither side is linked behaves exactly as it did yesterday.
--
-- ── Why a DROP ───────────────────────────────────────────────────────────
--
-- A new parameter means a new signature, and CREATE OR REPLACE would leave the
-- five-argument version in place as an overload -- then every existing call,
-- which names its arguments, becomes ambiguous and fails. So the old one is
-- dropped and the grants are restored explicitly: authenticated and
-- service_role held EXECUTE and must still hold it.
--
-- Both bodies were taken from pg_get_functiondef on production and patched;
-- nothing was retyped.

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
  v_survivor_src text; v_kill_src text;
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

  -- What the merge will do to the stock link, said BEFORE it happens. The
  -- per-variant source_consumable_id was already in this payload, but nothing
  -- compared the two sides, so the one case that loses information -- both
  -- linked, to different items -- looked exactly like the safe ones.
  select max(x.source_consumable_id) into v_survivor_src
    from public.products x where x.group_id = p_keep_group and x.source_consumable_id is not null;
  select max(d.source_consumable_id) into v_kill_src
    from public.products d where d.group_id = p_kill_group and d.source_consumable_id is not null;

  return jsonb_build_object(
    'stock_link', jsonb_build_object(
      'surviving_consumable_id', v_survivor_src,
      'surviving_consumable', (select ci.consumable_inventory_item from public.consumable_inventory ci
                                where ci.consumable_inventory_id = v_survivor_src),
      'retiring_consumable_id', v_kill_src,
      'retiring_consumable', (select ci.consumable_inventory_item from public.consumable_inventory ci
                               where ci.consumable_inventory_id = v_kill_src),
      'outcome', case
        when v_survivor_src is null and v_kill_src is null then 'none'
        when v_survivor_src is null                        then 'carried_over'
        when v_kill_src is null                            then 'kept'
        when v_survivor_src = v_kill_src                   then 'same'
        else 'conflict' end),
    'keeping', v_keep.group_name, 'retiring', v_kill.group_name,
    'keeping_type', v_keep.product_type, 'retiring_type', v_kill.product_type,
    'retiring_variants', v_retiring_variants,
    'surviving_variants', v_surviving_variants,
    'variants_merged', v_like, 'variants_added', v_adds,
    'order_lines_kept_in_place', v_lines, 'units', v_units,
    'discounts_moved', v_disc,
    'issued_invoices_affected_if_renamed', v_invoices);
end; $function$;

drop function if exists public.merge_product_groups(uuid, uuid, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.merge_product_groups(p_keep_group uuid, p_kill_group uuid, p_surviving_name text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_variant_plan jsonb DEFAULT NULL::jsonb, p_source_consumable text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_keep public.product_groups%rowtype;
  v_kill public.product_groups%rowtype;
  r record;
  v_merged int := 0; v_added int := 0; v_disc int := 0; v_lines int; v_units numeric;
  v_moved int := 0; v_archived int := 0; v_plan record; v_keep_src text;
  v_survivor_src text;
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

  -- ── Two products, two audiences, one answer required ─────────────────────
  --
  -- A merge moves the retiring product's variants under the survivor and
  -- points its canonical_group_id here. Everything downstream then asks the
  -- SURVIVOR who may see it. So merging a product that is reserved for one
  -- cafe into one that is not PUBLISHES it, silently, to everybody with shop
  -- access -- and the reverse hides a product that was open.
  --
  -- This is not something to guess at on the roaster's behalf. The audiences
  -- are a commercial fact, not a formatting detail, and a merge is already a
  -- function that refuses rather than improvises: it refuses two companies, a
  -- product already merged away, and a variant plan that does not say where a
  -- size goes. Same shape here.
  --
  -- Equal means equal as SETS and treats NULL and '{}' alike, because the
  -- operator UI writes an empty array as readily as a null when the last name
  -- is removed.
  if not (
    coalesce(v_keep.exclusive_to_customer_ids,  '{}') @> coalesce(v_kill.exclusive_to_customer_ids,  '{}')
    and coalesce(v_kill.exclusive_to_customer_ids,  '{}') @> coalesce(v_keep.exclusive_to_customer_ids,  '{}')
    and coalesce(v_keep.excluded_from_customer_ids, '{}') @> coalesce(v_kill.excluded_from_customer_ids, '{}')
    and coalesce(v_kill.excluded_from_customer_ids, '{}') @> coalesce(v_keep.excluded_from_customer_ids, '{}')
    and coalesce(v_keep.exclusive_to_chain_ids,     '{}') @> coalesce(v_kill.exclusive_to_chain_ids,     '{}')
    and coalesce(v_kill.exclusive_to_chain_ids,     '{}') @> coalesce(v_keep.exclusive_to_chain_ids,     '{}')
    -- 🔴 AND THE COLLECTION AXIS, which this guard's first draft ignored while
    -- the SAME RELEASE made it a visibility gate.
    --
    -- 20261015000006 put the three allowlists on `collection`, and the
    -- storefront's rule is ALL-allow: every RESERVED collection a product is
    -- in must admit the buyer. A merge retires the losing group and the
    -- storefront folds its variants onto the survivor, judging them by the
    -- SURVIVOR's collections -- so merging a product that sits on a reserved
    -- shelf into one that does not publishes it, which is exactly the thing
    -- the three arrays above are compared to prevent. Checking those and not
    -- this left the hole open through a second door.
    --
    -- Only RESERVED collections are compared. An unrestricted shelf is silent
    -- under ALL-allow, so differing on "Decaf" changes nobody's access and
    -- refusing over it would block the ordinary tidy-up a merge exists for.
    -- `collection_is_reserved` is the one definition, from 20261015000017
    -- (it lived in 006 until 2026-10-16; see the note there).
    and (
      select coalesce(array_agg(pgc.collection_id order by pgc.collection_id), '{}')
        from public.product_group_collection pgc
       where pgc.group_id = p_keep_group
         and public.collection_is_reserved(pgc.collection_id)
    ) = (
      select coalesce(array_agg(pgc.collection_id order by pgc.collection_id), '{}')
        from public.product_group_collection pgc
       where pgc.group_id = p_kill_group
         and public.collection_is_reserved(pgc.collection_id)
    )
  ) then
    raise exception 'These two products are visible to different customers, so merging them would change who can buy one of them. Make the shop visibility and the reserved collections the same on both, then merge.'
      using errcode = 'check_violation';
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
  --
  -- 🔴 AND WHEN BOTH SIDES HAVE ONE, ASK. The carry-over below is guarded by
  -- "the survivor has none", so two linked products merged in SILENCE: the
  -- survivor kept its own row and the retiring product's was abandoned with
  -- nothing said. Caught on MCR's 12-cup filters, where the product being
  -- retired held the row with 5 in stock AND a supplier while the survivor
  -- held a QuickBooks row with 1 and none. The roaster spotted it by eye; the
  -- app would never have mentioned it. 107 of his product groups carry a link.
  --
  -- A constraint is a choice, not a recovery: the merge refuses and names both
  -- items rather than picking the likelier one, because either answer can be
  -- right and only the operator knows which. Nothing is deleted either way --
  -- the losing consumable keeps its own stock and history.
  select max(d.source_consumable_id) into v_keep_src
    from public.products d
   where d.group_id = p_kill_group and d.source_consumable_id is not null;

  select max(x.source_consumable_id) into v_survivor_src
    from public.products x
   where x.group_id = p_keep_group and x.source_consumable_id is not null;

  if v_keep_src is not null and v_survivor_src is not null
     and v_keep_src <> v_survivor_src then
    if p_source_consumable is null then
      raise exception
        'Both products draw on stock, and not the same item: "%" uses %, "%" uses %. Say which one the merged product should draw on. The other keeps its own stock and history.',
        v_keep.group_name,
        coalesce((select ci.consumable_inventory_item from public.consumable_inventory ci
                   where ci.consumable_inventory_id = v_survivor_src), 'an item that no longer exists'),
        v_kill.group_name,
        coalesce((select ci.consumable_inventory_item from public.consumable_inventory ci
                   where ci.consumable_inventory_id = v_keep_src), 'an item that no longer exists')
        using errcode = 'cardinality_violation';
    end if;

    if p_source_consumable is distinct from v_survivor_src
       and p_source_consumable is distinct from v_keep_src then
      raise exception 'That stock item belongs to neither of these products.'
        using errcode = 'invalid_parameter_value';
    end if;

    -- Every live variant of the survivor, because the variants of one product
    -- are its sizes and channels: they sell the same thing and a pack size is
    -- carried by size.units_per_case, never by a second stock row.
    update public.products k
       set source_consumable_id = p_source_consumable
     where k.group_id = p_keep_group
       and k.merge_into_id is null
       and k.is_active
       and k.source_consumable_id is distinct from p_source_consumable;

  elsif v_keep_src is not null then
    -- UNCHANGED. Exactly one side has a link, so there is nothing to choose.
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

grant execute on function public.merge_product_groups(uuid, uuid, text, text, jsonb, text) to authenticated, service_role;

do $$
declare
  n_new int; n_old int; ok_auth bool; ok_svc bool; has_stock_link bool;
begin
  select count(*) into n_new from pg_proc
   where proname = 'merge_product_groups' and pronamespace = 'public'::regnamespace
     and pg_get_function_identity_arguments(oid) = 'p_keep_group uuid, p_kill_group uuid, p_surviving_name text, p_notes text, p_variant_plan jsonb, p_source_consumable text';
  if n_new <> 1 then raise exception 'the six-argument merge_product_groups is not there (found %)', n_new; end if;

  -- 🔴 The old one must be GONE, not merely shadowed: two overloads make every
  -- named-argument call ambiguous, which is a worse failure than the bug.
  select count(*) into n_old from pg_proc
   where proname = 'merge_product_groups' and pronamespace = 'public'::regnamespace
     and pg_get_function_identity_arguments(oid) = 'p_keep_group uuid, p_kill_group uuid, p_surviving_name text, p_notes text, p_variant_plan jsonb';
  if n_old <> 0 then raise exception 'the five-argument merge_product_groups is still present'; end if;

  ok_auth := has_function_privilege('authenticated',
    'public.merge_product_groups(uuid, uuid, text, text, jsonb, text)', 'execute');
  ok_svc := has_function_privilege('service_role',
    'public.merge_product_groups(uuid, uuid, text, text, jsonb, text)', 'execute');
  if not ok_auth or not ok_svc then
    raise exception 'merge_product_groups lost a grant: authenticated %, service_role %', ok_auth, ok_svc;
  end if;

  select prosrc ilike '%stock_link%' into has_stock_link from pg_proc
   where proname = 'merge_product_preview' and pronamespace = 'public'::regnamespace;
  if not coalesce(has_stock_link, false) then
    raise exception 'merge_product_preview does not report the stock link';
  end if;

  -- 🔴 Asserting SHAPE, never this roastery's rows. Staging holds none of
  -- these products, and an assertion only production could satisfy would turn
  -- the rehearsal into the thing that breaks the release.
  raise notice 'a conflicting stock link is now surfaced and refused rather than dropped';
end $$;

commit;
