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
  n_anon int;
  n_auth int;
  found  boolean;
begin
  -- Both roles, because a key and its policy that do not admit the same roles
  -- fail silently in BOTH directions, which is the whole reason this migration
  -- exists. Asserting one of them would reproduce the original bug.
  select count(*) into n_anon
    from information_schema.role_routine_grants
   where routine_schema = 'public' and routine_name = 'shop_slug_exists' and grantee = 'anon';
  select count(*) into n_auth
    from information_schema.role_routine_grants
   where routine_schema = 'public' and routine_name = 'shop_slug_exists' and grantee = 'authenticated';
  if n_anon = 0 or n_auth = 0 then
    raise exception 'shop_slug_exists must be executable by anon (%) and authenticated (%)', n_anon, n_auth;
  end if;

  -- And prove it ANSWERS as anon, not merely that the grant row exists. The
  -- grant was never the thing in doubt; reading the table was.
  set local role anon;
  select public.shop_slug_exists('definitely-not-a-shop-slug-xyzzy') into found;
  if found then
    raise exception 'shop_slug_exists said a nonsense slug exists';
  end if;
  reset role;

  -- 🔴 NOT asserting that any particular slug IS present. Staging carries no
  -- storefront rows, and an assertion that only production can satisfy turns the
  -- rehearsal into the thing that breaks the release. Absent is not a fault.
  raise notice 'shop_slug_exists is callable by anon and answers false for an unknown slug';
end $$;

commit;
