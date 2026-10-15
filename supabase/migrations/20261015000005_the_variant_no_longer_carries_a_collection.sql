-- products.category_id goes away.
--
-- 20261015000002 moved the classification off the variant and onto the product
-- (then ...003 renamed the table to `collection` and made it many-to-many) and
-- deliberately left this column standing, with this written on it:
--
--   "Nothing reads it after this migration, but 'nothing reads it' is a claim a
--    release should prove before a column holding 379 rows of a roaster's own
--    classification goes away."
--
-- This is that proof, and it is an assertion rather than a sentence.
--
-- ── What the assertion actually asks ──────────────────────────────────────
--
-- Not "is every variant's old value still present". It is not, ON PURPOSE:
-- measured against prod data, seven variants carry a collection their product
-- is no longer in, and six of those seven are the owner's own corrections --
-- he read the mixed-product report and chose the product's collection over
-- what one of its sizes happened to say:
--
--   French Maui Blend 5lbs       said Custom Coffees           -> Hawaiian
--   Mama's Fish House Mokka 8oz  said VIP                      -> Hawaiian  (x2)
--   Marco's Blend 5lbs           said Custom Coffees           -> Flavor
--   Organic French 5lbs          said Certified Organic (USDA) -> Organic
--
-- The seventh and eighth were Maui Blend Decaf's 2oz sizes saying Hawaiian
-- while the product had only Decaf, and 20261015000004 answered that by
-- putting the product in both.
--
-- So the question that distinguishes a deliberate supersession from real loss
-- is: **is the product in ANY collection at all?** If it is, the roaster's
-- classification survives in the place the resolver and the storefront read,
-- and the variant's older, narrower value is superseded. If it is NOT, this
-- column holds the only record of how that product was filed, and dropping it
-- destroys it. That raises, names the products, and nothing is dropped.
--
-- ── Nothing in the frontend reads it ───────────────────────────────────────
--
-- Verified 2026-10-15: `grep -rn "category_id" app lib components`, minus
-- restock_category_id and supplier_category_id, returns nothing at all.

begin;

do $prove$
declare v_lost int; v_superseded int; v_rec record;
begin
  -- Absent is fine: a database built fresh from the squashed baseline has
  -- nothing to prove and nothing to drop.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'products' and column_name = 'category_id'
  ) then
    raise notice 'products.category_id is not here; nothing to drop';
    return;
  end if;

  -- 🔴 REAL LOSS: a variant that was filed, whose product is in no collection.
  select count(*) into v_lost
    from public.products p
    join public.product_groups g on g.group_id = p.group_id
   where p.category_id is not null
     and not exists (
       select 1 from public.product_group_collection pgc
        where pgc.group_id = coalesce(g.canonical_group_id, g.group_id)
     );

  if v_lost > 0 then
    for v_rec in
      select distinct g.group_name, pc.name as was_filed_under
        from public.products p
        join public.product_groups g on g.group_id = p.group_id
        left join public.collection pc on pc.id = p.category_id
       where p.category_id is not null
         and not exists (
           select 1 from public.product_group_collection pgc
            where pgc.group_id = coalesce(g.canonical_group_id, g.group_id)
         )
       order by 1
       limit 20
    loop
      raise notice 'WOULD LOSE: % was filed under % and its product is in no collection',
        v_rec.group_name, coalesce(v_rec.was_filed_under, '(a deleted collection)');
    end loop;
    raise exception
      '% variant(s) hold the only record of how their product is filed. Put those products in a collection first; not dropping.',
      v_lost;
  end if;

  -- SUPERSEDED: filed differently from the product it belongs to. Reported by
  -- name, never raised. This is what a deliberate correction looks like, and a
  -- release that stopped on it would be stopping on the right answer.
  select count(*) into v_superseded
    from public.products p
    join public.product_groups g on g.group_id = p.group_id
   where p.category_id is not null
     and not exists (
       select 1 from public.product_group_collection pgc
        where pgc.group_id = coalesce(g.canonical_group_id, g.group_id)
          and pgc.collection_id = p.category_id
     );

  for v_rec in
    select p.product_name, pc.name as variant_said
      from public.products p
      join public.product_groups g on g.group_id = p.group_id
      left join public.collection pc on pc.id = p.category_id
     where p.category_id is not null
       and not exists (
         select 1 from public.product_group_collection pgc
          where pgc.group_id = coalesce(g.canonical_group_id, g.group_id)
            and pgc.collection_id = p.category_id
       )
     order by 1
     limit 20
  loop
    raise notice 'superseded: % said %, and its product is filed elsewhere',
      v_rec.product_name, coalesce(v_rec.variant_said, '(a deleted collection)');
  end loop;
  raise notice '% variant value(s) superseded, 0 lost; dropping the column', v_superseded;

  alter table public.products drop column category_id;
end $prove$;

do $verify$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'products' and column_name = 'category_id'
  ) then
    raise exception 'products.category_id is still there';
  end if;
  raise notice 'products.category_id is gone';
end $verify$;

commit;
