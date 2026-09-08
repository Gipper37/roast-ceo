-- MCR roast re-attribution (2026-06-24)
-- Single-origin-recipe roasts whose roast_log.origin_id is a stale/archived origin
-- after the flavor-group consolidation. STRATA attributes single-origin usage via
-- roast_log.origin_id, so these left the correct consolidated group with 0 usage/par.
-- Blend roasts attribute via recipe_components (already correct) and are NOT touched.
-- Rule: a roast whose recipe has exactly one component group must carry that group as
-- origin_id. 40 rows / 5 mappings:
--   Mexico->Organic(19,1111lb), Peru->Organic(17,1014lb), Maui->Maui Moka(2,72lb),
--   El Salvador->Fruit(1,48lb), Papua New Guinea->Pacific Peaberry(1,48lb).
-- Snapshot: scripts/mcr_roast_reattribution_snapshot_2026-06-24.tsv (rollback record).
WITH sc AS (
  SELECT recipe_id, min(coffee_item) AS grp
  FROM recipe_components
  GROUP BY recipe_id
  HAVING count(DISTINCT coffee_item) = 1)
UPDATE roast_log rl
   SET origin_id = sc.grp, updated_at = now()
  FROM sc
 WHERE rl.recipe_id = sc.recipe_id
   AND rl.company_id = '9ShiyDAXhV'
   AND rl.origin_id IS DISTINCT FROM sc.grp;

-- Recompute usage/par for all MCR active groups (nudge fires trg_recalc_coffee_on_nudge,
-- which recomputes daily_usage_lbs; par/restock recompute follows the same path).
UPDATE coffee_inventory
   SET updated_at = now()
 WHERE facility_id = '5cc581b9-2803-42c2-98de-0ba16ae42f8e';
