-- Imported order lines get their roasted weight (it is physical, not financial).
--
-- handle_order_detail_logic skips its whole recompute block for a legacy QuickBooks
-- import, which is right for MONEY: the historical amounts — signed credit-memo
-- totals, negotiated prices, period COGS — are supplied by the importer and must
-- survive exactly. But the same block also sets roasted_weight, so every imported
-- coffee line landed at 0.
--
-- QuickBooks never supplied a weight. roasted_weight is just quantity x the
-- product's own weight_lbs, so there is nothing to preserve and nothing to conflict
-- with. Leaving it blank made imported orders read "Total Weight 0 lbs" (MCR: 4,347
-- lines / 11,670 lbs / 227 orders) and silently undercounted every pounds-based
-- report of trading history.
--
-- The new step only fills a BLANK weight, so it cannot overwrite one the live path
-- or an operator already set, and it leaves total_price completely untouched.
-- Non-coffee lines (weight_lbs null/0) stay at 0, which is correct.

CREATE OR REPLACE FUNCTION public.handle_order_detail_logic()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_company_id      text;
    v_facility_id     text;
    v_product_weight  numeric;
    v_product_price   numeric;
    v_recipe_id       text;
    v_cogs            numeric;
    v_is_legacy       boolean;
BEGIN
    -- 1. Always sync order metadata from parent (+ read the legacy-import flag).
    SELECT order_date, customer_id, company_id, facility_id, COALESCE(is_legacy_import, false)
    INTO   NEW.order_date, NEW.customer_id, v_company_id, v_facility_id, v_is_legacy
    FROM   orders
    WHERE  order_id = NEW.order_id;

    NEW.company_id  := v_company_id;
    NEW.facility_id := v_facility_id;

    -- 2. Recompute price/weight/cost from the product on INSERT / qty / product
    --    change. SKIP for a legacy QB import: the historical amounts (signed
    --    credit-memo totals, discounted prices, period COGS) are supplied by the
    --    importer and must be preserved EXACTLY. Live orders unchanged.
    IF NOT v_is_legacy
       AND (TG_OP = 'INSERT'
            OR NEW.quantity   IS DISTINCT FROM OLD.quantity
            OR NEW.product_id IS DISTINCT FROM OLD.product_id)
    THEN
        SELECT p.weight_lbs,
               p.price,
               p.recipe_id,
               COALESCE(p.total_unit_cogs, 0)
        INTO   v_product_weight, v_product_price, v_recipe_id, v_cogs
        FROM   products p
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        NEW.total_price       := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

    -- 2b. Weight is PHYSICAL, not financial — so a legacy import gets it too.
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

-- Backfill the lines already imported with a blank weight. Scoped to legacy imports
-- with a product that HAS a weight, so it can only ever fill in a zero — no live
-- order, and no line an operator weighed by hand, is touched.
UPDATE public.order_details d
SET    roasted_weight = d.quantity * p.weight_lbs
FROM   public.products p, public.orders o
WHERE  p.product_id = d.product_id
  AND  o.order_id   = d.order_id
  AND  COALESCE(o.is_legacy_import, false)
  AND  COALESCE(d.roasted_weight, 0) = 0
  AND  COALESCE(p.weight_lbs, 0) > 0;
