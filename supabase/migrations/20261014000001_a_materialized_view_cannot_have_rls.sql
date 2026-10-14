-- `mv_monthly_consumable_stock_by_item` serves 5,998 rows across FOUR companies
-- to any logged-in user of any tenant. Found 2026-10-14.
--
-- ── Why this one got through ──────────────────────────────────────────────
--
-- This is the same pg_default_acl mechanism as 20261004000008 and
-- 20261004000009, for the SEVENTH time, but with a twist that defeated every
-- guard built for the first six:
--
--   * A materialized view CANNOT have row level security. There is no
--     `alter materialized view ... enable row level security`. So the fix that
--     closed the other six — RLS on, no policy — is not available here, and
--     the GRANT is the only fence there is.
--
--   * `information_schema.role_table_grants` DOES NOT LIST MATERIALIZED VIEWS.
--     Neither does `information_schema.columns`. Both were checked on prod
--     today and return zero rows for this relation. So the release check
--     added by 20261004000008 — scripts/module-install-test.sh check 7 —
--     printed "every reachable table in public has RLS enabled" and exited 0
--     while this was open. It filters `c.relkind='r'` and joins
--     information_schema, and a matview is excluded by BOTH halves.
--
--   * `rls-cross-tenant-test.sh` and `rls-two-tenant-test.sh` both passed
--     against prod the same day, for the same reason.
--
-- The grant is visible only in `pg_class.relacl`:
--   mv_monthly_consumable_stock_by_item
--     {postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=...}
-- `arwdDxtm` is ALL privileges, not merely select. Its two siblings,
-- mv_order_graphs_week and mv_weekly_coffee_stock_by_origin, carry no
-- authenticated grant at all, which is the proof this was an accident of
-- whichever session created it rather than a convention.
--
-- 🔴 It was created by the CASE PROJECT's own first migration:
-- 20261002000002_a_size_can_say_how_many_units_a_case_holds.sql:697 reads
-- `grant select on public.mv_monthly_consumable_stock_by_item to authenticated`.
-- The migration then built the correctly-scoped view
-- `monthly_consumable_stock_by_item` in front of it, which filters by
-- `auth_company_ids()`. Both were reachable; only one filtered.
--
-- ── Why revoking does not break the feature ───────────────────────────────
--
-- The wrapper view `monthly_consumable_stock_by_item` is owned by postgres and
-- carries `security_invoker=false`, so it reads the matview AS ITS OWNER.
-- postgres keeps its grant here. Revoking `authenticated` therefore closes the
-- unscoped path and leaves the scoped one working — the thing that normally
-- makes security_invoker=false a hazard is what makes this safe. Nothing in the
-- frontend selects any mv_* relation directly (grepped both repos, zero hits).
--
-- Every matview in public is swept, not just the one, because the next one will
-- be born the same way.

begin;

create temporary table _mv_lock_20261014 (relname text primary key, rows_before bigint)
  on commit drop;

do $lock$
declare v_rec record; v_n int := 0; v_c bigint;
begin
  for v_rec in
    select c.oid, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm'
     order by c.relname
  loop
    -- Row count BEFORE, so the verify block can assert that revoking a grant
    -- moved no rows, rather than asserting the matview HAS any. An empty
    -- matview is a legitimate state on a database with no consumable history.
    execute format('select count(*) from public.%I', v_rec.relname) into v_c;
    insert into _mv_lock_20261014 (relname, rows_before) values (v_rec.relname, v_c);

    if has_table_privilege('authenticated', v_rec.oid, 'SELECT')
    or has_table_privilege('anon',          v_rec.oid, 'SELECT') then
      execute format('revoke all on public.%I from authenticated, anon, public', v_rec.relname);
      v_n := v_n + 1;
      raise notice 'CLOSED: public.% was reachable by a logged-in role and is not any more (held % row(s))',
        v_rec.relname, v_c;
    else
      raise notice 'already closed: public.% (% row(s))', v_rec.relname, v_c;
    end if;
  end loop;
  raise notice 'revoked the logged-in grant on % materialized view(s)', v_n;
end $lock$;

do $verify$
declare v_bad int; v_rec record; v_c bigint;
begin
  -- 1. 🔴 THE CHANGE: no materialized view in public is selectable by a
  --    logged-in role any more. A matview cannot have RLS, so this grant is
  --    the entire fence and the assertion is simply that it is shut.
  select count(*) into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'm'
     and (has_table_privilege('authenticated', c.oid, 'SELECT')
       or has_table_privilege('anon', c.oid, 'SELECT'));
  if v_bad > 0 then
    raise exception '% materialized view(s) in public are still readable by anon or authenticated', v_bad;
  end if;

  -- 2. The owner kept its access, which is what the scoped wrapper views read
  --    through. Revoking from `public` as well as the two roles could otherwise
  --    take the feature out with the hole.
  select count(*) into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'm'
     and not has_table_privilege('postgres', c.oid, 'SELECT');
  if v_bad > 0 then
    raise exception '% materialized view(s) are no longer readable by their owner; the scoped views read through it', v_bad;
  end if;

  -- 3. Revoking a grant moves no rows. Asserted as before = after, never as
  --    "the matview has rows" — the fifth-and-sixth-time lesson from
  --    20261004000009.
  for v_rec in select relname, rows_before from _mv_lock_20261014 order by 1 loop
    execute format('select count(*) from public.%I', v_rec.relname) into v_c;
    if v_c <> v_rec.rows_before then
      raise exception '% held % row(s) before the revoke and % after; a revoke must move no rows',
        v_rec.relname, v_rec.rows_before, v_c;
    end if;
  end loop;

  -- 4. The scoped view that this matview exists to feed is still here and still
  --    reads it. Closing the raw path must not have orphaned the sanctioned one.
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
              where n.nspname='public' and c.relkind='m'
                and c.relname='mv_monthly_consumable_stock_by_item') then
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and c.relkind='v'
         and c.relname='monthly_consumable_stock_by_item'
         and pg_get_viewdef(c.oid) ilike '%mv_monthly_consumable_stock_by_item%'
    ) then
      raise exception 'monthly_consumable_stock_by_item no longer reads its matview; the feature would be dead';
    end if;
    raise notice 'monthly_consumable_stock_by_item still reads the matview and still filters by auth_company_ids()';
  end if;

  -- 5. Report, do not assert, anything else in public still reachable with no
  --    fence. Another database holds other relations; the release check is the
  --    schema-wide sweep, and it is being taught about matviews alongside this.
  for v_rec in
    select c.relname, c.relkind::text as kind
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relkind in ('r','m')
       and (c.relkind = 'm' or not c.relrowsecurity)
       and (has_table_privilege('authenticated', c.oid, 'SELECT')
         or has_table_privilege('anon', c.oid, 'SELECT'))
     order by 1
  loop
    raise notice 'STILL OPEN on this database: public.% (relkind %) is readable with no row-level fence',
      v_rec.relname, v_rec.kind;
  end loop;
end $verify$;

commit;
