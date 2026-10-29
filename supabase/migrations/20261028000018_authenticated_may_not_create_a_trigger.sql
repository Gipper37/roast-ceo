-- `authenticated` may not create a trigger.
--
-- ── Why this is not the moot item I filed it as ──────────────────────────
--
-- The open list said "worth a look; creating a trigger also needs ownership,
-- so probably moot". That was a guess and it was wrong. Probed on prod as a
-- real `authenticated` session, in a rolled-back transaction:
--
--   create trigger zz_probe before update on public.customers
--     for each row execute function public.handle_updated_at_timestamp();
--   -> CREATE TRIGGER
--
-- 🔴 My FIRST probe named a function that does not exist, so it failed with
-- "function public.set_updated_at() does not exist" -- before any privilege
-- check ran. I nearly recorded that as confirmation of the guess. A test that
-- errors for the wrong reason is not a negative result.
--
-- ── The surface, measured on prod ────────────────────────────────────────
--
-- `authenticated` holds TRIGGER on **200 relations**: 197 of the 211 tables,
-- AND 3 views -- `monthly_consumable_stock_by_item`,
-- `product_consumables_effective`, `recipe_demand_source`. A view takes an
-- INSTEAD OF trigger, so the views are surface too, not a rounding error.
-- `revoke ... on all tables in schema public` does reach views (checked: 195r
-- + 3v -> 0 on staging), so one statement covers all 200; the verify block
-- below therefore counts EVERY relkind rather than just 'r', or it would pass
-- while a view kept the privilege.
--
-- The 14 tables that do NOT have it are a mixed bag and worth naming honestly
-- rather than as one story: `team_pin`, `provider_credentials`,
-- `customer_payment_methods`, `developer_users`,
-- `developer_impersonation_log`, `subscription_admin_log` and
-- `config_audit_log` were deliberately tightened; `ai_model_rates`,
-- `lot_code_sequence`, `roast_plan`, `roast_plan_dirty`, `roast_plan_drift`,
-- `roast_origin_plan` and the dated snapshot `_case_naming_20261004` simply
-- had their grants written narrowly when they were created. Do not read the
-- exempt set as 14 hardening decisions.
--
-- ── What it could do. 🔴 I UNDERSTATED THIS FIRST TIME ROUND ─────────────
--
-- My first draft bounded the blast radius at "attach any of 144 existing
-- trigger functions" and said it CANNOT create its own. An adversarial review
-- challenged that, and the review was right:
--
--   select has_database_privilege('authenticated', current_database(),
--                                 'TEMPORARY');   -> t
--
-- `CREATE FUNCTION pg_temp.f()` needs TEMPORARY on the DATABASE, not CREATE on
-- a schema, and TEMPORARY is granted. Measured end to end on staging as
-- `authenticated`:
--
--   create function pg_temp.zz_evil() returns trigger ...   -> CREATE FUNCTION
--   create trigger zz_probe before update on public.customers
--     for each row execute function pg_temp.zz_evil();      -> CREATE TRIGGER
--
-- So the ceiling was never "a pick from 144 vetted functions". It was
-- **arbitrary attacker-authored plpgsql running inside a BEFORE trigger on any
-- of 200 relations**, including the two it cannot even read (`invitations`,
-- `shop_invitations`), able to read and rewrite NEW/OLD on every tenant's
-- writes to that table.
--
-- 🔴 Bounded, also measured, so this is not re-reported as worse than it is:
-- the trigger takes a NORMAL dependency on the temp function
-- (`pg_depend.deptype = 'n'`, refobjid in `pg_temp_53`), so it goes when the
-- temp schema does at session end. The arbitrary-code window is one session,
-- not permanent.
--
-- The 144 figure was right for what it described and is kept with its filter
-- stated: 152 functions in `public` return `trigger`, `authenticated` holds
-- EXECUTE on 144 of them, 22 are SECURITY DEFINER and 14 of those 22 are
-- executable by `authenticated`. A SECURITY DEFINER one attached to a table of
-- the caller's choosing runs postgres-owned code on rows the caller picks, and
-- unlike the pg_temp route it SURVIVES the session.
--
-- 🔴 One worst case I named first time round was wrong and is corrected rather
-- than quietly dropped: I wrote that attaching `guard_demo_readonly` "makes
-- every write to that table raise, for every tenant". It does not.
-- `pg_get_functiondef` shows it returns the row unchanged when `auth.uid()` is
-- null and raises only for a demo identity, so it would pass ordinary tenant
-- writes straight through. Breaking a table for everyone needs the pg_temp
-- route above, not that guard.
--
-- CANNOT, measured:
--   · DROP an existing trigger: "must be owner of relation orders".
--   · DISABLE one: "must be owner of table orders".
--   · reach any of it through the API: PostgREST has no DDL verb, and on PROD
--     `anon` holds TRIGGER on ZERO relations. (On STAGING it holds 188 --
--     staging's grant surface is wider by design and never rehearses prod's
--     grants, which is why the verify block REPORTS anon instead of asserting
--     it.)
-- So the app's own guards cannot be removed, and nobody reaches any of this
-- without already executing SQL as `authenticated`. It is an AMPLIFIER, the
-- same class as the TRUNCATE revoked in 20261028000016 -- but a sharper one
-- than that was, because the pg_temp route makes the payload arbitrary.
--
-- Nothing in either repo creates, drops or disables a trigger at runtime, and
-- no migration does it as `authenticated`: migrations run as `postgres`. The
-- 235 existing triggers are unaffected -- FIRING a trigger needs no privilege
-- on it, only CREATE TRIGGER does.
--
-- ── The default privileges, and what they prove ──────────────────────────
--
-- 🔴 These matter as much as the revoke: a new table materialises the schema
-- default, and **the `t` in `arwdDxtm` is TRIGGER**, so without the second
-- statement the next migration that creates a table re-grants it.
--
-- 20261028000016 noted that a SECOND set of defaults, owned by
-- `supabase_admin`, is not ours to alter, and left it there. It is worth being
-- precise now, because `pg_default_acl` for schema `public` makes it visible on
-- both databases:
--
--   supabase_admin  authenticated=arwdDxtm   <- untouched, not ours
--   postgres        authenticated=arwdxtm    <- the D is GONE
--
-- The missing `D` is 20261028000016 working, which settles the question that
-- migration left open: the default that applies to a table OUR migrations
-- create is the `postgres`-owned one, because db push connects as `postgres`;
-- `supabase_admin`'s applies to what Supabase itself provisions. Editing the
-- postgres-owned set is the right and sufficient fix, and this takes the `t`
-- out of it the way the last one took the `D`. (So `arwdDxtm` above describes
-- the supabase_admin set and the pre-000016 state, not what the postgres set
-- reads today.)
--
-- The same table explains the environment split that nearly broke this
-- release: on prod the postgres-owned default has NO `anon` entry, while on
-- staging it reads `anon=arwdDxtm`. Hence 188 staging relations and 0 on prod.
--
-- 🔴 Scope: this covers schema `public` only. The postgres-owned default for
-- schema `storage` still reads `anon=arwdDxtm,authenticated=arwdDxtm` -- it IS
-- ours to alter, and it hands out TRIGGER and TRUNCATE on any future
-- `storage.*` table. Left alone here deliberately, because batches stay small
-- and that is a different decision; it is on the open list.
--
-- 🔴 No `set role` here, deliberately. A behavioural assertion would need one,
-- and `RESET ROLE` discards db push's own role, so CI dies recording the
-- migration after the body has committed. The behaviour was instead proven on
-- staging OUTSIDE this file, by running the revoke statement alone inside a
-- transaction that was rolled back, with CREATE TRIGGER attempted as
-- `authenticated` before it (CREATE TRIGGER) and after it (permission denied).

