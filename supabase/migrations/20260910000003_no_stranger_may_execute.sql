-- No stranger may execute.
--
-- Every function in public was executable by the public anon key: Postgres
-- grants EXECUTE to PUBLIC on every new function by default, and 153 functions
-- on prod additionally carry an explicit anon grant from the project's default
-- privileges. That is how ensure_company_pricing_default() (SECURITY DEFINER,
-- takes the tenant as an argument) could be called with nothing but the key
-- that ships in every page bundle, how process_staged_imports() would write
-- roast history into any company the caller names the day its table reference
-- is repaired, and why the save_shipment_lines lesson of 2026-08-04 (a new
-- signature silently re-opened to PUBLIC) keeps recurring — the audits found
-- the same lapse on reserve_terminal_charge, apply_late_fee,
-- gross_margin_report, create_credit_memo, delete_roasts, drop_bt_for_sessions,
-- set_roast_measured_weight, next_po_number, apply_group_count_to_lots,
-- move_coffee_source_to_group and allocate_shop_order_ref.
--
-- Nothing anonymous legitimately calls a public function directly: the
-- storefront, the marketing site and the signup path all go through server
-- routes on the service role. The one place anon touches a function at all is
-- inside an RLS policy on a table anon may SELECT (customer_category,
-- shop_config on prod), where auth_company_ids() runs to return the empty set.
-- Those helpers — whichever a policy names, in any schema, in this environment
-- — are granted back to anon so an anonymous read still says "no rows" rather
-- than "permission denied". Everything else: gone, for anon and for PUBLIC.
--
-- `authenticated` keeps every grant it has (checked: no function relied on
-- PUBLIC for authenticated access). Two admin-only backfills and the demo
-- reseed are taken from it as well; nothing in the app calls them.
--
-- The default privileges for the role migrations run as are changed too, so
-- the next `create function` does not re-open the door — the fix that was
-- missing every previous time this was cleaned up.
--
-- Revokes are done one routine at a time inside an exception handler rather
-- than with REVOKE ... ON ALL FUNCTIONS, so a routine owned by another role
-- (an extension, say) produces a WARNING in the push log instead of aborting
-- the release tag mid-migration.
--
-- Also: authenticated held INSERT/UPDATE/DELETE/TRUNCATE on developer_users,
-- developer_impersonation_log and subscription_admin_log — the same shape as
-- the team_self_update hole, saved only by the absence of a write policy. The
-- dev portal writes them on the service role; authenticated needs SELECT on
-- developer_users alone (dev_self_read, used by requireDeveloper()).

begin;

-- ── 1. Revoke EXECUTE from PUBLIC and anon on every routine in public ──────
do $$
declare
  r record;
  n_ok int := 0;
  n_skip int := 0;
begin
  for r in
    select p.oid::regprocedure as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
     order by p.proname
  loop
    begin
      execute format('revoke execute on %s %s from public, anon',
                     case when r.prokind = 'p' then 'procedure' else 'function' end, r.sig);
      n_ok := n_ok + 1;
    exception when others then
      n_skip := n_skip + 1;
      raise warning 'could not revoke on %: %', r.sig, sqlerrm;
    end;
  end loop;
  raise notice 'revoked PUBLIC/anon EXECUTE on % routines (% skipped)', n_ok, n_skip;
end $$;

-- ── 2. Keep the door shut for functions created from now on ───────────────
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;
alter default privileges for role postgres in schema public revoke execute on routines  from public, anon;

-- ── 3. Grant back to anon exactly the helpers RLS policies call ───────────
-- Computed here, not listed: on prod that is auth_company_ids /
-- auth_facility_ids / auth_customer_ids / auth_is_company_admin; staging's
-- pending policies also name auth_has_permission and the terminal helpers.
do $$
declare
  f record;
begin
  for f in
    select distinct p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and exists (
         select 1 from pg_policies pol
          where (coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, ''))
                ~ ('\m' || p.proname || '\(')
       )
  loop
    execute format('grant execute on function %s to anon', f.sig);
    raise notice 'anon keeps EXECUTE on % (named by a policy)', f.sig;
  end loop;
end $$;

-- ── 4. Admin-only routines nobody in the app calls as a user ──────────────
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('backfill_order_total_price', 'backfill_order_unit_costs', 'refresh_demo_dates')
  loop
    begin
      execute format('revoke execute on %s %s from authenticated',
                     case when r.prokind = 'p' then 'procedure' else 'function' end, r.sig);
      raise notice 'authenticated may no longer call %', r.sig;
    exception when others then
      raise warning 'could not revoke % from authenticated: %', r.sig, sqlerrm;
    end;
  end loop;
end $$;

-- ── 5. The developer tables are written by the service role only ──────────
do $$
declare
  t text;
begin
  foreach t in array array['developer_users', 'developer_impersonation_log', 'subscription_admin_log']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke all on public.%I from anon, authenticated', t);
    end if;
  end loop;
  if to_regclass('public.developer_users') is not null then
    grant select on public.developer_users to authenticated;   -- dev_self_read
  end if;
end $$;

commit;
