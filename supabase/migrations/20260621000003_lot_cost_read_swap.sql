-- ============================================================================
-- Lot-precise COGS — Step 2 of 4: read-swap (product/order COGS -> lot cost)
-- ----------------------------------------------------------------------------
-- Repoints product + order COGS from the group rollup (coffee_inventory.
-- latest_cost = weighted-avg of latest shipment, ROASTED-equivalent) to the
-- lot-precise roasted cost from the Step-1 ledger.
--
-- PERFORMANCE: the live COGS trigger (update_product_total_cogs) fires on every
-- product change, so it must NOT scan the ledger. Instead we CACHE the
-- per-origin roasted cost in coffee_inventory.latest_roasted_cost — refreshed
-- ONCE per roast (when the roast is valued) — and the live trigger reads that
-- COLUMN, exactly mirroring how latest_cost is cached today. Ledger scans
-- happen once per roast per origin, never per product recompute.
--
-- SAFE / INERT UNTIL DATA: latest_roasted_cost is NULL until an origin has a
-- valued roast; the live trigger falls back to latest_cost, and the historical
-- path falls back to get_coffee_cost_on_date. So on any DB whose ledger isn't
-- populated (staging, prod until the Step-4 backfill), COGS is byte-for-byte
-- identical to today.
--
-- Green vs roasted: coffee_inventory.last_cost_lb / coffee_inventory_purchased.
-- cost_lb stay the GREEN $/lb surfaces (inventory + order forms). latest_cost
-- and the new latest_roasted_cost are the ROASTED-equivalent COGS inputs.
-- ============================================================================

BEGIN;

-- 1. Cached per-origin roasted cost (the lot-precise analogue of latest_cost) -
ALTER TABLE public.coffee_inventory
    ADD COLUMN IF NOT EXISTS latest_roasted_cost numeric;

-- index the origin lookup used by the as-of-date roasted-cost query
CREATE INDEX IF NOT EXISTS idx_cip_origin_facility
    ON public.coffee_inventory_purchased(origin, facility_id);

-- 2. As-of-date lot-precise roasted cost for an origin ----------------------
-- lbs-weighted roasted $/lb from the FIFO ledger over roasts on/before the
-- date. Per-origin roasted lbs uses each roast's ACTUAL yield, so a blend
-- isolates this origin's contribution. NULL when no ledger data -> fall back.
CREATE OR REPLACE FUNCTION public.get_origin_roasted_cost_on_date(
    p_origin_id text, p_facility_id text, p_order_date date)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_cost numeric;
BEGIN
    SELECT SUM(rlc.lot_cost)
           / NULLIF(SUM(rlc.lbs_consumed
               * COALESCE(rl.measured_roasted_weight, rl.roasted_weight,
                          rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82))
               / NULLIF(rl.charge_weight_lbs, 0)), 0)
      INTO v_cost
      FROM public.roast_log_lot_consumption rlc
      JOIN public.roast_log rl  ON rl.roast_log_id       = rlc.roast_log_id
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin       = p_origin_id
       AND rl.facility_id   = p_facility_id
       AND rl.roast_date   <= p_order_date
       AND rlc.lot_cost IS NOT NULL;
    RETURN v_cost;  -- NULL => caller falls back to the group/shipment path
END;
$$;

