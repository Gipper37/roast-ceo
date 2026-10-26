-- A parent's demand belongs to the recipes that actually get roasted.
--
-- Step 3 of the post-blend wiring: amend `recipe_demand_source` so it can be
-- read, and stop a parent asking to be roasted.
--
-- The view as shipped in 20261023000005 is two branches:
--
--   identity   every recipe -> itself at share 1
--   component  every recipe component -> its PARENT as the source, at the
--              component's percentage
--
-- Read it as: "for recipe R, demand also arrives from SOURCE S at share X."
--
-- ── 🔴 THE PARENT MUST LOSE ITS IDENTITY ROW ─────────────────────────────
--
-- Leave it in and the demand is counted TWICE: once on the parent, which still
-- looks roastable, and once on each child that inherited it. Four live callers
-- sum this engine's rows blindly with no recipe filter (the Left to roast
-- card, the sidebar badge, and the Load From Queue header), so the week's
-- figure would simply double.
--
-- Dropping it is also what makes "a parent is never roasted" true by
-- ARITHMETIC rather than by a flag: with no identity row the parent draws no
-- demand, so it asks for no batches, and nothing has to know what a parent is.
--
-- ── 🔴 AND A DUPLICATE COMPONENT ROW WOULD DOUBLE A CHILD'S SHARE ────────
--
-- Nothing stopped two component rows on the same parent naming the same child.
-- The view would emit that child's share twice and it would quietly absorb
-- demand meant for its sibling. The migration's own verify block counted only
-- identity rows, so it stayed green. One unique index closes it, and it has to
-- exist BEFORE anything reads the view.
--
-- ── WHAT STAYS THE SAME ──────────────────────────────────────────────────
--
-- With no component rows anywhere, which is production today, the `not exists`
-- is false for every recipe and the view is still the identity mapping, one
-- row per recipe at share 1. Verified below rather than asserted.

begin;

-- 🔴 BEFORE the view is read by anything. A parent naming the same child twice
-- is not a configuration an operator can see, and the arithmetic it produces
-- looks entirely reasonable.
create unique index if not exists recipe_components_one_parent_child
  on public.recipe_components (recipe_id, component_recipe_id)
  where component_recipe_id is not null;

create or replace view public.recipe_demand_source
with (security_invoker = true) as
  -- A recipe is its own demand source, UNLESS it is a container for others.
  -- That exclusion is the whole of "a parent is never roasted".
  select r.recipe_id,
         r.recipe_id as source_recipe_id,
         1::numeric  as share,
         r.company_id,
         r.facility_id,
         false       as is_container
    from public.roast_recipes r
   where not exists (
     select 1 from public.recipe_components rc
      where rc.recipe_id = r.recipe_id
        and rc.component_recipe_id is not null)

  union all

  -- The container itself, kept as a row so a caller can SEE one without a
  -- second query, but at share 0 so it draws no demand.
  select r.recipe_id,
         r.recipe_id,
         0::numeric,
         r.company_id,
         r.facility_id,
         true
    from public.roast_recipes r
   where exists (
     select 1 from public.recipe_components rc
      where rc.recipe_id = r.recipe_id
        and rc.component_recipe_id is not null)

  union all

  -- A child draws its parent's demand at its own share.
  --
  -- 🔴 company and facility come from the CHILD, not from the component row.
  -- `recipe_components.facility_id` is nullable, and a NULL there would drop
  -- the child out of any caller that filters by facility -- which is every
  -- caller, because the engine is per-facility.
  select rc.component_recipe_id as recipe_id,
         rc.recipe_id           as source_recipe_id,
         coalesce(rc.percentage, 0::numeric) as share,
         child.company_id,
         child.facility_id,
         false
    from public.recipe_components rc
    join public.roast_recipes child on child.recipe_id = rc.component_recipe_id
   where rc.component_recipe_id is not null;

comment on view public.recipe_demand_source is
  'Where a recipe''s demand comes from. A container (one with recipe components) has NO identity row at share 1, so it draws no demand and asks for no batches; its children draw it at their shares. One hop only.';

do $$
declare
  n_recipes int;
  n_identity int;
  n_dupes int;
  n_si int;
begin
  -- With no post-blend anywhere, the view is still the identity mapping.
  select count(*) into n_recipes from public.roast_recipes;
  select count(*) into n_identity from public.recipe_demand_source
   where share = 1 and recipe_id = source_recipe_id;
  if not exists (select 1 from public.recipe_components where component_recipe_id is not null)
     and n_identity <> n_recipes then
    raise exception 'identity mapping broke: % recipes but % identity rows', n_recipes, n_identity;
  end if;

  -- No recipe may draw its own demand twice.
  select count(*) into n_dupes from (
    select recipe_id, source_recipe_id, count(*) c
      from public.recipe_demand_source group by 1, 2 having count(*) > 1) x;
  if n_dupes > 0 then
    raise exception '% recipe/source pair(s) appear twice in recipe_demand_source', n_dupes;
  end if;

  -- A container must never carry share 1, or its demand is counted twice.
  if exists (select 1 from public.recipe_demand_source
              where is_container and share <> 0) then
    raise exception 'a container recipe is still drawing demand';
  end if;

  select count(*) into n_si from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname = 'recipe_demand_source'
     and c.reloptions @> array['security_invoker=true'];
  if n_si <> 1 then raise exception 'security_invoker missing on recipe_demand_source'; end if;
end $$;

commit;
