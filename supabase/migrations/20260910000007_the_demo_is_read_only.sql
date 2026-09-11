-- The demo is read-only, and now the database knows it.
--
-- "Enter Demo" signs any visitor in as demo@strataroast.com — a company_admin
-- of the demo roastery on prod, enterprise_plus plan, 4,843 orders. The page
-- promises "View-only mode … buttons are visible but disabled". That promise
-- was kept by lib/demo-guard.ts, a helper that 31 of the action files import
-- and the rest do not, and that no API route calls at all. Nothing in the
-- database knew companies.is_demo existed, so every "any authenticated user
-- can…" finding in the audit was really "anyone on the internet can…".
--
-- One BEFORE trigger on every table that carries a company_id: if the row's
-- company is a demo company and the caller holds a JWT, the write is refused
-- with a sentence the toast can show. Callers with no JWT — the service role,
-- pg_cron's nightly refresh_demo_dates(), migrations — are untouched, which is
-- how the demo keeps getting re-seeded. A person may still update their OWN
-- team row (help toggle, last-seen, name); its privileged columns are guarded
-- by 20260908000034 and …0008.
--
-- Storage gets the same rule by a different test, because an object's tenant
-- is in its path, not a column: a caller whose every active membership is in
-- a demo company writes nothing to a bucket.
--
-- Left out on purpose: the _snap_sim_cleanup* snapshots and sales_state_backup
-- (scratch), and client_telemetry_events — error beacons from public demo
-- sessions are worth keeping.
--
-- Staging: neither company is flagged is_demo, so this is inert there until a
-- test transaction sets the flag. Prod: demo-aloha-coffee-roasters is the one
-- demo company; its only member is demo@strataroast.com.

begin;

-- ── 1. rows ───────────────────────────────────────────────────────────────
-- SECURITY DEFINER so the companies lookup does not depend on what RLS shows
-- the caller; auth.uid() is read from the request's JWT either way.
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

  if exists (
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
  'A row of a demo company is never written by a caller with a JWT. Service role, cron and migrations (no JWT) still may — that is how the demo is re-seeded.';

do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'company_id' and not a.attisdropped
     where n.nspname = 'public'
       and c.relkind = 'r'
       and c.relname not like '\_snap\_%'
       and c.relname not in ('sales_state_backup', 'client_telemetry_events')
     order by 1
  loop
    execute format('drop trigger if exists aa_guard_demo_readonly on public.%I', r.relname);
    execute format(
      'create trigger aa_guard_demo_readonly before insert or update or delete on public.%I '
      'for each row execute function public.guard_demo_readonly()', r.relname);
    n := n + 1;
  end loop;
  raise notice 'demo guard on % tables', n;
end $$;

-- ── 2. storage ────────────────────────────────────────────────────────────
create or replace function public.auth_is_demo_only()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
     and exists (
       select 1 from public.team t
        where t.auth_user_id = auth.uid() and coalesce(t.is_active, true))
     and not exists (
       select 1 from public.team t
         join public.companies c on c.company_id = t.company_id
        where t.auth_user_id = auth.uid()
          and coalesce(t.is_active, true)
          and not coalesce(c.is_demo, false));
$$;

comment on function public.auth_is_demo_only() is
  'True when the caller is signed in and every active membership they hold is in a demo company. False for service role (no JWT) and for shop buyers (no memberships).';

revoke all on function public.auth_is_demo_only() from public, anon;
grant execute on function public.auth_is_demo_only() to authenticated, service_role;

create or replace function public.guard_demo_readonly_storage()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if public.auth_is_demo_only() then
    raise exception 'The demo is read-only. Start a free trial to make it yours.'
      using errcode = 'insufficient_privilege';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists aa_guard_demo_readonly on storage.objects;
create trigger aa_guard_demo_readonly
  before insert or update or delete on storage.objects
  for each row execute function public.guard_demo_readonly_storage();

commit;