-- 3. value_roast_lot_consumption (REPLACES Step 1): now also refreshes the
--    cached per-origin latest_roasted_cost for the origin(s) this roast used. --
CREATE OR REPLACE FUNCTION public.value_roast_lot_consumption(p_roast_log_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_green numeric;
    v_roasted_lbs numeric;
    v_facility    text;
    v_origin      text;
    v_new_cost    numeric;
BEGIN
    -- a. snapshot each ledger row's green + shipping cost from its lot
    UPDATE public.roast_log_lot_consumption rlc
    SET green_cost_lb    = cip.cost_lb,
        shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
    FROM public.coffee_inventory_purchased cip
    LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
    WHERE rlc.roast_log_id = p_roast_log_id
      AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (NULL when no ledger rows — see Step 1)
    SELECT SUM(lot_cost)
      INTO v_total_green
      FROM public.roast_log_lot_consumption
     WHERE roast_log_id = p_roast_log_id;

    SELECT COALESCE(rl.measured_roasted_weight,
                    rl.roasted_weight,
                    rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82)),
           rl.facility_id
      INTO v_roasted_lbs, v_facility
      FROM public.roast_log rl
     WHERE rl.roast_log_id = p_roast_log_id;

    UPDATE public.roast_log rl
    SET green_cost      = v_total_green,
        roasted_cost_lb = CASE WHEN v_total_green IS NOT NULL AND COALESCE(v_roasted_lbs,0) > 0
                               THEN v_total_green / v_roasted_lbs
                               ELSE NULL END
    WHERE rl.roast_log_id = p_roast_log_id;

    -- c. refresh the cached per-origin roasted cost for each origin this roast
    --    touched (once per origin — the only ledger scan in the roast path).
    FOR v_origin IN
        SELECT DISTINCT cip.origin
          FROM public.roast_log_lot_consumption rlc
          JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
         WHERE rlc.roast_log_id = p_roast_log_id
    LOOP
        v_new_cost := public.get_origin_roasted_cost_on_date(v_origin, v_facility, CURRENT_DATE);
        UPDATE public.coffee_inventory ci
        SET latest_roasted_cost = v_new_cost
        WHERE ci.origin_id   = v_origin
          AND ci.facility_id = v_facility
          AND ci.latest_roasted_cost IS DISTINCT FROM v_new_cost;  -- only when changed
    END LOOP;
END;
$$;

-- 4. Propagate a cached-cost change to live product COGS --------------------
-- Mirrors propagate_coffee_cost_change (which keys off latest_cost). Touches
-- only the products whose recipe uses the changed origin.
CREATE OR REPLACE FUNCTION public.propagate_roasted_cost_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.latest_roasted_cost IS NOT DISTINCT FROM OLD.latest_roasted_cost THEN
        RETURN NEW;
    END IF;
    UPDATE public.products p
    SET updated_at = NOW()
    FROM public.recipe_components rc
    WHERE p.recipe_id    = rc.recipe_id
      AND rc.facility_id = NEW.facility_id
      AND rc.coffee_item = NEW.origin_id
      AND p.facility_id  = NEW.facility_id
      AND p.is_active    = true;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_propagate_roasted_cost ON public.coffee_inventory;
CREATE TRIGGER trg_propagate_roasted_cost
    AFTER UPDATE OF latest_roasted_cost ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_roasted_cost_change();

-- 5. Live product COGS reads the CACHED column (no ledger scan) -------------
-- (Full re-paste of update_product_total_cogs; only the coffee-cost SELECT
--  changes — COALESCE(latest_roasted_cost, latest_cost). All other logic kept.)
CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
    v_total_cogs            numeric;
    v_gross_profit          numeric;
    v_cogs_pct              numeric;
    v_margin_pct            numeric;
    v_kind                  text;
    v_is_coffee             boolean;
