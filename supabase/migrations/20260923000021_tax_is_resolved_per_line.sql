-- Tax is a fact about a LINE, not about an order.
--
-- recompute_order_tax resolved ONE rate for the whole order, picked from
-- whichever channel and product type had the largest line total:
--
--   order by sum(od.total_price) desc nulls last limit 1
--
-- and applied it to order_total. A tax rule keys on channel AND product type,
-- so an order whose lines disagree gets taxed at whichever half is bigger.
--
-- MCR charges wholesale at 0.5025% and retail at 4.7120%. On a mixed order:
--
--   $600 wholesale + $500 retail   correct $26.58   actual  $5.53
--                                  -> the roaster owes Hawaii $21.05
--   $500 wholesale + $600 retail   correct $26.58   actual $51.83
--                                  -> the customer is overcharged $25.25
--
-- LATENT, NOT LIVE, and measured before writing this: MCR has 0 orders whose
-- lines span more than one channel and 0 orders on the vip channel, which is
-- their only rule keyed on product type. It bites the day they use either.
--
-- THREE PARTS, because fixing the arithmetic alone would leave the filing
-- wrong:
--
--  1. order_details carries its own tax_rate_id and tax_amount. Tax was only
--     ever stored per order, so a mixed order had nowhere to record that half
--     of it was taxed differently.
--  2. recompute_order_tax resolves a rate PER LINE and sums. orders.tax_amount
--     is now the sum of its lines rather than a rate applied to a total.
--     orders.tax_rate_id keeps the dominant rate for display and for anything
--     still reading it, but it is no longer what the money is computed from.
--  3. tax_liability_by_rate groups by the LINE's rate. Grouping by the order's
--     single rate would have filed a mixed order entirely under one of them.
--
-- The no-rate case is unchanged and deliberate: a line that resolves no rate
-- is taxed at nothing and keeps whatever it had, because "no rate today" does
-- not mean "never taxed" -- that distinction was fixed once already and the
-- comment in the old function stays true.

begin;

alter table public.order_details
  add column if not exists tax_rate_id text references public.tax_rate(tax_rate_id) on delete set null,
  add column if not exists tax_amount  numeric;

comment on column public.order_details.tax_rate_id is
  'The rate THIS line resolved to. An order whose lines sit on different channels is taxed line by line; orders.tax_rate_id holds only the dominant one.';
comment on column public.order_details.tax_amount is
  'Tax charged on this line. orders.tax_amount is the sum of these.';

