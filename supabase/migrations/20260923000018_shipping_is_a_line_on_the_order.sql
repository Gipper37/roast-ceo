-- Shipping charged by the shop has to land on the order.
--
-- serverComputeCartCents adds a shipping charge to what the card is billed,
-- and nothing records it. The order keeps only the goods, so:
--
--   charged      subtotal 198000 + shipping 3750 = 201750   ($2,017.50)
--   recorded     orders.order_total                = 1980.00
--   A/R short by the shipping, every time.
--
-- And because nothing stores it, the invoice INVENTS it by subtraction --
-- chargedCents - subtotal - tax -- so editing an order afterwards fabricates a
-- shipping figure out of the difference.
--
-- A LINE, not a column. Ten things compute an invoice total (7 functions, 3
-- views) and a column would need adding to every one, plus its own tax
-- treatment. A line flows into order_total, invoice_ar_balances, the invoice
-- document and the tax base with no new arithmetic anywhere -- and it is
-- REPORTABLE, which the owner asked for: "shipping should be tracked/reported
-- for bookkeeping purposes." A line is already grouped by product in every
-- revenue and margin surface. A column would be invisible to all of them.
--
-- It is also what MCR already does: they have a Shipping product of type
-- Service carrying $470.61 of history.
--
-- This migration only makes the line POSSIBLE -- the column to hang it on, and
-- a product for any shop that charges shipping without one. The checkout
-- change that writes the line rides with it.
--
-- NOT ADDRESSED HERE, and deliberately: the shop prices shipping per POUND,
-- and every one of the 105 consumables carries no weight while all 327 coffees
-- do. So a cart of syrups ships free at any rate. That is a pricing policy
-- decision, not a bug with one right answer, and it is the owner's to make.

begin;

alter table public.shop_config
  add column if not exists shipping_product_id text
    references public.products(product_id) on delete set null;

comment on column public.shop_config.shipping_product_id is
  'The product a shop shipping charge is billed on. Lets shipping be a real order line, so it reaches the invoice, A/R and every revenue report without special-casing.';

do $$
declare
  r            record;
  v_group      uuid;
  v_product    text;
  v_type       text;
  v_made       int := 0;
  v_linked     int := 0;
begin
  select product_type_id into v_type from public.product_type
  where lower(product_type) = 'service' limit 1;

  for r in
    select sc.company_id, sc.facility_id
    from public.shop_config sc
    where coalesce(sc.shipping_enabled, false)
      and sc.shipping_product_id is null
  loop
    -- Reuse a Shipping product if the tenant already has one.
    select p.product_id into v_product
    from public.products p
    where p.company_id = r.company_id and p.is_active
      and p.product_name ilike 'shipping'
    limit 1;

    if v_product is null then
      -- Mint one. A shop that charges shipping needs something to bill it on;
      -- without this the charge keeps vanishing from the order.
      v_group   := gen_random_uuid();
      v_product := gen_random_uuid()::text;

      insert into public.product_groups (group_id, group_name, company_id, facility_id)
      values (v_group, 'Shipping', r.company_id, r.facility_id);

      insert into public.products (
        product_id, group_id, product_name, product_type,
        company_id, facility_id, is_active, price
      ) values (
        v_product, v_group, 'Shipping', v_type,
        r.company_id, r.facility_id, true,
        -- Priced per order by the cart, never from the catalogue.
        null
      );
      v_made := v_made + 1;
    end if;

    update public.shop_config
       set shipping_product_id = v_product
     where company_id = r.company_id;
    v_linked := v_linked + 1;
  end loop;

  raise notice 'linked % shops to a shipping product (% newly created)', v_linked, v_made;
end $$;

do $$
declare
  v_missing int;
begin
  -- Any shop still charging shipping with nowhere to record it is the bug this
  -- migration exists to remove.
  select count(*) into v_missing from public.shop_config
  where coalesce(shipping_enabled, false) and shipping_product_id is null;
  if v_missing > 0 then
    raise exception '% shops charge shipping with no product to bill it on', v_missing;
  end if;
end $$;

commit;
