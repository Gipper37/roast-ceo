-- anon may not open a socket from the database.
--
-- ── What is live right now ───────────────────────────────────────────────
--
-- `dblink` is installed in `public` on production and `anon` can execute it.
-- Proven on prod, not inferred:
--
--     set local role anon;
--     select public.dblink_connect('probe2','host=127.0.0.1 port=1 ... password=x');
--     -> "could not establish connection ... Connection refused"
--
-- The function RAN TO COMPLETION as `anon`. The connection failed because
-- nothing is listening on that port, not because anyone stopped it. So an
-- anonymous caller -- no login, no tenant, the key that is in the browser --
-- can make the production database server open an outbound TCP connection to
-- any host and port it likes. That is SSRF from inside Supabase's network, and
-- a ready-made exfiltration channel for any future SQL-injection or
-- SECURITY DEFINER bug: the data never has to come back through PostgREST.
--
-- The one thing that stops the worst case: without a password dblink refuses
-- non-superusers ("password or GSSAPI delegated credentials required"), so the
-- loopback-trust-to-superuser path is closed. The outbound socket is not.
--
-- 🔴 REVOKING IS NOT ENOUGH. `anon` holds EXECUTE on these functions TWICE:
-- the default PUBLIC grant that comes with the extension, and an explicit
-- grant to `anon` on top of it. Revoking from `anon` alone leaves PUBLIC, and
-- `anon` is a member of PUBLIC. Dropping the extension removes the functions,
-- both grants and the question.
--
-- ── Why dropping it is safe, measured today ──────────────────────────────
--
--   our own function bodies mentioning dblink ...... 0
--     (41 do, and all 41 BELONG TO the extension -- checked against pg_depend
--      deptype 'e', not by reading names)
--   migrations referencing dblink .................. 0
--   non-extension objects depending on it .......... 0
--   foreign servers using dblink_fdw ............... 0
--     (the wrapper exists because the extension ships it; nothing uses it)
--
-- 🔴 The code "references" are generated types and NOT usage. The earlier note
-- said zero and I found eighteen, which looked like a contradiction until I
-- read them: every one is in lib/supabase/database.types.ts, a file generated
-- FROM the database. There is a second generated types file the note did not
-- name. Grep both before concluding either way.
--
-- Nothing in this product has ever called dblink. It is on by default, not by
-- decision.

begin;

drop extension if exists dblink;

do $$
declare n_ext int; n_fn int; n_fdw int;
begin
  select count(*) into n_ext from pg_extension where extname = 'dblink';
  if n_ext <> 0 then raise exception 'dblink is still installed'; end if;

  -- The functions and the wrapper go with it. Asserted rather than assumed,
  -- because the whole point was that a revoke would have left them reachable.
  select count(*) into n_fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'dblink%';
  if n_fn <> 0 then raise exception '% dblink function(s) survived the drop', n_fn; end if;

  select count(*) into n_fdw from pg_foreign_data_wrapper where fdwname = 'dblink_fdw';
  if n_fdw <> 0 then raise exception 'dblink_fdw survived the drop'; end if;

  -- 🔴 Shape, not this database's rows. `if exists` above means an environment
  -- that never had it passes here too, which is what keeps the rehearsal honest.
  raise notice 'dblink is gone: no functions, no wrapper, nothing for anon to execute';
end $$;

commit;
