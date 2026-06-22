-- ============================================================================
-- Artisan parity: import the roast-phase telemetry we currently drop
-- ----------------------------------------------------------------------------
-- The Artisan download.json roast objects carry full phase telemetry per batch
-- (turning point, dry-end, first crack, development, roast loss) that the
-- importer never parsed. roast_sessions already holds auc/auc_base/
-- ambient_humidity/ambient_temp/target_dev_*; add the ACTUAL measured phases so
-- imported roasts show dev time/ratio, first crack, etc. (was blank).
--
-- Units: Artisan exports temps in °C (verified: MCR drop temps ~227-241 = °C).
-- The importer converts °C→°F to match STRATA's convention (live Loring + .alog
-- curves are stored °F), so these line up with the temperature curve. Times are
-- seconds-from-charge; loss + dev_ratio are already percentages; fc_ror is °/min
-- (delta-converted ×9/5). target_dev_secs/target_dev_pct stay the TARGETs; these
-- are the ACTUALs.
-- ============================================================================

BEGIN;

ALTER TABLE public.roast_sessions
    ADD COLUMN IF NOT EXISTS tp_time_secs      numeric,  -- turning point (s from charge)
    ADD COLUMN IF NOT EXISTS tp_temp           numeric,  -- turning point BT (°F)
    ADD COLUMN IF NOT EXISTS dry_end_time_secs numeric,  -- dry-end / yellowing (s)
    ADD COLUMN IF NOT EXISTS dry_end_temp      numeric,  -- dry-end BT (°F)
    ADD COLUMN IF NOT EXISTS fc_time_secs      numeric,  -- first crack start (s)
    ADD COLUMN IF NOT EXISTS fc_temp           numeric,  -- first crack BT (°F)
    ADD COLUMN IF NOT EXISTS fc_ror            numeric,  -- RoR at first crack (°F/min)
    ADD COLUMN IF NOT EXISTS dev_time_secs     numeric,  -- ACTUAL development time (s)
    ADD COLUMN IF NOT EXISTS dev_ratio_pct     numeric,  -- ACTUAL development ratio (%)
    ADD COLUMN IF NOT EXISTS roast_loss_pct    numeric;  -- green→roasted shrinkage (%)

COMMIT;
