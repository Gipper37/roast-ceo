-- Who has a second factor: `team_mfa_status`.
--
-- The team screen needs one boolean per person — does this login hold a
-- verified authenticator? — and there is no good way to get it from the client.
-- `auth.mfa_factors` is in the `auth` schema, which PostgREST does not expose,
-- and the admin API answers for ONE user per call: fourteen HTTP round trips to
-- paint a table of fourteen rows.
--
-- So: one SECURITY DEFINER function, modelled directly on `team_pin_status`
-- (20260907000006), which solves the identical problem for PINs.
--
-- 🔴 STATUS ONLY, and that is the whole design. `auth.mfa_factors` carries the
-- TOTP `secret` — the shared seed. A function that returned the row, or `select
-- *`, would hand every signed-in member of a company the means to generate
-- their colleagues' codes, which is strictly worse than having no second factor
-- at all. This returns a `team_member_id` and a boolean and nothing else, the
-- same way the PIN function returns status and never the hash.
--
-- Tenant scoping is the same single clause as the PIN function:
-- `p_company_id in (select auth_company_ids())`. Without it, any signed-in user
-- could ask about any company's team.
--
-- No permission key to READ this, deliberately and by precedent: any member who
-- can already see the team list can see who has a PIN, and "has two-factor" is
-- the same kind of fact. RESETTING somebody's factor is the sensitive act, and
-- that is gated by `team.mfa_reset` (20261028000021) plus a seniority rule in
-- the server action.

begin;

create or replace function public.team_mfa_status(p_company_id text)
returns table(team_member_id text, has_factor boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select t.team_member_id,
         exists (
           select 1 from auth.mfa_factors f
            where f.user_id = t.auth_user_id
              and f.status = 'verified'
         ) as has_factor
    from public.team t
   where t.company_id = p_company_id
     and t.auth_user_id is not null
     and p_company_id in (select auth_company_ids());
$fn$;

revoke all on function public.team_mfa_status(text) from public;
grant execute on function public.team_mfa_status(text) to authenticated;

do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'team_mfa_status' and p.prosecdef;
  if n <> 1 then raise exception 'team_mfa_status is missing or not SECURITY DEFINER'; end if;

  -- 🔴 A pinned search_path is not optional on a definer function that reads
  -- the auth schema: `authenticated` holds TEMPORARY on this database, so an
  -- unpinned one could be pointed at a pg_temp table of the caller's making.
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'team_mfa_status'
     and p.proconfig is not null
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  if n <> 1 then raise exception 'team_mfa_status has no pinned search_path'; end if;

  -- 🔴 The return shape must not have grown a column. This is the assertion
  -- that matters most in the block: if a later edit adds `secret`, or anything
  -- else off mfa_factors, the release fails here instead of handing every
  -- member of a company the seed for their colleagues' codes.
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'team_mfa_status'
     and pg_get_function_result(p.oid) = 'TABLE(team_member_id text, has_factor boolean)';
  if n <> 1 then
    raise exception 'team_mfa_status returns an unexpected shape: %',
      (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace s on s.oid=p.pronamespace
        where s.nspname='public' and p.proname='team_mfa_status');
  end if;

  if has_function_privilege('anon', 'public.team_mfa_status(text)', 'EXECUTE') then
    raise exception 'anon can execute team_mfa_status';
  end if;
  if not has_function_privilege('authenticated', 'public.team_mfa_status(text)', 'EXECUTE') then
    raise exception 'authenticated cannot execute team_mfa_status';
  end if;

  raise notice 'team_mfa_status returns status only, scoped to the caller''s own companies';
end $$;

commit;
