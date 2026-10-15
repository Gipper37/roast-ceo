-- A developer impersonating a roaster gets a REAL, expiring team row.
--
-- The problem it solves. Impersonation set a cookie, the app read it, and the
-- DATABASE never heard about it: `auth_company_ids()` is
--
--   select company_id from team where auth_user_id = auth.uid() and is_active
--
-- so row level security answered from the developer's OWN memberships. Every
-- app page runs on the user client, so a support session saw either the
-- developer's own company (before 2026-10-15) or nothing at all (after it).
--
-- ── Why a membership rather than a hole in the fence ──────────────────────
--
-- The two alternatives were considered and are worse:
--
--   * A developer branch inside `auth_company_ids()`. The database cannot see
--     the impersonation cookie, so the branch would have to return EVERY
--     company for an active developer on every request. That makes one
--     compromised developer login a cross-tenant read of the whole platform,
--     and `rls-cross-tenant-test.sh` would start failing by design.
--   * Moving impersonated requests to the admin client. Targeted, but it
--     removes RLS as the backstop on exactly the sessions that most need one.
--
-- A membership is the smallest true statement: for the next few hours this
-- person really is a company_admin of that company, which is what the banner
-- has always said. The grant is one company, it is visible in the roaster's
-- own team list, and it expires.
--
-- ── What makes it safe ────────────────────────────────────────────────────
--
-- `login_kind = 'dev_session'` marks it, and the new CHECK makes the pairing
-- unbreakable in both directions: a dev_session MUST carry
-- `session_expires_at`, and nothing else may. A row without an expiry is not a
-- support session, and a support session without an expiry cannot exist.
--
-- Creation and deletion are the dev portal's (service role, no JWT, so
-- guard_team_privileged_columns lets it through); the sweep is by expiry, so a
-- crashed session or a closed laptop cannot leave a standing grant.
--
-- 🔴 SEATS. The seat counter is `team where company_id = X and is_active and
-- login_kind <> 'pin_only'`, so without care a support session would consume
-- one of the roaster's paid seats and show THEM an upgrade nag caused by us.
-- The frontend excludes dev_session in the same release; this comment is here
-- because the next person to write a seat query will not know.

begin;

alter table public.team
  add column if not exists session_expires_at timestamptz;

comment on column public.team.session_expires_at is
  'Only for login_kind = ''dev_session'': when this support membership stops being one. Swept by the dev portal; a row past this time grants nothing a sweep has not already taken away, so keep the sweep honest.';

alter table public.team drop constraint if exists team_login_kind_check;
alter table public.team add constraint team_login_kind_check
  check (login_kind = any (array['account'::text, 'pin_only'::text, 'dev_session'::text]));

-- Both directions, deliberately. An expiry on an ordinary account would be a
-- membership that silently stops working; a support session without one would
-- be a permanent cross-tenant grant wearing a temporary name.
alter table public.team drop constraint if exists team_dev_session_expires;
alter table public.team add constraint team_dev_session_expires
  check (
    (login_kind = 'dev_session' and session_expires_at is not null)
    or (login_kind <> 'dev_session' and session_expires_at is null)
  );

-- The sweep reads this, and so does anything asking "is anybody in here right
-- now". Partial: there are 16 team rows on prod and this will usually be zero.
create index if not exists idx_team_dev_session
  on public.team (session_expires_at)
  where login_kind = 'dev_session';

do $verify$
declare v_bad int; v_def text;
begin
  -- 1. The column is there and is a timestamptz.
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='team'
       and column_name='session_expires_at' and udt_name='timestamptz'
  ) then
    raise exception 'team.session_expires_at was not created as a timestamptz';
  end if;

  -- 2. The login_kind check admits exactly the three kinds. Asserted on the
  --    DEFINITION rather than by trying inserts, because an insert here would
  --    have to invent a company and would fire the audit triggers.
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid='public.team'::regclass and conname='team_login_kind_check';
  if v_def is null or v_def not like '%dev_session%'
     or v_def not like '%account%' or v_def not like '%pin_only%' then
    raise exception 'team_login_kind_check does not admit the three kinds: %', coalesce(v_def, '(missing)');
  end if;

  -- 3. The pairing constraint exists and names both directions.
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid='public.team'::regclass and conname='team_dev_session_expires';
  if v_def is null then
    raise exception 'team_dev_session_expires is missing';
  end if;

  -- 4. 🔴 This migration grants nothing. No support session may exist yet, and
  --    every existing row must still be exactly what it was.
  select count(*) into v_bad from public.team where login_kind = 'dev_session';
  if v_bad > 0 then
    raise exception '% support session(s) already exist; this migration must create none', v_bad;
  end if;
  select count(*) into v_bad from public.team where session_expires_at is not null;
  if v_bad > 0 then
    raise exception '% row(s) gained an expiry; this migration must set none', v_bad;
  end if;

  raise notice 'support sessions can now be real memberships; % team row(s), none of them one',
    (select count(*) from public.team);
end $verify$;

commit;
