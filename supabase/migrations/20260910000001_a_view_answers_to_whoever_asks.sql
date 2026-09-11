-- A view answers to whoever asks — not to whoever created it.
--
-- Two independent audits (2026-09-09 / 2026-09-10) found the same thing from
-- six directions: 24 views in public (25 on staging, with pack_run_remaining)
-- are owned by postgres, carry no security_invoker, and are SELECT-granted to
-- authenticated. postgres has BYPASSRLS, and a view without security_invoker
-- runs as its owner, so the RLS on orders / order_details / customers /
-- contacts / equipment_schedule / roast_log underneath them was never
-- evaluated. Reproduced on prod as a bare `authenticated` role with no JWT:
--
--   order_profitability               15,131 rows across 5 companies
--   product_margins                      741 rows  (and auto-UPDATABLE)
--   totals                             1,042 rows
--   order_graphs_weekly_avg_by_month     163 rows  (revenue, COGS, margin)
--   contacts_view                        280 rows  (customer contacts, emails)
--   company_subscription_status            5 rows  (every tenant's plan)
--   equipment_due_status                  48 rows
--
-- 20260828000015 diagnosed exactly this class, fixed three views, and stopped.
-- `create or replace view` silently drops the reloption, which is how a fixed
-- view regresses; the migration-lint check that catches that is a separate
-- change. `scripts/rls-cross-tenant-test.sh` now walks views as well as tables.
--
-- Three of the offenders are MATERIALIZED views, which cannot take
-- security_invoker and have no RLS of their own. Those are renamed to mv_*
-- (the refresh job and refresh_order_graphs() follow the rename) and a plain
-- view with the ORIGINAL name is put in front of each, filtering on
-- auth_company_ids() — so the frontend reads the same name it always did and
-- sees only its own tenant. Roles that bypass RLS (postgres, service_role)
-- see everything through those views too, exactly as they would through a
-- table; the predicate mirrors RLS rather than inventing a second rule.
--
-- Every base table under every view already carries a SELECT policy for
-- authenticated (checked on prod and staging before writing this), so no view
-- goes blank for a legitimate reader — it goes blank for the wrong one.
--
-- Also: authenticated held INSERT/UPDATE/DELETE/TRUNCATE on every view. On an
-- aggregate that is noise; on product_margins it was a live write path
-- (is_updatable = YES). Revoked everywhere.

begin;

-- ── 1. Every plain view runs as the caller ────────────────────────────────
do $$
declare
  v record;
begin
  for v in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'v'
       and coalesce(array_to_string(c.reloptions, ','), '') not ilike '%security_invoker=true%'
     order by c.relname
  loop
    execute format('alter view public.%I set (security_invoker = true)', v.relname);
    raise notice 'security_invoker=true: %', v.relname;
  end loop;
end $$;

-- ── 2. Materialized views go behind a tenant-scoped view of the same name ──
do $$
declare
  mv          text;
  mv_oid      oid;
  dep         record;
  deps        text[] := '{}';
  defs        text[] := '{}';
  i           int;
  j           record;
begin
  foreach mv in array array['order_graphs_week', 'weekly_coffee_stock_by_origin', 'monthly_consumable_stock_by_item']
  loop
    mv_oid := to_regclass('public.' || mv);
    if mv_oid is null then
      raise notice 'skip %: does not exist here', mv;
      continue;
    end if;
    if (select relkind from pg_class where oid = mv_oid) <> 'm' then
      raise notice 'skip %: already a view (migration re-run)', mv;
      continue;
    end if;

    -- Capture the plain views that read this matview BEFORE the rename: their
    -- text still names the old identifier, which after step 2c resolves to
    -- the scoped view. (Dependents reference the matview by OID, so without
    -- this re-create they would keep reading the raw, unscoped matview.)
    deps := '{}'; defs := '{}';
    for dep in
      select distinct c.relname,
             rtrim(pg_get_viewdef(c.oid, true), E'; \n\t') as def
        from pg_rewrite r
        join pg_depend d on d.objid = r.oid and d.classid = 'pg_rewrite'::regclass
        join pg_class c on c.oid = r.ev_class
        join pg_namespace n on n.oid = c.relnamespace
       where d.refobjid = mv_oid and d.refclassid = 'pg_class'::regclass
         and c.relkind = 'v' and n.nspname = 'public' and c.oid <> mv_oid
    loop
      deps := deps || dep.relname;
      defs := defs || dep.def;
    end loop;

    -- 2a. rename the matview out of the way; indexes and the unique index the
    --     CONCURRENTLY refresh needs come with it
    execute format('alter materialized view public.%I rename to %I', mv, 'mv_' || mv);
    execute format('revoke all on public.%I from anon, authenticated', 'mv_' || mv);

    -- 2b. the view the app reads, under the old name
    execute format($f$
      create view public.%I with (security_invoker = true) as
        select *
          from public.%I
         where company_id in (select public.auth_company_ids())
            or (select rolbypassrls from pg_roles where rolname = current_user)
    $f$, mv, 'mv_' || mv);
    execute format('grant select on public.%I to authenticated, service_role', mv);
    execute format('comment on view public.%I is %L', mv,
      'Tenant-scoped front for mv_' || mv || '. Refresh the mv_, read this. '
      || 'If the matview ever gains columns, recreate this view (select * is frozen at creation).');

    -- 2c. re-point the dependents at the scoped view
    for i in 1 .. coalesce(array_length(deps, 1), 0) loop
      execute format('create or replace view public.%I with (security_invoker = true) as %s', deps[i], defs[i]);
      raise notice 're-pointed % at the scoped %', deps[i], mv;
    end loop;

    -- 2d. the hourly refresh follows the rename. pg_cron exists on prod only,
    --     so this branch cannot be rehearsed on staging — it is therefore not
    --     allowed to abort the release: a failure here degrades to a stale
    --     matview and a WARNING in the push log, never a half-applied tag.
    if to_regclass('cron.job') is not null then
      for j in select jobid, command from cron.job where command ilike '%' || mv || '%' loop
        begin
          perform cron.alter_job(job_id => j.jobid,
                                 command => replace(j.command, 'public.' || mv, 'public.mv_' || mv));
          raise notice 'cron job % now refreshes mv_%', j.jobid, mv;
        exception when others then
          begin
            update cron.job
               set command = replace(command, 'public.' || mv, 'public.mv_' || mv)
             where jobid = j.jobid;
            raise notice 'cron job % re-pointed at mv_% (direct update; alter_job said: %)', j.jobid, mv, sqlerrm;
          exception when others then
            raise warning 'cron job % still refreshes % — fix by hand: %', j.jobid, mv, sqlerrm;
          end;
        end;
      end loop;
    end if;

    raise notice 'matview % -> mv_% behind a scoped view', mv, mv;
  end loop;
end $$;

-- The one refresher that names its matview from inside a function.
create or replace function public.refresh_order_graphs()
returns void
language plpgsql
as $$
begin
  refresh materialized view concurrently public.mv_order_graphs_week;
end;
$$;

-- ── 3. Nobody writes through a view ───────────────────────────────────────
do $$
declare
  v record;
begin
  for v in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'v'
  loop
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated', v.relname);
  end loop;
end $$;

commit;
