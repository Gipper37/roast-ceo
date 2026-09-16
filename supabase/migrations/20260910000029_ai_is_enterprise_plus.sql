-- AI is Enterprise Plus.
--
-- Owner, 2026-09-15: "ai invoice, or ai anything is enterprise plus."
--
-- `invoice.process` — the AI invoice extraction — was granted on BOTH enterprise
-- and enterprise_plus. It is the one key in the app that spends STRATA's own
-- Anthropic credit on a tenant's behalf, so where it sits is a billing decision,
-- not a packaging nicety.
--
-- The app has been selling it wrong in two directions at once: inventory/page.tsx
-- advertises "AI-assisted invoice parsing (Pro+)" while the grant denied Pro
-- outright, so a Pro tenant could read the promise, open the uploader, upload a
-- file, and only then have the route answer 403 — leaving a staged row behind.
-- The copy is corrected alongside this.
--
-- No role changes: company_admin, facility_admin and manager keep it. The plan
-- is the gate.

begin;

update public.plan_permissions
   set granted = false
 where permission_id = 'invoice.process'
   and plan_id <> 'enterprise_plus';

update public.plan_permissions
   set granted = true
 where permission_id = 'invoice.process'
   and plan_id = 'enterprise_plus';

-- The key must actually BE plan-gated, or the grid above is decorative.
update public.permissions
   set is_plan_gated = true
 where permission_id = 'invoice.process'
   and is_plan_gated is distinct from true;

do $probe$
declare
  v_bad text;
begin
  select string_agg(plan_id || '=' || granted::text, ', ' order by plan_id)
    into v_bad
    from public.plan_permissions
   where permission_id = 'invoice.process'
     and granted <> (plan_id = 'enterprise_plus');
  if v_bad is not null then
    raise exception 'invoice.process is not enterprise_plus-only: %', v_bad;
  end if;

  if not exists (select 1 from public.permissions
                  where permission_id = 'invoice.process' and is_plan_gated) then
    raise exception 'invoice.process is not plan-gated, so the plan grid does nothing';
  end if;

  -- Somebody must still be able to use it.
  if not exists (select 1 from public.role_permissions
                  where permission_id = 'invoice.process' and granted) then
    raise exception 'no role holds invoice.process';
  end if;
end
$probe$;

commit;
