-- Recipe-level reference profile for PRE-BLEND recipes.
--
-- A pre-blend roasts all its components together as ONE batch on ONE curve, so
-- a per-component reference profile (recipe_components.reference_profile_session_id,
-- migration 20260713000002) is contradictory data for a pre-blend — the charge
-- path already collapsed N component links down to the highest-percentage one.
-- Model that reality directly: give the RECIPE a single profile-of-record.
--
-- Scope of use:
--   • Pre-Blend    → this recipe-level column is the profile (charge-time
--                    auto-load + fallback profile-of-record).
--   • Single-Origin→ keeps its single component's link (one component == recipe
--                    level; no planner change needed).
--   • Post-Blend   → keeps per-component links (the only case where per-component
--                    roast-sharing across recipes is physically real).
--
-- Nullable; ON DELETE SET NULL mirrors the component-level FK so deleting a
-- profile template quietly unlinks rather than blocking.

ALTER TABLE public.roast_recipes
  ADD COLUMN IF NOT EXISTS reference_profile_session_id text
    REFERENCES public.roast_sessions(session_id) ON DELETE SET NULL;

-- Backfill existing PRE-BLEND recipes from the highest-percentage component that
-- carries a link — the exact profile the charge path was already collapsing to —
-- so linked pre-blends keep their profile-of-record at the recipe level. (No-op
-- for tenants with no linked pre-blend components, e.g. MCR today: 0 links.)
UPDATE public.roast_recipes r
SET reference_profile_session_id = sub.reference_profile_session_id
FROM (
  SELECT DISTINCT ON (rc.recipe_id)
         rc.recipe_id,
         rc.reference_profile_session_id
  FROM public.recipe_components rc
  WHERE rc.reference_profile_session_id IS NOT NULL
  ORDER BY rc.recipe_id, rc.percentage DESC NULLS LAST
) sub
WHERE r.recipe_id = sub.recipe_id
  AND r.roast_type = 'Pre-Blend'
  AND r.reference_profile_session_id IS NULL;

COMMENT ON COLUMN public.roast_recipes.reference_profile_session_id IS
  'Recipe-level linked reference profile — the profile-of-record for a PRE-BLEND (one curve for the whole blend). Single-origin uses its lone component''s link; post-blend uses per-component links. Charge-time auto-load + fallback.';
