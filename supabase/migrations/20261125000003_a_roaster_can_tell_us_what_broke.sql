-- A roaster can tell us what broke.
--
-- Owner, 2026-11-25: *"we need to add a bug report option and flow to the
-- platform. an icon that they can click in the side bar that lets them
-- screenshot optionally and describe a bug that is submitted to the dev
-- portal"*.
--
-- Until now there was NO channel from a user to us. The help centre has no
-- contact page, the sidebar has no support row, and `/dev/errors` and
-- `/dev/telemetry` only ever hear from the machine: a thrown error, a stalled
-- transition, a long task. A screen that is simply WRONG -- the number that
-- disagrees with the invoice, the button that does nothing, the word nobody
-- understands -- throws nothing, so it reached us only if the owner happened to
-- say it out loud. This is the row that carries it.
--
-- ── WHAT IT IS NOT ────────────────────────────────────────────────────────
--
-- Not a ticketing system. One box of prose, one optional picture, and a status
-- the dev portal can move. No reply thread, no assignee, no severity the
-- reporter has to judge: they are standing in front of a roaster, not filling
-- in a form. The reporter never reads the row back (see the grants below) --
-- they get a confirmation and that is the whole of their side of it.
--
-- ── IT IS INSERT-ONLY, AND THE REVOKE IS THE FENCE ────────────────────────
--
-- Shaped on client_telemetry_events (20260702000001): one INSERT policy, no
-- SELECT/UPDATE/DELETE policy, and the dev portal reads with the service-role
-- admin client, which bypasses RLS.
--
-- 🔴 But a new public table does not arrive empty-handed: this project's
-- `pg_default_acl` hands the whole ACL to `authenticated` (and, under the
-- supabase_admin default, to `anon` too) before a line of policy runs. On
-- tables that leave it there, RLS is the only fence, and one permissive SELECT
-- policy added later by mistake would expose every tenant's reports to every
-- signed-in session. So this file takes the ACL away and grants back the one
-- privilege the panel needs: two independent fences, and a future policy slip
-- cannot open the table on its own. See the revoke below for the measurement.
--
-- ── NO PERMISSION KEY, AND NO PLAN GATE ───────────────────────────────────
--
-- Deliberate, and the reason is the same one Help has neither: a key that can
-- be switched off is a key that will be, and the first person to lose it is
-- some roastery's assistant roaster at 5am -- exactly the person whose bug we
-- most need and who has nobody to tell. `auth_has_permission` does not appear
-- in these policies. Being signed in IS the permission.
--
-- ── company_id IS NULLABLE, ON PURPOSE ────────────────────────────────────
--
-- Unlike client_telemetry_events, which refuses an event it cannot attribute.
-- A bug report must never be refused for want of a tenant, because "I have no
-- roastery / the app says I am not on a team" is itself one of the reports we
-- need. The reporter is identified by auth_user_id either way, and the INSERT
-- policy still pins that to auth.uid(), so a null company buys nobody anything
-- they did not already have.
--
-- ── THE DEMO MAY FILE ONE ─────────────────────────────────────────────────
--
-- No `aa_guard_demo_readonly` trigger (20260910000010), which every other
-- tenant-scoped table carries. A demo visitor finding a bug is the cheapest
-- bug report there is, and nothing in the demo is harmed by a row in this
-- table. This is the one write the demo is allowed.
--
-- ── THE SCREENSHOT PATH NAMES THE REPORTER, NOT THE COMPANY ───────────────
--
--   bug-screenshots/<auth_user_id>/<bug_report_id>.<ext>
--
-- Every other private bucket puts the company first, because the policy
-- compares segment one with auth_company_ids(). This one cannot: the report
-- whose point is that the user has no company still gets a picture. Segment
-- one is the uid and the policy compares it with auth.uid(), which is a
-- tighter fence anyway -- you may write into your own folder and nowhere else.
-- 🔴 The writer (lib/bug-report/actions.ts) must put the uid first or the
-- policy admits nobody, silently.
--
-- There is no SELECT policy on the bucket either, so not even the reporter can
-- fetch their own screenshot back; the dev portal signs a URL with the service
-- role.
--
-- ── client_session_id IS THE JOIN, NOT A COPY ─────────────────────────────
--
-- The report records the telemetry session id the client already generates
-- (lib/telemetry/client.ts getClientSessionId). So /dev/bug-reports can show
-- every js_error, hydration_error and stalled_transition from the SAME session
-- beside the prose, without this table copying a single event. "Nothing
-- happened when I pressed save" and the TypeError that says why, on one screen.

