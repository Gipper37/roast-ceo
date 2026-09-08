-- A packer can walk away from a session they opened. Voiding a recorded run is
-- still roastmaster work.
--
-- 20260908000007 made the lot code appear at OPEN, which is the whole point —
-- labels get printed and applied while the bags are being filled. The cost is
-- that a session started by mistake now holds a real lot code, and the only way
-- to get rid of it was void_pack_run, gated on pack.void: company_admin,
-- facility_admin, manager and roastmaster. A staff packer who opened the wrong
-- product could not undo it and would have had to find someone senior — or, far
-- more likely, close it out with fake numbers to make it go away.
--
-- The two cases are not the same act:
--
--   an OPEN session   has no bag count, no sources, no allocations and nothing
--                     downstream. Nothing has been asserted yet. Whoever opened
--                     it can drop it with the same pack.run they used to start.
--   a CLOSED run      is a signed food-safety record that other things point at.
--                     Unwinding it stays pack.void.
--
-- Either way the lot code is kept, never released. An open session may already
-- have had its labels printed and stuck on bags — that is the feature — so
-- next_lot_code must not hand the number out again.

begin;

create or replace function public.void_pack_run(p_pack_run_id text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run    record;
  v_actor  record;
  v_alloc  int;
  v_isopen boolean;
begin
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging run is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  v_isopen := v_run.closed_at is null;

  if v_isopen then
    -- Nothing has been asserted yet. The person who opened it can drop it.
    if not public.auth_has_permission('pack.run', v_run.company_id) then
      raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
    end if;
  else
    if not public.auth_has_permission('pack.void', v_run.company_id) then
      raise exception 'Voiding a recorded bagging run needs a supervisor. Ask your roastmaster or manager.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- A recorded run must say why. An abandoned session is self-explanatory, and
  -- demanding a sentence for "I picked the wrong product" is the kind of
  -- friction that gets worked around instead of complied with.
  if not v_isopen and coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why this run is being voided. A voided food-safety record without a reason is worse than no record.'
      using errcode = 'invalid_parameter_value';
  end if;

  if v_run.voided_at is not null then
    return jsonb_build_object('pack_run_id', p_pack_run_id, 'already_voided', true);
  end if;

  select count(*) into v_alloc from public.pack_run_allocation where pack_run_id = p_pack_run_id;
  select * into v_actor from public.actor_at();

  -- 🔴 THE LOT CODE IS NEVER RELEASED, open or closed. An open session is the
  -- case where labels have most likely ALREADY been printed and stuck on bags —
  -- that is what opening early is for — so the number has to stay spent.
  update public.pack_run
     set voided_at   = now(),
         voided_by   = v_actor.team_member_id,
         void_reason = coalesce(nullif(trim(p_reason), ''),
                                case when v_isopen then 'Session abandoned before any bags were recorded' end),
         updated_by  = v_actor.actor_name,
         updated_at  = now()
   where pack_run_id = p_pack_run_id;

  delete from public.pack_run_allocation where pack_run_id = p_pack_run_id;

  return jsonb_build_object(
    'pack_run_id', p_pack_run_id,
    'lot_code',    v_run.lot_code,
    'was_open',    v_isopen,
    'released_allocations', v_alloc);
end;
$$;

comment on function public.void_pack_run(text, text) is
  'Void a bagging run. An OPEN session (nothing recorded yet) can be dropped by whoever can bag; a CLOSED run needs pack.void and a stated reason. The lot code is kept reserved either way — labels may already be on bags.';

revoke all on function public.void_pack_run(text, text) from public;
grant execute on function public.void_pack_run(text, text) to authenticated;

commit;
