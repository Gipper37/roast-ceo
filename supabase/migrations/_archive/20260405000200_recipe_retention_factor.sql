-- Migration 00200: Per-recipe retention factor
-- Adds retention_factor to roast_recipes.
-- Priority: recipe → facility param → standard param → 0.82
-- Updates calculate_roasted_cost, recalculate_inventory_cost,
-- and roast_detail_by_blend view to use recipe-level retention when set.

-- ── 1. Column ─────────────────────────────────────────────────────────────
ALTER TABLE roast_recipes ADD COLUMN IF NOT EXISTS retention_factor numeric;

-- ── 2. Helper: 4-tier retention lookup ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_retention_factor(
  p_facility_id text,
  p_recipe_id   text DEFAULT NULL
) RETURNS numeric
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_retention numeric;
BEGIN
  -- Tier 1: recipe-level override
  IF p_recipe_id IS NOT NULL THEN
    SELECT retention_factor INTO v_retention
    FROM roast_recipes
    WHERE recipe_id = p_recipe_id
      AND retention_factor IS NOT NULL
      AND retention_factor > 0
    LIMIT 1;
  END IF;

  -- Tier 2: facility/company parameter
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT value_number INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;
  END IF;

  -- Tier 3: standard parameters
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT amount INTO v_retention
    FROM standard_parameters
    WHERE parameters_id = '1de271df'
    LIMIT 1;
  END IF;

  -- Tier 4: hardcoded default
  IF v_retention IS NULL OR v_retention = 0 THEN
    v_retention := 0.82;
  END IF;

  RETURN v_retention;
END;
$$;

-- ── 3. calculate_roasted_cost — add optional recipe_id ───────────────────
CREATE OR REPLACE FUNCTION public.calculate_roasted_cost(
  green_cost    numeric,
  p_facility_id text,
  p_recipe_id   text DEFAULT NULL
) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
  v_retention numeric;
BEGIN
  v_retention := public.get_retention_factor(p_facility_id, p_recipe_id);
  RETURN ROUND((green_cost / v_retention), 2);
END;
$$;

