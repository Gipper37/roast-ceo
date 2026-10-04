-- An operator can look at the shop as a customer, and it is written down.
--
-- Impersonation exists but only reaches the roaster's side of the app: the
-- `strata_dev_impersonation` cookie is read by resolveIdentity() in
-- lib/permissions/server.ts:82, which makes a developer company_admin of the
-- impersonated company. app/(shop)/** references impersonation nowhere and
-- resolves a buyer strictly from getServerUser() -> customer_users.
--
-- So nobody has ever seen the storefront as a buyer sees it. Not figuratively:
-- there are three customer_users rows on prod, all Social Hour, two of them
-- also staff, and ZERO at MCR. Every one of the 363 MCR customers holding a
-- shop tier has no login. The storefront has shipped, been changed repeatedly,
-- and never once been looked at through a customer's eyes.
--
-- Owner, 2026-10-03: "do we have a way for a dev admin to view a store as a
-- customer. we should."
--
-- This is the audit half. developer_impersonation_log already exists and
-- already records developer_id, company_id, facility_id, started_at, ended_at,
-- reason, ip_address and user_agent. It is COMPANY-scoped, because that is all
-- impersonation could mean until now. Viewing as a customer needs one more
-- dimension, so customer_id joins it rather than a second table: one log, one
-- place to look, and an app-side session simply leaves it null.
--
-- The column is nullable on purpose. The two existing rows are company
-- impersonations and stay valid exactly as they are.

begin;

alter table public.developer_impersonation_log
  add column if not exists customer_id text references public.customers(customer_id);

comment on column public.developer_impersonation_log.customer_id is
  'Set when the developer was viewing the STOREFRONT as this customer. Null for an ordinary company impersonation, which is what every row before 2026-10-03 is.';

create index if not exists developer_impersonation_log_customer_idx
  on public.developer_impersonation_log (customer_id)
  where customer_id is not null;

do $verify$
declare v_bad int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='developer_impersonation_log'
                    and column_name='customer_id') then
    raise exception 'the column was not added';
  end if;

  -- Nullable, or the existing company impersonations become invalid.
  if (select is_nullable from information_schema.columns
       where table_schema='public' and table_name='developer_impersonation_log'
         and column_name='customer_id') <> 'YES' then
    raise exception 'customer_id must stay nullable; an app-side session has no customer';
  end if;

  -- The rows that were already there are untouched and still company-scoped.
  select count(*) into v_bad from public.developer_impersonation_log where company_id is null;
  if v_bad > 0 then raise exception '% existing log row(s) lost their company', v_bad; end if;

  -- The gate this whole feature rests on still exists. Without an active
  -- developer_users row nothing can impersonate anything.
  if not exists (select 1 from public.developer_users where is_active and revoked_at is null) then
    raise exception 'no active developer exists; the impersonation gate would admit nobody';
  end if;
end;
$verify$;

commit;
