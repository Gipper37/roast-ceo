-- Let a tenant read the change history about their OWN company.
--
-- 20260906000003 shipped config_audit_log with RLS on and no policies at all —
-- service-role only, read from /app/dev/audit. That is right for the two global
-- catalogs it tracks (plan_permissions, role_permissions are platform config and
-- none of a tenant's business) and wrong for the third: company_kyc rows are
-- ABOUT one company, and an approve/reject on that company's KYC is exactly the
-- kind of change its own admin, and an auditor sitting with them, should be able
-- to see. A change trail nobody but us can read cannot be shown as evidence.
--
-- So the policy is deliberately narrow: rows WITH a company_id, matched to the
-- caller's companies. The catalog rows carry company_id NULL and stay invisible
-- to every tenant, exactly as before. Still append-only for everyone: no INSERT,
-- UPDATE or DELETE policy exists, and the writer is the security-definer trigger.
--
-- Costco Food Safety GMP V3.0 scores this twice over — 5.1.11 (no falsification
-- of records, an automatic-failure critical) and 5.1.1 (records can be easily
-- located during the audit). Not plan-gated: your own history is not an upsell.

begin;

create policy config_audit_log_select_own_company on public.config_audit_log
  for select using (
    company_id is not null
    and company_id in (select auth_company_ids())
  );

grant select on public.config_audit_log to authenticated;

comment on table public.config_audit_log is
  'History for plan/role permission changes and KYC status. Global catalog rows (company_id null) are dev-portal only via service_role; company-scoped rows are readable by that company under config_audit_log_select_own_company. Written by trg_config_audit (security definer); no writer policies by design. Rows hold allowlisted columns only (no KYC PII).';

insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'config.audit_view',
  'Configuration',
  'View configuration history',
  'See the dated trail of changes to this company''s record — who changed what and when. Read-only; the log cannot be edited by anyone.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  false,
  34
)
on conflict (permission_id) do nothing;

-- Ungated: every plan. A tenant reading their own history is not a paid feature.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'config.audit_view', true, 'Own-company change history — all plans'),
  ('pro',             'config.audit_view', true, 'Own-company change history — all plans'),
  ('enterprise',      'config.audit_view', true, 'Own-company change history — all plans'),
  ('enterprise_plus', 'config.audit_view', true, 'Own-company change history — all plans')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- The company record and its KYC status are company_admin / accounting territory.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'config.audit_view', true),
  ('accounting_admin',  'config.audit_view', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

commit;
