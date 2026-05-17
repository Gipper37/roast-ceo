-- 20260503000004_fix_lbs_allocated_semantics.sql
-- Correct the backfilled lbs_allocated values in roast_log_recipes.
--
-- BUG
--   The original backfill (20260503000001) populated
--   roast_log_recipes.lbs_allocated using ROASTED weight (~18.5 lb avg)
--   instead of GREEN charge weight (~22 lb avg).
--
--   The newly-rewritten roast_detail_by_blend view (20260503000003)
--   reads roasted_weight × (lbs_allocated / charge_weight_lbs) to
--   compute per-recipe roasted contribution. For single-recipe rows,
--   that ratio MUST be 1.0 — meaning lbs_allocated == charge_weight_lbs.
--   With the wrong backfill, the ratio came out ~0.84, causing
--   total_roasted to under-count by ~16%, which collapsed
--   in_stock_roasted (717 → 89 in observed test) and inflated
--   roasted_left / Projected Left.
--
-- FIX
--   For all rows in roast_log_recipes, reset lbs_allocated to the
--   matching roast_log.charge_weight_lbs. This is correct for every
--   row currently in the table since LFQ has not yet emitted any
--   multi-recipe boundary batches (single recipe per batch → the join
--   row's lbs_allocated == the full batch's green weight).
--
-- INVARIANT (going forward)
--   lbs_allocated represents GREEN lbs of that batch attributed to a
--   given recipe. For a single-recipe batch: lbs_allocated ==
--   charge_weight_lbs. For a multi-recipe boundary batch:
--   SUM(lbs_allocated) across all join rows for that batch ==
--   charge_weight_lbs.

BEGIN;

UPDATE roast_log_recipes rlr
SET lbs_allocated = rl.charge_weight_lbs
FROM roast_log rl
WHERE rlr.roast_log_id = rl.roast_log_id
  AND rl.charge_weight_lbs IS NOT NULL
  AND rl.charge_weight_lbs > 0;

DO $$
DECLARE
  v_total integer;
  v_avg numeric;
  v_min numeric;
  v_max numeric;
BEGIN
  SELECT COUNT(*), AVG(lbs_allocated), MIN(lbs_allocated), MAX(lbs_allocated)
  INTO v_total, v_avg, v_min, v_max
  FROM roast_log_recipes;
  RAISE NOTICE 'roast_log_recipes after fix: % rows, avg lbs_allocated = %, min = %, max = %',
    v_total, v_avg, v_min, v_max;
END $$;

COMMIT;
