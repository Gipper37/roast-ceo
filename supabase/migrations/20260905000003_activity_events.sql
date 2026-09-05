-- Error toasts reach the notification bell (owner-approved 2026-09-05).
--
-- A failed action used to be a 5-second bottom-right toast and then gone —
-- no operator-visible record anywhere (the two error tables are dev-portal
-- diagnostics, one not even tenant-readable by design). activity_events is
-- the ACTIVITY record of what the operator saw: company-scoped, readable by
-- the company (unlike telemetry), deliberately free of stacks/digests — the
-- dev tables keep the debugging job, client_session_id is the correlation
-- key across. The bell's feed reads the last 7 days; a cron purge at 30
-- days is owed (same TODO client_telemetry_events already carries).

begin;

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  company_id text not null,
  auth_user_id text,
  kind text not null default 'action_failed',
  title text not null check (char_length(title) <= 300),
  detail text check (char_length(detail) <= 1000),
  route text check (char_length(route) <= 300),
  client_session_id text,
  created_at timestamptz not null default now()
);

create index idx_activity_events_feed
  on public.activity_events (company_id, created_at desc);

alter table public.activity_events enable row level security;

-- Same shape as client_telemetry's INSERT policy — but activity is READABLE
-- by the company: the whole point is the operator (and their admin) seeing it.
create policy activity_events_insert on public.activity_events
  for insert with check (company_id in (select public.auth_company_ids()));

create policy activity_events_select on public.activity_events
  for select using (company_id in (select public.auth_company_ids()));

commit;
