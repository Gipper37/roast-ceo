-- A merge must not change who can buy the product.
--
-- `merge_product_groups` moves the retiring product's variants under the
-- survivor and points its canonical_group_id at it. Everything downstream then
-- asks the SURVIVOR who may see the result -- the storefront render has always
-- done so, and as of 2026-10-15 the checkout does too. So merging a product
-- reserved for one cafe into one that is not PUBLISHES it to everybody with
-- shop access, and the reverse hides a product that was open. Neither says a
-- word.
--
-- Prod carries 26 groups pinned to a single customer, so this is not a corner.
--
-- ── Refused, not reconciled ───────────────────────────────────────────────
--
-- Carrying the lists forward is not available: a union of two allowlists
-- WIDENS access (one cafe's private label becomes two cafes'), and an
-- intersection can empty to nobody. Either way the function would be choosing
-- a commercial fact on the roaster's behalf, silently, during an operation
-- they asked for for an unrelated reason.
--
-- So it refuses and says what to do, which is the idiom this function already
-- uses for two companies, for a product already merged away, and for a variant
-- plan that does not say where a size goes. The roaster equalises the
-- visibility on both products and merges.
--
-- 🔴 THE BODY BELOW IS THE LIVE DEFINITION WITH ONE BLOCK INSERTED. It was
-- dumped from prod with pg_get_functiondef and patched, never retyped:
-- CREATE OR REPLACE rewrites the WHOLE function, so retyping one from memory
-- is how the other 180 lines get quietly reverted.

begin;

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


do $verify$
declare v_def text;
begin
  select pg_get_functiondef(oid) into v_def from pg_proc where proname = 'merge_product_groups';
  if v_def is null then
    raise exception 'merge_product_groups is gone';
  end if;

  -- 1. The new refusal is in there.
  if v_def not like '%visible to different customers%' then
    raise exception 'merge_product_groups does not refuse a visibility mismatch';
  end if;

  -- 2. 🔴 And everything that was there before still is. A CREATE OR REPLACE
  --    that dropped one of these would be a silent revert of the fix it was
  --    named for, which is exactly the failure this file is guarded against.
  if v_def not like '%auth_has_permission%' then
    raise exception 'merge_product_groups lost its product.merge permission gate';
  end if;
  if v_def not like '%refusing to merge products from different companies%' then
    raise exception 'merge_product_groups lost the cross-company refusal';
  end if;
  if v_def not like '%already been merged away%' then
    raise exception 'merge_product_groups lost the already-merged refusal';
  end if;
  if v_def not like '%canonical_group_id%' then
    raise exception 'merge_product_groups lost the canonical pointer';
  end if;

  -- 3. 🔴 THE COLLECTION AXIS IS IN THERE. The first draft of this guard
  --    compared only the three product-level arrays while the same release
  --    made collection membership a visibility gate, so a merge could still
  --    publish a reserved product through that door. Asserted by name,
  --    because a future CREATE OR REPLACE that drops it would be a silent
  --    revert of the half that was added last and is easiest to forget.
  if v_def not like '%collection_is_reserved%' then
    raise exception 'merge_product_groups does not compare reserved collections; a merge can still change who can buy';
  end if;
  -- And the predicate it depends on exists, since 20261015000006 defines it
  -- and this file would otherwise fail only when somebody tried a merge.
  if to_regprocedure('public.collection_is_reserved(text)') is null then
    raise exception 'collection_is_reserved is missing; 20261015000006 must run before this';
  end if;

  raise notice 'a merge now refuses to change who can buy the product, including through a reserved collection';
end $verify$;

commit;
