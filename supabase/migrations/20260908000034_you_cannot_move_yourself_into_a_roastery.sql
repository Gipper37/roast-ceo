-- You cannot walk into another roastery by editing your own row.
--
-- 20260907000015 added a guard for the privileged columns on public.team, and
-- its company_id branch asks the wrong question:
--
--     if (new.company_id is distinct from old.company_id) ... then
--       if not public.auth_is_company_admin(old.company_id) then raise
--
-- auth_is_company_admin(old.company_id) means "are you an admin of the company
-- you are currently in". For your OWN row that is nearly always yes — and it is
-- ALWAYS yes for anyone who signed up, because company-signup/index.ts:185
-- mints every new signup as company_admin of the company it creates for them.
-- So the guard reads: you may change which roastery you belong to, provided you
-- are an admin of the one you are leaving. Which is the thing to prevent.
--
-- The full chain, every link verified against production:
--   1. https://www.strataroast.com/mauicoffee is public and its HTML contains
--      9ShiyDAXhV. One anonymous curl, no account needed.
--   2. Sign up at /signup. The edge function creates a company and makes you
--      its company_admin.
--   3. PATCH your own team row over PostgREST: company_id = '9ShiyDAXhV'.
--      team_self_update permits it (it pins auth_user_id and nothing else) and
--      `authenticated` holds table-level UPDATE on public.team, including the
--      company_id column.
--   4. auth_company_ids() reads company_id from that same row, so every tenant
--      RLS policy in the schema now agrees you are inside Maui Coffee Roasters,
--      and the app shell scopes you there.
--
-- That is a stranger on the internet reaching a real roastery's customers,
-- orders, costs and recipes. It is live on prod now and 20260907000015 does not
-- close it.
--
-- ── The rule ──────────────────────────────────────────────────────────────
-- Nobody moves THEMSELVES between companies, ever. Moving somebody else needs
-- admin of BOTH ends — you cannot push yourself in, and you cannot pull someone
-- out of a roastery you do not run. Service role, cron and migrations keep the
-- exemption they already have (auth.uid() is null); that is how support moves
-- an account, and it leaves a trail.
--
-- Belt and braces: the column grants go too. The policy should not be the only
-- thing standing between a PATCH and the tenant boundary.

begin;

create or replace function public.guard_team_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_rank int;
  v_is_self    boolean;
begin
  -- Service role, cron and migrations have no JWT. They are already trusted.
  if auth.uid() is null then return new; end if;

  v_is_self := (old.auth_user_id is not null and old.auth_user_id = auth.uid());

  -- 🔴 WHICH ROASTERY YOU BELONG TO. Never your own, and never one-ended.
  if new.company_id is distinct from old.company_id then
    if v_is_self then
      raise exception 'You cannot move your own account to another company.'
        using errcode = 'insufficient_privilege';
    end if;
    -- Admin of the company they are LEAVING...
    if not public.auth_is_company_admin(old.company_id) then
      raise exception 'Only an admin can move an account out of a company.'
        using errcode = 'insufficient_privilege';
    end if;
    -- ...and of the one they are joining. Without this half, being an admin of
    -- a company you created yourself is enough to reach into any other.
    if not public.auth_is_company_admin(new.company_id) then
      raise exception 'Only an admin of that company can move an account into it.'
        using errcode = 'insufficient_privilege';
    end if;
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

  return new;
end;
$$;

-- ── Do not let the policy be the only thing there ──────────────────────────
-- team_self_update restricts the ROW, not the columns, so the table-wide UPDATE
-- grant is what makes company_id and role reachable at all. Narrow it to the
-- columns a person legitimately edits about themselves. The trigger above still
-- stands behind this; neither is load-bearing alone.
revoke update on public.team from authenticated;
grant update (name, email, facility_id, ui_hide_help, onboarding_completed,
              first_app_open_at, activity_last_seen_at, updated_at, updated_by)
  on public.team to authenticated;

comment on function public.guard_team_privileged_columns() is
  'Nobody moves themselves between companies; moving somebody else needs admin of both ends. Nobody changes their own role, and nobody grants a role at or above their own. Enforced here because team_self_update restricts the row, not the columns.';

commit;
