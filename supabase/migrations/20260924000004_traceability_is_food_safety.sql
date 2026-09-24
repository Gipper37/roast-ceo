-- Traceability is food safety. It is not a separate thing.
--
-- Owner, 2026-09-24: "traceability is haccp only. thats the whole thing. why
-- would we surface tracability for any other reason."
--
-- He is right, and the permission table disagreed with him. Every other key in
-- the food-safety bundle is enterprise_plus — pack.run, pack.void,
-- pack.configure, recall.manage, recall.exercise — and trace.reconcile and
-- trace.waive were the two that leaked onto pro and enterprise.
--
-- The visible symptom: Social Hour Coffee Roasters, on the enterprise plan,
-- sees "6,601 roasts with no green behind them — 155,443.6 lbs that can't be
-- traced to a lot" permanently on their inventory page, while the Food Safety
-- section those roasts exist to serve is locked behind an upgrade wall. A
-- reconciliation queue for a recall they cannot run.
--
-- A roastery traces green to a lot to answer one question: which bags does
-- this affect. That question is a recall. There is no second reason, so there
-- is no plan on which tracing is useful and food safety is not.
--
-- NOT a role change. Who may reconcile within a subscribing tenant is
-- unchanged; this is only which plans include the capability at all.

begin;

delete from public.plan_permissions
 where permission_id in ('trace.reconcile', 'trace.waive')
   and plan_id in ('pro', 'enterprise', 'starter');

do $$
declare
  v_trace text;
  v_bundle text;
  v_odd int;
begin
  select string_agg(distinct plan_id, ', ' order by plan_id) into v_trace
    from plan_permissions
   where permission_id in ('trace.reconcile', 'trace.waive') and granted;

  select string_agg(distinct plan_id, ', ' order by plan_id) into v_bundle
    from plan_permissions
   where permission_id in ('pack.run', 'pack.void', 'pack.configure',
                           'recall.manage', 'recall.exercise') and granted;

  if v_trace is distinct from v_bundle then
    raise exception 'traceability (%) does not match the food-safety bundle (%)', v_trace, v_bundle;
  end if;

  -- Both keys must still be granted SOMEWHERE, or this silently removed the
  -- feature from everyone: an unknown or ungranted key denies for every role.
  select count(*) into v_odd from plan_permissions
   where permission_id in ('trace.reconcile', 'trace.waive') and granted;
  if v_odd < 2 then
    raise exception 'traceability is now granted on no plan at all (% grant rows)', v_odd;
  end if;

  raise notice 'traceability now matches food safety: %', v_trace;
  raise notice 'NOTE pack.bin_card is still granted on % — flagged, not changed',
    (select string_agg(distinct plan_id, ', ' order by plan_id)
       from plan_permissions where permission_id = 'pack.bin_card' and granted);
end $$;

commit;
