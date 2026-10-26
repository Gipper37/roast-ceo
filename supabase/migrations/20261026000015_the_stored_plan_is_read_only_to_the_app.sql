-- The stored plan is READ-ONLY to the app.
--
-- 20261026000012 created public.roast_plan and said:
--
--     line  84:  revoke all on table public.roast_plan       from anon;
--     line 104:  revoke all on table public.roast_plan_dirty from anon, authenticated;
--
-- The second line is right and the first is not. Supabase ships DEFAULT PRIVILEGES that
-- grant ALL on every new table in `public` to anon, authenticated and service_role, so a
-- `grant select ... to authenticated` does not NARROW anything -- it re-states one privilege
-- the role already had, next to INSERT, UPDATE, DELETE and TRUNCATE it also already had.
-- Revoking from `anon` alone left `authenticated` holding the lot. Verified on production:
--
--     has_table_privilege('authenticated','public.roast_plan','TRUNCATE')  ->  t
--
-- RLS does not save us here. The table has exactly one policy, roast_plan_read (SELECT), so
-- INSERT/UPDATE/DELETE are denied for want of a policy -- but TRUNCATE is a TABLE-level
-- privilege that row-level security never consults. Any signed-in user of any tenant could
-- empty the plan for every tenant at once. It is derived data and the drain would rebuild it,
-- so this is a denial of service on the roasting screen rather than data loss; that is not a
-- reason to leave it.
--
-- 🔴 The same default-privilege pattern holds on 189 public tables (project-wide, tracked as
-- M11 phase 2). This migration does NOT attempt that sweep -- a blanket revoke across 189
-- tables during a live shift is how you turn one bug into an outage. It fixes the two tables
-- this work created, the way 000012 should have.
--
-- Changes no read path: `authenticated` keeps SELECT, which is all any reader needs.

begin;

revoke all on table public.roast_plan from anon, authenticated;
grant select on table public.roast_plan to authenticated;

-- Belt and braces for the queue: 000012 got this one right, so this is a no-op that keeps
-- the two tables stated in one place rather than inferred from two different migrations.
revoke all on table public.roast_plan_dirty from anon, authenticated;

do $$
begin
  -- The privileges that must be GONE.
  if has_table_privilege('authenticated','public.roast_plan','TRUNCATE') then
    raise exception 'authenticated still holds TRUNCATE on roast_plan';
  end if;
  if has_table_privilege('authenticated','public.roast_plan','INSERT')
     or has_table_privilege('authenticated','public.roast_plan','UPDATE')
     or has_table_privilege('authenticated','public.roast_plan','DELETE') then
    raise exception 'authenticated still holds a write privilege on roast_plan';
  end if;
  if has_table_privilege('anon','public.roast_plan','SELECT') then
    raise exception 'anon can still read roast_plan';
  end if;

  -- The privilege that must REMAIN, or every reader breaks the moment it cuts over.
  if not has_table_privilege('authenticated','public.roast_plan','SELECT') then
    raise exception 'authenticated lost SELECT on roast_plan; readers would 403';
  end if;

  -- RLS must still be the thing scoping rows, not the grant.
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='roast_plan' and c.relrowsecurity
  ) then
    raise exception 'row level security is off on roast_plan';
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='roast_plan' and cmd='SELECT'
  ) then
    raise exception 'roast_plan has no SELECT policy; authenticated would read nothing';
  end if;

  raise notice 'roast_plan is read-only to authenticated, scoped by RLS';
end $$;

commit;
