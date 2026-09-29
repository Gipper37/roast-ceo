-- Remove roast_shortfall.resolve. It was a duplicate of a key that already ships.
--
-- 20260929000001 added `roast_shortfall.resolve` on the reasoning that
-- roast_lot_shortfall "is read by nothing in the application". That was wrong,
-- and the mistake was in the method: I grepped the frontend for the TABLE name
-- and got no hits, then concluded the ledger was invisible. The UI reaches it
-- through RPCs, so the table name never appears.
--
-- What actually ships, since 2026-09-08:
--   app/app/(app)/inventory/UnassignedLots.tsx   the queue, beside ReceiptsToRecord
--   lib/inventory/traceActions.ts                attribute_unsourced_roasts,
--                                                waive_roast_shortfall,
--                                                unwaive_roast_shortfall
--   trace.reconcile   name the lots behind a roast. Held by accounting_admin,
--                     company_admin, facility_admin, manager, roastery_manager,
--                     roastmaster -- whoever records purchases.
--   trace.waive       accept the gap. company_admin and facility_admin only,
--                     because it is a signature rather than data entry.
--
-- `roast_shortfall.resolve` meant exactly what trace.waive already means, and
-- would have been a second key over one action -- the failure 20260926000014 was
-- written to undo. Two keys over one action is worse than none: whichever the
-- code names, the other silently grants nothing to nobody, and the role matrix
-- says the feature is available to people who cannot reach it.
--
-- The 2,889 unresolved rows are not evidence that nobody can act on them. The
-- queue is deliberately bounded -- fs_settings.trace_start_date keeps
-- pre-implementation history out, and naming is hard-limited to roasts at or
-- before a group's count anchor, because after it the replay looked at real
-- stock and found nothing, and that is a finding rather than something to paper
-- over. Reporting "zero ever waived" as a defect was the same mistake twice.

begin;

-- role_permissions has an FK to permissions, so the grants go first.
delete from public.role_permissions where permission_id = 'roast_shortfall.resolve';
delete from public.plan_permissions  where permission_id = 'roast_shortfall.resolve';
delete from public.permissions       where permission_id = 'roast_shortfall.resolve';

do $verify$
declare v_bad int;
begin
  if exists (select 1 from public.permissions where permission_id = 'roast_shortfall.resolve') then
    raise exception 'roast_shortfall.resolve is still registered';
  end if;
  select count(*) into v_bad from public.role_permissions where permission_id = 'roast_shortfall.resolve';
  if v_bad > 0 then raise exception '% orphan grant(s) left behind', v_bad; end if;

  -- And the keys that DO own this action are still whole, so removing the
  -- duplicate cannot have taken the real thing with it.
  if not exists (select 1 from public.permissions where permission_id = 'trace.waive')
     or not exists (select 1 from public.permissions where permission_id = 'trace.reconcile') then
    raise exception 'the trace keys are missing; this migration removed the wrong one';
  end if;
  select count(*) into v_bad from public.role_permissions
   where permission_id = 'trace.reconcile' and granted;
  if v_bad = 0 then raise exception 'trace.reconcile is granted to no role'; end if;
  select count(*) into v_bad from public.role_permissions
   where permission_id = 'trace.waive' and granted;
  if v_bad = 0 then raise exception 'trace.waive is granted to no role'; end if;
end;
$verify$;

commit;
