-- ============================================================================
-- INCIDENT FIX (2026-06-22): drop obsolete roast_sessions.charge_weight_id FK
-- ----------------------------------------------------------------------------
-- The charge-weight picker became FREE-ENTRY (writes a numeric lbs string, e.g.
-- "25") — charge_weight_options is no longer the source for it (kept only for
-- the roaster-unit max/min LFP limits). roast_log.charge_weight is free text and
-- accepted the numeric value fine, but roast_sessions.charge_weight_id still had
-- a FK -> charge_weight_options(id). So CHARGING a roast worked (writes
-- roast_log) but ENDING it (which inserts a roast_session) threw:
--   violates foreign key constraint "roast_sessions_charge_weight_id_fkey"
--   Key (charge_weight_id)=(25) is not present in table "charge_weight_options".
-- The profiler End-save rolled back, so the roast appeared stuck "roasting
-- forever" (the in-progress state lives in client localStorage). Social Hour USA
-- is the only profiler user, so they were the only company affected.
--
-- charge_weight_id is now free text like roast_log.charge_weight. Applied as a
-- direct prod hotfix during the incident; this migration records it + applies it
-- to staging. Idempotent (IF EXISTS).
-- ============================================================================

BEGIN;

ALTER TABLE public.roast_sessions
    DROP CONSTRAINT IF EXISTS roast_sessions_charge_weight_id_fkey;

COMMIT;
