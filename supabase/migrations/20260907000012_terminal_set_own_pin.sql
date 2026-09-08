-- Let somebody standing at a terminal actually finish replacing their PIN.
--
-- The bug, found by running the flow: a packer PINs in with the temporary PIN a
-- manager gave them, the lock screen asks them to choose their own, they do —
-- and it is STILL marked temporary, so they are asked again every single shift.
--
-- Why: set_team_pin decides `must_change` from whether the caller is setting
-- their OWN pin, tested as team.auth_user_id = auth.uid(). At a terminal the
-- caller is the TERMINAL's login, and the packer has no auth account at all, so
-- that test is false by construction. It can never be true for the exact people
-- the PIN exists for.
--
-- The fix is not to let the client assert "this is me". It is to ask the
-- database who is standing there: the open actor session at this terminal, which
-- only exists because somebody just entered that person's correct PIN. So the
-- proof of identity is the PIN they are replacing.
--
-- Deliberately no p_team_member_id argument. The only PIN this can change is the
-- one belonging to whoever is currently PIN'd in here, so a terminal cannot be
-- used to reset a colleague's PIN.

begin;

create or replace function public.terminal_set_own_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_term   public.team;
  v_actor  text;
  v_policy public.company_terminal_policy;
begin
  v_term := public.current_terminal();
  if v_term.team_member_id is null then
    raise exception 'This login is not a shared terminal.' using errcode = 'insufficient_privilege';
  end if;

  select s.team_member_id into v_actor
    from public.terminal_actor_session s
   where s.terminal_member_id = v_term.team_member_id
     and s.ended_at is null
     and s.expires_at > now();

  if v_actor is null then
    raise exception 'Nobody is signed in at this terminal.' using errcode = 'insufficient_privilege';
  end if;

  v_policy := public.terminal_policy(v_term.company_id);

  -- Same rules as set_team_pin. Kept here rather than shared through a helper
  -- because the messages are read by somebody standing at a machine mid-shift,
  -- and they should say what to do next.
  if p_pin !~ ('^[0-9]{' || v_policy.pin_length || '}$') then
    raise exception 'Your PIN needs to be exactly % digits.', v_policy.pin_length using errcode = 'check_violation';
  end if;
  if p_pin ~ '^(.)\1*$' then
    raise exception 'Pick a PIN that is not all the same digit.' using errcode = 'check_violation';
  end if;
  if position(p_pin in '01234567890') > 0 or position(p_pin in '09876543210') > 0 then
    raise exception 'Pick a PIN that is not a run of digits in order.' using errcode = 'check_violation';
  end if;

  update public.team_pin
     set pin_hash     = extensions.crypt(p_pin, extensions.gen_salt('bf', 10)),
         set_at       = now(),
         set_by       = 'self at terminal',
         must_change  = false,   -- theirs now
         failed_count = 0,
         locked_until = null
   where team_member_id = v_actor;
end;
$$;

revoke all on function public.terminal_set_own_pin(text) from public;
grant execute on function public.terminal_set_own_pin(text) to authenticated;

commit;
