-- ============================================================
-- Add external_roast_id column to roast_log
-- ============================================================
-- Stores the source system's stable roast identifier (e.g. Artisan's
-- `roast_id` / `roastUUID`) so the same physical roast can be matched
-- across import surfaces:
--
--   1. Artisan Plus `download.json` library import lands the row first
--      (header data: charge/drop temps, AUC, humidity, blend), stamping
--      external_roast_id from the JSON's `roast_id` field.
--   2. A later `.alog` import (same UUID, carried as `roastUUID` in the
--      file) finds the existing row by external_roast_id and attaches
--      the curve (roast_temp_nodes + roast_events) to the existing
--      session_id — no duplicate roast_log row gets created.
--
-- Nullable: only platform imports populate it; native STRATA roasts
-- and Roastmaster imports stay NULL.
--
-- Partial index for fast lookup during alog cross-link without bloating
-- the table for the (very common) NULL case.
-- ============================================================

ALTER TABLE public.roast_log
  ADD COLUMN IF NOT EXISTS external_roast_id text;

CREATE INDEX IF NOT EXISTS idx_roast_log_external_roast_id
  ON public.roast_log (external_roast_id)
  WHERE external_roast_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
