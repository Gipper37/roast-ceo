-- `_case_conversion_20261004` was created with row level security OFF and the
-- schema's default grant, so on staging it is served to anon and authenticated
-- alike. It holds one roaster's bill-of-materials quantities and the size rows
-- behind their packaging costs.
--
-- 20261004000005 created it. 20261004000008, three files later, exists
-- specifically to close five tables that were open for exactly this reason, and
-- added a release check so a sixth could not happen. The sixth was created by
-- the file three before the fix, by me, and the release check caught it on
-- staging rather than on production. Worth writing down plainly: the guard
-- worked, the author did not read his own finding before writing the next
-- migration.
--
-- 20261004000006 did it right, which is the proof it was knowable: its
-- `_case_conversion_20261004_uk` enables RLS, creates no policy, and drops
-- itself when empty, so on staging the table is not there at all.
--
-- Same treatment as 20261004000008: RLS on, no policy. No policy means no row
-- is visible to any role that is not the owner or BYPASSRLS, which is what a
-- snapshot wants. The grants are deliberately left alone, because revoking them
-- would make the schema's convention inconsistent and the next table would
-- still be born open. The rows stay, because the table IS the undo path for a
-- migration that rewrote packaging quantities.
--
-- Absent is fine and reported, not raised: the table exists only where
-- 20261004000005 found cases to convert, which is one tenant on one database.

begin;

-- Row counts BEFORE the lock, so the verify block can assert that enabling RLS
-- changed no data rather than asserting the table has any. An EMPTY snapshot is
-- a legitimate state: 20261004000005 creates the table and converts nothing on a
-- database with no cases, which is exactly what staging is.
create temporary table _lock_counts_20261004000009 (relname text primary key, n bigint)
  on commit drop;

do $lock$
declare v_n int := 0; v_t text; v_c bigint;
begin
  foreach v_t in array array['_case_conversion_20261004', '_case_conversion_20261004_uk'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_t and c.relkind = 'r'
    ) then
      raise notice 'not here: % (its migration either skipped or dropped an empty snapshot)', v_t;
      continue;
    end if;
    execute format('select count(*) from public.%I', v_t) into v_c;
    insert into _lock_counts_20261004000009 (relname, n) values (v_t, v_c);
    execute format('alter table public.%I enable row level security', v_t);
    v_n := v_n + 1;
    raise notice 'locked: public.% now has RLS on and no policy', v_t;
  end loop;
  raise notice 'enabled row level security on % case-conversion snapshot(s)', v_n;
end $lock$;

do $verify$
declare v_bad int; v_rec record;
begin
  -- 1. Any case-conversion snapshot that exists here now has RLS on.
  select count(*) into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname like '\_case\_conversion%'
     and not c.relrowsecurity;
  if v_bad > 0 then
    raise exception '% case-conversion snapshot(s) still have row level security off', v_bad;
  end if;

  -- 2. And none gained a policy, which would undo the point.
  select count(*) into v_bad from pg_policies
   where schemaname = 'public' and tablename like '\_case\_conversion%';
  if v_bad > 0 then
    raise exception '% policy(ies) exist on a case-conversion snapshot; no row should be visible to anyone', v_bad;
  end if;

  -- 3. 🔴 The lock changed no DATA. Asserted as before = after, never as
  --    "the table has rows".
  --
  --    The first draft of this file raised when the snapshot was empty, and
  --    staging refused it: 20261004000005 creates the table and converts
  --    nothing on a database with no cases to convert, so empty is correct
  --    there. That is the fifth time in two days that a migration asserted a
  --    database's DATA rather than its own change, and this file was written
  --    about that mistake, so it is worth the extra paragraph.
  --
  --    What is genuinely invariant is that ALTER TABLE ... ENABLE ROW LEVEL
  --    SECURITY moves no rows. Comparing the count either side says so and is
  --    true on an empty table, a full one, and a database without the table.
  for v_rec in select relname, n from _lock_counts_20261004000009 order by 1 loop
    execute format('select count(*) from public.%I', v_rec.relname) into v_bad;
    if v_bad <> v_rec.n then
      raise exception '% held % row(s) before the lock and % after; enabling RLS must move no rows',
        v_rec.relname, v_rec.n, v_bad;
    end if;
    raise notice '% holds % row(s), unchanged by the lock', v_rec.relname, v_bad;
  end loop;

  -- 4. Report what else is still open HERE, without deciding the release on it.
  --    Another database holds other tables and this file is not a schema sweep;
  --    scripts/module-install-test.sh check 7 is. Anything printed is real.
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
