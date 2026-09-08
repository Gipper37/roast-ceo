-- The person PIN'd in narrows what the terminal may do.
--
-- Owner, 2026-09-08: *"we will need to be able to assign pinned in staff roles
-- that can narrow their permissions even though the logged in user is a wider
-- permission set up. ie wsorders@mcr is roastmaster but a pinned employee might
-- only be staff or assistant roaster."*
--
-- 🔴 THE HOLE. Permissions resolve from `auth.uid()` → that login's `team` row →
-- `role`. `actor_at()` decides whose NAME goes on a record and touches authority
-- not at all. So `wsorders@mcr` being a roastmaster meant EVERY person who
-- PIN'd in at that station acted with roastmaster permissions — including floor
-- staff who have no login of their own. The record correctly named the packer
-- while the authority belonged to the machine. That is backwards, and it gets
-- worse the moment a food-safety record's verification depends on a PIN: the
-- PIN would prove identity but not standing.
--
-- ── The rule ────────────────────────────────────────────────────────────────
-- Effective grant = the login's grant AND the PIN'd-in person's grant.
-- Narrow only, never widen:
--   staff PIN at a roastmaster terminal      → staff
--   roastmaster PIN at a staff terminal      → staff (a PIN must never elevate;
--                                              the login is the ceiling)
--   no open session at a terminal            → NOTHING
--
-- That last line is the part a client cannot be trusted with. The lock screen is
-- a React overlay, not an authorisation boundary: a request arriving as the
-- terminal login through a server action or straight over PostgREST never passes
-- through it. `auth_has_permission` is what every write policy and every
-- security-definer function already calls, so putting the rule here covers all
-- of them at once, including the ones not written yet.
--
-- Reads are untouched. They go through `company_id in (select auth_company_ids())`,
-- not through this function, so a locked station still shows its queue while
-- being unable to change a single record.
--
-- ── What this deliberately does NOT do ──────────────────────────────────────
-- Plan and feature gates are unchanged. Owner: *"not sure if it touches plan
-- gates, why would it?"* — a plan is a fact about the COMPANY, not about who is
-- standing at the machine. The intersection is over ROLE grants only.
--
-- Nor does it let anybody pick their own role. Owner: *"no one can pick their
-- own role. it's always assigned by a higher up in the chain."* Assignment is
-- already governed by `trg_guard_team_privileged` (20260907000015) — never your
-- own role, and only a role strictly below yours. This inherits that guard
-- rather than inventing a second rule.

begin;

create or replace function public.auth_has_permission(p_permission_id text, p_company_id text default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.team t
      join public.role_permissions rp
        on rp.role_id = t.role and rp.permission_id = p_permission_id and rp.granted
      join public.permissions p
        on p.permission_id = p_permission_id
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
       and (p_company_id is null or t.company_id = p_company_id)
       and (
         not p.is_plan_gated
         or exists (
           select 1
             from public.company_subscription_status s
             join public.plan_permissions pp
               on pp.plan_id = s.plan_id and pp.permission_id = p_permission_id and pp.granted
            where s.company_id = t.company_id
         )
       )
       -- ── The terminal narrowing ───────────────────────────────────────────
       -- An ordinary login is unaffected. A TERMINAL login must have somebody
       -- PIN'd in, and that person's own role has to grant the key too.
       and (
         not coalesce(t.is_terminal, false)
         or exists (
           select 1
             from public.terminal_actor_session ses
             join public.team pinned
               on pinned.team_member_id = ses.team_member_id
             join public.role_permissions rp2
               on rp2.role_id = pinned.role
              and rp2.permission_id = p_permission_id
              and rp2.granted
            where ses.terminal_member_id = t.team_member_id
              and ses.ended_at is null
              and ses.expires_at > now()
              and coalesce(pinned.is_active, true)
         )
       )
  );
$$;

comment on function public.auth_has_permission(text, text) is
  'Role x plan permission check for security-definer functions and write policies. At a TERMINAL login the person PIN''d in narrows it — effective grant = the login''s grant AND theirs, never wider — and with no open session a terminal can change nothing. Reads are unaffected: they go through auth_company_ids(), not this. Mirrors lib/permissions/server.ts.';

commit;