begin;

-- ── The bucket the picture lands in ───────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bug-screenshots', 'bug-screenshots', false, 5242880,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bug_screenshots_own_folder_insert on storage.objects;

create policy bug_screenshots_own_folder_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'bug-screenshots'
              and (storage.foldername(name))[1] = auth.uid()::text);

-- ── The report ────────────────────────────────────────────────────────────

create table if not exists public.bug_report (
  id                uuid        primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),

  -- Who. auth_user_id is the only identity the INSERT policy trusts; the name
  -- and address are copied at report time so a later rename or a departed
  -- team member does not leave the row anonymous.
  auth_user_id      uuid        not null,
  reporter_name     text,
  reporter_email    text,

  -- Where they were standing. Nullable company: see the header.
  company_id        text        references public.companies(company_id) on delete cascade,
  facility_id       text        references public.facilities(facility_id) on delete set null,
  reporter_role     text,
  company_plan      text,

  -- What they said. The only thing they are required to type, and it may not
  -- be whitespace: an empty report is worse than none, because it looks like
  -- one we ignored.
  description       text        not null check (length(btrim(description)) > 0),

  -- Pathname only, no query string -- the same rule client telemetry follows,
  -- for the same reason: a query string carries ids and search terms.
  route             text,

  -- The picture, in the private bucket above. Null when they sent none.
  screenshot_path   text,

  -- The join to client_telemetry_events, not a copy of it.
  client_session_id uuid,
  app_version       text,
  platform          text,
  user_agent        text,
  viewport          text,

  -- Ours, not theirs. 'new' is what the dev portal's unread count counts, so
  -- a report stays bold until somebody actually moves it.
  status            text        not null default 'new'
                      check (status in ('new', 'looking', 'fixed', 'wont_fix')),
  dev_notes         text,
  status_changed_at timestamptz,
  status_changed_by uuid
);

comment on table public.bug_report is
  'A user-written bug report from the sidebar. INSERT-only via RLS (and select/update/delete revoked from authenticated); the dev portal reads and triages it with the admin client. The optional screenshot lives in the private bug-screenshots bucket at <auth_user_id>/<id>.<ext>.';

comment on column public.bug_report.company_id is
  'Nullable on purpose: a report must never be refused for want of a tenant, because "the app says I am not on a team" is one of the reports we need.';

comment on column public.bug_report.client_session_id is
  'The telemetry session id from the same browser session, so /dev/bug-reports can show this session''s client errors beside the prose. Joins client_telemetry_events.client_session_id.';

comment on column public.bug_report.status is
  'new | looking | fixed | wont_fix. Moved only by the dev portal; the reporter never sees it.';

alter table public.bug_report enable row level security;

-- INSERT only, and only as yourself. No SELECT, UPDATE or DELETE policy
-- exists: the reporter cannot read the row back, cannot edit it and cannot
-- withdraw it. The dev portal uses the service role, which bypasses all of
-- this.
drop policy if exists bug_report_insert_as_self on public.bug_report;

create policy bug_report_insert_as_self on public.bug_report
  for insert to authenticated
  with check (
    auth_user_id = auth.uid()
    and (company_id is null or company_id in (select public.auth_company_ids()))
    -- A reporter may not open a row already triaged, or write our notes.
    and status = 'new'
    and dev_notes is null
    and status_changed_at is null
    and status_changed_by is null
  );

