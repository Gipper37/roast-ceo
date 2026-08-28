-- Four corrections, three of them from primary DOTAX sources and one from the
-- owner spotting that an absorbed sale has a different base.
--
-- ── 1. DOTAX TRUNCATES ITS PASS-ON RATE, IT DOES NOT ROUND ───────────────────
-- The published maximum for 4.5% activities is 4.712000%, and 4.5/95.5 is
-- 0.04712041884... — truncated at six decimals of the fraction, downward. The
-- charge_rate column was rounding. The difference is about a cent per $100,000,
-- which matters only because the cap is ONE-DIRECTIONAL: Tax Facts 37-1 Q8 says
-- "Consumer protection laws prohibit businesses from charging customers more GET
-- than the business will pay on the transaction." Under is fine; over is not. So
-- truncate, and never round up.
--
-- ── 2. MAUI COUNTY SURCHARGE ON RETAIL, FROM 2024-01-01 ──────────────────────
-- Ordinance No. 5551 via Tax Announcement 2023-05: a 0.5% county surcharge on
-- Maui from 2024-01-01 to 2030-12-31, so retail is 4% + 0.5% = 4.5%, max visible
-- pass-on 4.712000%.
--
-- MCR has been charging ~4.167% since then — the pre-surcharge rate — across 145
-- retail invoices on $64,443.62 of sales, collecting $2,265.68 where 4.5% of
-- gross would be $3,001.92. The owner's call: retail is a small part of the
-- business, past invoices stay as billed, fix it going forward. So the old
-- retail rate is CLOSED and a 4.5% successor opens, exactly as the wholesale
-- change was handled — history keeps reporting under the rate it was billed at.
--
-- DOTAX is explicit and repeats it three times: the surcharge does NOT apply to
-- wholesale. "the CS does not apply to wholesale sales or insurance commission
-- where the GET rates are 0.5% and 0.15%". The wholesale rate is untouched here.
--
-- ── 3. AN ABSORBED SALE IS TAXED ON A SMALLER BASE ───────────────────────────
-- The owner's catch. Grossing up exists only because the GET you COLLECT is
-- itself gross income (G-45 instructions: "Gross income includes any cost passed
-- on to the customer and represented to be the GET"). Collect nothing and there
-- is nothing extra in the base — you owe a flat 0.5% of the sale, not 0.502512%
-- of it. The liability view already had this right, because it multiplies
-- (order_total + tax_amount) and tax_amount is zero when absorbed. What was
-- wrong is what got RECORDED on the order: the grossed-up charge rate, on an
-- invoice that charged nothing. It now records the statutory rate.
--
-- ── 4. A DISCOUNT SCOPE FOR RESOLD GOODS ─────────────────────────────────────
-- The owner wants coffee at one rate and resale/distribution at another. Coffee
-- is a clean product type (411 active variants). Resold goods are NOT a type —
-- they are consumables carrying products.source_consumable_id, and 63 of MCR's
-- 75 consumables are resold while 12 are internal supplies like bags and
-- filters. Scoping to the Consumable type would quietly discount the filters
-- too, so 'distribution' becomes its own scope, matching the same derived test
-- the Products page filter already uses.

begin;

-- 1 ───────────────────────────────────────────────────────────────────────────
-- Regenerating the column recomputes it for every row, but nothing historical
-- reads it: orders stamp their own tax_rate at the time, and the liability view
-- uses statutory_rate. Checked before changing it.
alter table public.tax_rate drop column charge_rate;
alter table public.tax_rate add column charge_rate numeric(12,10)
  generated always as (
    case when gross_up
         -- trunc, not round: DOTAX's own convention, and the cap only bites upward.
         then trunc(statutory_rate / (1 - statutory_rate), 6)
         else trunc(statutory_rate, 6) end
  ) stored;

comment on column public.tax_rate.charge_rate is
  'What is actually charged, derived from the statutory rate. TRUNCATED at six '
  'decimals, matching DOTAX''s published pass-on rates (4.5/95.5 = 0.04712041... '
  'published as 0.047120) — and because the pass-on cap is one-directional: a '
  'business may never charge more GET than it will pay.';

-- 2 ───────────────────────────────────────────────────────────────────────────
update public.tax_rate
   set effective_to = current_date,
       label = label || ' (through ' || current_date || ')',
       updated_at = now()
 where tax_rate_id = 'mcr-hi-retail'
   and company_id = '9ShiyDAXhV'
   and effective_to is null;

insert into public.tax_rate
  (tax_rate_id, company_id, jurisdiction_id, code, label,
   statutory_rate, gross_up, kind, requires_resale_cert, filing_class, effective_from)
select 'mcr-hi-retail-45', '9ShiyDAXhV', t.jurisdiction_id, 'GET_RETAIL_45',
       'GET retail 4.5% on the gross (incl. Maui county)',
       0.045, true, 'standard', false, 'retailing', current_date + 1
  from public.tax_rate t where t.tax_rate_id = 'mcr-hi-retail'
on conflict (tax_rate_id) do nothing;

update public.tax_rule
   set tax_rate_id = 'mcr-hi-retail-45', updated_at = now()
 where company_id = '9ShiyDAXhV' and tax_rate_id = 'mcr-hi-retail';

update public.customers
   set tax_rate_id = 'mcr-hi-retail-45'
 where company_id = '9ShiyDAXhV' and tax_rate_id = 'mcr-hi-retail';

-- 3 ───────────────────────────────────────────────────────────────────────────
create or replace function public.recompute_order_tax(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_o        record;
  v_rate_id  text;
  v_charge   numeric;
  v_statutory numeric;
  v_pass     boolean;
  v_tax      numeric;
begin
  select o.order_id, o.company_id, o.facility_id, o.customer_id, o.order_date,
         o.order_total, coalesce(o.posted,false) as posted
    into v_o from public.orders o where o.order_id = p_order_id;
  if not found then return null; end if;
  if v_o.posted then
    raise exception 'order % is posted — its tax is locked', p_order_id;
  end if;

  select public.resolve_tax_rate(
           v_o.company_id, v_o.facility_id,
           (select p.channel from public.order_details od
              join public.products p on p.product_id = od.product_id
             where od.order_id = p_order_id
             group by p.channel order by sum(od.total_price) desc nulls last limit 1),
           (select p.product_type from public.order_details od
              join public.products p on p.product_id = od.product_id
             where od.order_id = p_order_id
             group by p.product_type order by sum(od.total_price) desc nulls last limit 1),
           v_o.customer_id, v_o.order_date)
    into v_rate_id;

  if v_rate_id is null then
    update public.orders set tax_rate_id = null where order_id = p_order_id;
    return null;
  end if;

  select t.charge_rate, t.statutory_rate into v_charge, v_statutory
    from public.tax_rate t where t.tax_rate_id = v_rate_id;
  select coalesce(c.tax_passed_through, true) into v_pass
    from public.customers c where c.customer_id = v_o.customer_id;

  v_tax := case when coalesce(v_pass, true)
                then round(coalesce(v_o.order_total,0) * coalesce(v_charge,0), 2)
                else 0 end;

  update public.orders
     set tax_rate_id = v_rate_id,
         -- The rate that describes THIS sale. Charging nothing means nothing is
         -- added to gross income, so the base is just the sale and the rate that
         -- applies to it is the statutory one — the gross-up exists only to
         -- cover tax collected, and none was.
         tax_rate = case when coalesce(v_pass, true) then v_charge else v_statutory end,
         tax_amount = v_tax,
         tax_passed_through = coalesce(v_pass, true)
   where order_id = p_order_id;
  return v_tax;
end;
$function$;

-- 4 ───────────────────────────────────────────────────────────────────────────
alter table public.customer_discount drop constraint if exists customer_discount_scope_check;
alter table public.customer_discount drop constraint customer_discount_scope_ref_present;
alter table public.customer_discount
  add constraint customer_discount_scope_check
  check (scope in ('all','product_type','product','distribution'));
alter table public.customer_discount
  add constraint customer_discount_scope_ref_present
  check (
    (scope in ('all','distribution') and scope_ref is null)
    or (scope in ('product_type','product') and scope_ref is not null)
  );

create or replace function public.resolve_customer_discount(
  p_customer_id text,
  p_product_id  text,
  p_on_date     date default current_date
)
returns table (customer_discount_id text, kind text, value numeric, scope text)
language sql
stable
security invoker
as $function$
  select d.customer_discount_id, d.kind, d.value, d.scope
  from public.customer_discount d
  join public.products p on p.product_id = p_product_id
  left join public.product_groups pg on pg.group_id = p.group_id
  where d.customer_id = p_customer_id
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      -- Resold goods: the same derived test the Products page filter uses.
      -- Deliberately not the Consumable product type, which would also catch
      -- the internal supplies that are never resold.
      or (d.scope = 'distribution'  and p.source_consumable_id is not null)
      or (d.scope = 'product_type'  and d.scope_ref = p.product_type)
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
    )
  -- Most specific wins. Distribution sits above a plain type because "resold
  -- goods" is the narrower statement about the same item.
  order by case d.scope
             when 'product' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc
  limit 1;
$function$;

commit;
