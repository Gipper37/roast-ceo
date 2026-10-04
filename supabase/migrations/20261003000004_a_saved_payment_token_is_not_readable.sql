-- A saved payment token is not readable, and not writable from a browser.
--
-- customer_payment_methods holds no card data, which is right and stays right:
-- the only card-shaped things in it are display_brand, last4 and the expiry,
-- which are what a buyer needs to recognise their own card. What it DOES hold
-- is provider_vault_customer_id and provider_payment_method_id, the two tokens
-- that let a charge be made against a stored method. Those are the credential.
--
-- Owner's rule, 2026-10-03: "cards should not ever be stored in our db. only
-- with the gateway. and yes, no one should be able to access tokens."
--
-- It shipped with the opposite. One policy, `tenant_company_access`, FOR ALL to
-- the public role keyed on company_id alone, plus full table grants to
-- authenticated including UPDATE, DELETE and TRUNCATE. So any signed-in staff
-- member of the tenant could read every customer's tokens through PostgREST,
-- forge a row pointing at somebody else's vaulted card, or empty the table.
-- There was no permission check anywhere in it, even though
-- payment.saved_methods already exists as the key for exactly this.
--
-- The shape this adopts is the one provider_credentials already uses and gets
-- right, three layers rather than one:
--   1. no table grant to authenticated at all; service_role writes
--   2. column grants that stop at the tokens, so the columns a human needs are
--      readable and the two that authorise a charge are not reachable by any
--      query, however it is written
--   3. a SELECT policy scoped to the tenant AND gated on payment.saved_methods
--
-- A buyer is not given a policy. The storefront runs on the service role, so
-- the server resolves a buyer's own methods and hands back brand and last4; a
-- buyer never queries this table and does not need to.
--
-- Zero rows and zero code reference it today, so this tightens freely.

begin;

revoke all on public.customer_payment_methods from authenticated;

-- Everything a person needs to recognise a card, and nothing that can charge
-- one. provider_vault_customer_id and provider_payment_method_id are omitted
-- deliberately and must stay omitted.
grant select (
  payment_method_id, company_id, customer_id, provider, method_type,
  display_brand, last4, exp_month, exp_year, is_default,
  removed_at, created_at, created_by, updated_at, updated_by
) on public.customer_payment_methods to authenticated;

drop policy if exists tenant_company_access on public.customer_payment_methods;

create policy saved_methods_tenant_read
  on public.customer_payment_methods
  for select
  to authenticated
  using (
    company_id in (select public.auth_company_ids())
    and public.auth_has_permission('payment.saved_methods', company_id)
  );

comment on table public.customer_payment_methods is
  'A payment method vaulted AT THE GATEWAY. Holds no card number. provider_vault_customer_id and provider_payment_method_id authorise a charge and are readable only by service_role: never grant them to authenticated.';

do $verify$
declare v_bad int; v_cols int;
begin
  -- 🔴 The tokens are unreachable by an authenticated session, by any query.
  select count(*) into v_bad
    from information_schema.column_privileges
   where table_schema='public' and table_name='customer_payment_methods'
     and grantee='authenticated'
     and column_name in ('provider_vault_customer_id','provider_payment_method_id');
  if v_bad > 0 then
    raise exception 'authenticated can still read % token column(s)', v_bad;
  end if;

  -- And cannot write the table at all.
  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema='public' and table_name='customer_payment_methods'
     and grantee='authenticated' and privilege_type <> 'SELECT';
  if v_bad > 0 then
    raise exception 'authenticated still holds % write grant(s)', v_bad;
  end if;

  -- The columns a human needs ARE still readable, or the UI cannot show a card.
  select count(*) into v_cols
    from information_schema.column_privileges
   where table_schema='public' and table_name='customer_payment_methods'
     and grantee='authenticated' and privilege_type='SELECT'
     and column_name in ('display_brand','last4','exp_month','exp_year','is_default');
  if v_cols <> 5 then
    raise exception 'only % of the 5 display columns are readable', v_cols;
  end if;

  -- No policy reaches anon or public any more, and the one that remains is a
  -- read gated on the permission.
  select count(*) into v_bad from pg_policies
   where schemaname='public' and tablename='customer_payment_methods'
     and ('anon' = any(roles) or 'public' = any(roles));
  if v_bad > 0 then raise exception '% policy(ies) still name anon or public', v_bad; end if;

  select count(*) into v_bad from pg_policies
   where schemaname='public' and tablename='customer_payment_methods' and cmd <> 'SELECT';
  if v_bad > 0 then raise exception '% non-SELECT policy(ies) remain', v_bad; end if;

  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='customer_payment_methods'
       and policyname='saved_methods_tenant_read'
       and qual like '%payment.saved_methods%'
  ) then
    raise exception 'the read policy is not gated on payment.saved_methods';
  end if;

  -- service_role still writes, or the server cannot save a method at all.
  select count(*) into v_bad
    from information_schema.role_table_grants
   where table_schema='public' and table_name='customer_payment_methods'
     and grantee='service_role' and privilege_type in ('INSERT','UPDATE','SELECT');
  if v_bad < 3 then
    raise exception 'service_role lost its write access; nothing could save a method';
  end if;
end;
$verify$;

commit;
