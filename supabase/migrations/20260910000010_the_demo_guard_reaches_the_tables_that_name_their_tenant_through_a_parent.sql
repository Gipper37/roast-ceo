-- The demo guard reaches the tables that name their tenant through a parent.
--
-- 20260910000007 put the guard on the 141 tables that carry a company_id.
-- Forty-two more are tenant data by way of a parent — roast_temp_nodes and
-- roast_events through the session, customer_users through the customer,
-- pack_run_allocation through the run, recall_notice through the recall —
-- and a demo visitor could still write those. The row cannot say whose it
-- is, so the caller does: a person whose every active membership is in a
-- demo company writes nothing, on any table. That is the test the storage
-- guard already uses. It now runs first on every guarded table, ahead of
-- the row test, so a demo visitor's write is refused whether or not the row
-- has a company_id to look at.
--
-- A person with a real membership somewhere (staff trying the demo) is not
-- caught by it and falls through to the row test, as before. A shop buyer
-- has no memberships at all and is not caught either.
--
-- auth_is_demo_only() is rewritten as one pass over the caller's
-- memberships; it now runs on every row write, so it should be one scan of
-- a small table, not two.
--
-- Left out: server_error_events and login_events (telemetry, written by the
-- service role anyway) and the _snap_* scratch tables.

begin;

create or replace function public.auth_is_demo_only()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- bool_and over zero rows is null: no memberships → false.
  select coalesce((
    select bool_and(coalesce(c.is_demo, false))
      from public.team t
      join public.companies c on c.company_id = t.company_id
     where t.auth_user_id = auth.uid()
       and coalesce(t.is_active, true)
  ), false);
$$;

create or replace function public.guard_demo_readonly()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row     jsonb;
  v_company text;
  v_old     text;
begin
  -- No JWT: service role, cron, migrations. Already trusted; the reseed lives here.
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  v_row     := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_company := v_row->>'company_id';
  v_old     := case when tg_op = 'UPDATE' then to_jsonb(old)->>'company_id' else null end;

  -- Your own team row is yours to touch (help toggle, last-seen, name).
  -- role / company_id / is_active on it are refused by guard_team_privileged_columns.
  if tg_table_name = 'team' and tg_op = 'UPDATE'
     and (v_row->>'auth_user_id') = auth.uid()::text then
    return new;
  end if;

  -- The caller: a person who belongs only to demo companies writes nothing.
  if public.auth_is_demo_only() then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;

  -- The row: a demo company's row is not written by anyone with a JWT.
  if (v_company is not null or v_old is not null) and exists (
    select 1 from public.companies c
     where c.is_demo
       and (c.company_id = v_company or c.company_id = v_old)
  ) then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function public.guard_demo_readonly() is
  'Nothing is written by a caller who belongs only to demo companies, and a demo company''s row is written by nobody with a JWT. Service role, cron and migrations (no JWT) still may — that is how the demo is re-seeded.';

do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       and c.relrowsecurity
       and not exists (
         select 1 from pg_attribute a
          where a.attrelid = c.oid and a.attname = 'company_id' and not a.attisdropped)
       and c.relname not like '\_snap\_%'
       and c.relname not in ('server_error_events', 'login_events')
     order by 1
  loop
    execute format('drop trigger if exists aa_guard_demo_readonly on public.%I', r.relname);
    execute format(
      'create trigger aa_guard_demo_readonly before insert or update or delete on public.%I '
      'for each row execute function public.guard_demo_readonly()', r.relname);
    n := n + 1;
  end loop;
  raise notice 'demo guard on % parent-scoped tables', n;
end $$;

commit;
