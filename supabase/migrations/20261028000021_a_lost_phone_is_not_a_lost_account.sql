-- A lost phone is not a lost account: `team.mfa_reset`.
--
-- PCI 8.4.2 wants multi-factor authentication, and this is the FIRST migration
-- of that work rather than the feature itself. The key has to exist in the
-- database before any frontend names it, because an unknown permission key is
-- DENIED SILENTLY -- so the order is: this, then the UI.
--
-- ── Why the reset path ships with MFA and not after it ───────────────────
--
-- Proven on staging before writing a line of UI, against this project's real
-- auth config: enrol TOTP -> challenge -> verify with a generated code ->
-- `aal` goes from aal1 to aal2. All of it works. And:
--
--   admin.auth.admin.mfa.listFactors({ userId })   -> yes
--   admin.auth.admin.mfa.deleteFactor({ userId })  -> YES
--
-- 🔴 But `@supabase/auth-js` 2.101 exposes NO recovery-code API to the client.
-- The server tables exist (`auth.mfa_recovery_codes`), the client method does
-- not. So if somebody loses or wipes their phone, the ONLY way back in is
-- another person deleting their factor with the service role.
--
-- Which means MFA without this key is a trap: enrol the owner, let him drop his
-- phone, and nobody can sign in to the business. **Prod has 14 active logins,
-- 7 of them company_admin** -- there is no support desk behind this. So the
-- recovery path is part of shipping MFA, not a follow-up.
--
-- ── Who gets it, and the guard that a permission alone cannot express ────
--
-- Granted to the same three roles as every other non-plan-gated `team.*` key
-- (`team.invite`, `team.role_edit`, `team.archive`, `team.facility_assign`):
-- company_admin, facility_admin, manager. Granted on ALL FOUR plans and
-- `is_plan_gated = false` on purpose -- putting account recovery behind a paid
-- tier would mean a starter tenant cannot get a locked-out admin back in, which
-- is a worse failure than any revenue it protects.
--
-- 🔴 A permission alone is not enough here, because removing somebody's second
-- factor leaves their account password-only. A `manager` stripping a
-- `company_admin`'s factor is an escalation path dressed up as a helpdesk
-- action. So the server action that performs the reset ALSO refuses when the
-- caller is less senior than the target, using the same ROLE_HIERARCHY that
-- `public.auth_role_rank()` mirrors (lower is more senior; the caller must be
-- `<=` the target's rank). Equal ranks are allowed deliberately -- with seven
-- company_admins they have to be able to help each other.
--
-- That guard lives in the action rather than in a policy because the reset is
-- not a database write at all: it goes through Supabase's admin auth API, which
-- no RLS policy can see.

begin;

insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values ('team.mfa_reset', 'Team', 'Reset two-factor for a team member',
        'Remove someone''s authenticator app so they can sign in and set it up again — for a lost, replaced or wiped phone. They will have no second factor until they enrol a new one. You cannot do this for someone more senior than you.',
        false, 50)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin',  'team.mfa_reset', true),
       ('facility_admin', 'team.mfa_reset', true),
       ('manager',        'team.mfa_reset', true)
on conflict (role_id, permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
values ('starter',         'team.mfa_reset', true),
       ('pro',             'team.mfa_reset', true),
       ('enterprise',      'team.mfa_reset', true),
       ('enterprise_plus', 'team.mfa_reset', true)
on conflict (plan_id, permission_id) do nothing;

do $$
declare n_perm int; n_role int; n_plan int; n_gated int;
begin
  select count(*) into n_perm from public.permissions where permission_id = 'team.mfa_reset';
  if n_perm <> 1 then raise exception 'team.mfa_reset was not created'; end if;

  select count(*) into n_role from public.role_permissions
   where permission_id = 'team.mfa_reset' and granted;
  if n_role <> 3 then
    raise exception 'team.mfa_reset is granted to % role(s), expected 3', n_role;
  end if;

  -- 🔴 all four plans, including starter. A locked-out admin on the cheapest
  -- plan must still be recoverable.
  select count(*) into n_plan from public.plan_permissions
   where permission_id = 'team.mfa_reset' and granted;
  if n_plan <> 4 then
    raise exception 'team.mfa_reset is granted on % plan(s), expected 4', n_plan;
  end if;

  select count(*) into n_gated from public.permissions
   where permission_id = 'team.mfa_reset' and is_plan_gated;
  if n_gated <> 0 then
    raise exception 'team.mfa_reset must not be plan-gated';
  end if;

  raise notice 'team.mfa_reset is live for company_admin, facility_admin and manager on all four plans';
end $$;

commit;
