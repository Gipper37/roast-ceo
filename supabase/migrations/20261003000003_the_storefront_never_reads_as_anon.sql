-- The storefront never reads as anon, so anon does not get to read shop_config.
--
-- shop_config was readable by the entire internet: GRANT SELECT TO anon plus a
-- `public_read_enabled` policy on `is_enabled = true`. That exposed the WHOLE
-- row of every enabled shop, which is 28 columns including company_id,
-- facility_id, stripe_connect_account_id, reply_to_email and
-- invoice_payment_instructions.
--
-- It was deliberate, not an accident: _archive/20260516000003 added the grant
-- on purpose, because the public_read_enabled policy from 20260516000002 was a
-- no-op without it (RLS runs after grants). The reasoning was sound. What has
-- changed since is that no code reads it that way any more.
--
-- 🔴 PROVED DEAD BEFORE REVOKING. Every read of shop_config in the frontend:
--   app/(shop)/[slug]/page.tsx, actions-checkout.ts, request-access/actions.ts,
--   login/page.tsx ........................ createAdminClient (service role)
--   app/api/shop-invite/accept/route.ts
--   app/api/invoice-account/accept/route.ts  createClient(SERVICE_ROLE_KEY)
--   everything under app/app/(app)/ ....... createUserClient (authenticated)
-- No browser client and no anon client touches the table: of every file
-- importing @/lib/supabase/client, none references shop_config, and there is no
-- direct REST or fetch against it. The storefront is server-rendered on the
-- service role, so the anon path has been dead since that rendering changed.
--
-- public_read_enabled goes with it. Its roles are {public}, which also covers
-- AUTHENTICATED, so it let any signed-in user of any tenant read any enabled
-- shop's full row. Tenant reads keep working through shop_config_tenant_read,
-- which is scoped to auth_company_ids().
--
-- 🔴 WHY NO AUDIT CAUGHT THIS. Neither release script tests the anon role at
-- all: `grep -c anon` is 0 in rls-cross-tenant-test.sh and
-- rls-two-tenant-test.sh. Both check tenant-against-tenant as authenticated
-- users. The anon surface has never been in a release check, so no pass could
-- have found it. That gap is closed alongside this, in scripts/rls-anon-test.sh.
--
-- The remaining anon surface after this is two tables, both of which are
-- reference data a signed-out visitor genuinely needs: customer_category and
-- subscription_plans (the public pricing page).

begin;

-- 🔴 ALL, not SELECT. This revoked only SELECT and then asserted that anon held
-- ZERO grants on the table, which is true on prod (anon has exactly SELECT
-- there) and false on staging, where shop_config carries the full default
-- privilege set: revoking SELECT left six grants standing and the migration
-- aborted with "anon still holds 6 grant(s) on shop_config" on a database whose
-- only sin was having been created by a different path. Revoking everything is
-- also what we actually mean. anon has no business touching this table at all,
-- and the storefront reads it on the service role, which bypasses both grants
-- and RLS.
revoke all on public.shop_config from anon;

drop policy if exists public_read_enabled on public.shop_config;

do $verify$
declare v_bad int;
begin
  -- anon cannot reach it, by grant or by policy.
  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema='public' and table_name='shop_config' and grantee='anon';
  if v_bad > 0 then raise exception 'anon still holds % grant(s) on shop_config', v_bad; end if;

  select count(*) into v_bad from pg_policies
   where schemaname='public' and tablename='shop_config'
     and ('anon' = any(roles) or 'public' = any(roles));
  if v_bad > 0 then raise exception '% policy(ies) still expose shop_config to anon or public', v_bad; end if;

  -- 🔴 And the tenant can still read its own shop, or this takes the Shop
  -- settings page down with it.
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='shop_config'
       and policyname='shop_config_tenant_read' and cmd='SELECT'
       and 'authenticated' = any(roles)
  ) then
    raise exception 'the tenant read policy is gone; this would blank the shop settings page';
  end if;

  -- The storefront reads on the service role, which bypasses RLS. Asserted so
  -- that if that ever stops being true, this migration is where it is noticed.
  if not exists (select 1 from pg_class where relname='shop_config' and relrowsecurity) then
    raise exception 'row level security is not enabled on shop_config';
  end if;

  -- 🔴 The whole-schema anon posture is deliberately NOT asserted here any more.
  --
  -- This used to also require that anon held no non-SELECT grant anywhere in
  -- public, and that anon could read exactly two tables. Those are the right
  -- invariants and they are worth enforcing, but they are not THIS migration's
  -- change, and encoding one database's grant posture into a migration means a
  -- database that differs cannot apply it. Staging differs. The eleven
  -- migrations queued behind this one did not apply because of an assertion
  -- about tables this file does not touch.
  --
  -- They live in scripts/rls-anon-test.sh instead, which is in the pre-release
  -- checklist, runs against whichever database you point it at, and REPORTS the
  -- whole posture rather than aborting on the first surprise. See its
  -- allowed_read array, which is the same two tables, and its non-SELECT sweep.
  -- A migration asserts its own change; the release check asserts the posture.
end;
$verify$;

commit;
