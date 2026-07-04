-- QB import (P1/M4) prerequisite: guard the order→inventory trigger chain against
-- legacy historical imports (orders.is_legacy_import = true), so importing QB
-- history does NOT trigger the live-order side effects that corrupt the data.
-- REVIEW-FIRST: written for review; apply only when approved (commit → db-push
-- staging → golden test → prod release tag).
--
-- Two behaviors must be neutralized for is_legacy_import orders:
--   A) total_price clobber — handle_order_detail_logic recomputes
--      total_price:=qty*product.price on INSERT. QB history lines carry their own
--      signed Amount (credit memos NEGATIVE, discounts/manual prices differ), so
--      the clobber flips credit memos positive and breaks the $ reconciliation.
--      → skip the recompute for legacy imports (preserve the imported amounts).
--   B) consumable usage — EVERY function that sums order_details usage must exclude
--      legacy orders, else historical imports deduct consumables that were consumed
--      long ago and inflate reorder signals. Current consumable stock is anchored to
--      the physical count. There are SIX such usage sums across FIVE functions (an
--      adversarial review proved a partial guard is self-defeating: the unguarded
--      update_consumable_metrics re-folds legacy usage into persisted in_stock on any
--      updated_at touch — qty-999 legacy order → in_stock −999). All are guarded here.
--
-- LIVE-ORDER SAFETY: every guard is a no-op for non-legacy orders. is_legacy_import
-- is boolean NOT NULL DEFAULT false, so COALESCE(...,false)=false is true for live
-- orders → the recompute gate collapses to the original condition and the usage
-- filters include exactly the same rows as today. Verified byte-for-byte in review.
-- NOT guarded (correct as-is): update_order_aggregates rolls the preserved signed
-- line totals to the true QB invoice total; audit triggers record the import; orders
-- never deduct COFFEE (roasts do). is_legacy_import exists on prod (spine 20260701000001).

-- ── (A) Preserve historical amounts on legacy-import order_details ──────────────
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

    RETURN NEW;
END;
$function$;

-- ── (B1) On-demand consumable stock calculator ────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
BEGIN
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cp.facility_id = p_facility_id;

    -- Subtractions (non-canceled orders). EXCLUDE legacy QB imports — historical
    -- records must never affect current consumable stock (anchored to the count).
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$function$;

-- ── (B2) Per-row consumable recompute trigger — short-circuit for legacy rows ──
CREATE OR REPLACE FUNCTION public.update_consumable_stock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    r               RECORD;
    v_product_id    TEXT;
    v_facility_id   TEXT;
    v_current_stock NUMERIC;
    v_par           NUMERIC;
    v_restock_level NUMERIC;
    v_is_legacy     BOOLEAN;
BEGIN
    -- Legacy imports never affect consumable stock (excluded from every usage
    -- sum), so skip the expensive per-consumable recompute for them entirely —
    -- avoids thousands of no-op recomputes during a bulk historical import. If the
    -- parent order is absent (cascade delete), the lookup is NULL → IF not taken →
    -- normal (still legacy-excluded) recompute runs; harmless.
    SELECT COALESCE(is_legacy_import, false) INTO v_is_legacy
    FROM orders WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);
    IF v_is_legacy THEN RETURN NULL; END IF;

    v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    FOR r IN
        SELECT consumable_id
        FROM public.product_consumables
        WHERE product_id = v_product_id
    LOOP
        v_current_stock := public.calculate_current_stock_consumables(r.consumable_id, v_facility_id);
        v_par           := public.calculate_consumable_par(r.consumable_id, v_facility_id);
        v_restock_level := public.calculate_consumable_restock_level(r.consumable_id, v_facility_id);

        UPDATE public.consumable_inventory
        SET
            in_stock      = v_current_stock,
            par           = v_par,
            restock_level = v_restock_level,
            to_order      = CASE
                                WHEN v_current_stock <= v_restock_level
                                THEN GREATEST(0, v_par - v_current_stock)
                                ELSE 0
                            END,
            updated_at    = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = v_facility_id;
    END LOOP;

    RETURN NULL;
END;
$function$;

