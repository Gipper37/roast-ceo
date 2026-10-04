-- Five tables in public hold tenant data with RLS off and a grant to
-- `authenticated`, which is every logged-in user of every tenant.
--
-- Found 2026-10-04 while reviewing a migration that was about to create a sixth
-- one the same way. The reviewer caught it in the new file; checking prod showed
-- it was already true five times over.
--
-- ── Why it happens, so the sixth one does not ─────────────────────────────
--
-- Supabase ships default privileges on the public schema:
--
--   pg_default_acl, role postgres, tables:
--     {postgres=arwdDxtm, authenticated=arwdDxtm, service_role=arwdDxtm}
--   pg_default_acl, role supabase_admin, tables:
--     {postgres=..., anon=arwdDxtm, authenticated=arwdDxtm, service_role=...}
--
-- So `create table public.anything` is born granted to authenticated, with ALL
-- privileges: select, insert, update, delete. That is the intended Supabase
-- convention, and it is safe ONLY because RLS is supposed to be the fence. RLS
-- defaults OFF, and a migration writing a quick snapshot table does not think
-- of itself as publishing an API. PostgREST exposes every table in public that
-- the role can reach, so it published five.
--
-- The grants are therefore NOT the bug and are not revoked here: revoking them
-- would make this schema's convention inconsistent, and the next table would
-- still be born open. RLS with no policy is the fix. It denies every role
-- except the owner and service_role, which is exactly what a snapshot wants,
-- and it leaves the data in place as the undo path these tables exist to be.
--
-- ── What was exposed ──────────────────────────────────────────────────────
--
--   table                              rows  company_id  what it holds
--   _snap_planned_lots_20260905         122  yes         roast plans
--   lot_backfill_audit                   21  yes         4 companies' lot edits
--   _snap_receipt_pending_20260905        4   yes         purchase amounts and cost/lb
--   _snap_shusa_payments_off_20260905     2   yes         payment values
--   _mcr_adopt_open_ar_snapshot         201   no          one roaster's open A/R
--
-- 350 rows, four companies, every one readable AND writable through PostgREST
-- by any authenticated user of any tenant. Nothing in the frontend references
-- any of them, so the read is the whole exposure: no feature breaks by closing
-- it, and nothing was relying on the openness.
--
-- Not dropped, deliberately. Each one is the undo path for a migration that
-- rewrote money or lots, and 20261004000005 and 20261004000006 both leave
-- another behind on purpose. Deleting an audit trail to close a read hole trades
-- one problem for a worse one.
--
-- ── The recurrence guard ──────────────────────────────────────────────────
--
-- scripts/module-install-test.sh gains a check that no table in public has RLS
-- off while granted to anon or authenticated, so the sixth one fails a release
-- check instead of sitting there. A migration cannot guard the future; a release
-- check can.

begin;

do $lock$
declare
  v_t   text;
  v_n   int := 0;
  v_tables text[] := array[
    '_mcr_adopt_open_ar_snapshot',
    '_snap_planned_lots_20260905',
    '_snap_receipt_pending_20260905',
    '_snap_shusa_payments_off_20260905',
    'lot_backfill_audit'
  ];
begin
  foreach v_t in array v_tables loop
    -- Absent is fine. These are per-incident tables and another database will
    -- not hold the same set; a migration that asserts one database's tables
    -- exist is a migration that cannot pass the staging gate, which this repo
    -- learned three times in one day.
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_t and c.relkind = 'r'
    ) then
      raise notice 'not here: %', v_t;
      continue;
    end if;

    execute format('alter table public.%I enable row level security', v_t);
    -- No policy is created. No policy means no row is visible to a role that is
    -- not the owner and is not BYPASSRLS, which is what a snapshot wants. A
    -- policy would be a decision about who may read a dead table, and the
    -- answer is nobody.
    v_n := v_n + 1;
    raise notice 'locked: public.% now has RLS on and no policy', v_t;
  end loop;

  raise notice 'enabled row level security on % snapshot table(s)', v_n;
end $lock$;

do $verify$
declare v_bad int; v_rec record;
begin
  -- 1. Every table this file names, that exists, now has RLS on.
  select count(*) into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname = any (array['_mcr_adopt_open_ar_snapshot','_snap_planned_lots_20260905',
                               '_snap_receipt_pending_20260905','_snap_shusa_payments_off_20260905',
                               'lot_backfill_audit'])
     and not c.relrowsecurity;
  if v_bad > 0 then
    raise exception '% named table(s) still have row level security off', v_bad;
  end if;

  -- 2. And none of them gained a policy, which would undo the point.
  select count(*) into v_bad from pg_policies
   where schemaname = 'public'
     and tablename = any (array['_mcr_adopt_open_ar_snapshot','_snap_planned_lots_20260905',
                               '_snap_receipt_pending_20260905','_snap_shusa_payments_off_20260905',
                               'lot_backfill_audit']);
  if v_bad > 0 then
    raise exception '% policy(ies) exist on a snapshot table; no row should be visible to anyone', v_bad;
  end if;

  -- 3. The data is still there. Closing a read hole must not have emptied the
  --    audit trail it was protecting.
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
              where n.nspname='public' and c.relname='lot_backfill_audit') then
    execute 'select count(*) from public.lot_backfill_audit' into v_bad;
    if v_bad = 0 then
      raise exception 'lot_backfill_audit is empty; the lock-down must not delete rows';
    end if;
    raise notice 'lot_backfill_audit still holds % row(s)', v_bad;
  end if;

  -- 4. Report, do not assert, what ELSE is still open. Another database holds
  --    other tables and this file is not a schema-wide sweep; the release check
  --    is. Anything printed here is a real finding on this database.
  for v_rec in
    select c.relname,
           (select string_agg(distinct g.grantee, ',' order by g.grantee)
              from information_schema.role_table_grants g
             where g.table_schema='public' and g.table_name=c.relname
               and g.grantee in ('anon','authenticated')) as exposed_to
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
       and exists (select 1 from information_schema.role_table_grants g
                    where g.table_schema='public' and g.table_name=c.relname
                      and g.grantee in ('anon','authenticated'))
     order by 1
  loop
    raise notice 'STILL OPEN on this database: public.% is readable by %', v_rec.relname, v_rec.exposed_to;
  end loop;
end $verify$;

commit;
