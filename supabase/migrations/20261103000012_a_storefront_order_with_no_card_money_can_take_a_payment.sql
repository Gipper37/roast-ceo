-- A storefront order with no card money on it can take a payment from its own page.
--
-- Owner, 2026-11-03: "there should be an option to manually process a card ... we need
-- that to be possible on every order detail page."
--
-- reserve_order_charge refused every order carrying a shop_order_ref, on the premise
-- that a storefront order is already paid. A net-terms order never had a card on it and
-- a declined one took nothing, and neither could take a payment at all: the only thing
-- on offer was the storefront's own Send invoice, which records nothing.
--
-- 🔴 THE ORDER DECIDES, THE SAME WAY Send invoice ALREADY DECIDES. Any card status but a
-- failed or voided one means money moved or may be moving, so that order stays refused,
-- under this function's lock, before any card is touched. That refusal is the double
-- charge. Only this test changes, and payment_status joins the row it reads. Everything
-- else, finalize_invoice's refusals, the holds and the ceiling, applies to these orders
-- as it does to any other.
--
-- Security invoker, unchanged: CREATE OR REPLACE keeps the grants from 20261103000007.
--
-- Two more things ride with it, because taking a payment on these orders is what makes
-- them bite: a shop with shipping on needs a product to bill it on, and a voided checkout
-- must not keep the date of a payment that never arrived. Both are further down.

