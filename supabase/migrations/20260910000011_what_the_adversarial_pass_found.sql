-- What the adversarial pass found after chunks 1-3, closed.
--
-- Twenty-six agents spent 34 minutes trying to get past 20260910000001-10 and
-- their frontend halves; twelve claims survived an independent re-check. The
-- ones that are the database's to close are here. The pass's other product —
-- twenty-four SECURITY DEFINER functions any team member may call with no
-- tenant check (allocate_order_number, set_roast_measured_weight, …) — is
-- chunk 4's list, not this file's.
--
-- 1. team. The guard ran on UPDATE only. A facility_admin could INSERT a
--    second row for their own login as company_admin (the INSERT grant and
--    team_admin_write both admit them), deactivate every company_admin
--    (is_active had only the self-check, and 0008 turns that into an
--    immediate lockout), DELETE anyone — and anyone at all could move their
--    own facility_id to another tenant's facility, which auth_facility_ids()
--    then hands to RLS: another roastery's roast curves, events and weekly
--    targets, readable by the public demo login and writable by any real one.
--    Now: BEFORE INSERT OR UPDATE OR DELETE; nobody inserts a row that carries
--    a login (the accept route and signup do that, on the service role); a
--    facility must belong to the row's company; is_active of others and
--    DELETE follow the rank rule role already follows (below your own;
--    company admins are peers); auth_facility_ids() joins the facility to the
--    company; the INSERT grant loses auth_user_id and is_active; is_active is
--    NOT NULL, because every helper treated NULL as active while the app now
--    treats it as gone.
-- 2. rank at a terminal. auth_role_rank() read the LOGIN's role, so a manager
--    PIN'd into a company_admin terminal could invite a company_admin. The
--    narrowing 20260908000004 put in auth_has_permission() is in
--    auth_role_rank() too: at a terminal the rank is the PIN'd-in person's,
--    never better than the login's; nobody PIN'd in is rank 99.
-- 3. invitations. Any member could insert one (only minting was gated), and
--    as_terminal was not gated at all. The guard requires team.invite,
--    terminal.manage for as_terminal, and a facility of the same company.
-- 4. equipment. recompute_equipment_usage() is SECURITY DEFINER and was
--    EXECUTE-granted to authenticated: a login with no memberships rewrote
--    every tenant's lifetime-lbs counter, and a member could steer the number
--    by pointing an own roast_log row at another tenant's roaster, because
--    the two views joined on the unit alone. Revoked from authenticated (the
--    hourly cron runs as postgres; nothing in the app calls it); both views
--    also match company; the five child tables (schedule, subscription, log,
--    visit, document) must name a machine of their own company.
--    reminder_candidates() and standing_order_candidates() — cron scans of
--    every tenant's customers — revoked from authenticated too.
-- 5. demo. The guard fired FIRST (aa_) and tested the company_id the caller
--    sent; 0005's guards then rewrote it from the product or customer, so a
--    member of both a demo and a real company could land a row in the demo by
--    naming the real one. It is now last (zzz_) and sees the row as it will be
--    written. Its own-team-row exemption covered every column; it now covers
--    only the ambient ones (last-seen, first-open, onboarding, help toggle), so
--    the shared demo login's name, email, title and facility stay put. The
--    storage guard becomes SECURITY DEFINER, so a storage-api role without
--    EXECUTE on auth_is_demo_only() cannot fail on it. sales_state_backup,
--    which does carry a policy and a company_id, is no longer left out.
-- 6. views. With security_invoker, a wholesale buyer's own JWT reads the
--    roaster's per-order COGS and margin through customer_profitability,
--    customer_revenue, order_profitability, revenue_recognized and
--    weekly_orders_live — the buyer policies on orders reach the views. Those
--    five now also require a team membership.
-- 7. 0003's "the next function stays closed" did not hold: a per-schema
--    default ACL is ADDED to the built-in global default, and that default
--    grants PUBLIC EXECUTE. The revoke is now global, and this file proves it
--    on the spot by creating a function and refusing to commit if anon can
--    run it.
--
-- Prod today: 0 team rows with is_active null, 0 with a facility outside
-- their company, 0 invitations likewise. Nothing to repair.

begin;

-- ═══ 1. team ═══════════════════════════════════════════════════════════════
alter table public.team alter column is_active set default true;
update public.team set is_active = true where is_active is null;
alter table public.team alter column is_active set not null;

revoke insert on public.team from authenticated;
grant insert (team_member_id, name, email, company_id, facility_id, role, login_kind, is_terminal,
              job_title, department, shift, started_on, reports_to, onboarding_completed,
              created_at, created_by, updated_at, updated_by)
  on public.team to authenticated;

