-- An invitation carries no more authority than the person who sent it.
--
-- Two holes, both live on prod:
--   * sendInvite never compared the invited role with the inviter's. team.invite
--     is held by managers, and /api/invite/accept inserts the team row on the
--     service role, where 20260907000015's guard cannot see it (BEFORE UPDATE,
--     and it returns on auth.uid() is null). A manager could invite a
--     company_admin and accept it from a second mailbox.
--   * invitations.token was SELECT-granted and the policy is company-scoped:
--     any team member could read a pending colleague's token, POST it to the
--     accept route with their own password, and become that person — the
--     invited role, under the invited email.
--
-- The rank rule is 20260907000015's with one exception the data demands: a
-- company admin may invite a company admin. That is how a roastery gets its
-- second owner, and Social Hour has three. Everyone else invites strictly
-- below themselves. The trigger also writes invited_by itself, so the accept
-- route's re-check of the sender cannot be pointed at somebody more senior.
--
-- The token becomes unreadable: the table grant is rebuilt without it, and the
-- link is minted by invitation_link_token(), which hands it only to the person
-- who sent the invitation or to a company admin, only while the invitation is
-- open, and only to a caller who may hold team.invite and could still grant
-- that role today. shop_invitations gets the same treatment: same shape, same
-- exposure (a colleague could set the password on a customer's future login).
--
-- Prod today: 0 pending invitations in either table; nothing to migrate.

begin;

-- ── 1. rank, and who the sender is ───────────────────────────────────────
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

  v_actor  := public.auth_role_rank(new.company_id);
  v_target := public.role_rank(new.role_id);

  if not (v_actor = 0 and v_target = 0) and v_target <= v_actor then
    raise exception 'You can only invite someone to a role below your own.'
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
  before insert or update of role_id, company_id, invited_by on public.invitations
  for each row execute function public.guard_invitation_rank();

comment on function public.guard_invitation_rank() is
  'An invitation is for a role below the sender''s (a company admin may invite a company admin), and invited_by is always the sender.';

-- ── 2. the token is not a column anybody reads ────────────────────────────
revoke all on public.invitations from anon;
revoke select, insert, update on public.invitations from authenticated;
grant select (invitation_id, company_id, facility_id, invited_email, role_id, invited_by,
              accepted_at, expires_at, created_at, created_by, updated_at, updated_by, as_terminal)
  on public.invitations to authenticated;
grant insert (company_id, facility_id, invited_email, role_id, invited_by, created_by, updated_by, as_terminal)
  on public.invitations to authenticated;
grant update (expires_at, updated_at, updated_by)
  on public.invitations to authenticated;

revoke all on public.shop_invitations from anon;
revoke select, insert, update on public.shop_invitations from authenticated;
grant select (invitation_id, customer_id, company_id, slug, invited_email, expires_at, accepted_at,
              created_at, created_by, updated_at, updated_by, target_role)
  on public.shop_invitations to authenticated;
grant insert (customer_id, company_id, slug, invited_email, target_role, created_by, updated_by)
  on public.shop_invitations to authenticated;
grant update (expires_at, updated_at, updated_by)
  on public.shop_invitations to authenticated;

-- ── 3. the link is minted, for the sender ─────────────────────────────────
create or replace function public.invitation_link_token(p_invitation_id text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v      public.invitations%rowtype;
  v_me   text;
  v_rank int;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = 'insufficient_privilege';
  end if;

  select * into v from public.invitations where invitation_id = p_invitation_id;
  if not found or v.company_id not in (select public.auth_company_ids()) then
    raise exception 'That invitation is not yours.' using errcode = 'insufficient_privilege';
  end if;
  if v.accepted_at is not null or v.expires_at <= now() then
    raise exception 'That invitation is no longer open.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('team.invite', v.company_id) then
    raise exception 'You may not send invitations.' using errcode = 'insufficient_privilege';
  end if;

  select t.team_member_id into v_me
    from public.team t
   where t.auth_user_id = auth.uid()
     and t.company_id = v.company_id
     and coalesce(t.is_active, true)
   order by t.created_at
   limit 1;
  v_rank := public.auth_role_rank(v.company_id);

  -- The sender, or a company admin. Nobody else ever sees a link.
  if v.invited_by is distinct from v_me and v_rank <> 0 then
    raise exception 'Only the person who sent this invitation, or an admin, can resend it.'
      using errcode = 'insufficient_privilege';
  end if;
  -- And never for a role the caller could not grant today.
  if not (v_rank = 0 and public.role_rank(v.role_id) = 0)
     and public.role_rank(v.role_id) <= v_rank then
    raise exception 'You can only invite someone to a role below your own.'
      using errcode = 'insufficient_privilege';
  end if;

  return v.token;
end;
$$;

revoke all on function public.invitation_link_token(text) from public, anon;
grant execute on function public.invitation_link_token(text) to authenticated;

create or replace function public.shop_invitation_link_token(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.shop_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.' using errcode = 'insufficient_privilege';
  end if;

  select * into v from public.shop_invitations where invitation_id = p_invitation_id;
  if not found or v.company_id not in (select public.auth_company_ids()) then
    raise exception 'That invitation is not yours.' using errcode = 'insufficient_privilege';
  end if;
  if v.accepted_at is not null or v.expires_at <= now() then
    raise exception 'That invitation is no longer open.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('shop.customer_invite', v.company_id) then
    raise exception 'You may not invite customers.' using errcode = 'insufficient_privilege';
  end if;

  return v.token;
end;
$$;

revoke all on function public.shop_invitation_link_token(uuid) from public, anon;
grant execute on function public.shop_invitation_link_token(uuid) to authenticated;

commit;