-- ── (B3) The OTHER persisted-in_stock writer (BEFORE UPDATE OF updated_at on
--         consumable_inventory). Exclude legacy from BOTH usage sums — else it
--         re-folds legacy usage into in_stock (its recompute wins over B2) and
--         inflates 92-day daily_usage. ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_consumable_metrics()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_baseline   DATE;
  v_received   NUMERIC;
  v_used       NUMERIC;
  v_in_stock   NUMERIC;
  v_par        NUMERIC;
  v_restock    NUMERIC;
  v_92day      NUMERIC;
BEGIN
  v_baseline := COALESCE(NEW.last_inventory_date, '2000-01-01');

  SELECT COALESCE(SUM(cip.amount), 0) INTO v_received
  FROM consumable_inventory_purchased cip
  JOIN shipment_received sr ON cip.shipment_id = sr.shipment_id
  WHERE cip.consumable_inventory_item = NEW.consumable_inventory_id
    AND sr.date_received >= v_baseline
    AND (sr.voided IS NULL OR sr.voided = false);

  -- Units consumed since baseline (exclude legacy imports).
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_used
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = NEW.facility_id;

  v_in_stock := GREATEST(0, COALESCE(NEW.inventory_count, 0) + v_received - v_used);
  NEW.in_stock := v_in_stock;

  v_par := calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id);
  v_restock := calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id);
  NEW.par := v_par;
  NEW.restock_level := v_restock;
  NEW.to_order := CASE WHEN v_in_stock <= v_restock THEN GREATEST(0, v_par - v_in_stock) ELSE 0 END;

  -- Daily usage from 92-day order history (exclude legacy imports).
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_92day
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := v_92day / 92.0;

  RETURN NEW;
END;
$function$;

-- ── (B4) par: 92-day reorder signal (exclude legacy imports) ────────────────────
CREATE OR REPLACE FUNCTION public.calculate_consumable_par(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_92day_usage    numeric;
  v_monthly_usage  numeric;
  v_target_months  numeric;
  v_buffer         numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  RETURN CEIL(v_monthly_usage * v_target_months * v_buffer);
END;
$function$;

-- ── (B5) restock_level: 92-day reorder signal (exclude legacy imports) ──────────
CREATE OR REPLACE FUNCTION public.calculate_consumable_restock_level(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_92day_usage       numeric;
  v_monthly_usage     numeric;
  v_reorder_months    numeric;
  v_buffer            numeric;
  v_par               numeric;
  v_result            numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  v_result := CEIL(v_monthly_usage * v_reorder_months * v_buffer);

  v_par := calculate_consumable_par(p_consumable_id, p_facility_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;

-- ── (B6) consumable cost propagation to orders — never re-cost legacy imports ───
--         (already books-closed-gated; add the legacy filter so an imported line's
--         preserved unit_cost_at_sale can't be clobbered by a later cost edit). ──
CREATE OR REPLACE FUNCTION public.propagate_consumable_purchase_to_orders()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.cost_unit IS NOT DISTINCT FROM NEW.cost_unit THEN
        RETURN NULL;
    END IF;
    IF COALESCE(NEW.cost_unit, 0) = 0 THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;
    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    SELECT sr.date_received INTO v_next_date
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = NEW.consumable_inventory_item
       AND cp.facility_id               = NEW.facility_id
       AND sr.date_received              IS NOT NULL
       AND sr.date_received               > v_this_date
       AND cp.consumable_purchase_id    != NEW.consumable_purchase_id
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC
     LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id,
                        od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o           ON o.order_id   = od.order_id
          JOIN public.product_consumables pc
               ON pc.product_id  = od.product_id AND pc.facility_id = od.facility_id
          JOIN public.companies cmp      ON cmp.company_id = od.company_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND od.order_date      > COALESCE(cmp.books_closed_through, '-infinity'::date)  -- books-closed guard
           AND COALESCE(o.is_legacy_import, false) = false                                 -- never re-cost imports
           AND pc.consumable_id   = NEW.consumable_inventory_item
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(v_rec.product_id, v_rec.facility_id, v_rec.order_date);
        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity, updated_at = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$function$;

NOTIFY pgrst, 'reload schema';