-- ── 4. recalculate_inventory_cost — use helper (facility-level; per-origin, no recipe ctx) ──
CREATE OR REPLACE FUNCTION public.recalculate_inventory_cost(
  p_origin_id   text,
  p_facility_id text
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
    v_fallback_cost         numeric;
BEGIN
    -- 1. Resolve retention factor (facility-level via helper)
    v_retention := public.get_retention_factor(p_facility_id);

    -- 2. Weighted average green cost from most recent non-voided shipment
    WITH latest_shipment AS (
        SELECT cp.shipment_id
        FROM coffee_inventory_purchased cp
        LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
        WHERE cp.origin        = p_origin_id
          AND cp.cost_lb       > 0
          AND cp.facility_id   = p_facility_id
          AND COALESCE(sr.voided, false) = false
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

    -- 3. Most recent non-voided shipment shipping cost
    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin      = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
      AND COALESCE(sr.voided, false) = false
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    -- 4. Fallback cost if no shipment green cost found
    IF v_latest_green_cost = 0 THEN
        SELECT ci.fallback_cost INTO v_fallback_cost
        FROM public.coffee_inventory ci
        WHERE ci.origin_id   = p_origin_id
          AND ci.facility_id = p_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
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

-- ── 5. roast_detail_by_blend — use recipe retention_factor when set ───────
CREATE OR REPLACE VIEW public.roast_detail_by_blend AS
WITH facility_params AS (
    SELECT f.facility_id,
           f.company_id,
           COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
           COALESCE((
               SELECT (cp.value_number)::integer
               FROM company_parameters cp
               WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = f.facility_id
               LIMIT 1
           ), 4) AS roast_reset_day,
           COALESCE((
               SELECT cp.value_number
               FROM company_parameters cp
               WHERE cp.parameter_id = '761fd894' AND cp.facility_id = f.facility_id
               LIMIT 1
           ), 25) AS charge_weight,
           COALESCE((
               SELECT cp.value_number
               FROM company_parameters cp
               WHERE cp.parameter_id = '1de271df' AND cp.facility_id = f.facility_id
               LIMIT 1
           ), (
               SELECT sp.amount
               FROM standard_parameters sp
               WHERE sp.parameters_id = '1de271df'
               LIMIT 1
           ), 0.82) AS retention_rate
    FROM facilities f
),
calc AS (
    SELECT fp.facility_id,
           fp.company_id,
           fp.timezone,
           fp.charge_weight,
           fp.retention_rate,
           ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
            - (((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
                 - fp.roast_reset_day) + 7) % 7)) AS roast_week_start
    FROM facility_params fp
),
recipe_facility AS (
    SELECT rr.recipe_id,
           rr.retention_factor,          -- carry recipe-level retention
           f.facility_id,
           f.company_id
    FROM roast_recipes rr
    JOIN facilities f ON f.company_id = rr.company_id
                     AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
),
per_recipe AS (
    SELECT rf.recipe_id,
           rf.facility_id,
           rf.company_id,
           COALESCE(stock.in_stock_roasted, 0)          AS in_stock_roasted,
           COALESCE(ordered.total_ordered, 0)           AS total_ordered,
           COALESCE(roasted.total_roasted, 0)           AS total_roasted,
           -- recipe retention overrides facility retention when set
           COALESCE(NULLIF(rf.retention_factor, 0), c.retention_rate) AS retention_rate,
           COALESCE((
               SELECT AVG(rl.charge_weight_lbs)
               FROM (
                   SELECT roast_log.charge_weight_lbs
                   FROM roast_log
                   WHERE roast_log.recipe_id    = rf.recipe_id
                     AND roast_log.facility_id  = rf.facility_id
                     AND roast_log.charge_weight_lbs > 0
                   ORDER BY roast_log.roast_date DESC
                   LIMIT 5
               ) rl
           ), c.charge_weight, 25) AS effective_charge_weight
    FROM recipe_facility rf
    JOIN calc c ON c.facility_id = rf.facility_id
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(rsl.lbs_in_stock), 0) AS in_stock_roasted
        FROM roast_stock_log rsl
        WHERE rsl.blend_id    = rf.recipe_id
          AND rsl.facility_id = rf.facility_id
          AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
    ) stock ON true
    LEFT JOIN LATERAL (
        SELECT SUM(od.roasted_weight) AS total_ordered
        FROM order_details od
        JOIN orders  o ON od.order_id  = o.order_id
        JOIN products p ON od.product_id = p.product_id
        WHERE p.recipe_id    = rf.recipe_id
          AND o.order_status = 'Open'
          AND o.facility_id  = rf.facility_id
    ) ordered ON true
    LEFT JOIN LATERAL (
        SELECT SUM(rl.roasted_weight) AS total_roasted
        FROM roast_log rl
        WHERE rl.recipe_id   = rf.recipe_id
          AND rl."charged?"  = true
          AND rl.roast_date >= c.roast_week_start
          AND rl.facility_id = rf.facility_id
    ) roasted ON true
)
SELECT (recipe_id || '-' || facility_id)                                  AS roast_blend_id,
       recipe_id,
       facility_id,
       company_id,
       in_stock_roasted,
       total_ordered,
       total_roasted,
       GREATEST(0::double precision,
           total_ordered - in_stock_roasted::double precision - total_roasted::double precision
       )                                                                   AS roasted_left,
       (GREATEST(0::double precision,
           total_ordered - in_stock_roasted::double precision - total_roasted::double precision
        ) / NULLIF(retention_rate, 0)::double precision
        / NULLIF(effective_charge_weight, 0)::double precision
       )                                                                   AS roasts_remaining
FROM per_recipe;