create or replace function public.recompute_order_tax(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_o         record;
  v_pass      boolean;
  v_tax       numeric := 0;
  v_dominant  text;
  v_line      record;
  v_rate_id   text;
  v_charge    numeric;
  v_statutory numeric;
  v_line_tax  numeric;
begin
  select o.order_id, o.company_id, o.facility_id, o.customer_id, o.order_date,
         o.order_total, coalesce(o.posted,false) as posted,
         coalesce(o.is_legacy_import,false) as legacy
    into v_o from public.orders o where o.order_id = p_order_id;
  if not found then return null; end if;
  if v_o.posted or v_o.legacy then
    raise exception 'order % is posted or imported history — its tax is locked', p_order_id;
  end if;

  select coalesce(c.tax_passed_through, true) into v_pass
    from public.customers c where c.customer_id = v_o.customer_id;
  v_pass := coalesce(v_pass, true);

  -- LINE BY LINE. Each resolves against its OWN channel and product type,
  -- which is what a tax rule keys on.
  for v_line in
    select od.order_detail_id, od.total_price, p.channel, p.product_type
    from public.order_details od
    left join public.products p on p.product_id = od.product_id
    where od.order_id = p_order_id
  loop
    v_rate_id := public.resolve_tax_rate(
      v_o.company_id, v_o.facility_id, v_line.channel, v_line.product_type,
      v_o.customer_id, v_o.order_date);

    if v_rate_id is null then
      -- No rate for this line. It contributes nothing, and its own stamp is
      -- left alone for the same reason the order-level one always was.
      continue;
    end if;

    select t.charge_rate into v_charge
      from public.tax_rate t where t.tax_rate_id = v_rate_id;

    v_line_tax := case when v_pass
                       then round(coalesce(v_line.total_price,0) * coalesce(v_charge,0), 2)
                       else 0 end;

    update public.order_details
       set tax_rate_id = v_rate_id,
           tax_amount  = v_line_tax
     where order_detail_id = v_line.order_detail_id;

    v_tax := v_tax + v_line_tax;
  end loop;

  -- The dominant rate, for display and for anything still reading the order's
  -- single tax_rate_id. The MONEY no longer comes from it.
  select od.tax_rate_id into v_dominant
  from public.order_details od
  where od.order_id = p_order_id and od.tax_rate_id is not null
  group by od.tax_rate_id
  order by sum(coalesce(od.total_price,0)) desc nulls last
  limit 1;

  if v_dominant is null then
    -- Nothing resolved at all: leave the order's existing stamp as history.
    return null;
  end if;

  select t.charge_rate, t.statutory_rate into v_charge, v_statutory
    from public.tax_rate t where t.tax_rate_id = v_dominant;

  update public.orders
     set tax_rate_id = v_dominant,
         tax_rate = case when v_pass then v_charge else v_statutory end,
         tax_amount = v_tax,
         tax_passed_through = v_pass
   where order_id = p_order_id;
  return v_tax;
end;
$function$;

-- The filing report follows the money: group by the LINE's rate, or a mixed
-- order files entirely under whichever rate happened to be larger.
create or replace view public.tax_liability_by_rate
with (security_invoker = true)
as
 SELECT o.company_id,
    date_trunc('month'::text,
        CASE WHEN COALESCE(b.accounting_basis, 'accrual'::text) = 'cash'::text
             THEN o.paid_at::date ELSE o.order_date END::timestamp with time zone)::date AS period,
    COALESCE(b.accounting_basis, 'accrual'::text) AS accounting_basis,
    t.tax_rate_id,
    t.code,
    t.label,
    t.statutory_rate,
    count(DISTINCT o.order_id) AS invoices,
    round(sum(od.total_price), 2) AS taxable_sales,
    round(sum((od.total_price + COALESCE(od.tax_amount, 0::numeric)) * t.statutory_rate), 2) AS tax_owed,
    round(sum(COALESCE(od.tax_amount, 0::numeric)), 2) AS tax_collected,
    round(sum((od.total_price + COALESCE(od.tax_amount, 0::numeric)) * t.statutory_rate)
          - sum(COALESCE(od.tax_amount, 0::numeric)), 2) AS tax_absorbed
   FROM orders o
     JOIN order_details od ON od.order_id = o.order_id
     JOIN tax_rate t ON t.tax_rate_id = od.tax_rate_id
     LEFT JOIN billing_settings b ON b.company_id = o.company_id
  WHERE o.order_status <> 'Canceled'::text
    AND (COALESCE(b.accounting_basis, 'accrual'::text) <> 'cash'::text OR o.paid_at IS NOT NULL)
  GROUP BY o.company_id, (date_trunc('month'::text,
        CASE WHEN COALESCE(b.accounting_basis, 'accrual'::text) = 'cash'::text
             THEN o.paid_at::date ELSE o.order_date END::timestamp with time zone)::date),
        (COALESCE(b.accounting_basis, 'accrual'::text)), t.tax_rate_id, t.code, t.label, t.statutory_rate;

do $$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.recompute_order_tax(text)'::regprocedure;

  -- The tell that it no longer picks one rate for everything.
  if position('for v_line in' in v_src) = 0 then
    raise exception 'recompute_order_tax still resolves a single rate for the order';
  end if;
  if position('order by sum(coalesce(od.total_price,0)) desc' in v_src) = 0 then
    raise exception 'the dominant-rate fallback is missing';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='order_details' and column_name='tax_amount'
  ) then
    raise exception 'order_details.tax_amount was not added';
  end if;

  -- The filing view must read the LINE's rate now.
  if position('od.tax_rate_id' in pg_get_viewdef('public.tax_liability_by_rate'::regclass, true)) = 0 then
    raise exception 'tax_liability_by_rate still groups by the order rate';
  end if;
end $$;

commit;
