-- The storefront charges no tax at all.
--
-- recompute_order_tax is called from exactly five places, all of them in the
-- admin order actions. The shop checkout calls none of them, so a storefront
-- order is created with tax_amount null and tax_rate_id null -- and the one
-- shop order in the database proves it.
--
-- For a Hawaii roaster that is a GET liability they pay out of their own
-- pocket on every online sale.
--
-- WHY THE CART HAS TO ASK, rather than the order being fixed up afterwards.
-- The charge amount is RESERVED before the order row exists --
-- reserve_terminal_charge mints the payment_transactions row, then
-- insertParkedOrder writes the order. Stamping tax on the order later would
-- leave the card charged without it, which is the same charge-versus-record
-- divergence the discount fix just closed. The cart has to know before it
-- reserves.
--
-- Same shape as resolve_customer_discounts_for_products: a set-returning
-- wrapper around the real resolver, so the storefront cannot drift from the
-- order engine. There are already two copies of the discount precedence rules
-- and the audit found the second one wrong in four ways; tax is not getting a
-- second copy.
--
-- Returns the CHARGE rate, which is what a customer pays. Whether it is passed
-- through at all is a property of the customer and is applied by the caller,
-- exactly as recompute_order_tax does.

begin;

create or replace function public.resolve_tax_rates_for_products(
  p_company_id  text,
  p_facility_id text,
  p_customer_id text,
  p_product_ids text[],
  p_on_date     date
)
returns table (
  product_id  text,
  tax_rate_id text,
  charge_rate numeric
)
language sql
stable
security definer
set search_path = public
as $function$
  select pid.product_id, r.tax_rate_id, t.charge_rate
  from unnest(p_product_ids) as pid(product_id)
  join public.products p on p.product_id = pid.product_id
  cross join lateral public.resolve_tax_rate(
    p_company_id, p_facility_id, p.channel, p.product_type, p_customer_id, p_on_date
  ) as r(tax_rate_id)
  join public.tax_rate t on t.tax_rate_id = r.tax_rate_id
  -- A caller may not price another tenant's catalogue.
  where p.company_id = p_company_id;
$function$;

revoke all on function public.resolve_tax_rates_for_products(text, text, text, text[], date) from public;
grant execute on function public.resolve_tax_rates_for_products(text, text, text, text[], date) to authenticated, service_role;

comment on function public.resolve_tax_rates_for_products is
  'Per-product tax rates for a whole cart, so the storefront can charge tax in the same breath as it reserves the card. A wrapper around resolve_tax_rate -- never a second copy of the rules.';

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolve_tax_rates_for_products(
    '9ShiyDAXhV',
    (select facility_id from public.facilities where company_id='9ShiyDAXhV' limit 1),
    (select customer_id from public.customers where company_id='9ShiyDAXhV' limit 1),
    array(select product_id from public.products where company_id='9ShiyDAXhV' limit 5),
    current_date);
  raise notice 'cart tax resolver returned % rates for a 5-product MCR probe', v_n;

  if has_function_privilege('anon',
       'public.resolve_tax_rates_for_products(text,text,text,text[],date)', 'execute') then
    raise exception 'anon can execute the cart tax resolver';
  end if;
end $$;

commit;
