-- Verification for 20260906000003_config_audit_log — STAGING, rolled back. Passed 2026-09-05:
-- (1) one row per real change, none for a no-op update; (2) deny_message logged as a value (reason null);
-- (3) tenant path (authenticated + JWT) logs with the user's email, excluded PII never appears, excluded-only edit writes nothing;
-- (3b) authenticated cannot read the log. Run: psql <staging pooler> -f this file
\set ON_ERROR_STOP on
begin;
-- (1) dev-portal path: service role / postgres writing plan_permissions with updated_by stamped
select plan_id, permission_id into temp _pp from plan_permissions limit 1;
update plan_permissions p set granted = not granted, updated_reason = 'smoke', updated_by = 'smoke@test'
  from _pp where p.plan_id = _pp.plan_id and p.permission_id = _pp.permission_id;
update plan_permissions p set updated_at = now() from _pp where p.plan_id = _pp.plan_id and p.permission_id = _pp.permission_id;   -- no allowlisted change → no row
select '(1) expect ONE row, changed_by smoke@test, reason smoke' as step, table_name, row_key, changed_by, action, changed_columns, reason from config_audit_log order by id desc limit 3;
-- (2) role_permissions: deny_message is a value, not a reason
update role_permissions set deny_message = 'smoke deny' where (role_id, permission_id) = (select role_id, permission_id from role_permissions limit 1);
select '(2) expect role_permissions row, changed_columns {deny_message}, reason null' as step, table_name, changed_columns, reason, changed_by from config_audit_log order by id desc limit 1;
-- (3) tenant path: authenticated role with the test user's JWT → RLS on company_kyc, security-definer trigger writes the log
select set_config('request.jwt.claims', json_build_object('role','authenticated','sub','f2daa8b6-1c34-45bb-b7d3-6fb3cba99a5a','email','claude-uitest@example.com')::text, true);
set local role authenticated;
insert into company_kyc (company_id, status, legal_name, ein_last4, business_phone) values ('demo-aloha-coffee-roasters', 'submitted', 'SIM Roasters LLC', '1234', '808-555-0100');
update company_kyc set status = 'approved', reviewed_by = 'dev@strata', rolling_reserve_pct = 0.05 where company_id = 'demo-aloha-coffee-roasters';
update company_kyc set business_phone = '808-555-0199' where company_id = 'demo-aloha-coffee-roasters';   -- excluded column only → no row
reset role;
select '(3) expect 2 kyc rows (insert, update); actor claude-uitest@example.com; NO phone/ein in old/new' as step, action, changed_by, changed_columns, new_row from config_audit_log where table_name='company_kyc' order by id;
select '(3b) tenant cannot read the log: expect permission denied' as step;
savepoint sp;
do $$ begin
  set local role authenticated;
  perform count(*) from config_audit_log;
  raise exception 'FAIL: authenticated could read config_audit_log';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  raise notice '(3b) refused as expected → %', sqlerrm;
end $$;
rollback to savepoint sp;
rollback;

-- (4) the same developer editing the same row twice via the dev portal (service role) is credited both times
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select plan_id, permission_id into temp _pp from plan_permissions limit 1;
update plan_permissions p set granted = not granted, updated_by = 'dev@strata' from _pp where p.plan_id=_pp.plan_id and p.permission_id=_pp.permission_id;
update plan_permissions p set granted = not granted, updated_by = 'dev@strata' from _pp where p.plan_id=_pp.plan_id and p.permission_id=_pp.permission_id;   -- same dev, same row, again
select 'same dev twice: expect dev@strata on BOTH rows' as step, changed_by, changed_columns from config_audit_log order by id desc limit 2;
rollback;
