-- ============================================================================
-- Add roast_log_recipes join table for honest multi-recipe attribution.
--
-- Background: LFQ now aggregates post-blend roasts per origin so Chocolate
-- going into 5 different post-blend recipes collapses into ONE Chocolate
-- batch (matching the Projected Left card's logic). The catch: the
-- existing roast_log.recipe_id is a single FK — when one Chocolate roast
-- is destined for 5 recipes, we can't honestly attribute it via that one
-- column. Today's stopgap is "primary contributor wins" (Path A from
-- prior conversation), which is a small data lie.
--
-- This migration adds a `roast_log_recipes` join table:
--   roast_log_id × recipe_id, with lbs_allocated for the per-recipe slice.
--
-- Insert pattern:
--   • Single Origin / Pre-Blend → 1 join row (1:1 with roast_log.recipe_id)
--   • Post-Blend aggregated     → N join rows, one per destination recipe
--
-- The roast_log.recipe_id column is preserved (kept pointing at the
-- primary contributor) for back-compat with existing views / functions /
-- reports. New consumers JOIN through this table for the full picture.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS roast_log_recipes (
  roast_log_recipe_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  roast_log_id        text NOT NULL REFERENCES roast_log(roast_log_id) ON DELETE CASCADE,
  recipe_id           text NOT NULL REFERENCES roast_recipes(recipe_id),
  /** lbs of the roasted batch destined for this recipe. For single-
   *  origin / pre-blend rows this is the full charge_weight_lbs. For
   *  post-blend aggregated rows it's the recipe's percentage share. */
  lbs_allocated       numeric NOT NULL,
  created_at          timestamp with time zone DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_roast_log_recipes_log
  ON roast_log_recipes(roast_log_id);
CREATE INDEX IF NOT EXISTS idx_roast_log_recipes_recipe
  ON roast_log_recipes(recipe_id);
-- Composite for "all recipes for this log" lookups.
CREATE INDEX IF NOT EXISTS idx_roast_log_recipes_log_recipe
  ON roast_log_recipes(roast_log_id, recipe_id);

COMMENT ON TABLE roast_log_recipes IS
  'Many-to-many between roast_log and roast_recipes. Lets a single '
  'aggregated post-blend roast row be attributed to multiple destination '
  'recipes honestly (Chocolate batch going into NOLA + Rubix + Et Al). '
  'For single-origin / pre-blend, this is a 1:1 join.';
COMMENT ON COLUMN roast_log_recipes.lbs_allocated IS
  'Roasted lbs (post-loss) destined for this recipe. Sums to roughly '
  'roast_log.roasted_weight across all join rows for a given log id.';

-- Backfill: 1:1 join rows for every existing roast_log row with a recipe_id
-- THAT POINTS TO A LIVE roast_recipes row. Some legacy roast_log rows have
-- stale recipe_id values referencing recipes that have since been deleted
-- (no FK existed on the old column to enforce referential integrity);
-- those rows are left without a join entry so the new FK on this table
-- holds.
INSERT INTO roast_log_recipes (roast_log_id, recipe_id, lbs_allocated)
SELECT rl.roast_log_id, rl.recipe_id, COALESCE(rl.roasted_weight, rl.charge_weight_lbs, 0)
FROM roast_log rl
WHERE rl.recipe_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM roast_recipes rr WHERE rr.recipe_id = rl.recipe_id)
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  total int;
  with_join int;
BEGIN
  SELECT COUNT(*) INTO total FROM roast_log WHERE recipe_id IS NOT NULL;
  SELECT COUNT(DISTINCT roast_log_id) INTO with_join FROM roast_log_recipes;
  RAISE NOTICE 'roast_log_recipes backfilled: % logs with recipes, % logs joined', total, with_join;
END $$;

COMMIT;
