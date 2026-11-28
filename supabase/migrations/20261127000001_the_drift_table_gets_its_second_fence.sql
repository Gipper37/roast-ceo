-- roast_plan_drift was the one table left in `public` with RLS off.
--
-- 🔴 WHAT THE REPORT GOT RIGHT, AND WHAT IT GOT WRONG.
-- Right: RLS is off. Wrong: "anyone with the public app key can read or change
-- it". Measured against PROD before writing this, with the legacy anon JWT and
-- the new publishable key, and with subscription_plans as a positive control
-- that returned 200 on the same request shape:
--
--     roast_plan_drift  -> 401, 42501 permission denied for table
--     subscription_plans -> 200
--
-- Because 20261026000016:58 already did `revoke all ... from anon,
-- authenticated`, so neither role holds a single privilege. The grant layer
-- was the fence, and it held. This migration adds the SECOND fence, so that a
-- future `grant select` — or this database's default ACL, which hands new
-- tables to anon and authenticated automatically — cannot open the table on
-- its own.
--
-- 🔴 AND IT NEEDS NO POLICY. The report suggested adding one "so the hourly
-- check can still write". That would be the only way to get this wrong. The
-- writer is public.roast_plan_reconcile(), SECURITY DEFINER owned by postgres,
-- run by a pg_cron job (`35 * * * *`, username postgres). A table's OWNER is
-- exempt from its own RLS unless FORCE is set, and service_role carries
-- BYPASSRLS. So both writers are unaffected, and a permissive policy would
-- hand back exactly the access this is closing.
--
-- NOT forcing RLS, deliberately: `alter table ... force row level security`
-- would subject the owner to the policies, and with no policy that stops the
-- hourly reconcile dead.

begin;

alter table public.roast_plan_drift enable row level security;

-- No policy, on purpose. With RLS on and no policy, anon and authenticated are
-- denied twice over; postgres (owner, not forced) and service_role (BYPASSRLS)
-- are untouched.

do $$
declare
  v_rls     boolean;
  v_forced  boolean;
  v_pol     integer;
  v_grants  integer;
begin
  select relrowsecurity, relforcerowsecurity into v_rls, v_forced
    from pg_class
   where relname = 'roast_plan_drift' and relnamespace = 'public'::regnamespace;

  if not v_rls then
    raise exception 'roast_plan_drift still has RLS off';
  end if;

  if v_forced then
    raise exception 'roast_plan_drift has FORCE rls, which stops the hourly reconcile';
  end if;

  select count(*) into v_pol from pg_policies where tablename = 'roast_plan_drift';
  if v_pol <> 0 then
    raise exception 'roast_plan_drift has % policies; it is meant to have none', v_pol;
  end if;

  select count(*) into v_grants
    from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'roast_plan_drift'
     and grantee in ('anon', 'authenticated', 'PUBLIC');
  if v_grants <> 0 then
    raise exception 'anon/authenticated/PUBLIC hold % grants on roast_plan_drift', v_grants;
  end if;
end $$;

commit;