begin;

revoke trigger on all tables in schema public from authenticated;

-- New tables in THIS schema stop handing it out. See the scope note above.
alter default privileges in schema public revoke trigger on tables from authenticated;

do $$
declare n_trig int; n_orders int; n_anon int; leftovers text;
begin
  -- 🔴 Every relkind, not just 'r'. Three of the 200 were VIEWS, and a filter
  -- of relkind='r' would report success while they kept the privilege.
  select count(*), coalesce(string_agg(c.relname || ' (' || c.relkind::text || ')', ', '), '')
    into n_trig, leftovers
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and has_table_privilege('authenticated', c.oid, 'TRIGGER');
  if n_trig <> 0 then
    raise exception '% relation(s) still let authenticated CREATE TRIGGER: %', n_trig, leftovers;
  end if;

  -- 🔴 And the app must still work. A revoke that took the ordinary privileges
  -- with it would be a far worse outage than the thing being fixed, so they are
  -- asserted to have survived on the table the whole app reads and writes.
  select count(*) into n_orders
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'orders'
     and has_table_privilege('authenticated', c.oid, 'SELECT')
     and has_table_privilege('authenticated', c.oid, 'INSERT')
     and has_table_privilege('authenticated', c.oid, 'UPDATE');
  if n_orders <> 1 then
    raise exception 'the revoke took ordinary privileges with it -- orders is no longer readable or writable';
  end if;

  -- 🔴 anon is REPORTED, never asserted. I wrote this as
  -- `if n_anon <> 0 then raise` and it would have failed the staging push:
  -- anon holds TRIGGER on 188 relations there and 0 on prod. A verify block may
  -- assert only what its own migration CHANGES; anything else is a claim about
  -- an environment it has not seen, and can only roll back a good release.
  select count(*) into n_anon
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and has_table_privilege('anon', c.oid, 'TRIGGER');
  -- No baseline number in the message: it would be a point-in-time figure
  -- printed beside the live one it is meant to explain, and the two drift
  -- apart. The prod/staging contrast is in the header comment, which does
  -- not get re-read as a CI log line.
  raise notice 'anon holds TRIGGER on % relation(s) in this database (0 expected on prod; staging grants are wider by design)', n_anon;

  raise notice 'authenticated can no longer create a trigger in public, and new tables there will not grant it';
end $$;

commit;
