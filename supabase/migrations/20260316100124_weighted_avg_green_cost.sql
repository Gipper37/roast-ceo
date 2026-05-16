-- Migration 00124: Weighted average green cost across multiple coffees in the same shipment
--
-- Previously, recalculate_inventory_cost() used LIMIT 1 to grab the single most recently
-- created purchase row's cost_lb as the "latest green cost." When two coffees of the same
-- origin category (e.g., two Decafs) land in the same shipment with different prices, the
-- one with the later created_at timestamp won — the other price was silently discarded.
--
-- Fix: identify the most recent shipment for the origin, then compute a lbs-weighted average
-- cost_lb across ALL purchases in that shipment for the origin. This gives an accurate blended
-- green cost when multiple coffees of the same origin category arrive together.
--
-- Shipping cost stays as LIMIT 1 — shipping_cost_unit lives on the shipment row itself,
-- so every coffee in the same shipment shares the same value. No change needed there.

CREATE OR REPLACE FUNCTION public.recalculate_inventory_cost(
    p_origin_id  text,
    p_facility_id text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
    v_fallback_cost         numeric;
BEGIN
    -- 1. Resolve retention factor (3-tier: company override → system default → 0.82)
    SELECT value_number
      INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
      SELECT sp.amount
        INTO v_retention
      FROM standard_parameters sp
      WHERE sp.parameters_id = '1de271df'
      LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
      v_retention := 0.82;
    END IF;

    -- 2. Weighted average green cost across all purchases in the most recent shipment.
    --    Step A: find the shipment_id of the most recent delivery for this origin.
    --    Step B: average cost_lb weighted by lbs (amount) across all purchases in that shipment.
    --    This correctly handles multiple coffees of the same origin category (e.g., two Decafs)
    --    arriving in the same order at different prices.
    WITH latest_shipment AS (
        SELECT cp.shipment_id
        FROM coffee_inventory_purchased cp
        LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
        WHERE cp.origin        = p_origin_id
          AND cp.cost_lb       > 0
          AND cp.facility_id   = p_facility_id
        ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
        LIMIT 1
    )
    SELECT
        SUM(cp.cost_lb * COALESCE(cp.amount, 0))
        / NULLIF(SUM(COALESCE(cp.amount, 0)), 0)
    INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    JOIN latest_shipment ls
      ON (cp.shipment_id = ls.shipment_id)
      OR (cp.shipment_id IS NULL AND ls.shipment_id IS NULL)
    WHERE cp.origin      = p_origin_id
      AND cp.cost_lb     > 0
      AND cp.facility_id = p_facility_id;

    -- 3. Find most recent shipment shipping cost (per-shipment value — LIMIT 1 is correct here)
    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin      = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    -- 4. If no shipment green cost found, try fallback_cost before defaulting to 0
    IF v_latest_green_cost = 0 THEN
        SELECT ci.fallback_cost INTO v_fallback_cost
        FROM public.coffee_inventory ci
        WHERE ci.origin_id   = p_origin_id
          AND ci.facility_id = p_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            -- fallback_cost is already roasted $/lb — use directly.
            -- Set last_cost_lb = NULL to signal "fallback only, no real shipment"
            -- (data_quality_issues uses this to show "Fallback cost only" advisory).
            UPDATE public.coffee_inventory
               SET last_cost_lb       = NULL,
                   last_shipping_cost = NULL,
                   latest_cost        = v_fallback_cost
             WHERE origin_id   = p_origin_id
               AND facility_id = p_facility_id;
            RETURN;
        END IF;
    END IF;

    -- 5. Normal shipment path
    IF v_retention > 0 THEN
      v_final_landed_cost := (v_latest_green_cost + v_latest_shipping_cost) / v_retention;
    ELSE
      v_final_landed_cost := 0;
    END IF;

    UPDATE public.coffee_inventory
       SET last_cost_lb        = v_latest_green_cost,
           last_shipping_cost  = v_latest_shipping_cost,
           latest_cost         = v_final_landed_cost
     WHERE origin_id   = p_origin_id
       AND facility_id = p_facility_id;
END;
$$;
