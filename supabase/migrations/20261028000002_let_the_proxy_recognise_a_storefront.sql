-- Let the proxy recognise a storefront, so a customer lands on the shop's login.
--
-- ── The measurement ──────────────────────────────────────────────────────
--
-- On production, right now:
--     https://www.strataroast.com/mauicoffee              -> 307 /login
--     https://www.strataroast.com/mauicoffee/pay/INV-x?t=  -> 307 /login?t=...
--
-- A wholesale customer who opens their roaster's shop is handed the STRATA
-- STAFF login. Not their shop's branded login: ours.
--
-- ── Why, and why nobody saw it ───────────────────────────────────────────
--
-- lib/supabase/middleware.ts has had the right behaviour written into it all
-- along. On an unauthenticated request to a gated path it takes the first path
-- segment and asks whether it is a shop:
--
--     const { data: shop } = await supabase
--       .from('shop_config').select('slug').eq('slug', firstSeg).maybeSingle()
--     if (shop) target = `/${firstSeg}/login`
--
-- That client is built with the ANON key, and the request has no session, so
-- the query runs as `anon`. Measured on production:
--
--     set role anon; select count(*) from public.shop_config;
--     ERROR:  permission denied for table shop_config
--
-- `anon` holds NO grant on shop_config and all four of its policies are
-- {authenticated}. So the lookup has never once succeeded on production. And
-- because the destructure keeps only `data` and drops `error`, a permission
-- denial is indistinguishable from "no such shop": it silently falls through to
-- the staff login, which is the branch an operator would read as correct.
--
-- 🔴 THIS IS THE STAGING/PROD GRANT TRAP, EXACTLY AS WRITTEN DOWN. Staging's
-- anon surface is wide open (1295 tables; production's is 2), so this code
-- works everywhere it was tried and fails only where it matters. A migration
-- rehearsal proves that SQL APPLIES, never that production's grants admit it.
--
-- ── Why a function and not a grant on the table ──────────────────────────
--
-- `grant select on shop_config to anon` would answer the question and hand over
-- the rest of the row with it: payments_enabled, retail_enabled, accent colours,
-- logo urls, facility_id, and every future column anybody adds to that table,
-- to the entire internet. The proxy needs one bit.
--
-- So: a function that returns that one bit and nothing else. What it discloses
-- is whether a given string is a storefront slug, which is already public --
-- the slug is in the URL, printed on invoices and in every emailed pay link.
-- It cannot be used to read a shop's settings, to list the shops, or to learn
-- anything about one whose slug you have not already guessed.
--
-- 🔴 It takes the slug and returns a boolean. It deliberately does NOT return
-- the row, or the company_id: the proxy only needs to choose between two login
-- URLs, and a function that hands back a company_id is one somebody later reads
-- a tenant out of on an unauthenticated path.

begin;

create or replace function public.shop_slug_exists(p_slug text)
returns boolean
language sql
stable
security definer
-- Pinned: a security definer function with a mutable search_path is how a
-- caller gets to choose which `shop_config` it reads.
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.shop_config
     where slug = lower(trim(coalesce(p_slug, '')))
  );
$$;

comment on function public.shop_slug_exists(text) is
  'Is this path segment a storefront slug? One boolean, for the proxy to choose '
  'between /login and /<slug>/login on an unauthenticated request. Returns no row '
  'and no company_id by design. See 20261028000002.';

-- The proxy calls it as `anon` (no session) and as `authenticated` (a signed-in
-- user whose own session is mid-refresh still takes the !user branch).
revoke all on function public.shop_slug_exists(text) from public;
grant execute on function public.shop_slug_exists(text) to anon, authenticated;

do $$
declare
  fn      oid;
  ok_anon boolean;
  ok_auth boolean;
  found   boolean;
begin
  select p.oid into fn
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'shop_slug_exists';
  if fn is null then
    raise exception 'shop_slug_exists was not created';
  end if;

  -- 🔴 ASKED OF THE CATALOGUE, NOT BY BECOMING THE ROLE.
  --
  -- This block used to do `set local role anon; select shop_slug_exists(...);
  -- reset role` to prove the function answers for a guest. That broke CI:
  --     NOTICE:  shop_slug_exists is callable by anon ...
  --     ERROR:   permission denied for schema supabase_migrations
  --     At statement: 7
  --       INSERT INTO supabase_migrations.schema_migrations(...)
  -- The body had already committed; only the bookkeeping failed, so staging got
  -- the function and no record of it.
  --
  -- 🔴 `RESET ROLE` DOES NOT MEAN "PUT IT BACK". It resets to the session's
  -- startup role, which DISCARDS a `SET ROLE` the client made itself. Measured:
  --     set role authenticated;  -- what the client chose
  --     begin; do $x$ begin set local role anon; reset role; end $x$;
  --     select current_user;     -->  postgres, not authenticated
  -- `supabase db push` prints "Initialising login role..." and does exactly
  -- that, so the reset handed the rest of the transaction a role with no rights
  -- on supabase_migrations. A plain local dry run hid it completely, because
  -- there the startup role IS the superuser and nothing it reset mattered.
  --
  -- So: a migration must not touch `role` at all. Only the client knows what to
  -- restore. has_function_privilege answers the identical question -- may THAT
  -- role execute this -- and mutates no session state.
  ok_anon := has_function_privilege('anon', fn, 'execute');
  ok_auth := has_function_privilege('authenticated', fn, 'execute');
  -- Both, because a key and its policy that do not admit the same roles fail
  -- silently in BOTH directions, which is the whole reason this migration
  -- exists. Asserting one of them would reproduce the original bug.
  if not ok_anon or not ok_auth then
    raise exception
      'shop_slug_exists must be executable by anon (%) and authenticated (%)', ok_anon, ok_auth;
  end if;

  -- And that it answers. Run as whoever is applying this: the question here is
  -- whether the body is sound, and the grants above are what decide who may ask.
  select public.shop_slug_exists('definitely-not-a-shop-slug-xyzzy') into found;
  if found then
    raise exception 'shop_slug_exists said a nonsense slug exists';
  end if;

  -- 🔴 NOT asserting that any particular slug IS present. Staging carries one
  -- storefront row and it is neither of production's, and an assertion only
  -- production can satisfy turns the rehearsal into the thing that breaks the
  -- release. Absent is not a fault.
  raise notice 'shop_slug_exists is executable by anon and authenticated, and answers false for an unknown slug';
end $$;

commit;
