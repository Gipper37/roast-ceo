-- Drop roast_sessions.created_by: a column that was never written.
--
-- It was meant to record who saved a roast. It never did: 0 of 10,478 rows on prod
-- carry a value, across every session from 2026-04-13 to 2026-09-03. Nothing writes
-- it. The three `created_by` writes in the roast area of the frontend
-- (S/app/app/(app)/roast/actions.ts) are on roast_stock_log and recipe_weekly_targets,
-- not here.
--
-- Proven unread before dropping (owner, 2026-09-07: "yeah drop it."):
--   * no RLS policy names it — roast_sessions has exactly one policy,
--     tenant_company_access, on company_id.
--   * no index, no view, no trigger, no function body in the public schema
--     references it (checked against prod, not schema.sql).
--   * the frontend never selects, filters or writes it; only the generated type
--     files carry it, and they are updated in the same change.
--   * the only object that goes with it is its own FK,
--     roast_sessions_created_by_fkey -> auth.users(id) ON DELETE SET NULL.
--
-- Why not fill it forward instead: an auth.users uuid is the wrong shape for the
-- record this needs to become. 21 CFR 117.305 wants the person who performed the
-- operation, and that record has to survive them leaving the company and their
-- login being deleted — which ON DELETE SET NULL would silently erase. The HACCP
-- operator-identity work stamps roasted_by_team_member (a team_members FK) plus a
-- name snapshot instead. Keeping a dormant auth-uuid column beside it would be a
-- second, weaker answer to the same question, which is how the roast_log_id trap
-- got built (dropped in 20260906000005 for the same reason).

alter table public.roast_sessions
  drop column if exists created_by;   -- takes roast_sessions_created_by_fkey with it
