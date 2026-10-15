-- The five products whose variants disagreed about their collection, settled
-- by the person who sells them.
--
-- 20261015000002 had to pick ONE collection per product from variants that
-- carried several, and it picked the majority, ties broken by the smallest id.
-- It reported the mixed ones at apply time precisely because a majority is a
-- guess. The owner read the list and answered, 2026-10-14:
--
--   French Maui Blend         -> Hawaiian
--   Mama's Fish House Blend   -> Hawaiian
--   Marco's Blend             -> Flavor
--   Organic French            -> Organic
--   Maui Blend Decaf          -> Decaf AND Hawaiian
--
-- Four of the five the backfill already got right. The fifth is the one this
-- file exists for: **Maui Blend Decaf is in two collections**, and under the
-- single-value model it could only be in one. It is the first product in the
-- schema to use the many-to-many the model was changed for, which is a decent
-- argument that the change was right.
--
-- ── Why this is not "just insert a row" ───────────────────────────────────
--
-- It is one row, and it is a PRICE. A collection discount reaches a product
-- through product_group_collection, so adding this membership is what makes a
-- Hawaiian deal reach the decaf -- which is the owner's intent and is the
-- whole reason the answer was asked for.
--
-- 🔴 Keyed by NAME inside the company, never by the ids above. Those ids are
-- one tenant's, and a migration that names them is a migration that cannot
-- apply to staging, which is the gate. Absent is a NOTICE, not an error: a
-- database without this roaster's products is not a broken database.

begin;

do $fix$
declare
  v_group   uuid;
  v_company text;
  v_coll    text;
  v_added   int := 0;
begin
  -- The product, and the company it belongs to. Taken TOGETHER from the group
  -- row, never from two independent lookups: picking a company with its own
  -- `limit 1` is how two migrations this month wrote a row that crossed
  -- tenants and tripped the same-tenant guard.
  select g.group_id, g.company_id
    into v_group, v_company
    from public.product_groups g
   where g.group_name = 'Maui Blend Decaf'
     and coalesce(g.canonical_group_id, g.group_id) = g.group_id
   order by g.group_id
   limit 1;

  if v_group is null then
    raise notice 'no product called Maui Blend Decaf here; nothing to correct';
    return;
  end if;

  select c.id into v_coll
    from public.collection c
   where c.company_id = v_company
     and c.name = 'Hawaiian'
   limit 1;

  if v_coll is null then
    raise notice 'that roaster has no collection called Hawaiian; nothing to correct';
    return;
  end if;

  insert into public.product_group_collection (group_id, collection_id, company_id, created_by)
  values (v_group, v_coll, v_company, 'migration 20261015000004')
  on conflict (group_id, collection_id) do nothing;

  get diagnostics v_added = row_count;
  if v_added = 0 then
    raise notice 'Maui Blend Decaf was already in Hawaiian';
  else
    raise notice 'Maui Blend Decaf is now in Hawaiian as well as Decaf';
  end if;
end $fix$;

do $verify$
declare v_n int;
begin
  -- Where the product exists, it is in BOTH. Where it does not, this says so
  -- and passes: the assertion is about this file's change, not about which
  -- products a database happens to hold.
  select count(distinct pgc.collection_id) into v_n
    from public.product_group_collection pgc
    join public.product_groups g on g.group_id = pgc.group_id
    join public.collection c on c.id = pgc.collection_id
   where g.group_name = 'Maui Blend Decaf'
     and c.name in ('Hawaiian', 'Decaf');

  if not exists (select 1 from public.product_groups where group_name = 'Maui Blend Decaf') then
    raise notice 'Maui Blend Decaf is not on this database; nothing to verify';
  elsif v_n < 2 then
    raise exception 'Maui Blend Decaf should be in both Decaf and Hawaiian; it is in % of them', v_n;
  else
    raise notice 'Maui Blend Decaf is in both collections';
  end if;
end $verify$;

commit;
