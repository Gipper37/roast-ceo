-- A product has a type.
--
-- products.product_type and product_groups.product_type were both nullable
-- while every path that creates a product requires one. The gap mattered once
-- already: createProduct used to leave product_type NULL, and because the
-- Products list filters by type a brand-new product was invisible the moment
-- anybody had a type chip selected. The owner made one, searched for it, got
-- "No products found", and the row was sitting there with an active priced
-- variant. That was fixed by resolving the Coffee type on create; the column
-- stayed nullable.
--
-- It surfaced again today in the storefront. Product type became the top
-- navigation layer, and a group whose type would not resolve belonged to no
-- tab. The first version of that showed untyped groups on EVERY tab so nothing
-- could silently vanish; the owner's correction was that type is required when
-- creating a product, so that fallback could only ever misfile something onto
-- tabs it did not belong on.
--
-- He is right, and the honest fix is to stop writing defensive code around a
-- rule the application already enforces and let the database enforce it too.
--
-- MEASURED ON PROD, all tenants: 1,093 products, 0 with a null type, 0 pointing
-- at a product_type row that does not exist. So this validates as it stands.
--
-- product_groups stays NULLABLE. A group's type is adopted from its variants by
-- trg_product_group_adopt_variant_type, which runs AFTER INSERT, so a group is
-- legitimately typeless for the instant between its own insert and its first
-- variant's. Constraining it would refuse a product the moment anybody made
-- one.

begin;

do $verify$
declare v_bad int;
begin
  select count(*) into v_bad from public.products where product_type is null;
  if v_bad > 0 then
    raise exception '% product(s) have no type; fix those before constraining the column', v_bad;
  end if;

  select count(*) into v_bad
    from public.products p
    left join public.product_type pt on pt.product_type_id = p.product_type
   where pt.product_type_id is null;
  if v_bad > 0 then
    raise exception '% product(s) point at a product_type that does not exist', v_bad;
  end if;
end;
$verify$;

alter table public.products
  alter column product_type set not null;

do $verify$
begin
  if (select is_nullable from information_schema.columns
       where table_schema='public' and table_name='products' and column_name='product_type') <> 'NO' then
    raise exception 'products.product_type is still nullable';
  end if;

  -- product_groups must stay nullable, for the trigger window described above.
  if (select is_nullable from information_schema.columns
       where table_schema='public' and table_name='product_groups' and column_name='product_type') <> 'YES' then
    raise exception 'product_groups.product_type was constrained; that refuses a group before its first variant exists';
  end if;
end;
$verify$;

commit;
