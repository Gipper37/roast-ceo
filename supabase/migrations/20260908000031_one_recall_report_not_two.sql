-- Adding the date range created an OVERLOAD, not a replacement.
--
-- 20260908000030 used `create or replace` with two extra defaulted arguments,
-- which in Postgres makes a SECOND function rather than replacing the first.
-- Every existing four-argument call then fails:
--   ERROR: function public.recall_report(unknown, text, unknown, unknown) is not unique
--
-- This is the exact hazard the release audit flagged as a category and I then
-- walked into. Drop the old signature so there is one recall_report, and
-- re-state its grants — a new signature does not inherit the old one's ACL, and
-- forgetting that is how save_shipment_lines ended up PUBLIC-EXECUTE for two
-- months in August.

begin;

drop function if exists public.recall_report(text, text, text, text);

revoke all on function public.recall_report(text, text, text, text, date, date) from public, anon;
grant execute on function public.recall_report(text, text, text, text, date, date) to authenticated;

commit;
