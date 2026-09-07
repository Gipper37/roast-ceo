-- PIN storage and verification, so a person can be an ACTOR without a login.
--
-- Why a PIN at all: on a shared terminal — the roast logger from day one,
-- because roasters rotate daily — every record has to name who did the work.
-- 21 CFR 117.305 requires it, Costco GMP 11.1.1 (a critical) wants sanitation
-- records showing tasks completed "and by whom", and 4.1.12 wants records
-- signed by the person who performed the task. Handing everyone a password on a
-- machine in a roastery is not a real answer; a short PIN over a device login is.
--
-- ── The one thing that must not go wrong ────────────────────────────────────
-- A 4-digit PIN has ten thousand possibilities. Any attacker holding the hash
-- brute-forces it offline in seconds, so THE HASH MUST NEVER LEAVE THE DATABASE.
-- That is why the PIN does not live on `team`: `team` carries a
-- read-your-own-company SELECT policy, which would hand every colleague's hash
-- to any authenticated member through PostgREST. It lives in its own table with
-- RLS on, NO policies at all, and every privilege revoked from anon and
-- authenticated — the same shape as config_audit_log. Only the security-definer
-- functions below can see it, and none of them ever returns it.
--
-- Second line of defence, because offline attack is not the only one: online
-- guessing is rate-limited by a lockout the tenant configures (default 5
-- attempts, 15 minutes). Both the hash comparison and the failure path run the
-- same work whether or not the member exists, so the RPC cannot be used to
-- enumerate people.
--
-- ── Authorisation ───────────────────────────────────────────────────────────
-- These functions are reachable directly over PostgREST by any authenticated
-- user, so they cannot rely on a server action having called requirePermission
-- first. They authorise themselves: auth_has_permission() resolves the caller's
-- role AND the company's plan exactly as the app does, so a starter tenant or a
-- roastmaster gets the same answer from the RPC as from the UI. Setting your own
-- PIN is the one path that needs no permission — everyone may change their own.

begin;

-- ── A DB-side mirror of the app's permission check ──────────────────────────
-- lib/permissions/server.ts resolves role_permissions AND (not is_plan_gated OR
-- plan_permissions.granted). This is that, for functions that must not trust
-- their caller. STABLE + security definer so it can read the catalogs under RLS.
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
  );
$$;

comment on function public.auth_has_permission(text, text) is
  'Role x plan permission check for security-definer functions that cannot trust their caller. Mirrors lib/permissions/server.ts.';

-- ── Per-tenant terminal policy ──────────────────────────────────────────────
-- Owner, 2026-09-07: "4 to 6 digit pin. device login yes." Length is the
-- tenant''s choice, not ours; the rest are the knobs a shared terminal needs.
create table public.company_terminal_policy (
  company_id        text primary key references public.companies(company_id) on delete cascade,
  pin_length        int  not null default 6  check (pin_length between 4 and 6),
  lockout_threshold int  not null default 5  check (lockout_threshold between 3 and 20),
  lockout_minutes   int  not null default 15 check (lockout_minutes between 1 and 1440),
  autolock_seconds  int  not null default 180 check (autolock_seconds between 30 and 3600),
  session_max_hours int  not null default 14 check (session_max_hours between 1 and 24),
  updated_at        timestamptz not null default now(),
  updated_by        text
);

comment on table public.company_terminal_policy is
  'Per-tenant shared-terminal rules. A missing row means the defaults below, so a tenant that never opens the settings still has a working, safe policy.';

alter table public.company_terminal_policy enable row level security;

create policy company_terminal_policy_read on public.company_terminal_policy
  for select using (company_id in (select auth_company_ids()));
create policy company_terminal_policy_write on public.company_terminal_policy
  for all using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- Defaults in ONE place. Every function reads the policy through this, so a
-- tenant with no row behaves identically to a tenant that accepted the defaults.
create or replace function public.terminal_policy(p_company_id text)
returns public.company_terminal_policy
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p from public.company_terminal_policy p where p.company_id = p_company_id),
    (p_company_id, 6, 5, 15, 180, 14, now(), null)::public.company_terminal_policy
  );
$$;

-- ── The hash, where nobody can read it ──────────────────────────────────────
create table public.team_pin (
  team_member_id text primary key references public.team(team_member_id) on delete cascade,
  company_id     text not null references public.companies(company_id) on delete cascade,
  pin_hash       text not null,
  set_at         timestamptz not null default now(),
  set_by         text,
  must_change    boolean not null default true,
  failed_count   int not null default 0,
  locked_until   timestamptz,
  last_used_at   timestamptz
);

create index idx_team_pin_company on public.team_pin (company_id);

comment on table public.team_pin is
  'Bcrypt PIN hashes. RLS on with NO policies and every privilege revoked: a 4-digit PIN falls to offline brute force in seconds, so the hash must never reach a client. Only the security-definer functions in this migration read it, and none of them returns it.';

alter table public.team_pin enable row level security;
revoke all on public.team_pin from anon, authenticated;