CREATE OR REPLACE FUNCTION public.reserve_order_charge(p_order_id text, p_amount_cents bigint, p_idempotency_key text, p_provider text, p_platform_fee_cents bigint DEFAULT 0, p_payout_cents bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_o       record;
  v_mode    text;
  v_cutover date;
  v_tz      text;
  v_today   date;
  v_total   bigint;
  v_held    bigint;
  v_txn_id  uuid;
begin
  if coalesce(p_amount_cents, 0) <= 0 then
    raise exception 'Enter an amount to charge.';
  end if;

  select o.company_id, o.customer_id, o.order_date, o.invoice_number, o.posted,
         o.is_legacy_import, o.is_opening_balance, o.order_status, o.shop_order_ref,
         o.payment_status,
         o.facility_id, o.order_total, o.tax_amount
    into v_o
    from public.orders o
   where o.order_id = p_order_id
     and o.company_id in (select public.auth_company_ids())
     for update;
  if not found then raise exception 'That order could not be found.'; end if;

  if v_o.invoice_number is not null or coalesce(v_o.posted, false) then
    raise exception 'This order already has an invoice. Refresh the page and charge it from there.';
  end if;
  -- lib/shop/checkoutPayment.ts asks the same thing: cardMoneyAtCheckout. A pending
  -- checkout counts, because billing it twice is the worse mistake.
  if v_o.shop_order_ref is not null
     and v_o.payment_status is not null
     and v_o.payment_status not in ('failed', 'voided') then
    raise exception 'This order has a card payment from checkout on it, so it cannot take another payment here.';
  end if;
  if v_o.customer_id is null then
    raise exception 'This order has no customer to invoice.';
  end if;
  if coalesce(v_o.is_legacy_import, false) then
    raise exception 'This order was imported from QuickBooks and keeps its original number.';
  end if;
  if coalesce(v_o.is_opening_balance, false) then
    raise exception 'This is an opening balance from your cutover, not an order to invoice.';
  end if;
  if v_o.order_status = 'Canceled' then
    raise exception 'Canceled orders cannot be charged. Reopen the order first.';
  end if;
  if coalesce(v_o.order_total, 0) <= 0 then
    raise exception 'Add at least one line item with a price before charging.';
  end if;

  select b.invoice_of_record, b.cutover_date into v_mode, v_cutover
    from public.billing_settings b where b.company_id = v_o.company_id;
  if coalesce(v_mode, 'quickbooks') <> 'strata' then
    raise exception 'STRATA is not your invoice of record yet.';
  end if;
  select f.time_zone into v_tz from public.facilities f where f.facility_id = v_o.facility_id;
  v_today := (now() at time zone coalesce(nullif(v_tz, ''), 'UTC'))::date;
  if v_cutover is not null and v_o.order_date is not null
     and v_o.order_date < v_cutover and v_o.order_date < v_today then
    raise exception 'This order is dated before your STRATA start date, so it stays in QuickBooks.';
  end if;

  v_total := round((coalesce(v_o.order_total, 0) + coalesce(v_o.tax_amount, 0)) * 100)::bigint;
  select coalesce(sum(h.amount_cents), 0) into v_held
    from public.terminal_charge_holds h
    join public.payment_transactions t on t.payment_transaction_id = h.payment_transaction_id
   where h.order_id = p_order_id
     and public.charge_hold_is_live(t.payment_transaction_id);
  if v_held + p_amount_cents > v_total then
    raise exception 'Only % can still be charged on this order. Another charge may be in flight.',
      to_char(greatest(v_total - v_held, 0) / 100.0, 'FM999999990.00');
  end if;

  insert into public.payment_transactions
    (company_id, order_id, provider, type, status, idempotency_key,
     gross_amount_cents, platform_fee_cents, roaster_payout_cents)
  values
    (v_o.company_id, p_order_id, p_provider, 'sale', 'pending', p_idempotency_key,
     p_amount_cents, coalesce(p_platform_fee_cents, 0), coalesce(p_payout_cents, 0))
  returning payment_transaction_id into v_txn_id;

  insert into public.terminal_charge_holds (payment_transaction_id, order_id, amount_cents)
  values (v_txn_id, p_order_id, p_amount_cents);

  return jsonb_build_object(
    'payment_transaction_id', v_txn_id,
    'allocations', jsonb_build_array(
      jsonb_build_object('order_id', p_order_id, 'amount_cents', p_amount_cents))
  );
end;
$function$;

-- ── A shop that charges shipping has a product to bill it on ──────────────────────────
--
-- 20260923000018 made shipping a line and gave a product to the shops that had shipping
-- on that day. Nothing has given one to anybody since: neither settings action sets
-- shipping_product_id, so a roaster who turns shipping on today has NULL, and checkout
-- writes no line on either path. The buyer is quoted the shipping and the order does
-- not record it, which used to be recovered by subtraction on the document. Now that
-- taking a payment numbers a storefront order, the invoice locks short by exactly that.
--
-- A trigger, so every writer gets it, and a security definer one, because shop.configure
-- is what the person flipping the switch holds and it says nothing about creating
-- products. It fires on the product column too: the foreign key sets NULL when the
-- product is deleted, and a shop still charging shipping needs another.
--
-- 🔴 ptype_service IS THE SEEDED GLOBAL ROW. The 000018 lookup matched on the name with
-- limit 1, and product_type also holds per-tenant rows, so it could have picked another
-- tenant's. A missing row is a foreign key error, which beats a shop that silently
-- under-bills.

create or replace function public.shop_config_shipping_product()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_product text;
  v_group   uuid;
begin
  if not coalesce(new.shipping_enabled, false) or new.shipping_product_id is not null then
    return new;
  end if;

  select p.product_id into v_product
    from public.products p
   where p.company_id = new.company_id
     and p.is_active
     and p.product_name ilike 'shipping'
   order by p.product_id
   limit 1;

  if v_product is null then
    v_group   := gen_random_uuid();
    v_product := gen_random_uuid()::text;

    insert into public.product_groups (group_id, group_name, company_id, facility_id)
    values (v_group, 'Shipping', new.company_id, new.facility_id);

    -- No price: the cart works shipping out per order, and bills it as amount_override.
    insert into public.products (
      product_id, group_id, product_name, product_type, company_id, facility_id, is_active, price
    ) values (
      v_product, v_group, 'Shipping', 'ptype_service', new.company_id, new.facility_id, true, null
    );
  end if;

  new.shipping_product_id := v_product;
  return new;
end;
$function$;

-- A trigger function cannot be called outside a trigger, and firing one does not check
-- this grant. Revoked so a definer function does not sit on anyone's list.
revoke all on function public.shop_config_shipping_product() from public, anon, authenticated;

drop trigger if exists trg_shop_config_shipping_product on public.shop_config;
create trigger trg_shop_config_shipping_product
  before insert or update of shipping_enabled, shipping_product_id on public.shop_config
  for each row execute function public.shop_config_shipping_product();

-- The shops that turned shipping on since 000018. Setting the column to itself is what
-- makes the trigger above fire, so there is one way of doing this and not two.
update public.shop_config
   set shipping_enabled = shipping_enabled
 where shipping_enabled
   and shipping_product_id is null;

do $$
declare
  v_missing int;
begin
  select count(*) into v_missing from public.shop_config
   where coalesce(shipping_enabled, false) and shipping_product_id is null;
  if v_missing > 0 then
    raise exception '% shops charge shipping with no product to bill it on', v_missing;
  end if;
end $$;

-- ── A voided checkout has no paid date ────────────────────────────────────────────────
--
-- The webhook stops writing these with this release, and these are the ones it already
-- left. A void called the charge off before it settled, so the date records money that
-- never arrived: such an order sits in cash-basis revenue for that month now, and a voided
-- storefront order can be paid again from its page, where recompute_invoice_ar_state
-- keeps a date it finds rather than stamping its own. Numbered orders are left out: their
-- date is the A/R ledger's.

update public.orders
   set paid_at = null
 where payment_status = 'voided'
   and invoice_number is null
   and paid_at is not null;
