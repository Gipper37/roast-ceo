-- A row may not point across a tenant.
--
-- Three tables carry a company_id that RLS checks, and a second column that
-- points at another table — which RLS does not check, because a foreign key
-- is validated by the constraint, not by the policy:
--
--   products_price_log.product_id   RLS checks company_id; the two SECURITY
--                                   DEFINER triggers act on product_id alone.
--                                   Insert {product_id: theirs, company_id:
--                                   mine} and THEIR products.price is set and
--                                   THEIR open order lines are re-totalled.
--                                   The victim cannot see the row.
--   shop_invitations.customer_id    Invite an address onto another tenant's
--                                   customer; accept it; the storefront trusts
--                                   the customer_users link and signs you in
--                                   as their wholesale account.
--   shop_config.facility_id         Point your storefront at another tenant's
--                                   facility; the catalogue is read on the
--                                   admin client by facility alone, so their
--                                   products and wholesale prices are served
--                                   on your public shop.
--
-- One guard, three tables: a BEFORE trigger looks the pointed-at row up AS THE
-- CALLER. Under that table's own RLS another tenant's product, customer or
-- facility is not there, so "not found" is the whole check — no second copy
-- of the tenancy rule to drift. For the price log and the invitation the
-- guard also writes company_id from the row it found, so a client that sends
-- the wrong company (by mistake or on purpose) is corrected rather than
-- refused. For shop_config, which IS the tenant's row, a mismatch is refused.
--
-- Roles that bypass RLS (service role, migrations) see every row, and the
-- guard then simply enforces consistency — a definer path cannot create a
-- cross-tenant pointer either.
--
-- Prod today: 0 mismatched rows in all three (checked before writing this).

begin;

-- ── products_price_log ────────────────────────────────────────────────────
create or replace function public.guard_price_log_tenant()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_company text;
begin
  select company_id into v_company
    from public.products
   where product_id = new.product_id;
  if not found then
    raise exception 'That product is not in your catalogue.'
      using errcode = 'insufficient_privilege';
  end if;
  -- The product decides the tenant, never the caller.
  new.company_id := v_company;
  return new;
end;
$$;

drop trigger if exists zz_guard_price_log_tenant on public.products_price_log;
create trigger zz_guard_price_log_tenant
  before insert or update of product_id, company_id on public.products_price_log
  for each row execute function public.guard_price_log_tenant();

comment on function public.guard_price_log_tenant() is
  'A price-log row belongs to the product''s company. Looked up as the caller, so RLS hides any other tenant''s product and the row is refused.';

-- ── shop_invitations ──────────────────────────────────────────────────────
create or replace function public.guard_shop_invitation_tenant()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_company text;
begin
  select company_id into v_company
    from public.customers
   where customer_id = new.customer_id;
  if not found then
    raise exception 'That customer is not yours.'
      using errcode = 'insufficient_privilege';
  end if;
  new.company_id := v_company;
  return new;
end;
$$;

drop trigger if exists zz_guard_shop_invitation_tenant on public.shop_invitations;
create trigger zz_guard_shop_invitation_tenant
  before insert or update of customer_id, company_id on public.shop_invitations
  for each row execute function public.guard_shop_invitation_tenant();

comment on function public.guard_shop_invitation_tenant() is
  'A shop invitation belongs to the customer''s company. Looked up as the caller, so another tenant''s customer is not there.';

-- ── shop_config ───────────────────────────────────────────────────────────
create or replace function public.guard_shop_config_tenant()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_company text;
begin
  if new.facility_id is null then
    return new;
  end if;
  select company_id into v_company
    from public.facilities
   where facility_id = new.facility_id;
  if not found or v_company is distinct from new.company_id then
    raise exception 'That facility is not part of this company.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists zz_guard_shop_config_tenant on public.shop_config;
create trigger zz_guard_shop_config_tenant
  before insert or update of facility_id, company_id on public.shop_config
  for each row execute function public.guard_shop_config_tenant();

comment on function public.guard_shop_config_tenant() is
  'A storefront may only serve a facility of its own company. Looked up as the caller, so another tenant''s facility is not there.';

commit;
