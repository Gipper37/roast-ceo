-- Audit the settings an auditor actually asks about.
--
-- `config_audit_log` shipped with a tenant-readable policy and a `config.audit_view`
-- permission, and nothing to read: the only per-company table carrying the
-- trigger was `company_kyc`. A change-history page over five KYC rows is not a
-- feature, so the surface stayed unbuilt and the permission unused.
--
-- What makes it worth having is auditing the configuration that decides whether
-- the RECORDS can be trusted. An auditor's questions in this area are always the
-- same shape — "was it always like this, and who changed it?":
--
--   company_feature          did somebody switch food safety OFF for a while?
--   fs_lot_code_format       did the lot code scheme change mid-year? (that is
--                            the one that quietly breaks a trace)
--   fs_settings              was the shelf life moved after the bags went out?
--   fs_label_format          did the label stop carrying the best-before?
--   company_terminal_policy  were the PIN rules weakened?
--   team                     who was given which role, and when
--
-- The allowlist is the point of this trigger: only the named columns are copied
-- into the log, so `team` contributes its PRIVILEGE columns and nothing else —
-- no names, no emails, no PINs. And a write that does not move an allowlisted
-- column writes no row at all, so ordinary churn costs nothing.

begin;

-- Turning the module off is the most audit-relevant change in the whole product.
create trigger trg_config_audit
  after insert or update or delete on public.company_feature
  for each row execute function public.config_audit_row(
    'feature_key,enabled',
    'company_id,feature_key',
    '');

-- Changing the lot code scheme mid-year is what quietly breaks a trace: codes
-- issued before and after look like they came from different systems.
create trigger trg_config_audit
  after insert or update or delete on public.fs_lot_code_format
  for each row execute function public.config_audit_row(
    'prefix,date_style,sequence_width,separator,resets_daily',
    'company_id',
    '');

-- Shelf life is a quality claim printed on bags that are already in the field.
create trigger trg_config_audit
  after insert or update or delete on public.fs_settings
  for each row execute function public.config_audit_row(
    'shelf_life_days,default_label_kind',
    'company_id',
    '');

-- A label that stopped carrying the best-before, and when.
create trigger trg_config_audit
  after insert or update or delete on public.fs_label_format
  for each row execute function public.config_audit_row(
    'kind,width_mm,height_mm,show_product,show_roasted_on,show_best_before,show_packed_on,show_net_weight,show_barcode,extra_line',
    'company_id,kind',
    '');

-- Weakening the PIN rules weakens every signature made after it.
create trigger trg_config_audit
  after insert or update or delete on public.company_terminal_policy
  for each row execute function public.config_audit_row(
    'pin_length,lockout_threshold,lockout_minutes,autolock_seconds,session_max_hours',
    'company_id',
    '');

-- 🔴 team: the PRIVILEGE columns only. Names, emails, phone numbers and PIN
-- state stay in the source table — an audit log that quietly accumulates staff
-- personal data is a liability, not a control. `role` is here because a role
-- change is the single most consequential edit a tenant can make, and until this
-- morning it was possible to make it on yourself (see 20260907000015).
create trigger trg_config_audit
  after insert or update or delete on public.team
  for each row execute function public.config_audit_row(
    'role,is_terminal,login_kind,is_active',
    'team_member_id',
    '');

commit;
