-- anon was left holding the grants that were taken off authenticated.
--
-- Three separate security passes hardened these four tables by revoking write
-- privileges from `authenticated`. Each time, `anon` kept its own copy of the
-- same grant, because Supabase's default ACL hands every new table
-- `arwdDxtm` to BOTH roles and a revoke names one of them:
--
--     team                  the role/company-rewrite hole
--     company_kyc           KYC status
--     customers             including merge_into_id, which fires a merge that
--                           MOVES orders and order_details
--     pack_run_correction   food-safety corrections
--
-- NOT EXPLOITABLE TODAY, and this is why it is a cleanup rather than a hotfix:
-- RLS is enabled on all four and not one of them has a policy that admits anon
-- for ALL/UPDATE/INSERT/DELETE, so every anon write is refused by the policy
-- layer before the grant is ever consulted. Verified on staging:
--
--     select ... from pg_policies where tablename in (...) and cmd in
--       ('ALL','UPDATE','INSERT','DELETE') and ('anon'=any(roles) or roles='{public}')
--     -> 0 rows
--
-- Which is exactly what makes the revoke safe: a privilege nothing can use
-- cannot be depended on by anything. The only genuinely anonymous client in
-- the app is createPublicClient(), and its sole caller is the marketing
-- pricing page reading subscription_plans.
--
-- What this buys is the second lock. Today one careless permissive policy —
-- a storefront feature, a public form, a share link — silently turns a
-- signed-out request into a writer on the team table. After this it does not,
-- because the grant is gone too.
--
-- SELECT is deliberately untouched: pack_run_correction has a real anon read
-- policy, and revoking reads here would be a different change with a
-- different blast radius.

begin;

revoke insert, update, delete, truncate on public.team                from anon;
revoke insert, update, delete, truncate on public.company_kyc         from anon;
revoke insert, update, delete, truncate on public.customers           from anon;
revoke insert, update, delete, truncate on public.pack_run_correction from anon;

do $verify$
declare v text;
begin
  select string_agg(table_name || '.' || privilege_type, ', ' order by table_name, privilege_type)
    into v
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'
     and table_name in ('team','company_kyc','customers','pack_run_correction')
     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
  if v is not null then raise exception 'anon still holds %', v; end if;

  -- And the reads that ARE policy-backed must survive.
  if not has_table_privilege('anon','public.pack_run_correction','SELECT') then
    raise exception 'revoked the anon read that pack_run_correction_read depends on';
  end if;

  raise notice 'anon holds no write privilege on team, company_kyc, customers or pack_run_correction';
end $verify$;

commit;
