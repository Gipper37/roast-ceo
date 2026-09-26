-- The module switch has to switch something off.
--
-- Seven permission keys name a feature_key of 'haccp' — pack.run, pack.void,
-- pack.configure, recall.manage, recall.exercise, terminal.manage,
-- team.floor_staff — and 17 SECURITY DEFINER functions gate on them. Every one
-- of those checks auth_has_permission, and auth_has_permission has never looked
-- at company_feature. The frontend does (lib/permissions/server.ts), so turning
-- Food Safety off removed the nav item and left every RPC behind it callable.
--
-- It also made one of my own migrations lie: 20260924000005 asserted "a Social
-- Hour admin can now reach the feature" by calling this function. It returned
-- true. The app showed them nothing, because the app was the only layer that
-- had ever honoured the switch.
--
-- WHY THIS IS SAFE TODAY, AND WILL NOT BE LATER. Measured on prod before
-- writing this:
--
--     companies with haccp enabled   0
--     team_pin rows                  0
--     pack_run rows                  0
--     recall rows                    0
--
-- Nothing anywhere depends on a module-gated key. The moment one roastery
-- switches Food Safety on, that stops being true and this becomes a behaviour
-- change instead of a correction. bin_card is deliberately unaffected —
-- pack.bin_card carries no feature_key, because a bin card is a production
-- record that works without HACCP (20260925000001).
--
-- Body from pg_get_functiondef(), patched in one place. Not retyped.

begin;

CREATE OR REPLACE FUNCTION public.auth_has_permission(p_permission_id text, p_company_id text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1
      from public.team t
      join public.role_permissions rp
        on rp.role_id = t.role and rp.permission_id = p_permission_id and rp.granted
      join public.permissions p
        on p.permission_id = p_permission_id
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
       and (p_company_id is null or t.company_id = p_company_id)
       and (
         not p.is_plan_gated
         or exists (
           select 1
             from public.company_subscription_status s
             join public.plan_permissions pp
               -- A trial IS the enterprise plan for as long as it lasts. The app
               -- has always resolved it that way (lib/permissions/server.ts);
               -- reading the raw plan_id here would have refused every plan-gated
               -- key to every tenant in their first 30 days — which is every new
               -- tenant company-signup creates.
               on pp.plan_id = (case when s.status = 'trialing' then 'enterprise' else s.plan_id end)
              and pp.permission_id = p_permission_id
              and pp.granted
            where s.company_id = t.company_id
         )
       )
       -- ── The module switch ────────────────────────────────────────────────
       -- A key that names a feature_key belongs to an OPTIONAL module, and a
       -- tenant chooses whether to use it (company_feature). The frontend has
       -- always honoured that — buildPermissionSnapshot computes
       -- `featureOk = !p.feature_key || enabledFeatures.has(p.feature_key)` —
       -- and this function never did. So the toggle was display-only: the nav
       -- item disappeared while all 17 RPCs behind it stayed callable over
       -- PostgREST.
       --
       -- It also made a migration lie. 20260924000005 proved "a Social Hour
       -- admin can now reach the feature" by calling THIS function, which
       -- returned true while the module was off and the app showed them
       -- nothing. A probe is only as good as the thing it asks.
       and (
         p.feature_key is null
         or exists (
           select 1
             from public.company_feature cf
            where cf.company_id = t.company_id
              and cf.feature_key = p.feature_key
              and cf.enabled
         )
       )
       -- ── The terminal narrowing ───────────────────────────────────────────
       -- An ordinary login is unaffected. A TERMINAL login must have somebody
       -- PIN'd in, and that person's own role has to grant the key too.
       and (
         not coalesce(t.is_terminal, false)
         or exists (
           select 1
             from public.terminal_actor_session ses
             join public.team pinned
               on pinned.team_member_id = ses.team_member_id
             join public.role_permissions rp2
               on rp2.role_id = pinned.role
              and rp2.permission_id = p_permission_id
              and rp2.granted
            where ses.terminal_member_id = t.team_member_id
              and ses.ended_at is null
              and ses.expires_at > now()
              and coalesce(pinned.is_active, true)
         )
       )
  );
$function$;


do $verify$
declare
  v_user text; v_key text; v_company text; v_can boolean; v_refs boolean;
begin
  -- 1. Structural: the function must actually consult the module table.
  select pg_get_functiondef(p.oid) ilike '%company_feature%' into v_refs
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'auth_has_permission';
  if not coalesce(v_refs, false) then
    raise exception 'auth_has_permission still ignores company_feature';
  end if;

  -- 2. Functional, and tenant-agnostic: find ANY active member whose role
  --    grants a feature-keyed permission their company has NOT switched on,
  --    and prove the answer is now no. Picked by query, never by id — a probe
  --    that needs one tenant's data has failed three times this week.
  select t.auth_user_id::text, p.permission_id, t.company_id
    into v_user, v_key, v_company
    from public.team t
    join public.role_permissions rp
      on rp.role_id = t.role and rp.granted
    join public.permissions p
      on p.permission_id = rp.permission_id and p.feature_key is not null
   where coalesce(t.is_active, true)
     and t.auth_user_id is not null
     and not exists (
       select 1 from public.company_feature cf
        where cf.company_id = t.company_id and cf.feature_key = p.feature_key and cf.enabled)
   limit 1;

  if v_user is null then
    raise notice 'no member holds a switched-off module key here; structural check only';
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    select public.auth_has_permission(v_key, v_company) into v_can;
    perform set_config('request.jwt.claims', null, true);
    if v_can then
      raise exception 'a switched-off module still grants % to a member of %', v_key, v_company;
    end if;
    raise notice 'module switch enforced: % is refused while its module is off', v_key;
  end if;
end $verify$;

commit;