BEGIN
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = false THEN
        RETURN NEW;
    END IF;

    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;

    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    SELECT pt.product_type INTO v_kind
    FROM public.product_type pt
    WHERE pt.product_type_id = NEW.product_type;
    v_is_coffee := (COALESCE(v_kind, 'Coffee') = 'Coffee');

    IF v_is_coffee THEN
        -- ▼ lot-precise cached roasted cost, fall back to group latest_cost ▼
        SELECT COALESCE(SUM(COALESCE(ci.latest_roasted_cost, ci.latest_cost) * rc.percentage), 0)
        INTO v_coffee_cost_total
        FROM public.recipe_components rc
        JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
        WHERE rc.recipe_id   = NEW.recipe_id
          AND ci.facility_id = NEW.facility_id;

        SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
        INTO v_consumable_cost_total
        FROM public.product_consumables pc
        JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
        WHERE pc.product_id  = NEW.product_id
          AND ci.facility_id = NEW.facility_id;

        v_total_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;
    ELSE
        IF NEW.source_consumable_id IS NOT NULL THEN
            SELECT ci.last_cost_unit INTO NEW.unit_cost
            FROM public.consumable_inventory ci
            WHERE ci.consumable_inventory_id = NEW.source_consumable_id
              AND ci.facility_id = NEW.facility_id;
        END IF;
        v_coffee_cost_total     := 0;
        v_consumable_cost_total := 0;
        v_total_cogs            := COALESCE(NEW.unit_cost, 0);
    END IF;

    v_gross_profit := COALESCE(NEW.price, 0) - v_total_cogs;
    v_cogs_pct     := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND(v_total_cogs / NEW.price * 100, 1) ELSE NULL END;
    v_margin_pct   := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND((1 - v_total_cogs / NEW.price) * 100, 1) ELSE NULL END;

    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = true THEN
        NEW.last_active_unit_cogs             := v_total_cogs;
        NEW.last_active_cogs_pct              := v_cogs_pct;
        NEW.last_active_gross_profit_per_unit := v_gross_profit;
        NEW.last_active_margin_pct            := v_margin_pct;
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    IF NEW.merge_into_id IS NOT NULL THEN
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    IF v_is_coffee THEN
        NEW.total_coffee_cost     := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
        NEW.total_consumable_cost := v_consumable_cost_total;
    ELSE
        NEW.total_coffee_cost     := NULL;
        NEW.total_consumable_cost := NULL;
    END IF;
    NEW.total_unit_cogs                   := v_total_cogs;
    NEW.gross_profit_per_unit             := v_gross_profit;
    NEW.cogs_pct                          := v_cogs_pct;
    NEW.margin_pct                        := v_margin_pct;
    NEW.last_active_unit_cogs             := v_total_cogs;
    NEW.last_active_cogs_pct              := v_cogs_pct;
    NEW.last_active_gross_profit_per_unit := v_gross_profit;
    NEW.last_active_margin_pct            := v_margin_pct;

    RETURN NEW;
END;
$function$;

-- 6. Historical / order COGS: prefer lot-precise, else the shipment path -----
-- (Date-precise, so it calls the function directly — used by the backfill +
--  the green-purchase re-propagation path, not on the hot per-roast path.)
CREATE OR REPLACE FUNCTION public.get_product_cogs_on_date(p_product_id text, p_facility_id text, p_order_date date)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_recipe_id       text;
    v_weight_lbs      numeric;
    v_coffee_cost     numeric := 0;
    v_consumable_cost numeric := 0;
    v_component_cost  numeric;
    v_rec             record;
    v_has_any_cost    boolean := false;
BEGIN
    SELECT recipe_id, weight_lbs
      INTO v_recipe_id, v_weight_lbs
      FROM public.products
     WHERE product_id = p_product_id
     LIMIT 1;

    IF v_recipe_id IS NOT NULL AND COALESCE(v_weight_lbs, 0) > 0 THEN
        FOR v_rec IN
            SELECT rc.coffee_item, rc.percentage
              FROM public.recipe_components rc
             WHERE rc.recipe_id   = v_recipe_id
               AND rc.facility_id = p_facility_id
        LOOP
            -- ▼ lot-precise first, fall back to the group/shipment cost ▼
            v_component_cost := COALESCE(
                public.get_origin_roasted_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date),
                public.get_coffee_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date)
            );
            IF v_component_cost IS NOT NULL THEN
                v_coffee_cost  := v_coffee_cost + (v_component_cost * COALESCE(v_rec.percentage, 0));
                v_has_any_cost := true;
            END IF;
        END LOOP;
    END IF;

    FOR v_rec IN
        SELECT pc.consumable_id, pc.quantity
          FROM public.product_consumables pc
         WHERE pc.product_id   = p_product_id
           AND pc.facility_id  = p_facility_id
    LOOP
        v_component_cost := public.get_consumable_cost_on_date(
            v_rec.consumable_id, p_facility_id, p_order_date
        );
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * COALESCE(v_rec.quantity, 1));
            v_has_any_cost    := true;
        END IF;
    END LOOP;

    IF NOT v_has_any_cost THEN
        RETURN NULL;
    END IF;

    RETURN (v_coffee_cost * COALESCE(v_weight_lbs, 0)) + v_consumable_cost;
END;
$function$;

COMMIT;
