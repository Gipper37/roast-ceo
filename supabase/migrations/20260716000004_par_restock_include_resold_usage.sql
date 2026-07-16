-- Unification P2 (cont.): par + restock-level for resold (distribution) consumables.
--
-- calculate_consumable_par and calculate_consumable_restock_level each compute
-- their OWN 92-day usage from the BOM (product_consumables) and RETURN 0 when it's
-- zero. A resold consumable has no BOM, so both return 0 -> par=0/restock=0/to_order=0
-- no matter how fast it actually sells. That makes the restock (lead-time) category
-- decorative for resold items: they never generate a reorder signal.
--
-- These are the last two of the resold-consumable function family still blind to
-- source_consumable_id (the other four -- calculate_current_stock_consumables,
-- get_product_cogs_on_date, update_consumable_stock, update_consumable_metrics --
-- were patched in 20260716000002/03). Add the same resold branch: 1 consumable unit
-- per unit of the linked product sold, same exclusions as the BOM sum.
--
-- Each function is reproduced verbatim from the live prod definition; the ONLY
-- addition is the clearly-marked resold branch folded into v_92day_usage.

-- ── 1. Par ───────────────────────────────────────────────────────────────────
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

  -- ▼▼ RESOLD 92-day usage: a product that IS this consumable (source_consumable_id)
  --    consumes 1 unit per unit sold. Same exclusions as the BOM sum. ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = p_consumable_id
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

-- ── 2. Restock level ─────────────────────────────────────────────────────────
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

  -- ▼▼ RESOLD 92-day usage (mirrors calculate_consumable_par). ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = p_consumable_id
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

NOTIFY pgrst, 'reload schema';
