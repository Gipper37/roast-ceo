-- A shared terminal is not a food safety feature.
--
-- Owner, after losing an afternoon to it: *"take that gate off, delete it."*
--
-- `terminal.manage` and `team.floor_staff` both carried
-- `permissions.feature_key = 'haccp'`, so with the Food safety module switched
-- off the Terminal column, the PIN column and even the Job title edit all
-- VANISHED from the Team Members table, with nothing on screen naming the
-- module. He had correctly guessed the connection to HACCP and was told it was
-- unrelated, which it was not.
--
-- ── WHY THESE TWO AND NOT THE OTHER FIVE ──────────────────────────────────
--
-- Seven permissions carried the key. Five of them are genuinely food safety and
-- keep it:
--
--   pack.configure   set the lot code format
--   pack.run         record bagging
--   pack.void        void a bagging run
--   recall.manage    run a recall
--   recall.exercise  run a practice recall
--
-- The two being freed are categorised **Team**, and that is the tell. A shared
-- machine on the floor asking whoever walks up for a PIN is ACCESS CONTROL. A
-- roastery that never records a bagging run still has one terminal in the pack
-- room and still wants to know who logged that order. Tying it to HACCP meant
-- "who is standing at this machine" could only be answered by a roastery that
-- had also opted into traceability, which is two unrelated decisions welded
-- together.
--
-- 🔴 The PLAN gate is untouched: both stay `is_plan_gated` and granted on
-- enterprise_plus only. The owner asked for the module gate removed, not for
-- the feature to be given away, and those are different questions.

begin;

update public.permissions
   set feature_key = null,
       updated_at  = now()
 where permission_id in ('terminal.manage', 'team.floor_staff');

comment on column public.permissions.feature_key is
  'Optional module this permission belongs to (company_feature.feature_key). NULL means the permission stands on its own and is gated only by role and plan. Keep it for things that are genuinely part of a module: a shared terminal and floor staff are ACCESS CONTROL, not food safety, and were wrongly gated on haccp until 20261023000004.';

-- 🔴 Asserts both halves: the two are free, and the five that should still be
-- gated still are. A migration that freed the wrong row would otherwise be
-- invisible until somebody without the module started recording bagging runs.
do $$
declare
  v_freed int;
  v_still int;
begin
  select count(*) into v_freed
    from public.permissions
   where permission_id in ('terminal.manage', 'team.floor_staff')
     and feature_key is null;
  if v_freed <> 2 then
    raise exception 'the terminal/floor-staff keys are still module gated (% of 2 freed)', v_freed;
  end if;

  select count(*) into v_still
    from public.permissions
   where permission_id in ('pack.configure', 'pack.run', 'pack.void',
                           'recall.manage', 'recall.exercise')
     and feature_key = 'haccp';
  if v_still <> 5 then
    raise exception 'a genuine food-safety permission lost its haccp gate (% of 5 still gated)', v_still;
  end if;
end $$;

commit;
