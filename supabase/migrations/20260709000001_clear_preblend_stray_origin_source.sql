-- Clear the stray single origin_id + coffee_source_id on PRE-BLEND roast_log rows (MCR).
--
-- A pre-blend's attribution is planned_lots + recipe_components; its single
-- origin_id / coffee_source_id are meaningless. The profiler was stamping them
-- with the carried-over loaded single-origin source (e.g. "Mexico Esmeralda
-- Decaf", unrelated to the blend), which surfaced as a wrong "coffee group"
-- (e.g. "Lokelani Blend · Decaf"). The charge/DROP code paths were fixed to stop
-- stamping these (commit 66078c1); this backfills the ~349 existing rows.
--
-- CONSUMPTION-SAFE — verified on prod:
--   * The deduct engine ignores these fields for pre-blends: _roast_affected_origins
--     uses recipe_components, and deduct_one_roast prefers planned_lots. Actual
--     consumption (roast_log_lot_consumption) was always correct (Brazil/Chocolate
--     etc., never the stray Decaf).
--   * Every affected row is at/before its component origin's most recent count
--     (0 rows after count), so its consumption sits in the PRESERVED pre-anchor
--     window and is never re-derived.
--   * This UPDATE touches only roast_log.origin_id/coffee_source_id — it does NOT
--     touch roast_log_lot_consumption. With both recompute triggers deferred, the
--     consumption + valuation caches are byte-for-byte unchanged. No reconcile.
--
-- Scoped to MCR (company 9ShiyDAXhV) — the only tenant verified pre-anchor-safe.
-- The display fix (isPreBlendRecipe) already hides the stray group for every
-- tenant, so this is data hygiene, not a user-visible change.

BEGIN;

-- Metadata-only, provably no consumption change (see header): skip the per-row
-- lot recompute + valuation replay so 349 rows don't trigger 349 no-op replays.
SET LOCAL app.defer_lot_recompute = 'true';
SET LOCAL app.defer_lot_valuation = 'true';

UPDATE public.roast_log rl
   SET origin_id = NULL,
       coffee_source_id = NULL
  FROM public.roast_recipes rr
 WHERE rr.recipe_id = rl.recipe_id
   AND rr.roast_type = 'Pre-Blend'
   AND rl.facility_id IN (
     SELECT facility_id FROM public.facilities WHERE company_id = '9ShiyDAXhV'
   )
   AND (rl.origin_id IS NOT NULL OR rl.coffee_source_id IS NOT NULL)
   -- Defensive: never touch closed-period rows (the closed-period guard would
   -- block the UPDATE anyway; verified 0 such rows exist).
   AND rl.roast_date > DATE '2026-04-30';

COMMIT;
