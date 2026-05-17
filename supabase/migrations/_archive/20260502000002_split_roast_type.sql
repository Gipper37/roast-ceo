-- ============================================================================
-- Split roast_recipes.roast_type from the combined 'Single Origin/Post-Blend'
-- value into two distinct values: 'Single Origin' and 'Post-Blend'.
--
-- Rationale: the combined value forced UI dropdowns to be ambiguous and
-- prevented type-aware behaviour (e.g. enforcing 1 component @ 100% for
-- single-origin recipes). After this split:
--   • Single Origin = exactly 1 component @ 100%
--   • Post-Blend    = 2+ components, blended after roasting
--   • Pre-Blend     = 2+ components, charged blended into the roaster
--
-- Backend impact: NONE. All 7 functions and 2 views that touch roast_type
-- compare ONLY against 'Pre-Blend' (either `= 'Pre-Blend'` or
-- `IS DISTINCT FROM 'Pre-Blend'`). Splitting the non-Pre-Blend bucket
-- doesn't change any of those branches — both new values fall through
-- the IS DISTINCT FROM check identically to the old combined value.
--
-- Frontend impact: dropdown options + the default value when creating
-- a new recipe. Updated in same PR as this migration.
-- ============================================================================

BEGIN;

-- 1. Backfill — split the existing combined value based on component count.
--    Recipes with 1 component → Single Origin.
--    Recipes with 2+ components → Post-Blend.
--    Recipes with 0 components are an oddity (manually-created shells); we
--    default them to Single Origin so creation flows can continue. The user
--    can fix them via the Recipes UI.
UPDATE roast_recipes rr
SET roast_type = CASE
  WHEN (
    SELECT COUNT(*) FROM recipe_components rc
    WHERE rc.recipe_id = rr.recipe_id
  ) >= 2 THEN 'Post-Blend'
  ELSE 'Single Origin'
END
WHERE roast_type = 'Single Origin/Post-Blend';

-- 2. Sanity check: surface a notice with the resulting distribution. Useful
--    when reviewing the migration log. (Doesn't fail the migration on its
--    own — the CHECK constraint below catches anything bogus.)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT roast_type, COUNT(*) AS n
    FROM roast_recipes
    GROUP BY roast_type
    ORDER BY roast_type
  LOOP
    RAISE NOTICE 'roast_type % → % rows', r.roast_type, r.n;
  END LOOP;
END $$;

-- 3. CHECK constraint pinning roast_type to the three allowed values.
--    NOT VALID first so we can verify before enforcing — though the backfill
--    above should leave the table fully clean. We immediately validate.
ALTER TABLE roast_recipes
  ADD CONSTRAINT roast_recipes_roast_type_check
  CHECK (roast_type IN ('Single Origin', 'Post-Blend', 'Pre-Blend'))
  NOT VALID;

ALTER TABLE roast_recipes VALIDATE CONSTRAINT roast_recipes_roast_type_check;

COMMIT;
