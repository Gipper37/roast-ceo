-- The money and identity tables check a permission, not just a tenant.
--
-- ── What is true today ───────────────────────────────────────────────────
--
-- 70 write policies on 70 tables are scoped to the tenant and nothing else:
-- `company_id IN (SELECT auth_company_ids())`, cmd=ALL. `authenticated` holds
-- the matching GRANT on 203 of 204 of those privilege slots, there are ZERO
-- restrictive policies schema-wide, and there is no PostgREST pre-request hook.
-- So every `requirePermission()` in the server actions is a Next.js-side check
-- that a direct call to PostgREST simply goes around. `safeupdate` is
-- preloaded, which blocks an UNQUALIFIED delete -- not a targeted one.
--
-- This is the insider and the phished-credential case, not cross-tenant. It is
-- also why the role model is not actually enforced where the data lives.
--
-- ── Why these three first ────────────────────────────────────────────────
--
-- Small batch on purpose. These three are the ones where a write is an act of
-- MONEY or IDENTITY, and where almost nothing legitimate writes them, so the
-- gate can go on with very little that can break:
--
--   roaster_bank_accounts  plaid_access_token_encrypted, nacha_authorized_at,
--                          nacha_auth_ip, nacha_auth_user_agent. 🔴 ZERO code
--                          references in the whole app and 0 rows, because it
--                          is pre-launch -- which is exactly the point: this is
--                          the table onboarding is about to fill, and NACHA
--                          authorization evidence has to be tamper-evident
--                          before it has anything in it, not after.
--
--   customer_users         binds an auth_user_id to a customer. An ungated
--                          INSERT here is PRIVILEGE GRANTING: any role could
--                          attach any login to any customer of the company and
--                          give it the shop. Its only writer is
--                          app/api/shop-invite/accept/route.ts, which uses the
--                          SERVICE ROLE key and so does not pass through RLS at
--                          all -- verified before writing this.
--
--   products_price_log     🔴 deleting a LIVE row makes
--                          sync_product_price_from_log REWRITE products.price
--                          (read from the live body: it early-returns only for
--                          future-dated STAGED rows). So an ungated DELETE here
--                          is "any staff role can change what things sell for".
--
-- orders and order_details are deliberately NOT in this batch. They are the
-- hottest tables in the app and gating them needs its own rehearsal.
--
-- ── 🔴 WHY EACH POLICY IS SPLIT RATHER THAN AMENDED ──────────────────────
--
-- All three are cmd=ALL, and ALL covers SELECT. Adding a permission to the
-- existing policy would have gated READS as well: price history is read all
-- over the app, and the customer page lists shop users. So each becomes the
-- shape the `size` table already uses -- a company-scoped SELECT that behaves
-- exactly as before, plus INSERT/UPDATE/DELETE that check a key.
--
-- Keys chosen to match what the real writers already demand, so nothing that
-- works today stops working:
--   products_price_log  product.edit / product.create  (what every insert site
--                       calls requirePermission with)
--   customer_users      customer.account_management / shop.customer_invite
--   roaster_bank_accounts  payments.merchant_onboard / billing.configure
--                       (both, because merchant_onboard is granted on every
--                        plan and billing.configure only on enterprise -- one
--                        alone would lock a starter tenant out of its own bank
--                        setup)
--
-- auth_has_permission applies the plan gate and the terminal narrowing itself,
-- so none of that is restated here.

begin;

-- ── roaster_bank_accounts ────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.roaster_bank_accounts;

create policy bank_tenant_read on public.roaster_bank_accounts
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy bank_write_insert on public.roaster_bank_accounts
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
    and (auth_has_permission('payments.merchant_onboard', company_id)
      or auth_has_permission('billing.configure', company_id)));

create policy bank_write_update on public.roaster_bank_accounts
  for update to authenticated
  using (company_id in (select auth_company_ids())
    and (auth_has_permission('payments.merchant_onboard', company_id)
      or auth_has_permission('billing.configure', company_id)))
  with check (company_id in (select auth_company_ids())
    and (auth_has_permission('payments.merchant_onboard', company_id)
      or auth_has_permission('billing.configure', company_id)));

