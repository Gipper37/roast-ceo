-- A tenant may not rewrite what it pays for, or who it is.
--
-- Found while mapping M11 phase 2, verified against PROD, not in the audit's
-- 21 red flags. Two tables in the ungated 124 carry `tenant_company_access`
-- FOR ALL — a policy whose USING is "the row is mine" and nothing else — while
-- `authenticated` holds table-wide INSERT/UPDATE/DELETE:
--
--   subscriptions   Any member of any tenant — staff, assistant_roaster,
--                   anyone with a session — can
--                     PATCH /rest/v1/subscriptions?company_id=eq.<their own>
--                   setting plan_id or status. subscriptions feeds the view
--                   company_subscription_status, which auth_has_permission
--                   reads for its plan check, which gates 70 plan-gated
--                   permission keys. status='trialing' is treated AS enterprise
--                   for as long as it lasts. So one PATCH buys the whole
--                   product, permanently, for free.
--
--   companies       Same shape. company_name is what every invoice, storefront
--                   and outbound email says the roastery is called;
--                   books_closed_through is the accounting lock.
--
-- Neither has an authenticated writer for the commands being closed:
--   subscriptions — every write is service_role. stripe-webhook and
--     company-signup (edge functions, SERVICE_ROLE_KEY), the STRATA staff
--     console (createAdminClient, app/(dev)/actions.ts:373-459), and shop
--     checkout (createAdminClient). Every from('subscriptions') on a user
--     client in the app is a .select(). Verified by grep across both repos.
--   companies — three UPDATE writers, all already gating on company.edit:
--     company/actions.ts:43 updateCompanyName, :58 updateCompanyMailingAddress,
--     cost-center/actions.ts:11 setBooksClosedThrough. No INSERT or DELETE
--     writer exists.
--
-- So subscriptions is closed with a REVOKE (no JWT caller should write it at
-- all — a permission key would be the weaker fix, since it would still let a
-- company_admin sell themselves a plan), and companies keeps the UPDATE its app
-- performs, behind the key the app already checks.
--
-- The one function that writes either table, process_company_signup, is
-- SECURITY DEFINER and unaffected; service_role holds BYPASSRLS, so Stripe,
-- signup and the staff console are untouched.

begin;

-- ── subscriptions: readable by its tenant, writable by nobody with a JWT ──
drop policy if exists tenant_company_access on public.subscriptions;

create policy subscriptions_tenant_read on public.subscriptions
  for select to authenticated
  using (company_id in (select public.auth_company_ids()));

revoke insert, update, delete, truncate on public.subscriptions from authenticated;
revoke insert, update, delete, truncate on public.subscriptions from anon;

-- ── companies: the tenant reads it, company.edit changes it ───────────────
drop policy if exists tenant_company_access on public.companies;

create policy companies_tenant_read on public.companies
  for select to authenticated
  using (company_id in (select public.auth_company_ids()));

create policy companies_edit on public.companies
  for update to authenticated
  using (
    company_id in (select public.auth_company_ids())
    and public.auth_has_permission('company.edit', company_id)
  )
  with check (
    company_id in (select public.auth_company_ids())
    and public.auth_has_permission('company.edit', company_id)
  );

-- No authenticated path creates or destroys a company; process_company_signup
-- is SECURITY DEFINER and the staff console runs as service_role.
revoke insert, delete, truncate on public.companies from authenticated;
revoke insert, delete, truncate on public.companies from anon;

-- ── The plan catalogue: grants with no policy behind them ─────────────────
-- permissions / plan_permissions / role_permissions / subscription_plans have
-- RLS on and NO write policy, so these grants buy nobody anything today. They
-- are removed because the day somebody adds a permissive policy to one of them
-- for a read, the grant is already sitting there — and rewriting
-- role_permissions is a rewrite of the whole authorisation model.
revoke insert, update, delete, truncate on public.permissions from authenticated, anon;
revoke insert, update, delete, truncate on public.plan_permissions from authenticated, anon;
revoke insert, update, delete, truncate on public.role_permissions from authenticated, anon;
revoke insert, update, delete, truncate on public.subscription_plans from authenticated, anon;

-- ── Probe: fail the migration if the hole is still open ───────────────────
do $probe$
declare
  v_bad text;
begin
  select string_agg(distinct table_name || '.' || lower(privilege_type), ', ')
    into v_bad
    from information_schema.table_privileges
   where table_schema = 'public'
     and grantee in ('authenticated', 'anon')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
     and (
       table_name in ('subscriptions', 'permissions', 'plan_permissions',
                      'role_permissions', 'subscription_plans')
       or (table_name = 'companies' and privilege_type in ('INSERT', 'DELETE'))
     );
  if v_bad is not null then
    raise exception 'plan/identity write grants survived the revoke: %', v_bad;
  end if;

  -- companies must still be UPDATE-able, or the app cannot rename itself.
  if not exists (
    select 1 from information_schema.table_privileges
     where table_schema = 'public' and table_name = 'companies'
       and grantee = 'authenticated' and privilege_type = 'UPDATE'
  ) then
    raise exception 'companies UPDATE grant was removed — company.edit can no longer rename the roastery';
  end if;
end
$probe$;

commit;
