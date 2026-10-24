-- A recipe can be made of recipes.
--
-- Owner, 2026-10-23: *"this is actually a post blending of a blend. we already
-- accomodate for a post blend. not sure how to handle that."* Then, on the two
-- options put to him: *"ok yes do A."*
--
-- ── THE PROBLEM, PROVEN ON PROD ───────────────────────────────────────────
--
-- `MB DK` and `MB LT` have IDENTICAL component sheets -- Maui H3 10%,
-- Chocolate 45%, Fruit 45% -- and differ only in roast level. They are roasted
-- separately and blended AFTER roasting into what MCR actually sells.
--
-- But `MB DK` has 28 products pointing at it (15 active: every Maui Blend, plus
-- Kraken, Marco's, Haliimaile, Costco, Safeway, Dean & Deluca) and `MB LT` has
-- ZERO. Demand is attributed through `products.recipe_id`, so DK absorbs 100%
-- of it and LT shows no usage and no target at all. The owner spotted it on his
-- first real stock count: *"there's no way they have different stock/usage
-- levels."*
--
-- It could not be fixed by re-pointing products. `products.recipe_id` holds ONE
-- value, and `recipe_components.coffee_item` has only ever referenced green
-- origins -- checked: zero rows anywhere reference one recipe as a component of
-- another. A post-blend of two ROASTS had no way to be expressed.
--
-- ── WHAT THIS ADDS ────────────────────────────────────────────────────────
--
-- A component may now be a RECIPE instead of a green origin. So MCR can have a
-- "Maui Blend" recipe whose components are MB LT 50% and MB DK 50%, point the
-- products at it, and have the demand flow down to both halves by percentage.
--
-- Rejected: letting a PRODUCT name several recipes with ratios. The blend is a
-- property of the blend, not of the bag, and that shape would make somebody
-- re-enter the same ratio on every bag size.
--
-- ── THIS MIGRATION CHANGES NO BEHAVIOUR ───────────────────────────────────
--
-- It adds a nullable column and a view. No row uses the column yet, so the
-- view returns exactly "every recipe draws its own demand, at 100%" -- which is
-- what the planner already does. Teaching `roast_detail_by_blend` to read the
-- view is the NEXT migration, on its own, because that function feeds planning
-- AND money and wants its numbers compared before and after on real data.

begin;

alter table public.recipe_components
  add column if not exists component_recipe_id text references public.roast_recipes(recipe_id) on delete cascade;

comment on column public.recipe_components.component_recipe_id is
  'When set, this component is another RECIPE (a post-blend of roasts) rather than a green origin. Exactly one of coffee_item / component_recipe_id is set. percentage means the same thing either way.';

-- 🔴 EXACTLY ONE of the two. A row with both would be ambiguous about what is
-- being consumed, and a row with neither is a component of nothing. Written as
-- NOT VALID first so the constraint cannot fail the release on a pre-existing
-- row nobody has looked at; validated immediately after, which reports the
-- problem without having already rolled the file back.
alter table public.recipe_components
  drop constraint if exists recipe_components_one_source;

alter table public.recipe_components
  add constraint recipe_components_one_source
  check (
    (coffee_item is not null and component_recipe_id is null)
    or (coffee_item is null and component_recipe_id is not null)
  ) not valid;

alter table public.recipe_components
  validate constraint recipe_components_one_source;

-- 🔴 A recipe cannot contain itself, directly. (Deeper cycles are prevented in
-- the application: a trigger walking the graph on every component write would
-- cost more than it saves, and nothing can build a cycle without going through
-- the composer UI, which refuses one.)
alter table public.recipe_components
  drop constraint if exists recipe_components_no_self;

alter table public.recipe_components
  add constraint recipe_components_no_self
  check (component_recipe_id is null or component_recipe_id <> recipe_id);

create index if not exists recipe_components_component_recipe_idx
  on public.recipe_components (component_recipe_id)
  where component_recipe_id is not null;

-- ── Where a recipe's demand comes from ────────────────────────────────────
--
-- One row per (recipe, the recipe whose PRODUCTS carry its demand, the share).
-- Every recipe draws its own at 100%; a component recipe also draws its parent's
-- at the component percentage. So with no post-blends defined this is exactly
-- the identity mapping, and the planner's behaviour is unchanged.
--
-- Deliberately ONE level deep. A post-blend of a post-blend is not a shape MCR
-- has, and a recursive CTE here would be a cycle risk in planning SQL for a case
-- nobody has. When somebody has it, this view is the one place that changes.

create or replace view public.recipe_demand_source
with (security_invoker = true)
as
  select r.recipe_id,
         r.recipe_id      as source_recipe_id,
         1::numeric       as share,
         r.company_id,
         r.facility_id
    from public.roast_recipes r

  union all

  select rc.component_recipe_id              as recipe_id,
         rc.recipe_id                        as source_recipe_id,
         coalesce(rc.percentage, 0)::numeric as share,
         rc.company_id,
         rc.facility_id
    from public.recipe_components rc
   where rc.component_recipe_id is not null;

comment on view public.recipe_demand_source is
  'Where each recipe draws its demand from: itself at 100%, plus any parent post-blend at the component percentage. With no post-blends defined this is the identity mapping. One level deep on purpose.';

grant select on public.recipe_demand_source to authenticated;

-- 🔴 security_invoker, so the view answers as the CALLER and roast_recipes /
-- recipe_components RLS still applies. pg_get_viewdef DROPS this option when a
-- later migration recreates a view from its own text, which is how a view has
-- silently become security-definer here before.
do $$
begin
  if to_regclass('public.recipe_demand_source') is null then
    raise exception 'recipe_demand_source was not created';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'recipe_demand_source'
       and 'security_invoker=true' = any (c.reloptions)
  ) then
    raise exception 'recipe_demand_source is not security_invoker: it would read past RLS';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'recipe_components'
       and column_name = 'component_recipe_id'
  ) then
    raise exception 'recipe_components.component_recipe_id was not added';
  end if;
  -- The identity half must cover every recipe, or a planner reading this view
  -- would lose recipes rather than gain shares.
  if (select count(*) from public.roast_recipes)
     <> (select count(*) from public.recipe_demand_source where recipe_id = source_recipe_id) then
    raise exception 'recipe_demand_source does not return every recipe at 100%%';
  end if;
end $$;

commit;