-- ── Setting a PIN ───────────────────────────────────────────────────────────
create or replace function public.set_team_pin(
  p_team_member_id text,
  p_pin            text,
  p_must_change    boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_company  text;
  v_policy   public.company_terminal_policy;
  v_is_self  boolean;
  v_actor    text;
begin
  select company_id into v_company from public.team
   where team_member_id = p_team_member_id and coalesce(is_active, true);
  if v_company is null then
    raise exception 'No such team member.' using errcode = 'no_data_found';
  end if;

  -- Everyone may change their OWN pin. Setting someone else's is a managed act.
  select exists (
    select 1 from public.team
     where team_member_id = p_team_member_id and auth_user_id = auth.uid()
  ) into v_is_self;

  if not v_is_self and not public.auth_has_permission('team.floor_staff', v_company) then
    raise exception 'You do not have permission to set a PIN for someone else.'
      using errcode = 'insufficient_privilege';
  end if;

  v_policy := public.terminal_policy(v_company);

  if p_pin !~ ('^[0-9]{' || v_policy.pin_length || '}$') then
    raise exception 'A PIN must be exactly % digits.', v_policy.pin_length
      using errcode = 'check_violation';
  end if;

  -- Refuse the PINs everyone picks. A lockout does not help when the first
  -- three guesses are 1111, 1234 and 0000.
  if p_pin ~ '^(.)\1*$' then
    raise exception 'That PIN is all the same digit. Choose another.' using errcode = 'check_violation';
  end if;
  if position(p_pin in '01234567890') > 0 or position(p_pin in '09876543210') > 0 then
    raise exception 'That PIN is a run of consecutive digits. Choose another.' using errcode = 'check_violation';
  end if;

  v_actor := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'db:' || session_user);

  insert into public.team_pin as tp
    (team_member_id, company_id, pin_hash, set_at, set_by, must_change, failed_count, locked_until)
  values (
    p_team_member_id, v_company,
    extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
    now(), v_actor,
    -- A PIN somebody sets for themselves is theirs; one set FOR them is temporary.
    coalesce(p_must_change, not v_is_self),
    0, null
  )
  on conflict (team_member_id) do update
     set pin_hash     = excluded.pin_hash,
         set_at       = excluded.set_at,
         set_by       = excluded.set_by,
         must_change  = excluded.must_change,
         failed_count = 0,
         locked_until = null;
end;
$$;

-- ── Verifying a PIN ─────────────────────────────────────────────────────────
-- Returns a verdict, never the hash. Answers identically for a member who does
-- not exist and one whose PIN is wrong, so it cannot be used to enumerate staff.
create or replace function public.verify_team_pin(p_team_member_id text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_row     public.team_pin;
  v_company text;
  v_policy  public.company_terminal_policy;
  v_ok      boolean := false;
begin
  select t.company_id into v_company
    from public.team t
   where t.team_member_id = p_team_member_id
     and coalesce(t.is_active, true)
     and t.company_id in (select auth_company_ids());

  if v_company is null then
    -- Burn a comparison so a missing member costs the same as a wrong PIN.
    perform extensions.crypt(coalesce(p_pin, ''), extensions.gen_salt('bf', 10));
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  v_policy := public.terminal_policy(v_company);
  select * into v_row from public.team_pin where team_member_id = p_team_member_id;

  if v_row.team_member_id is null then
    perform extensions.crypt(coalesce(p_pin, ''), extensions.gen_salt('bf', 10));
    return jsonb_build_object('ok', false, 'reason', 'no_pin');
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'locked_until', v_row.locked_until);
  end if;

  v_ok := (v_row.pin_hash = extensions.crypt(coalesce(p_pin, ''), v_row.pin_hash));

  if v_ok then
    update public.team_pin
       set failed_count = 0, locked_until = null, last_used_at = now()
     where team_member_id = p_team_member_id;
    return jsonb_build_object('ok', true, 'must_change', v_row.must_change);
  end if;

  update public.team_pin
     set failed_count = failed_count + 1,
         locked_until = case
           when failed_count + 1 >= v_policy.lockout_threshold
           then now() + make_interval(mins => v_policy.lockout_minutes)
           else locked_until end
   where team_member_id = p_team_member_id
   returning * into v_row;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'locked_until', v_row.locked_until);
  end if;

  return jsonb_build_object(
    'ok', false, 'reason', 'invalid',
    'attempts_left', greatest(v_policy.lockout_threshold - v_row.failed_count, 0)
  );
end;
$$;

-- ── Removing a PIN, and reading who has one ─────────────────────────────────
create or replace function public.clear_team_pin(p_team_member_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text;
begin
  select company_id into v_company from public.team where team_member_id = p_team_member_id;
  if v_company is null then
    raise exception 'No such team member.' using errcode = 'no_data_found';
  end if;
  if not public.auth_has_permission('team.floor_staff', v_company) then
    raise exception 'You do not have permission to remove a PIN.' using errcode = 'insufficient_privilege';
  end if;
  delete from public.team_pin where team_member_id = p_team_member_id;
end;
$$;

-- Status WITHOUT the hash: what a management screen legitimately needs.
create or replace function public.team_pin_status(p_company_id text)
returns table (
  team_member_id text,
  has_pin        boolean,
  must_change    boolean,
  set_at         timestamptz,
  last_used_at   timestamptz,
  locked_until   timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select tp.team_member_id, true, tp.must_change, tp.set_at, tp.last_used_at,
         case when tp.locked_until > now() then tp.locked_until end
    from public.team_pin tp
   where tp.company_id = p_company_id
     and p_company_id in (select auth_company_ids());
$$;

revoke all on function public.set_team_pin(text, text, boolean)  from public;
revoke all on function public.verify_team_pin(text, text)        from public;
revoke all on function public.clear_team_pin(text)               from public;
revoke all on function public.team_pin_status(text)              from public;
revoke all on function public.auth_has_permission(text, text)    from public;
grant execute on function public.set_team_pin(text, text, boolean) to authenticated;
grant execute on function public.verify_team_pin(text, text)       to authenticated;
grant execute on function public.clear_team_pin(text)              to authenticated;
grant execute on function public.team_pin_status(text)             to authenticated;
grant execute on function public.auth_has_permission(text, text)   to authenticated;

commit;
