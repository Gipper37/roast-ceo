-- ============================================================
-- Add AUC + AUC_base columns to roast_sessions
-- ============================================================
-- AUC (Area Under the Curve) = integrated area under the bean
-- temperature curve over time, above a baseline temp (default 100°C).
-- A single number summarizing total thermal energy delivered to the
-- beans during a roast — useful for profile matching, batch
-- consistency, and comparing roasts whose endpoints look identical
-- but whose curve shapes differ.
--
-- Both columns nullable: existing manual roasts won't have these
-- (AUC requires curve data), and only platform imports (Artisan,
-- future others) will populate them.
--
-- auc_base records what baseline temp the AUC was calculated against
-- so an analyst can correctly compare two AUC values that may have
-- been calculated relative to different baselines.
-- ============================================================

ALTER TABLE public.roast_sessions
  ADD COLUMN IF NOT EXISTS auc      numeric,
  ADD COLUMN IF NOT EXISTS auc_base numeric;

NOTIFY pgrst, 'reload schema';
