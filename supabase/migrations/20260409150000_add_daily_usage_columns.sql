-- Add daily_usage column to coffee + consumable inventory
-- Calculated from 92-day usage / 92, stored alongside par/restock

ALTER TABLE coffee_inventory ADD COLUMN IF NOT EXISTS daily_usage_lbs numeric DEFAULT 0;
ALTER TABLE consumable_inventory ADD COLUMN IF NOT EXISTS daily_usage numeric DEFAULT 0;

-- Update calculate_par to also set daily_usage_lbs
-- (The BEFORE trigger on coffee sets NEW.par — we piggyback on the nudge trigger)
CREATE OR REPLACE FUNCTION trg_recalc_coffee_on_nudge()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_total_usage   numeric;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  -- 92-day direct usage
  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = NEW.origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
    AND rl.facility_id = NEW.facility_id;

  -- 92-day blend usage
  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = NEW.origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = NEW.facility_id;

  v_total_usage := v_usage_direct + v_usage_blend;
  NEW.daily_usage_lbs := v_total_usage / 92.0;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$$;

-- Update consumable metrics to also set daily_usage
CREATE OR REPLACE FUNCTION public.update_consumable_metrics() RETURNS trigger
LANGUAGE plpgsql AS $$
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

  -- Units received since baseline
  SELECT COALESCE(SUM(cip.amount), 0) INTO v_received
  FROM consumable_inventory_purchased cip
  JOIN shipment_received sr ON cip.shipment_id = sr.shipment_id
  WHERE cip.consumable_inventory_item = NEW.consumable_inventory_id
    AND sr.date_received >= v_baseline
    AND (sr.voided IS NULL OR sr.voided = false);

  -- Units consumed since baseline (from order details × product BOM)
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_used
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  v_in_stock := GREATEST(0, COALESCE(NEW.inventory_count, 0) + v_received - v_used);
  NEW.in_stock := v_in_stock;

  v_par := calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id);
  v_restock := calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id);
  NEW.par := v_par;
  NEW.restock_level := v_restock;
  NEW.to_order := CASE WHEN v_in_stock <= v_restock THEN GREATEST(0, v_par - v_in_stock) ELSE 0 END;

  -- Daily usage from 92-day order history
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_92day
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := v_92day / 92.0;

  RETURN NEW;
END;
$$;

-- Force recalculate all inventory to populate daily_usage
UPDATE coffee_inventory SET updated_at = NOW();
UPDATE consumable_inventory SET updated_at = NOW();