create or replace function public.auth_facility_ids()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- A facility you belong to is one of your company's. A row pointing
  -- elsewhere (there are none, and the guard below refuses new ones) gives
  -- you nothing, rather than another roastery's roast data.
  select t.facility_id
    from public.team t
    join public.facilities f on f.facility_id = t.facility_id and f.company_id = t.company_id
   where t.auth_user_id = auth.uid()
     and coalesce(t.is_active, true)
     and t.facility_id is not null;
$$;

create or replace function public.guard_team_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_rank  int;
  v_target_rank int;
  v_is_self     boolean;
begin
  -- Service role, cron and migrations have no JWT. They are already trusted:
  -- the accept route and signup create logins there.
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- ── INSERT: floor staff and hand-added people, never a login ──────────
  if tg_op = 'INSERT' then
    if new.auth_user_id is not null then
      raise exception 'A login joins a team through an invitation, not by hand.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(new.company_id);
    v_target_rank := public.role_rank(new.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only add someone at a role below your own.'
        using errcode = 'insufficient_privilege';
    end if;
    if new.facility_id is not null and not exists (
      select 1 from public.facilities f
       where f.facility_id = new.facility_id and f.company_id = new.company_id) then
      raise exception 'That facility is not part of this company.'
        using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;

  -- ── DELETE: never yourself, and only below your own role ──────────────
  if tg_op = 'DELETE' then
    if old.auth_user_id is not null and old.auth_user_id = auth.uid() then
      raise exception 'You cannot remove your own account.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(old.company_id);
    v_target_rank := public.role_rank(old.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only remove someone below your own role.'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;

  -- ── UPDATE ────────────────────────────────────────────────────────────
  v_is_self := (old.auth_user_id is not null and old.auth_user_id = auth.uid());

  -- 🔴 WHICH ROASTERY YOU BELONG TO. Never your own, and never one-ended.
  if new.company_id is distinct from old.company_id then
    if v_is_self then
      raise exception 'You cannot move your own account to another company.'
        using errcode = 'insufficient_privilege';
    end if;
    if not public.auth_is_company_admin(old.company_id) then
      raise exception 'Only an admin can move an account out of a company.'
        using errcode = 'insufficient_privilege';
    end if;
    if not public.auth_is_company_admin(new.company_id) then
      raise exception 'Only an admin of that company can move an account into it.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Which facility: always one of the company's own, for yourself as for anyone.
  if new.facility_id is distinct from old.facility_id and new.facility_id is not null
     and not exists (
       select 1 from public.facilities f
        where f.facility_id = new.facility_id and f.company_id = new.company_id) then
    raise exception 'That facility is not part of this company.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Identity and privilege columns: admins of that company only.
  if (new.is_terminal   is distinct from old.is_terminal)
  or (new.login_kind    is distinct from old.login_kind)
  or (new.auth_user_id  is distinct from old.auth_user_id) then
    if not public.auth_is_company_admin(old.company_id) then
      raise exception 'Only an admin can change that about an account.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if new.role is distinct from old.role then
    if v_is_self then
      raise exception 'You cannot change your own role. Ask an admin.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank := public.auth_role_rank(old.company_id);
    if public.role_rank(new.role) <= v_actor_rank
    or public.role_rank(old.role) <= v_actor_rank then
      raise exception 'You can only change someone to a role below your own.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Whether somebody is still here: never your own, and otherwise the rule
  -- role follows — below your own; company admins are peers.
  if new.is_active is distinct from old.is_active then
    if v_is_self then
      raise exception 'You cannot change your own active status.'
        using errcode = 'insufficient_privilege';
    end if;
    v_actor_rank  := public.auth_role_rank(old.company_id);
    v_target_rank := public.role_rank(old.role);
    if not (v_actor_rank = 0 and v_target_rank = 0) and v_target_rank <= v_actor_rank then
      raise exception 'You can only deactivate or reactivate someone below your own role.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_team_privileged on public.team;
create trigger trg_guard_team_privileged
  before insert or update or delete on public.team
  for each row execute function public.guard_team_privileged_columns();

comment on function public.guard_team_privileged_columns() is
  'Nobody inserts a row carrying a login, moves themselves between companies, changes their own role or is_active, or removes themselves. A facility is always the row''s own company''s. Adding, re-roling, deactivating and removing follow one rank rule: below your own; company admins are peers.';

-- ═══ 2. rank at a terminal ═════════════════════════════════════════════════
create or replace function public.auth_role_rank(p_company_id text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Mirrors ROLE_HIERARCHY in S/lib/permissions/constants.ts. Lower is more
  -- senior. An unknown or absent role ranks below everything. A TERMINAL
  -- login's rank is the PIN'd-in person's, and never better than the login's
  -- own; a terminal with nobody PIN'd in outranks nobody.
  select coalesce(min(
    case when coalesce(t.is_terminal, false) then
      greatest(public.role_rank(t.role), coalesce((
        select public.role_rank(p.role)
          from public.terminal_actor_session ses
          join public.team p on p.team_member_id = ses.team_member_id
         where ses.terminal_member_id = t.team_member_id
           and ses.ended_at is null
           and ses.expires_at > now()
           and coalesce(p.is_active, true)
         order by ses.started_at desc
         limit 1), 99))
    else public.role_rank(t.role) end), 99)
    from public.team t
   where t.auth_user_id = auth.uid()
     and t.company_id = p_company_id
     and coalesce(t.is_active, true);
$$;

-- ═══ 3. invitations ════════════════════════════════════════════════════════
create or replace function public.guard_invitation_rank()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor  int;
  v_target int;
begin
  if auth.uid() is null then return new; end if;

  if tg_op = 'INSERT' and not public.auth_has_permission('team.invite', new.company_id) then
    raise exception 'You may not send invitations.'
      using errcode = 'insufficient_privilege';
  end if;

  v_actor  := public.auth_role_rank(new.company_id);
  v_target := public.role_rank(new.role_id);
  if not (v_actor = 0 and v_target = 0) and v_target <= v_actor then
    raise exception 'You can only invite someone to a role below your own.'
      using errcode = 'insufficient_privilege';
  end if;

  -- A shared-terminal login is a terminal decision, not an invite one.
  if coalesce(new.as_terminal, false)
     and not public.auth_has_permission('terminal.manage', new.company_id) then
    raise exception 'Only a terminal manager can invite a shared terminal.'
      using errcode = 'insufficient_privilege';
  end if;

  -- The facility the accept route will copy onto the team row must be ours.
  if new.facility_id is not null and not exists (
    select 1 from public.facilities f
     where f.facility_id = new.facility_id and f.company_id = new.company_id) then
    raise exception 'That facility is not part of this company.'
      using errcode = 'insufficient_privilege';
  end if;

  -- The sender is whoever is asking, never whoever the row claims.
  if tg_op = 'INSERT' then
    select t.team_member_id into new.invited_by
      from public.team t
     where t.auth_user_id = auth.uid()
       and t.company_id = new.company_id
       and coalesce(t.is_active, true)
     order by t.created_at
     limit 1;
  else
    new.invited_by := old.invited_by;
  end if;

  return new;
end;
$$;

drop trigger if exists zz_guard_invitation_rank on public.invitations;
create trigger zz_guard_invitation_rank
  before insert or update of role_id, company_id, invited_by, as_terminal, facility_id on public.invitations
  for each row execute function public.guard_invitation_rank();

-- ═══ 4. equipment ══════════════════════════════════════════════════════════
revoke execute on function public.recompute_equipment_usage() from authenticated;
revoke execute on function public.reminder_candidates() from authenticated;
revoke execute on function public.standing_order_candidates() from authenticated;

create or replace view public.equipment_roaster_lbs with (security_invoker = true) as
  select e.equipment_id,
         coalesce(sum(rl.roasted_weight), 0::numeric) as lbs_roasted_lifetime
    from public.equipment e
    join public.roast_log rl
      on rl.roaster_unit_id = e.linked_roaster_unit_id
     and rl.company_id = e.company_id
   where e.category = 'roaster'
     and e.linked_roaster_unit_id is not null
   group by e.equipment_id;

create or replace view public.equipment_grinder_lbs with (security_invoker = true) as
  select e.equipment_id,
         coalesce(sum(od.roasted_weight), 0::double precision)::numeric as lbs_ground_lifetime
    from public.equipment e
    join public.order_details od
      on od.customer_id = e.customer_id
     and od.company_id = e.company_id
    join public.orders o
      on o.order_id = od.order_id
     and o.company_id = e.company_id
   where e.category = 'grinder'
     and e.customer_id is not null
     and od.item_status = any (array['packed'::text, 'delivered'::text])
   group by e.equipment_id;

create or replace function public.guard_equipment_child_tenant()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_company text;
begin
  if new.equipment_id is null then return new; end if;
  select company_id into v_company from public.equipment where equipment_id = new.equipment_id;
  if not found or v_company is distinct from new.company_id then
    raise exception 'That equipment is not part of this company.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['equipment_schedule', 'equipment_program_subscription',
                           'maintenance_log', 'equipment_visit', 'equipment_document'] loop
    execute format('drop trigger if exists zz_guard_equipment_child_tenant on public.%I', t);
    execute format(
      'create trigger zz_guard_equipment_child_tenant before insert or update of equipment_id, company_id '
      'on public.%I for each row execute function public.guard_equipment_child_tenant()', t);
  end loop;
end $$;

comment on function public.guard_equipment_child_tenant() is
  'A schedule, subscription, log, visit or document names a machine of its own company. Looked up as the caller, so another tenant''s machine is not there.';

-- ═══ 5. demo ═══════════════════════════════════════════════════════════════
create or replace function public.guard_demo_readonly()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row     jsonb;
  v_company text;
  v_old     text;
begin
  -- No JWT: service role, cron, migrations. Already trusted; the reseed lives here.
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  v_row     := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_company := v_row->>'company_id';
  v_old     := case when tg_op = 'UPDATE' then to_jsonb(old)->>'company_id' else null end;

  -- Your own team row: the ambient columns are yours to touch (last-seen,
  -- first-open, onboarding, help toggle). Anything else on it — name, email,
  -- title, facility — is a demo write like any other.
  if tg_table_name = 'team' and tg_op = 'UPDATE'
     and (v_row->>'auth_user_id') = auth.uid()::text
     and not exists (
       select 1
         from jsonb_each(to_jsonb(new)) n
         join jsonb_each(to_jsonb(old)) o using (key)
        where n.value is distinct from o.value
          and key not in ('activity_last_seen_at', 'first_app_open_at', 'onboarding_completed',
                          'ui_hide_help', 'updated_at', 'updated_by')) then
    return new;
  end if;

  -- The caller: a person who belongs only to demo companies writes nothing.
  if public.auth_is_demo_only() then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;

  -- The row: a demo company's row is not written by anyone with a JWT.
  if (v_company is not null or v_old is not null) and exists (
    select 1 from public.companies c
     where c.is_demo
       and (c.company_id = v_company or c.company_id = v_old)
  ) then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.guard_demo_readonly_storage()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.auth_is_demo_only() then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Last among the BEFORE triggers (zzz_ sorts after every zz_guard_* that
-- rewrites company_id), so the guard judges the row as it will be written.
do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select c.oid::regclass as rel, c.relname,
           (n.nspname = 'storage') as is_storage
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where t.tgname = 'aa_guard_demo_readonly' and not t.tgisinternal
    union
    select 'public.sales_state_backup'::regclass, 'sales_state_backup', false
     order by 2
  loop
    execute format('drop trigger if exists aa_guard_demo_readonly on %s', r.rel);
    execute format('drop trigger if exists zzz_guard_demo_readonly on %s', r.rel);
    execute format(
      'create trigger zzz_guard_demo_readonly before insert or update or delete on %s '
      'for each row execute function public.%I()',
      r.rel, case when r.is_storage then 'guard_demo_readonly_storage' else 'guard_demo_readonly' end);
    n := n + 1;
  end loop;
  raise notice 'demo guard now last on % relations', n;
end $$;

-- ═══ 6. views a buyer could read ═══════════════════════════════════════════
create or replace function public.auth_is_team_member()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- No JWT (service role, cron, migrations) is not a buyer; a login with no
  -- active membership is.
  select auth.uid() is null or exists (
    select 1 from public.team t
     where t.auth_user_id = auth.uid() and coalesce(t.is_active, true));
$$;

revoke all on function public.auth_is_team_member() from public, anon;
grant execute on function public.auth_is_team_member() to authenticated, service_role;

do $$
declare
  v text;
  d text;
begin
  foreach v in array array['customer_profitability', 'customer_revenue', 'order_profitability',
                           'revenue_recognized', 'weekly_orders_live'] loop
    d := rtrim(pg_get_viewdef(('public.' || v)::regclass, true), E'; \n\t');
    execute format(
      'create or replace view public.%I with (security_invoker = true) as '
      'select * from (%s) v where public.auth_is_team_member()', v, d);
  end loop;
end $$;

-- ═══ 7. the next function stays closed — for real ══════════════════════════
alter default privileges for role postgres revoke execute on functions from public;

do $$
declare acl aclitem[];
begin
  create function public.zz_default_privilege_probe() returns int language sql as 'select 1';
  select proacl into acl from pg_proc where oid = 'public.zz_default_privilege_probe()'::regprocedure;
  if has_function_privilege('anon', 'public.zz_default_privilege_probe()', 'execute')
     or exists (select 1 from unnest(coalesce(acl, '{}')) a where a::text like '=X/%') then
    raise exception 'default privileges still hand new functions to PUBLIC or anon: %', acl;
  end if;
  drop function public.zz_default_privilege_probe();
  raise notice 'a new function is closed to PUBLIC and anon: %', acl;
end $$;

commit;
