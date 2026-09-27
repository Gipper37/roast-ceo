-- A roastmaster has their own terminal. A bagger shares one.
--
-- The idle autolock is one number per company, defaulting to 180 seconds, and
-- it is the wrong shape. Owner, 2026-09-26: *"3 minutes is the time out. it
-- should be 30 for the roastmaster. they have their own terminal. bagger can be
-- 3 but it also needs to be easy to switch."*
--
-- That is the whole distinction: a shared terminal in a packing room should
-- forget you quickly, because the next person to touch it is somebody else. A
-- roaster's own machine should not, because the next person to touch it is you,
-- and locking it costs a PIN entry with your hands full.
--
-- 🔴 WHY THIS IS NOT COSMETIC. lockNow() does not merely cover the screen — it
-- calls terminal_pin_out and ends the actor session server-side, so DROP and
-- event marks are refused until somebody PINs back in. At 180 seconds a
-- roastmaster watching a hardware-streamed curve crosses it without touching
-- anything: BLE readings arrive from Rust and fire no DOM event, so nothing
-- bumps the idle clock. The lock screen lands between them and the DROP button
-- at the one moment it matters.
--
-- terminal_pin_in ALREADY returns autolock_seconds to the client — the shape
-- anticipated a per-actor value and only ever had one to give. So this changes
-- exactly one line of it: where the number comes from. The body below is the
-- LIVE definition from pg_get_functiondef with that single substitution;
-- nothing else was retyped.
--
-- Per ROLE rather than per terminal, because a terminal is a machine and the
-- timeout belongs to the person standing at it. Seeded for the two roles that
-- run a roaster; everyone else keeps the company default, and any role can be
-- tuned without another migration.

begin;

create table if not exists public.terminal_role_autolock (
  company_id       text not null references public.companies(company_id) on delete cascade,
  role_id          text not null references public.user_roles(role_id) on delete cascade,
  autolock_seconds integer not null,
  updated_at       timestamptz not null default now(),
  updated_by       text,
  primary key (company_id, role_id),
  -- Same bounds company_terminal_policy enforces, so one cannot be set to
  -- something the other would refuse.
  constraint terminal_role_autolock_seconds_check
    check (autolock_seconds >= 30 and autolock_seconds <= 3600)
);

comment on table public.terminal_role_autolock is
  'Per-role idle autolock override for shared terminals. Falls back to '
  'company_terminal_policy.autolock_seconds when a role has no row. A roaster''s '
  'own machine should not forget them mid-roast; a shared packing terminal should.';

alter table public.terminal_role_autolock enable row level security;

drop policy if exists terminal_role_autolock_read on public.terminal_role_autolock;
create policy terminal_role_autolock_read on public.terminal_role_autolock
  for select to authenticated
  using (company_id in (select public.auth_company_ids()));

-- Changing how long a terminal stays unlocked is a security setting.
drop policy if exists terminal_role_autolock_write on public.terminal_role_autolock;
create policy terminal_role_autolock_write on public.terminal_role_autolock
  for all to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('config.parameters', company_id))
  with check ((company_id in (select public.auth_company_ids()))
              and public.auth_has_permission('config.parameters', company_id));

create or replace function public.terminal_autolock_seconds(p_company_id text, p_team_member_id text)
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select a.autolock_seconds
       from public.terminal_role_autolock a
       join public.team t on t.role = a.role_id
      where a.company_id = p_company_id
        and t.team_member_id = p_team_member_id
        and t.company_id = p_company_id
      limit 1),
    (select p.autolock_seconds from public.terminal_policy(p_company_id) p),
    180);
$fn$;

comment on function public.terminal_autolock_seconds(text, text) is
  'How long this person may leave this terminal idle before it locks and PINs '
  'them out. Their role first, then the company policy, then 180 seconds.';

CREATE OR REPLACE FUNCTION public.terminal_pin_in(p_team_member_id text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_term   public.team;
  v_policy public.company_terminal_policy;
  v_check  jsonb;
  v_member record;
  v_id     text;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then
    raise exception 'This login is not a shared terminal.' using errcode = 'insufficient_privilege';
  end if;

  select team_member_id, name, job_title into v_member
    from public.team
   where team_member_id = p_team_member_id
     and company_id = v_term.company_id
     and coalesce(is_active, true);

  v_check := public.verify_team_pin(p_team_member_id, p_pin);
  if not (v_check ->> 'ok')::boolean or v_member.team_member_id is null then
    return coalesce(v_check, jsonb_build_object('ok', false, 'reason', 'invalid'));
  end if;

  v_policy := public.terminal_policy(v_term.company_id);

  update public.terminal_actor_session
     set ended_at = now(), ended_reason = 'replaced'
   where terminal_member_id = v_term.team_member_id and ended_at is null;

  insert into public.terminal_actor_session
    (company_id, terminal_member_id, team_member_id, actor_name, actor_title, expires_at)
  values (
    v_term.company_id, v_term.team_member_id, v_member.team_member_id,
    coalesce(v_member.name, 'Unnamed'), v_member.job_title,
    now() + make_interval(hours => v_policy.session_max_hours)
  )
  returning session_id into v_id;

  return jsonb_build_object(
    'ok', true, 'session_id', v_id,
    'team_member_id', v_member.team_member_id,
    'name', v_member.name, 'job_title', v_member.job_title,
    'must_change', coalesce((v_check ->> 'must_change')::boolean, false),
    'autolock_seconds', public.terminal_autolock_seconds(v_term.company_id, v_member.team_member_id)
  );
end;
$function$;

-- Thirty minutes for the two roles that run a roaster, three for everybody
-- else by falling through to the company default. Written for every company so
-- the behaviour is the same on a tenant onboarded tomorrow.
insert into public.terminal_role_autolock (company_id, role_id, autolock_seconds, updated_by)
select c.company_id, r, 1800, 'migration:20260926000013'
  from public.companies c
  cross join (values ('roastmaster'), ('roastery_manager')) as t(r)
 where exists (select 1 from public.user_roles ur where ur.role_id = t.r)
on conflict (company_id, role_id) do nothing;

do $verify$
declare v_bad int;
begin
  -- Every seeded row is inside the bounds the policy table would accept.
  select count(*) into v_bad from public.terminal_role_autolock
   where autolock_seconds < 30 or autolock_seconds > 3600;
  if v_bad > 0 then raise exception '% row(s) hold an out-of-range autolock', v_bad; end if;

  -- The resolver falls back rather than returning null, for every member.
  select count(*) into v_bad
    from public.team t
   where t.company_id is not null
     and public.terminal_autolock_seconds(t.company_id, t.team_member_id) is null;
  if v_bad > 0 then raise exception '% team member(s) resolve to a null autolock', v_bad; end if;

  -- A roastmaster gets longer than the company default, everywhere.
  select count(*) into v_bad
    from public.team t
   where t.role = 'roastmaster' and t.company_id is not null
     and public.terminal_autolock_seconds(t.company_id, t.team_member_id)
         <= coalesce((select p.autolock_seconds from public.terminal_policy(t.company_id) p), 180);
  if v_bad > 0 then raise exception '% roastmaster(s) still lock as fast as everyone else', v_bad; end if;

  -- And terminal_pin_in now asks the resolver rather than the flat policy.
  if (select p.prosrc from pg_proc p where p.proname = 'terminal_pin_in')
     not like '%terminal_autolock_seconds%' then
    raise exception 'terminal_pin_in still returns the company-wide autolock';
  end if;

  raise notice 'autolock: roastmaster and roastery_manager 1800s, everyone else the company default';
end $verify$;

commit;
