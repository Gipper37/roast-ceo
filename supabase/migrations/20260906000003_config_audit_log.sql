-- config_audit_log — history behind /app/dev/audit (owner list item: "Unified
-- audit log (not just impersonation)").
--
-- developer_impersonation_log and subscription_admin_log are true append-only
-- logs. plan_permissions and role_permissions are NOT: the audit page shows
-- their CURRENT state (last updated_reason / deny_message) and its own comment
-- says "add a per-table audit trigger later". company_kyc.status has no
-- history at all — an approve/reject leaves nothing behind but the new row.
-- This is that trigger: ONE table + ONE generic row-level AFTER trigger on the
-- three mutation tables. Each attachment names (a) the allowlist of columns
-- worth remembering — company_kyc's EIN, phone, website and street address are
-- deliberately NOT in it, the log must never become a second copy of KYC PII —
-- (b) the row-key columns, (c) the row's own reason column when it has one.
-- An UPDATE that moves none of the allowlisted columns writes nothing (a
-- merchant re-saving a draft, a migration's no-op re-seed).
--
-- Actor: tenant writes arrive through the RLS client, so the JWT carries the
-- email. Dev-portal writes are service-role (no email in the JWT), so the
-- actions stamp updated_by on the row and the trigger trusts that column only
-- when THIS write changed it — a stale stamp from an earlier edit is not the
-- actor. Migrations run as postgres → 'db:postgres'. plan_permissions gains
-- updated_by for this (role_permissions already has it; the dev actions never
-- wrote it — 499/500 rows null on staging).
--
-- Security: same model as server_error_events / login_events — RLS on, NO
-- policies, anon + authenticated revoked outright; only the service role (the
-- dev portal) reads. The trigger function is SECURITY DEFINER so a tenant's
-- own KYC save (authenticated) can write the log row it is otherwise barred
-- from. app.skip_audit is deliberately NOT honoured here.

begin;

alter table public.plan_permissions
  add column if not exists updated_by text;

create table public.config_audit_log (
  id              bigint generated always as identity primary key,
  table_name      text not null,
  row_key         text not null,            -- 'plan:permission' | 'role:permission' | company_id
  company_id      text,                     -- company-scoped rows only (company_kyc)
  changed_at      timestamptz not null default now(),
  changed_by      text not null,            -- email | auth sub | 'service_role' | 'db:<session_user>'
  action          text not null check (action in ('insert', 'update', 'delete')),
  changed_columns text[] not null,
  old_row         jsonb,                    -- allowlisted columns only, nulls stripped
  new_row         jsonb,
  reason          text                      -- the row's own reason column, when this write set it
);

create index idx_config_audit_log_table_when
  on public.config_audit_log (table_name, changed_at desc);
create index idx_config_audit_log_company_when
  on public.config_audit_log (company_id, changed_at desc)
  where company_id is not null;

comment on table public.config_audit_log is
  'Dev portal only. No RLS policies by design — written by trg_config_audit (security definer) on plan_permissions / role_permissions / company_kyc; read from /app/dev/audit via service_role. Rows hold allowlisted columns only (no KYC PII).';

-- ── The one trigger function ────────────────────────────────────────────────
-- tg_argv[0] = comma list of allowlisted columns
-- tg_argv[1] = comma list of key columns (joined with ':' into row_key)
-- tg_argv[2] = the row's reason column, or '' when it has none
create or replace function public.config_audit_row()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_allow      text[] := string_to_array(tg_argv[0], ',');
  v_keys       text[] := string_to_array(tg_argv[1], ',');
  v_reason_col text   := nullif(tg_argv[2], '');
  v_old_full   jsonb;
  v_new_full   jsonb;
  v_old        jsonb;
  v_new        jsonb;
  v_changed    text[];
  v_row_key    text;
  v_claims     jsonb;
  v_actor      text;
  v_reason     text;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old_full := to_jsonb(old); end if;
  if tg_op in ('INSERT', 'UPDATE') then v_new_full := to_jsonb(new); end if;

  -- Project to the allowlist. Everything else never leaves the source table.
  select jsonb_object_agg(e.key, e.value) into v_old
    from jsonb_each(coalesce(v_old_full, '{}'::jsonb)) e
   where e.key = any (v_allow);
  select jsonb_object_agg(e.key, e.value) into v_new
    from jsonb_each(coalesce(v_new_full, '{}'::jsonb)) e
   where e.key = any (v_allow);
  v_old := jsonb_strip_nulls(coalesce(v_old, '{}'::jsonb));
  v_new := jsonb_strip_nulls(coalesce(v_new, '{}'::jsonb));

  -- Which allowlisted columns moved (insert/delete: every non-null one).
  select coalesce(array_agg(a order by a), '{}'::text[]) into v_changed
    from unnest(v_allow) a
   where (v_old -> a) is distinct from (v_new -> a);
  if tg_op = 'UPDATE' and cardinality(v_changed) = 0 then
    return null;                      -- nothing we track changed: no row
  end if;

  select string_agg(coalesce(v_new_full, v_old_full) ->> k.col, ':' order by k.ord)
    into v_row_key
    from unnest(v_keys) with ordinality as k(col, ord);

  v_claims := auth.jwt();
  v_actor := coalesce(
    nullif(v_claims ->> 'email', ''),                          -- tenant user (RLS client)
    nullif(v_claims ->> 'sub', ''),                            -- JWT without an email
    case when tg_op <> 'DELETE'
          and (v_new_full ? 'updated_by')
          and (tg_op = 'INSERT'
               or (v_new_full ->> 'updated_by') is distinct from (v_old_full ->> 'updated_by'))
         then nullif(v_new_full ->> 'updated_by', '') end,     -- stamped by THIS write
    case when v_claims ->> 'role' = 'service_role' then 'service_role' end,
    'db:' || session_user                                      -- migrations / psql
  );

  if v_reason_col is not null and tg_op <> 'DELETE'
     and (tg_op = 'INSERT'
          or (v_new_full ->> v_reason_col) is distinct from (v_old_full ->> v_reason_col)) then
    v_reason := nullif(v_new_full ->> v_reason_col, '');
  end if;

  insert into public.config_audit_log
    (table_name, row_key, company_id, changed_by, action, changed_columns, old_row, new_row, reason)
  values
    (tg_table_name,
     v_row_key,
     coalesce(v_new_full, v_old_full) ->> 'company_id',        -- null for the global catalogs
     v_actor,
     lower(tg_op),
     v_changed,
     case when tg_op = 'INSERT' then null else v_old end,
     case when tg_op = 'DELETE' then null else v_new end,
     v_reason);
  return null;
end;
$$;

-- ── Attachments (per-table config lives here) ───────────────────────────────
create trigger trg_config_audit
  after insert or update or delete on public.plan_permissions
  for each row execute function public.config_audit_row(
    'granted,updated_reason',
    'plan_id,permission_id',
    'updated_reason');

create trigger trg_config_audit
  after insert or update or delete on public.role_permissions
  for each row execute function public.config_audit_row(
    'granted,deny_message',
    'role_id,permission_id',
    '');

-- KYC allowlist: status + review outcome + underwriting facts already shown on
-- /dev/companies. NOT: ein_encrypted, ein_last4, business_phone,
-- business_website, business_address_* — PII stays in company_kyc only.
create trigger trg_config_audit
  after insert or update or delete on public.company_kyc
  for each row execute function public.config_audit_row(
    'status,reviewed_by,rejection_reason,provider_submerchant_id,rolling_reserve_pct,rolling_reserve_days,legal_name,dba,business_type,industry_mcc,expected_monthly_volume_cents,expected_average_ticket_cents',
    'company_id',
    'rejection_reason');

-- ── Access ──────────────────────────────────────────────────────────────────
alter table public.config_audit_log enable row level security;
-- Intentionally no policies: service-role only (dev portal read; the trigger
-- inserts as the function owner).
revoke all on public.config_audit_log from public, anon, authenticated;
grant select on public.config_audit_log to service_role;

-- Postgres refuses to call a trigger function directly, so EXECUTE is
-- harmless; granted to authenticated only so a tenant's KYC save can never
-- trip on it.
revoke all on function public.config_audit_row() from public, anon;
grant execute on function public.config_audit_row() to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
