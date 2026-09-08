-- Put a person's name on the work. This is what the PIN was for.
--
-- Until now a production record said which LOGIN saved it, which on a shared
-- machine is the machine. 21 CFR 117.305 wants the person who performed the
-- operation; Costco GMP 11.1.1 (an automatic-failure critical) wants records
-- showing tasks completed "and by whom"; 4.1.12 wants the performer named on
-- the record. A machine's name satisfies none of those.
--
-- ── actor_at(when) — the one answer every write path asks for ───────────────
-- At a terminal, the actor is whoever was PIN'd in AT THAT MOMENT — not whoever
-- is standing there when the row is finally written. A roast takes fifteen
-- minutes and a shift can change inside one; the batch belongs to the person who
-- charged it. So the lookup takes an instant and finds the session covering it.
--
-- Everywhere else the actor is simply the signed-in person, so ordinary logins
-- get the same stamp with no PIN and no terminal, and one function serves both.
--
-- The timestamp comes from the client (a roast's charge time is its own data),
-- but it cannot be used to impersonate: it can only select among sessions that
-- really happened at THIS terminal. The worst it can do is pick the colleague
-- who was genuinely standing there earlier.
--
-- ── Snapshots, again ───────────────────────────────────────────────────────
-- Every stamp is an id AND a name copied at the time. The id is the join; the
-- name is what an auditor reads three years later, after the person changed
-- their surname or left. ON DELETE RESTRICT so nobody can be deleted out from
-- under the work they did — archiving (is_active = false) is unaffected and
-- remains how somebody is retired.

begin;

create or replace function public.actor_at(p_when timestamptz default now())
returns table (team_member_id text, actor_name text, actor_title text, via text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_term public.team;
begin
  v_term := public.current_terminal();

  -- 1. A terminal: whoever was PIN'd in at that instant.
  if v_term.team_member_id is not null then
    return query
      select s.team_member_id, s.actor_name, s.actor_title, 'terminal'::text
        from public.terminal_actor_session s
       where s.terminal_member_id = v_term.team_member_id
         -- Half-open on purpose: [started_at, ended_at). A handover writes the
         -- outgoing session's ended_at and the incoming session's started_at at
         -- the SAME instant, so an inclusive end would match both and the answer
         -- would depend on tie-breaking. The moment of handover belongs to the
         -- person taking over.
         and s.started_at <= p_when
         and coalesce(s.ended_at, s.expires_at) > p_when
       order by s.started_at desc
       limit 1;
    if found then return; end if;
  end if;

  -- 2. Anyone else, and a terminal with nobody PIN'd in then: the login itself.
  return query
    select t.team_member_id, t.name, t.job_title, 'login'::text
      from public.team t
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
     order by t.created_at
     limit 1;
end;
$$;

comment on function public.actor_at(timestamptz) is
  'Who was doing the work at that instant: the terminal actor PIN''d in then, else the signed-in team member. One answer for every record-writing path.';

revoke all on function public.actor_at(timestamptz) from public;
grant execute on function public.actor_at(timestamptz) to authenticated;

-- ── Roast ───────────────────────────────────────────────────────────────────
alter table public.roast_sessions
  add column if not exists roasted_by_team_member text,
  add column if not exists roasted_by_name        text;

alter table public.roast_sessions
  drop constraint if exists roast_sessions_roasted_by_fkey;
alter table public.roast_sessions
  add constraint roast_sessions_roasted_by_fkey
  foreign key (roasted_by_team_member) references public.team(team_member_id) on delete restrict;

create index if not exists idx_roast_sessions_roasted_by
  on public.roast_sessions (roasted_by_team_member) where roasted_by_team_member is not null;

comment on column public.roast_sessions.roasted_by_team_member is
  'Who roasted it: the person PIN''d in at CHARGE on a terminal, else the signed-in member. Not an auth uuid — the record must outlive the login (which is why roast_sessions.created_by was dropped in 20260907000001).';
comment on column public.roast_sessions.roasted_by_name is
  'Their name as it read at the time. What an auditor reads years later.';

-- ── Maintenance and sanitation ──────────────────────────────────────────────
alter table public.maintenance_log
  add column if not exists completed_by_name text;

comment on column public.maintenance_log.completed_by_name is
  'Snapshot beside completed_by_team_member, so the record still names the person after a rename or a departure.';

commit;
