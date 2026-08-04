-- Drop the 5-argument save_shipment_lines. It is an accidental overload, and it
-- is breaking production right now.
--
-- WHAT I GOT WRONG IN 20260804000001. That migration set out to extend
-- save_shipment_lines IN PLACE with a defaulted p_allow_duplicate_lot, and its
-- own comment says overloading must be avoided precisely because PostgREST
-- cannot choose between same-named functions. But CREATE OR REPLACE only
-- replaces a function of the SAME signature — adding a parameter changes the
-- signature, so Postgres created a second function and left the original in
-- place. The migration did the exact thing it was written to prevent.
--
-- THE DAMAGE. PostgREST resolves by parameter name, and a 5-argument call now
-- matches both candidates:
--
--   POST /rest/v1/rpc/save_shipment_lines {5 params}
--   -> 300  PGRST203  "Could not choose the best candidate function between:
--            public.save_shipment_lines(p_shipment_id => text, ...5),
--            public.save_shipment_lines(p_shipment_id => text, ...6)"
--
-- Five parameters is exactly what the deployed frontend sends, so every save
-- from the Edit Shipment modal has been failing since 20260804000001 landed.
--
-- THE FIX. Drop the 5-argument version. The 6-argument one covers every caller:
-- p_allow_duplicate_lot defaults to false, so a 5-parameter request resolves to
-- it unambiguously and behaves exactly as before. Ordering is safe in both
-- directions — old clients keep working the moment this lands, and the new
-- client works whether or not it has been promoted yet.
--
-- Verified over the REST path, not just psql: PGRST203 is a PostgREST-layer
-- error that psql never sees, which is why the SQL-only check on the last
-- migration came back clean.

begin;

drop function if exists public.save_shipment_lines(
  p_shipment_id text,
  p_facility_id text,
  p_company_id text,
  p_lines jsonb,
  p_delete_ids text[]
);

commit;
