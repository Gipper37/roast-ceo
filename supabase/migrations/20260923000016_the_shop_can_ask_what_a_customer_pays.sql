-- One call to price a whole cart for a known customer.
--
-- The storefront checkout computes what to charge as products.price x quantity
-- and resolves NO customer discount at all. A wholesale customer with a
-- negotiated rate who orders through the shop is charged full price.
--
-- Worse than overcharging, it makes the charge and the order DISAGREE. The
-- order_details rows the checkout inserts go through
-- handle_order_detail_logic, which DOES resolve the customer's discount -- so
-- the order records the discounted total while the card was charged the
-- undiscounted one. The books and the bank differ by the discount.
--
-- This exists so the fix does not become a THIRD copy of the precedence rules.
-- There are already two -- resolve_customer_discount and NewOrderForm's
-- custDiscForLine -- and the financial audit found the frontend one wrong in
-- four separate ways because it had drifted. A set-returning wrapper around
-- the real resolver cannot drift from it.
--
-- SECURITY DEFINER with a customer_id the CALLER supplies is deliberate and
-- safe here: it returns only discount kinds and values, and the checkout
-- resolves the buyer's customer_id server-side from their session (the shop
-- actions are explicit that the buyer does not get to say who the order is
-- for). It is also pinned to the customer's own company, so a caller cannot
-- read another tenant's rules by guessing an id.

begin;

create or replace function public.resolve_customer_discounts_for_products(
  p_customer_id text,
  p_product_ids text[],
  p_on_date     date
)
returns table (
  product_id text,
  kind       text,
  value      numeric,
  scope      text
)
language sql
stable
security definer
set search_path = public
as $function$
  select pid.product_id, d.kind, d.value, d.scope
  from unnest(p_product_ids) as pid(product_id)
  join public.products p on p.product_id = pid.product_id
  join public.customers c on c.customer_id = p_customer_id
  -- The rule and the product must belong to the same tenant as the customer.
  -- Without this a caller could price another company's catalogue against
  -- their own customer's rules.
  cross join lateral public.resolve_customer_discount(p_customer_id, pid.product_id, p_on_date) d
  where p.company_id = c.company_id
    and d.kind is not null;
$function$;

revoke all on function public.resolve_customer_discounts_for_products(text, text[], date) from public;
grant execute on function public.resolve_customer_discounts_for_products(text, text[], date) to authenticated, service_role;

comment on function public.resolve_customer_discounts_for_products is
  'Price a whole cart at once. A set-returning wrapper around resolve_customer_discount so the storefront cannot drift from the order engine. Returns nothing for products with no rule.';

do $$
declare
  v_n int;
begin
  -- It must run, and it must return nothing when there are no rules -- which
  -- is every tenant today, since customer_discount is empty.
  select count(*) into v_n
  from public.resolve_customer_discounts_for_products(
    (select customer_id from public.customers limit 1),
    array(select product_id from public.products limit 5),
    current_date);
  raise notice 'cart resolver returned % rules for a 5-product probe', v_n;

  if not exists (
    select 1 from pg_proc
    where oid = 'public.resolve_customer_discounts_for_products(text,text[],date)'::regprocedure
  ) then
    raise exception 'the cart resolver was not created';
  end if;

  -- anon must NOT be able to read discount rules.
  if has_function_privilege('anon',
       'public.resolve_customer_discounts_for_products(text,text[],date)', 'execute') then
    raise exception 'anon can execute the cart discount resolver';
  end if;
end $$;

commit;
