-- An imported order is still a customer buying the thing.
--
-- MCR counted Monin Vanilla, and the app said it would last until February.
-- The shelf says weeks. daily_usage was 0.489 a day against a true 1.90.
--
-- update_consumable_metrics excluded every order carrying is_legacy_import
-- from the 92-day usage window. At MCR that flag is on 344 of the last 446
-- orders -- 77% -- because their QuickBooks history was imported and the
-- importer flags what it writes. So the forecast was built from the 23% of
-- demand that happened to be typed into STRATA by hand, and every run-out
-- date derived from it was roughly four times too far away.
--
-- The flag was meant to keep a one-time backfill of ancient invoices from
-- inventing usage. The 92-day window already does that job, and does it
-- without an opinion about where the order came from: the newest legacy
-- import at MCR is 2026-08-03, comfortably inside the window, and it is a
-- real case of syrup leaving the building. An order is an order.
--
-- WHAT THIS DELIBERATELY DOES NOT TOUCH. The same filter appears twice more,
-- in the blocks that compute consumption since the last physical count. Those
-- are unbounded -- an item never counted has a baseline of 2000-01-01 -- so
-- removing it there would deduct years of imported history from on-hand and
-- zero four items that are sitting on the shelf right now. That is a stock
-- decision, not a forecast one, and it is not made here.
--
-- 40 consumables change. Nothing is written except daily_usage, par, restock
-- and to_order, all of which are derived.

begin;

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

  -- Daily usage from 92-day order history. Imports COUNT: see the header.
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_92day
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  -- ▼▼ RESOLD 92-day usage (drives daily_usage → par/restock). Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_92_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := (v_92day + v_92_resold) / 92.0;

  RETURN NEW;
END;
$function$;

-- Recompute. The trigger is BEFORE UPDATE, so touching updated_at is enough.
-- lock_timeout, not a raised statement_timeout: a derived figure must never
-- be the reason somebody cannot work. 350 active rows.
set local lock_timeout = '2s';
update public.consumable_inventory set updated_at = now();

do $$
declare
  v_src  text;
  v_hits int;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.update_consumable_metrics()'::regprocedure;

  -- Two filters must survive (the since-last-count blocks) and no more.
  v_hits := (length(v_src) - length(replace(v_src, 'is_legacy_import', ''))) / length('is_legacy_import');
  if v_hits <> 2 then
    raise exception 'expected 2 is_legacy_import filters (the stock blocks), found %', v_hits;
  end if;

  -- And neither survivor may sit in a 92-day window.
  if v_src ~ 'CURRENT_DATE - interval ''92 days''(.|\n){0,200}?is_legacy_import' then
    raise exception 'a 92-day usage block still filters imports out';
  end if;
end $$;

commit;
