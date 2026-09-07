-- Drop roast_sessions.roast_log_id: a column that was never written.
--
-- The link between a roast and its session runs the OTHER way — roast_log.session_id
-- points at roast_sessions.session_id, and that is what saveRoastSession writes and
-- what every reader follows. This column was the mirror image and nothing ever
-- populated it: 0 of 10,478 rows on prod, 0 of 11 on staging, including everything
-- that predates the 2026-09-05 changes.
--
-- Proven unread before dropping (owner: "if we don't need it get rid of it"):
--   * every INSERT into roast_sessions in the DB — process_staged_imports (both
--     branches), process_artisan_staged_imports — omits it; set_roast_measured_weight
--     updates by session_id. No view, trigger or RLS policy names it.
--   * the frontend never selects or filters it; only the generated type files
--     carry the FK, and they are updated in the same change.
--   * the only objects that depend on it are its own partial index
--     (idx_roast_sessions_log) and its own FK (roast_sessions_roast_log_id_fkey),
--     both of which go with the column.
--
-- Found while emulating the July deploy-skew save failure in the roast simulator:
-- an assertion counted sessions by this column and got 0 for a roast that had
-- plainly saved. A dormant FK that looks like the link but is not one is exactly
-- the trap a future traceability feature would fall into.

alter table public.roast_sessions
  drop column if exists roast_log_id;   -- takes idx_roast_sessions_log and the FK with it
