-- Re-apply the PUBLIC EXECUTE revoke on save_shipment_lines (pass-1 audit
-- finding, owner-approved 2026-09-05).
--
-- 20260704000001 revoked PUBLIC on the 5-arg function. 20260804000001 then
-- extended it "in place" with a defaulted 6th parameter — which in Postgres
-- is a NEW function signature, and a new signature gets a FRESH default ACL
-- including PUBLIC EXECUTE. Neither it nor 20260804000002 (which dropped
-- the old, still-revoked overload) re-applied the revoke, so the hardening
-- silently lapsed. Mitigated in practice (SECURITY INVOKER + the function's
-- first statement raises 42501 unless the caller's company matches) — this
-- restores the defense-in-depth layer.
--
-- LESSON (recorded in the audit ledger): every in-place RPC extension that
-- adds a parameter creates a new signature — re-apply its REVOKEs.

begin;

revoke execute on function public.save_shipment_lines(text, text, text, jsonb, text[], boolean) from public;

commit;
