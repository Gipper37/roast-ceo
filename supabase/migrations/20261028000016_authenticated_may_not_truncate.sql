-- `authenticated` may not TRUNCATE, and new tables stop granting it.
--
-- ── What is true today ───────────────────────────────────────────────────
--
-- `authenticated` holds TRUNCATE on 188 public tables, including orders,
-- order_details, customers, products, product_groups, payment_transactions,
-- roaster_bank_accounts and team.
--
-- 🔴 RLS DOES NOT FILTER TRUNCATE. Every tenant-scoping policy in this database
-- is written for SELECT/INSERT/UPDATE/DELETE. A TRUNCATE is not row-level work
-- and is never filtered by a row-level rule, so the one privilege that ignores
-- multi-tenancy entirely is the one that was granted on nearly every table.
--
-- ── Honest about reachability ────────────────────────────────────────────
--
-- This is NOT directly reachable through the app today, and it should not be
-- written up as though it were. PostgREST builds SELECT, INSERT, UPDATE, DELETE
-- and function calls; it has no TRUNCATE verb, and `anon` holds TRUNCATE on
-- ZERO tables (checked). Nobody is handed a Postgres connection as
-- `authenticated`.
--
-- What it is, precisely: an amplifier. Any future bug that executes attacker
-- influenced SQL as `authenticated` -- a SECURITY INVOKER function building
-- dynamic SQL, an injection in a function body -- turns from "read or write
-- some rows in my own tenant" into "empty this table for every tenant at once,
-- in one statement, with no row-level rule consulted". It is also a privilege
-- nothing in this product has ever used: migrations and the seed run as
-- postgres, not as authenticated.
--
-- It is here because it is a Supabase default, not because anyone chose it.
--
-- ── Why the default privileges matter as much as the revoke ──────────────
--
-- 🔴 Revoking alone would have fixed today and nothing else. The schema's
-- default ACL grants `arwdDxtm` on new tables to authenticated, and the `D` in
-- that string IS truncate -- so the next migration that creates a table would
-- have granted it again, silently, and this fix would rot within a week.
--
-- Only the role that granted a default can alter it. The `postgres` default is
-- ours to change and is changed below. A second default owned by
-- `supabase_admin` also exists and is NOT ours to touch; it is why the verify
-- block below asserts the OUTCOME on real tables rather than asserting that no
-- default anywhere mentions truncate.

begin;

revoke truncate on all tables in schema public from authenticated;

-- New tables created by us stop handing it out.
alter default privileges in schema public revoke truncate on tables from authenticated;

do $$
declare n_trunc int; n_select int;
begin
  select count(*) into n_trunc
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and has_table_privilege('authenticated', c.oid, 'TRUNCATE');
  if n_trunc <> 0 then
    raise exception '% table(s) still let authenticated TRUNCATE', n_trunc;
  end if;

  -- 🔴 And the app must still work. A revoke that took SELECT with it would be
  -- a far worse outage than the thing being fixed, so the ordinary privileges
  -- are asserted to have survived on a table the whole app reads.
  select count(*) into n_select
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'orders'
     and has_table_privilege('authenticated', c.oid, 'SELECT')
     and has_table_privilege('authenticated', c.oid, 'INSERT')
     and has_table_privilege('authenticated', c.oid, 'UPDATE');
  if n_select <> 1 then
    raise exception 'the revoke took ordinary privileges with it -- orders is no longer readable or writable';
  end if;

  raise notice 'authenticated can no longer TRUNCATE anything, and new tables will not grant it';
end $$;

commit;
