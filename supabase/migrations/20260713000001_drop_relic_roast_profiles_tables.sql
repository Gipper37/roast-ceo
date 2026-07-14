-- Drop the relic roast_profiles / roast_profile_nodes tables.
--
-- These were an early "roast profile" model that never got used: 0 rows across
-- every tenant. The live roast-profile page (app/roast/profiles) reads
-- roast_sessions rows flagged is_profile_template — NOT these tables — and
-- roast_log.reference_profile_id points at those template sessions, not here.
--
-- Verified unused before drop (2026-07-13, prod):
--   • roast_profiles = 0 rows, roast_profile_nodes = 0 rows
--   • no inbound FKs from any other table
--   • no view / function references them
--   • only dependencies are their own updated_at trigger + the internal
--     nodes -> profiles FK, both of which drop with the tables
--   • frontend only references them via generated database.types.ts (schema
--     mirror, regenerated) — no application code path
--
-- This does NOT affect the planned profile-keyed roast-aggregation work, which
-- keys on roast_sessions templates, not these tables.

DROP TABLE IF EXISTS public.roast_profile_nodes;  -- child (FK -> roast_profiles)
DROP TABLE IF EXISTS public.roast_profiles;       -- takes its updated_at trigger with it
