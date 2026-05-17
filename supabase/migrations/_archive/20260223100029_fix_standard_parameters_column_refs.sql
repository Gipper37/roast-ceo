-- Fix incorrect column references to standard_parameters in cost functions
--
-- standard_parameters uses:
--   parameters_id  (PK, not parameter_id)
--   amount         (numeric value, not value_number)
--
-- company_parameters uses value_number — both broken functions mistakenly
-- used company_parameters column names when querying standard_parameters.
-- The bug is silent when company_parameters has the value, but fails when
-- the fallback path is hit (e.g. new facility with no retention rate set).

-- ─── calculate_roasted_cost ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  retention_factor NUMERIC;
BEGIN
  SELECT value_number
    INTO retention_factor
  FROM company_parameters
  WHERE parameter_id = '1de271df'
    AND facility_id = p_facility_id
  LIMIT 1;

  IF retention_factor IS NULL OR retention_factor = 0 THEN
    SELECT sp.amount                      -- FIXED: was sp.value_number
      INTO retention_factor
    FROM standard_parameters sp
    WHERE sp.parameters_id = '1de271df'  -- FIXED: was sp.parameter_id
    LIMIT 1;
  END IF;

  IF retention_factor IS NULL OR retention_factor = 0 THEN
    retention_factor := 0.82;
  END IF;

  RETURN ROUND((green_cost / retention_factor), 2);
END;
$$;

-- ─── recalculate_inventory_cost ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
BEGIN
    SELECT value_number
      INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
      SELECT sp.amount                      -- FIXED: was sp.value_number
        INTO v_retention
      FROM standard_parameters sp
      WHERE sp.parameters_id = '1de271df'  -- FIXED: was sp.parameter_id
      LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
      v_retention := 0.82;
    END IF;

    SELECT cp.cost_lb
      INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND cp.cost_lb > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    IF v_retention > 0 THEN
      v_final_landed_cost := (v_latest_green_cost + v_latest_shipping_cost) / v_retention;
    ELSE
      v_final_landed_cost := 0;
    END IF;

    UPDATE coffee_inventory
       SET last_cost_lb        = v_latest_green_cost,
           last_shipping_cost  = v_latest_shipping_cost,
           latest_cost         = v_final_landed_cost
     WHERE origin_id   = p_origin_id
       AND facility_id = p_facility_id;
END;
$$;