-- 🔴 EVERY PRIVILEGE OFF FIRST, AND EVERY ROLE NAMED. Naming the verbs to
-- revoke is not enough. Measured off prod's own `pg_default_acl`, a new table
-- in `public` arrives with the default already applied, and WHICH default
-- depends on who owns it:
--
--   owned by postgres        authenticated = arwdxm   (incl. REFERENCES, MAINTAIN)
--   owned by supabase_admin  anon = authenticated = service_role = arwdDxtm  (all seven)
--
-- So `revoke select, update, delete from authenticated` -- which is what this
-- file said first -- would have left REFERENCES and MAINTAIN on
-- `authenticated`, and under the supabase_admin default would have left a
-- SIGNED-OUT caller holding all seven on a table of other people's
-- screenshots and prose, with only RLS in the way. A peer session had staging
-- refuse exactly this on `order_activity` the same afternoon (7df605b).
--
-- 🔴 `revoke ... from public, anon` does NOT revoke from `authenticated`
-- ([[gotcha_revoke_from_public_does_not_revoke_from_authenticated]]), so all
-- three are named -- the line `config_audit_log` uses (20260906000003:178).
-- `service_role` keeps its default: the dev portal reads this table with it.
--
-- Then exactly one privilege back.
revoke all on public.bug_report from public, anon, authenticated;
grant insert on public.bug_report to authenticated;

-- The dev list is "newest first, filtered by status", and the nav badge is
-- "how many are still new" -- both answered by this one index.
create index if not exists bug_report_status_created_idx
  on public.bug_report (status, created_at desc);

create index if not exists bug_report_created_idx
  on public.bug_report (created_at desc);

-- Only for the reports that actually carry a session, which is most of them
-- but not the ones filed before telemetry initialised.
create index if not exists bug_report_session_idx
  on public.bug_report (client_session_id)
  where client_session_id is not null;

-- ── Asserts only what this file wrote ─────────────────────────────────────

do $$
declare
  n integer;
begin
  if not exists (select 1 from storage.buckets where id = 'bug-screenshots') then
    raise exception 'the bug-screenshots bucket was not created';
  end if;
  if (select public from storage.buckets where id = 'bug-screenshots') then
    raise exception 'the bug-screenshots bucket is PUBLIC; a screenshot can show anything on a roastery''s screen';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and qual like '%bug-screenshots%' and cmd = 'SELECT'
  ) then
    raise exception 'bug-screenshots has a SELECT policy; screenshots are served only through a signed URL from the service role';
  end if;
  if not exists (
    select 1 from pg_policies
     where tablename = 'bug_report' and policyname = 'bug_report_insert_as_self'
  ) then
    raise exception 'bug_report has no insert policy, so nobody can file one';
  end if;
  if exists (
    select 1 from pg_policies
     where tablename = 'bug_report' and cmd in ('SELECT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'bug_report has a read or write-back policy; it is insert-only by design';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.bug_report'::regclass) then
    raise exception 'bug_report does not have row level security enabled';
  end if;
  -- `authenticated` holds INSERT and nothing else.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'bug_report'
     and grantee = 'authenticated' and privilege_type <> 'INSERT';
  if n <> 0 then
    raise exception 'bug_report: authenticated holds % privileges beyond INSERT', n;
  end if;

  -- `anon` holds nothing at all. It is a different role with its own default
  -- grant, and a revoke aimed at `authenticated` never touches it.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'bug_report'
     and grantee in ('anon', 'PUBLIC');
  if n <> 0 then
    raise exception 'bug_report: anon still holds % privileges', n;
  end if;

  -- The one row that proves INSERT survived the revoke-all: an empty ACL would
  -- pass both checks above and leave the sidebar button failing silently.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'bug_report'
     and grantee = 'authenticated' and privilege_type = 'INSERT';
  if n <> 1 then
    raise exception 'bug_report: authenticated cannot INSERT it (% rows)', n;
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
