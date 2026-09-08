-- A facility admin can read the change history.
--
-- `config.audit_view` was granted to company_admin and accounting_admin when the
-- log covered exactly two things: billing permissions and KYC. Accounting was
-- the right second holder for that.
--
-- It now also covers the food-safety configuration — modules, lot code format,
-- label setup, PIN rules, team roles (20260908000001). The facility admin is who
-- runs the plant and who an auditor actually talks to, so leaving them out means
-- the person answering "did this change?" is the one who cannot look.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values ('facility_admin', 'config.audit_view', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

commit;