create policy bank_write_delete on public.roaster_bank_accounts
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and (auth_has_permission('payments.merchant_onboard', company_id)
      or auth_has_permission('billing.configure', company_id)));

-- ── customer_users ───────────────────────────────────────────────────────
-- 🔴 Scoped through customers, NOT by a company_id column: this table has
-- none. The original shape is preserved exactly and the key is added beside it.
-- shop_buyer_self_customer_users (a buyer reading their own row) is untouched.
drop policy if exists roaster_manage_customer_users on public.customer_users;

create policy roaster_read_customer_users on public.customer_users
  for select to authenticated
  using (customer_id in (select c.customer_id from public.customers c
                          where c.company_id in (select auth_company_ids())));

create policy roaster_insert_customer_users on public.customer_users
  for insert to authenticated
  with check (customer_id in (select c.customer_id from public.customers c
                               where c.company_id in (select auth_company_ids())
                                 and (auth_has_permission('customer.account_management', c.company_id)
                                   or auth_has_permission('shop.customer_invite', c.company_id))));

create policy roaster_update_customer_users on public.customer_users
  for update to authenticated
  using (customer_id in (select c.customer_id from public.customers c
                          where c.company_id in (select auth_company_ids())
                            and (auth_has_permission('customer.account_management', c.company_id)
                              or auth_has_permission('shop.customer_invite', c.company_id))))
  with check (customer_id in (select c.customer_id from public.customers c
                               where c.company_id in (select auth_company_ids())
                                 and (auth_has_permission('customer.account_management', c.company_id)
                                   or auth_has_permission('shop.customer_invite', c.company_id))));

create policy roaster_delete_customer_users on public.customer_users
  for delete to authenticated
  using (customer_id in (select c.customer_id from public.customers c
                          where c.company_id in (select auth_company_ids())
                            and (auth_has_permission('customer.account_management', c.company_id)
                              or auth_has_permission('shop.customer_invite', c.company_id))));

-- ── products_price_log ───────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.products_price_log;

create policy price_log_tenant_read on public.products_price_log
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy price_log_write_insert on public.products_price_log
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
    and (auth_has_permission('product.edit', company_id)
      or auth_has_permission('product.create', company_id)));

create policy price_log_write_update on public.products_price_log
  for update to authenticated
  using (company_id in (select auth_company_ids())
    and (auth_has_permission('product.edit', company_id)
      or auth_has_permission('product.create', company_id)))
  with check (company_id in (select auth_company_ids())
    and (auth_has_permission('product.edit', company_id)
      or auth_has_permission('product.create', company_id)));

create policy price_log_write_delete on public.products_price_log
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and (auth_has_permission('product.edit', company_id)
      or auth_has_permission('product.create', company_id)));

do $$
declare t text; n_read int; n_write int; n_ungated int;
begin
  foreach t in array array['roaster_bank_accounts','customer_users','products_price_log'] loop
    -- a read still exists, or the app goes blind
    select count(*) into n_read from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relname = t and p.polcmd = 'r';
    if n_read < 1 then raise exception '% lost its read policy', t; end if;

    -- three write policies, each naming a permission
    select count(*) into n_write from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relname = t and p.polcmd in ('a','w','d');
    if n_write <> 3 then raise exception '% has % write policies, expected 3', t, n_write; end if;

    select count(*) into n_ungated from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relname = t and p.polcmd in ('a','w','d')
       and coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') not like '%auth_has_permission%';
    if n_ungated > 0 then raise exception '% still has % ungated write policy(ies)', t, n_ungated; end if;

    -- 🔴 and no cmd=ALL survivor, which would re-open everything it covers
    if exists (select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
                where c.relname = t and p.polcmd = '*') then
      raise exception '% still has a cmd=ALL policy', t;
    end if;
  end loop;

  raise notice 'bank accounts, customer logins and the price log now check a permission to be written';
end $$;

commit;
