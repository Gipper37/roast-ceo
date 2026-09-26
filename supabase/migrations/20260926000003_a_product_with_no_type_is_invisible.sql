-- A product with no type cannot be found.
--
-- createProductsWithVariants — the "coffee you roast" path behind New Product —
-- never wrote product_type, on the group or on its variants. The Products list
-- filters by type, so a product created there vanished the moment any type chip
-- was selected. The owner made one, searched for it by name, and got "No
-- products found" while the row sat here with an active, priced variant:
--
--   Maui Blend 51% - Custom Printed Label   1 variant, 8oz Wholesale, $12.80
--
-- Exactly ONE of MCR's 315 groups is in this state, which is the shape of a bug
-- nobody had hit yet rather than a long-standing mess — every other product
-- came from an import or predates the modal.
--
-- The code is fixed separately so new ones carry a type. This repairs what is
-- already here, and repairs it by RULE rather than by naming that one row: a
-- group with no type whose variants carry a recipe is coffee, because a recipe
-- is what makes something coffee in this schema. Anything typeless WITHOUT a
-- recipe is left alone and reported — guessing there would be inventing a fact.

begin;

create temporary table _typeless on commit drop as
  select g.group_id, g.company_id,
         (select pt.product_type_id
            from public.product_type pt
           where pt.product_type = 'Coffee'
             and (pt.company_id = g.company_id or pt.company_id is null)
           order by (pt.company_id is null)   -- a tenant's own override first
           limit 1) as coffee_type_id
    from public.product_groups g
   where g.product_type is null
     and exists (select 1 from public.products p
                  where p.group_id = g.group_id and p.recipe_id is not null);

update public.product_groups g
   set product_type = t.coffee_type_id
  from _typeless t
 where g.group_id = t.group_id and t.coffee_type_id is not null;

update public.products p
   set product_type = t.coffee_type_id
  from _typeless t
 where p.group_id = t.group_id and p.product_type is null and t.coffee_type_id is not null;

do $verify$
declare v_fixed int; v_left int; v_norecipe int;
begin
  select count(*) into v_fixed from _typeless where coffee_type_id is not null;

  -- Nothing with a recipe may still be typeless.
  select count(*) into v_left
    from public.product_groups g
   where g.product_type is null
     and exists (select 1 from public.products p where p.group_id = g.group_id and p.recipe_id is not null);
  if v_left > 0 then raise exception '% group(s) with a recipe are still typeless', v_left; end if;

  -- Report, do not guess, the ones with no recipe to go on.
  select count(*) into v_norecipe from public.product_groups where product_type is null;
  if v_norecipe > 0 then
    raise notice '% group(s) remain typeless and have no recipe to infer from — left alone deliberately', v_norecipe;
  end if;

  raise notice '% typeless coffee product(s) given their type and made findable again', v_fixed;
end $verify$;

commit;
