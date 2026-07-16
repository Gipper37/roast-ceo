-- Unification P2 (cont.): update_consumable_metrics recomputes in_stock + daily
-- usage INLINE (BOM-only), so it overrode the resold-aware stock on any consumable
-- edit and left par/restock/daily_usage blind to resale velocity. Add the resold
-- (source_consumable_id) usage to both the since-baseline and 92-day sums, matching
-- the fix already made to calculate_current_stock_consumables/update_consumable_stock.
-- Reproduced verbatim from live; ONLY the two resold additions are new.

CREATE OR REPLACE FUNCTION public.update_consumable_metrics()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
DECLARE
  v_baseline   DATE;
  v_received   NUMERIC;
  v_used       NUMERIC;
  v_resold     NUMERIC;
  v_in_stock   NUMERIC;
  v_par        NUMERIC;
  v_restock    NUMERIC;
  v_92day      NUMERIC;
  v_92_resold  NUMERIC;
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

  -- ▼▼ RESOLD usage since baseline: a product that IS this consumable. ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = NEW.facility_id;

  v_in_stock := GREATEST(0, COALESCE(NEW.inventory_count, 0) + v_received - v_used - v_resold);
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

  -- ▼▼ RESOLD 92-day usage (drives daily_usage → par/restock for resold items). ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_92_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := (v_92day + v_92_resold) / 92.0;

  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
