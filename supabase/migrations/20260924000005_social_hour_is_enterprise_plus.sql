-- Social Hour is on Enterprise Plus, and a bin card is a food-safety record.
--
-- Two corrections the owner made, both of which the data had wrong rather than
-- the app.
--
-- 1. BOTH Social Hour companies (US R7CbqHmA1j and UK 752af3ed-4) were
--    recorded as `enterprise`. They are on Enterprise Plus. The app was
--    reading the row correctly and telling them Food Safety needed an upgrade
--    they had already bought. Neither row carries a stripe_subscription_id —
--    these are set by hand — so nothing will overwrite this and nothing is now
--    out of step with Stripe.
--
-- 2. pack.bin_card was granted on starter, pro, enterprise AND
--    enterprise_plus, the only key in the food-safety bundle that was.
--    Owner: "production record, route sheet, whatever you want to call it but
--    it only gets initiated with haccp and tracing." A bin card is minted at
--    charge, carries a lot code and names the roaster — it is the paper trail
--    the recall reads, so it belongs with the rest of the bundle.
--
-- Together with 20260924000004 this makes one coherent gate: everything that
-- produces or consumes a traceability record is Enterprise Plus, and the two
-- tenants who actually do food safety are on Enterprise Plus.

begin;

update public.subscriptions
   set plan_id    = 'enterprise_plus',
       updated_at = now()
 where company_id in ('R7CbqHmA1j', '752af3ed-4')
   and plan_id <> 'enterprise_plus';

delete from public.plan_permissions
 where permission_id = 'pack.bin_card'
   and plan_id in ('starter', 'pro', 'enterprise');

do $$
declare
  v_bundle text;
  v_wrong  int;
  v_user   uuid;
  v_can    boolean;
begin
  -- Every food-safety key now names exactly the same plans.
  select string_agg(distinct plan_id, ', ' order by plan_id) into v_bundle
    from plan_permissions
   where permission_id in ('pack.run','pack.void','pack.configure','pack.bin_card',
                           'recall.manage','recall.exercise','trace.reconcile','trace.waive')
     and granted;
  if v_bundle is distinct from 'enterprise_plus' then
    raise exception 'the food-safety bundle spans % — it must be enterprise_plus alone', v_bundle;
  end if;

  -- Each key must still be granted, or it denies for every role in silence.
  select count(*) into v_wrong from (
    select permission_id from plan_permissions
     where permission_id in ('pack.run','pack.void','pack.configure','pack.bin_card',
                             'recall.manage','recall.exercise','trace.reconcile','trace.waive')
       and granted
     group by permission_id) x;
  if v_wrong <> 8 then
    raise exception 'only % of the 8 food-safety keys are granted anywhere', v_wrong;
  end if;

  if exists (select 1 from subscriptions
              where company_id in ('R7CbqHmA1j','752af3ed-4') and plan_id <> 'enterprise_plus') then
    raise exception 'a Social Hour company is still not on enterprise_plus';
  end if;

  -- Prove it end to end: a real Social Hour admin can now reach the feature.
  select t.auth_user_id into v_user
    from team t where t.company_id = 'R7CbqHmA1j' and t.role = 'company_admin'
     and t.auth_user_id is not null and coalesce(t.is_active, true) limit 1;
  if v_user is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_user::text)::text, true);
    select public.auth_has_permission('recall.manage', 'R7CbqHmA1j') into v_can;
    if not v_can then raise exception 'Social Hour still cannot reach recall.manage'; end if;
    select public.auth_has_permission('trace.reconcile', 'R7CbqHmA1j') into v_can;
    if not v_can then raise exception 'Social Hour still cannot reach trace.reconcile'; end if;
    perform set_config('request.jwt.claims', null, true);
    raise notice 'a Social Hour admin now reaches recall.manage and trace.reconcile';
  end if;

  raise notice 'food-safety bundle: 8 keys, % only; Social Hour US and UK on enterprise_plus', v_bundle;
end $$;

commit;
