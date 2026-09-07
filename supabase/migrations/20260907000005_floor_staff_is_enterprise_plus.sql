-- Floor staff is enterprise_plus, not every plan.
--
-- 20260907000004 shipped team.floor_staff ungated on the reasoning that
-- "naming the people who do the work is not an upsell". Owner, 2026-09-07:
-- "make it plan gated enterprise plus for non login staff." Overruled, and the
-- owner is right on the product question: floor staff exist to be stamped on
-- records and to PIN in at a shared terminal, and both of those are the
-- enterprise_plus food-safety module. A starter tenant has nothing to do with
-- a person who cannot log in.
--
-- Resolution ANDs is_plan_gated with plan_permissions (S/lib/permissions/server.ts:287
-- for the request snapshot, :225 for the single check), so flipping the flag and
-- the four rows denies the key on both the display and the server side. The UI
-- already hides the Floor staff add affordance behind usePermission, and
-- addFloorStaff / updateTeamMemberDetails both requirePermission it.
--
-- The team RECORD columns stay ungated on purpose — job_title, department,
-- shift, started_on and reports_to are plain fields on rows every plan already
-- has, and updateTeamMemberDetails is how a title gets edited on an ACCOUNT
-- row too. Only creating and managing people who never log in is gated.

begin;

update public.permissions
   set is_plan_gated = true
 where permission_id = 'team.floor_staff';

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'team.floor_staff', false, 'Floor staff is part of the enterprise_plus food-safety module'),
  ('pro',             'team.floor_staff', false, 'Floor staff is part of the enterprise_plus food-safety module'),
  ('enterprise',      'team.floor_staff', false, 'Floor staff is part of the enterprise_plus food-safety module'),
  ('enterprise_plus', 'team.floor_staff', true,  'Floor staff — enterprise_plus only (owner, 2026-09-07)')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

commit;
