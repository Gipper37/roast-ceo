-- Snapshot the unit price on the order line, so repricing the catalogue cannot
-- rewrite an invoice that was already issued.
--
-- THE HOLE. handle_order_detail_logic() recomputes total_price from
-- products.price whenever a line is INSERTed or its quantity / product /
-- amount_override changes -- and the price it reaches for is TODAY'S. Change a
-- product's price, then edit a line on a months-old order, and that order
-- silently re-prices at the new figure. Measured on prod inside a rolled-back
-- transaction: a $149.50 line became $1,495.00 after a 10x price change and a
-- quantity nudge.
--
-- Changing a price BY ITSELF was always safe and still is -- nothing touches
-- order_details until someone edits a line. This closes the edit path.
--
-- WHAT WAS ALREADY PROTECTED, and why it was not enough:
--   * is_legacy_import orders (3,759 of MCR's 3,806) skip the recompute
--     entirely, so the QuickBooks history was never at risk.
--   * posted orders are frozen by guard_posted_order_detail_immutable.
--   * Everything else was exposed -- 45 STRATA-native unposted orders on MCR
--     alone, and every order any tenant writes from here on. Those are exactly
--     the live ones: quoted, sent, not yet posted.
--
-- THE FIX is the one the line already uses for its other two facts. It snapshots
-- the product's NAME (product_name_snapshot) and its COST (unit_cost_at_sale) at
-- sale time; price was the conspicuous omission. Now it snapshots that too, and
-- the recompute multiplies by the snapshot instead of by the live product. This
-- is how QuickBooks and Shopify model it: the line carries its own price, and
-- the catalogue is where you look up a price for a NEW line, never to re-derive
-- an old one.

begin;

alter table public.order_details
  add column if not exists unit_price_at_sale numeric;

comment on column public.order_details.unit_price_at_sale is
  'Unit price stamped when the line was written, or when its product changed. '
  'The recompute multiplies by this and never by products.price, so repricing '
  'the catalogue cannot restate an issued invoice.';

-- Backfill from what each line actually charged, so existing rows keep their own
-- price rather than adopting today's. Dividing by quantity recovers the unit
-- price that was used. Rows with no quantity, a zero total, or an explicit
-- amount_override are left null: there is no honest unit price to infer, and the
-- fallback in the function handles them exactly as they behave today.
--
-- Triggers OFF for the backfill, deliberately. This is a data stamp, not a
-- business event, and letting the row triggers fire would do two unwanted
-- things: the audit trigger would stamp updated_at/updated_by on every line in
-- the table, making a migration look like fifteen thousand operator edits; and
-- handle_order_detail_logic() re-syncs company_id from the parent order on ANY
-- update, which fails outright on a line whose parent is missing. Prod has
-- exactly one such orphan (order_detail_id 4b349306 -> order_id 999a5541,
-- $396.00) and it aborted this migration on the first rehearsal. That orphan is
-- a pre-existing data defect and is NOT repaired here -- deleting or reparenting
-- a line carrying money is its own decision, not a side effect of adding a
-- column.
--
-- Nothing but the new column is written, so skipping the triggers cannot skip
-- anything that mattered: the recompute branch would not have fired anyway
-- (quantity, product_id and amount_override are all untouched), and the
-- order-totals sync has no totals to re-sum.
alter table public.order_details disable trigger user;

update public.order_details
   set unit_price_at_sale = round(total_price / quantity, 6)
 where unit_price_at_sale is null
   and quantity is not null and quantity <> 0
   and total_price is not null and total_price <> 0
   and amount_override is null;

alter table public.order_details enable trigger user;

create or replace function public.handle_order_detail_logic()
returns trigger
language plpgsql
as $function$
DECLARE
    v_company_id      text;
    v_facility_id     text;
    v_product_weight  numeric;
    v_product_price   numeric;
    v_recipe_id       text;
    v_cogs            numeric;
    v_is_legacy       boolean;
    v_reduces         boolean;
    v_reprice         boolean;
BEGIN
    -- 1. Always sync order metadata from parent (+ read the legacy-import flag).
    SELECT order_date, customer_id, company_id, facility_id, COALESCE(is_legacy_import, false)
    INTO   NEW.order_date, NEW.customer_id, v_company_id, v_facility_id, v_is_legacy
    FROM   orders
    WHERE  order_id = NEW.order_id;

    NEW.company_id  := v_company_id;
    NEW.facility_id := v_facility_id;

    -- 2. Recompute price/weight/cost from the product on INSERT / qty / product /
    --    override change. SKIP for a legacy QB import: the historical amounts
    --    (signed credit-memo totals, discounted prices, period COGS) are supplied by
    --    the importer and must be preserved EXACTLY. Live orders unchanged.
    IF NOT v_is_legacy
       AND (TG_OP = 'INSERT'
            OR NEW.quantity        IS DISTINCT FROM OLD.quantity
            OR NEW.product_id      IS DISTINCT FROM OLD.product_id
            OR NEW.amount_override IS DISTINCT FROM OLD.amount_override)
    THEN
        SELECT p.weight_lbs,
               p.price,
               p.recipe_id,
               COALESCE(p.total_unit_cogs, 0),
               COALESCE(pt.reduces_total, false)
        INTO   v_product_weight, v_product_price, v_recipe_id, v_cogs, v_reduces
        FROM   products p
        LEFT   JOIN public.product_type pt ON pt.product_type_id = p.product_type
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        -- Which price applies. A NEW line, or a line whose PRODUCT changed, is
        -- being priced for the first time -- the catalogue is the right source
        -- and the result is stamped. An existing line whose quantity or override
        -- moved is NOT being repriced: it keeps the unit price it was sold at,
        -- because that is what the customer agreed to. This single branch is the
        -- whole fix.
        v_reprice := TG_OP = 'INSERT'
                     OR NEW.product_id IS DISTINCT FROM OLD.product_id
                     OR NEW.unit_price_at_sale IS NULL;

        IF v_reprice THEN
            NEW.unit_price_at_sale := v_product_price;
        ELSE
            v_product_price := NEW.unit_price_at_sale;
        END IF;

        IF NEW.amount_override IS NOT NULL THEN
            -- Verbatim, sign and all. An operator who types an exact amount means it.
            NEW.total_price := NEW.amount_override;
        ELSIF COALESCE(v_reduces, false) THEN
            -- abs() so the result is negative whether the product's price is stored
            -- positive (the normal case, and the one that caused this bug) or
            -- already negative. A discount cannot add, whatever the price field says.
            NEW.total_price := -abs(COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0));
        ELSE
            NEW.total_price := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
        END IF;

        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

    -- 2b. Weight is PHYSICAL, not financial -- so a legacy import gets it too.
    --     The skip above exists to protect QuickBooks' historical AMOUNTS (signed
    --     credit-memo totals, negotiated prices, period COGS). roasted_weight is not
    --     one of those: QuickBooks never supplied it, it is simply quantity x the
    --     product's own weight. Skipping it left every imported coffee line at 0 lbs,
    --     so imported orders showed "Total Weight 0 lbs" and every pounds-based
    --     report undercounted history. Only fills a BLANK, so it can never overwrite
    --     a weight the operator or the live path already set.
    IF NEW.product_id IS NOT NULL AND COALESCE(NEW.roasted_weight, 0) = 0 THEN
        SELECT p.weight_lbs INTO v_product_weight
        FROM   products p
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        IF COALESCE(v_product_weight, 0) > 0 THEN
            NEW.roasted_weight := COALESCE(NEW.quantity, 0) * v_product_weight;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

commit;
