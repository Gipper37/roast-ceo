-- Drop the five-argument pack_draw_plan.
--
-- 20260920000001 added p_pin_roast_log_id, and CREATE OR REPLACE with a new
-- signature does not replace anything -- it creates a second function beside
-- the first. Two overloads is not a tidiness problem: PostgREST resolves an
-- RPC by name and refuses an ambiguous candidate set, so the next call from
-- the app could fail with "Could not choose the best candidate function".
--
-- It is also the ACL trap this project has been bitten by before: a new
-- signature carries its own grants, so revoking on one leaves the other
-- reachable. Dropping the old one closes both.
--
-- The single caller (lib/food-safety/packActions.ts) passes named arguments,
-- which bind to the six-argument version with p_pin_roast_log_id defaulting
-- to null, so no application change is needed.

begin;

drop function if exists public.pack_draw_plan(text, text, numeric, integer, text);

commit;
