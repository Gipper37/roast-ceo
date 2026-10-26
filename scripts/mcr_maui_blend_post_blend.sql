-- MCR: Maui Blend becomes a post-blend of MB DK and MB LT.
--
-- Owner, 2026-10-26: *"i need you to build the parent and update all that in
-- the backend db right now so i can get to counting."*
--
-- MB DK and MB LT have IDENTICAL green sheets (Fruit 45%, Chocolate 45%,
-- Maui H3 10%) and differ only in roast level. A bag of Maui Blend is a
-- post-blend of the two roasted lots, so the 15 ACTIVE products that pointed at
-- MB DK move to a new parent that holds both at 50%.
--
-- 🔴 THE COGS PREDICTION IS THE PROOF. Because the two sheets are identical,
-- recipe_effective_green on a 50/50 parent flattens to the SAME sheet
-- (0.5 x 0.45 + 0.5 x 0.45 = 0.45 for each origin). So every product's
-- total_coffee_cost must come out BYTE IDENTICAL. This script asserts that and
-- rolls itself back if any product's cost moves at all.
--
-- 🔴 ACTIVE PRODUCTS ONLY. 13 archived ones stay on MB DK: they contribute no
-- demand, and moving them rewrites more of what past orders appear to be made
-- from for no benefit.
--
-- Requires 20261026000001..000005, which are on prod as release-2026-10-26.
-- Rollback is at the bottom of this file.

begin;

create temp table _before on commit drop as
  select product_id, total_coffee_cost, total_unit_cogs, margin_pct, recipe_id
    from products where recipe_id = 'rcp-mcr-mb-dk' and is_active;

insert into roast_recipes (recipe_id, recipe_name, roast_type, company_id, facility_id, is_active)
values ('rcp-mcr-mb-dklt', 'Maui Blend DK/LT', 'Post-Blend', '9ShiyDAXhV',
        '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true)
on conflict (recipe_id) do nothing;

insert into recipe_components (component_id, recipe_id, component_recipe_id, percentage, company_id, facility_id)
values (gen_random_uuid()::text, 'rcp-mcr-mb-dklt', 'rcp-mcr-mb-dk', 0.5, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e'),
       (gen_random_uuid()::text, 'rcp-mcr-mb-dklt', 'rcp-mcr-mb-lt', 0.5, '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e')
on conflict do nothing;

update products set recipe_id = 'rcp-mcr-mb-dklt'
 where recipe_id = 'rcp-mcr-mb-dk' and is_active;

do $$
declare n_moved int; n_cost_moved int; worst numeric; n_comp int;
begin
  select count(*) into n_moved from products where recipe_id = 'rcp-mcr-mb-dklt';
  if n_moved <> 15 then raise exception 'expected 15 products on the parent, found %', n_moved; end if;

  select count(*) into n_comp from recipe_components
   where recipe_id = 'rcp-mcr-mb-dklt' and component_recipe_id is not null;
  if n_comp <> 2 then raise exception 'parent should have 2 recipe components, found %', n_comp; end if;

  -- 🔴 THE ASSERTION THIS SCRIPT EXISTS FOR.
  select count(*), coalesce(max(abs(b.total_coffee_cost - a.total_coffee_cost)), 0)
    into n_cost_moved, worst
    from _before a join products b on b.product_id = a.product_id
   where b.total_coffee_cost is distinct from a.total_coffee_cost;
  raise notice 'products whose coffee cost moved: % (worst %)', n_cost_moved, worst;
  if n_cost_moved > 0 then
    raise exception 'COGS MOVED on % product(s), worst %. Rolling back.', n_cost_moved, worst;
  end if;

  raise notice 'MOVED 15 products to Maui Blend DK/LT with no change to any COGS';
end $$;

commit;

-- ── ROLLBACK, if ever needed ──────────────────────────────────────────────
-- begin;
--   update products set recipe_id = 'rcp-mcr-mb-dk' where recipe_id = 'rcp-mcr-mb-dklt';
--   delete from recipe_components where recipe_id = 'rcp-mcr-mb-dklt';
--   delete from roast_recipes where recipe_id = 'rcp-mcr-mb-dklt';
-- commit;
