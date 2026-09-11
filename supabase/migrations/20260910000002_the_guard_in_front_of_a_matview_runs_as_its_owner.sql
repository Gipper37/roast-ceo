-- The guard in front of a materialized view has to run as its owner.
--
-- 20260910000001 put a plain view with the original name in front of each of
-- the three renamed matviews, filtered on auth_company_ids(), and revoked the
-- matview itself from authenticated so nobody could read around the guard.
-- It also — in its first step — set security_invoker on every view, the
-- scoped fronts included. Those two decisions contradict each other: a
-- security_invoker view checks the CALLER's rights on what it reads, and the
-- caller has none on mv_*, so on staging every one of those views answered
-- "permission denied for materialized view".
--
-- A matview has no RLS to inherit, so "run as the caller" buys nothing here.
-- These three views run as their owner (postgres) and the WHERE clause is the
-- protection: auth_company_ids() reads the session's JWT regardless of who
-- owns the view, and rolbypassrls is checked against current_user — which is
-- still the caller, not the owner. Proven by the same three probes 000001
-- was meant to pass: bare authenticated → 0 rows, an impersonated member →
-- only their companies, service_role → everything.
--
-- The three plain views that read order_graphs_week keep security_invoker;
-- what they need is SELECT on the front view, which authenticated has.

begin;

do $$
declare
  v text;
begin
  foreach v in array array['order_graphs_week', 'weekly_coffee_stock_by_origin', 'monthly_consumable_stock_by_item']
  loop
    if (select relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = v) = 'v' then
      execute format('alter view public.%I set (security_invoker = false)', v);
      execute format('comment on view public.%I is %L', v,
        'Tenant-scoped front for mv_' || v || '. security_invoker is deliberately OFF: '
        || 'this view is the guard, the caller has no rights on the matview, and the WHERE '
        || 'clause (auth_company_ids() / rolbypassrls) is what protects it. Any future sweep '
        || 'that flips views to security_invoker must skip the mv_ fronts. If the matview '
        || 'ever gains columns, recreate this view (select * is frozen at creation).');
      raise notice 'security_invoker=false on the mv_ front: %', v;
    end if;
  end loop;
end $$;

commit;
