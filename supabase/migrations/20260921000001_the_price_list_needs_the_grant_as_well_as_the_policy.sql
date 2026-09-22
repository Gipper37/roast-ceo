-- anon may be named in the policy and still be refused at the door.
--
-- 20260920000007 widened catalog_read on subscription_plans to anon so the
-- marketing pricing page could read it without the service-role key. It was
-- right about the policy and it never issued the GRANT, and its probe only
-- checked the policy, so it passed.
--
-- Staging already carried `grant select ... to anon` from some earlier state,
-- so there the policy change was enough and everything worked. Prod never had
-- it. A grant is checked before RLS is consulted at all, so on prod anon was
-- refused before the policy naming it was ever reached. The rehearsal could
-- not have caught this: the two databases differed in the half nobody looked
-- at.
--
-- It surfaced as a production BUILD failure, not a runtime one. /pricing is
-- prerendered, so the read happens while the site is being built:
--
--   Error: Could not load the price list: permission denied for table
--   subscription_plans
--
-- Reading the price list is the pricing page's whole job and the rows are
-- what we print on a billboard. SELECT only, this table only. A tenant's own
-- subscription lives in `subscriptions`, which is untouched and stays
-- company-scoped.

begin;

grant select on public.subscription_plans to anon;

do $probe$
declare
  v_rows int;
begin
  -- Both halves, because either one alone is a silent no.
  if not exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'public' and table_name = 'subscription_plans'
       and grantee = 'anon' and privilege_type = 'SELECT'
  ) then
    raise exception 'anon has no SELECT grant on subscription_plans';
  end if;

  if not exists (
    select 1 from pg_policy
     where polrelid = 'public.subscription_plans'::regclass
       and polname = 'catalog_read'
       and 'anon' = any (select rolname from pg_roles where oid = any(polroles))
  ) then
    raise exception 'catalog_read does not admit anon';
  end if;

  -- Checked WITHOUT becoming anon. The first version of this probe did
  -- `set local role anon`, read, and reset. The read worked and the role
  -- did not come back cleanly, so the CLI's own INSERT into
  -- supabase_migrations was refused: permission denied for schema
  -- supabase_migrations. The grant had committed and the version had not
  -- been recorded, which is a worse state than either outcome on its own.
  -- has_table_privilege answers the same question and changes nothing.
  if not has_table_privilege('anon', 'public.subscription_plans', 'SELECT') then
    raise exception 'anon still cannot read the price list';
  end if;
  select count(*) into v_rows from public.subscription_plans;

  if v_rows = 0 then
    raise exception 'anon can read subscription_plans but sees no rows, so the pricing page would render empty';
  end if;

  raise notice 'anon reads % plan(s).', v_rows;
end
$probe$;

commit;

notify pgrst, 'reload schema';
