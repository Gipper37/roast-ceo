-- On hand has to mean on hand.
--
-- 20260923000001 made imported orders count toward the 92-day usage RATE and
-- deliberately left alone the two blocks that compute consumption since the
-- last physical count, because those are unbounded and the blast radius had
-- not been measured. It has been measured now, and the owner asked for it.
--
-- The worry was that an item never counted has a baseline of 2000-01-01, so
-- dropping the filter would deduct years of imported history from on hand. On
-- production that is not what happens, because almost everything HAS been
-- counted: MCR counted on 2026-04-30 and their newest legacy import is
-- 2026-08-03. Every order this newly deducts is a real sale that happened
-- AFTER the count, which is exactly what a count-to-now window is for. On
-- hand was too high, and is not about to become too low.
--
-- BLAST RADIUS, measured on prod before writing this:
--   20 active consumables drop, 4,484 units in total
--   4 reach zero: 4 X 6 Direct Thermal (5lb) 3,529 -> 0, 2oz Gold Bag 18 -> 0,
--     Rishi Matcha 2.2lb 3 -> 0, Monin 64oz Sauce Pump 0 -> 0
--   the other 16 move by between 1 and 33 units
-- The big one is a label roll consumed per bag, so a four-figure move is the
-- expected shape rather than a surprise.
--
-- A count settles quantity. Anything that now reads low is fixed the way it
-- always is: count it, which re-anchors the baseline to that day and discards
-- everything before it. Nothing about traceability changes.
--
-- update_consumable_metrics now has no opinion at all about where an order
-- came from, which is the point: an order is an order.

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

  -- Units consumed since baseline. Imports count: see the header.
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_used
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  -- ▼▼ RESOLD since baseline: a product that IS this consumable. Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
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

-- Recompute. BEFORE UPDATE trigger, so touching updated_at is enough.
--
-- Batched, and not for elegance. Each row's trigger runs four order-scanning
-- queries plus calculate_consumable_par and calculate_consumable_restock_level,
-- so one UPDATE across every row is a single statement whose cost scales with
-- the tenant's order history -- precisely the shape that hit prod's 120s
-- statement timeout during the September release and took 62 later migrations
-- down with it. Chunking means each statement gets its own budget.
--
-- lock_timeout rather than a raised statement_timeout, for the other half of
-- that lesson: a derived figure must never be the reason somebody cannot work.
-- If a chunk cannot get its locks it yields, and the whole migration rolls
-- back cleanly rather than holding rows while a roaster is trying to trade.
set local lock_timeout = '2s';

do $$
declare
  v_ids   text[];
  v_done  int := 0;
begin
  loop
    select array_agg(consumable_inventory_id)
      into v_ids
    from (
      select consumable_inventory_id
      from public.consumable_inventory
      where updated_at < now()
      order by consumable_inventory_id
      limit 50
    ) c;

    exit when v_ids is null;

    update public.consumable_inventory
       set updated_at = now()
     where consumable_inventory_id = any(v_ids);

    v_done := v_done + array_length(v_ids, 1);
  end loop;

  raise notice 'recomputed % consumable rows', v_done;
end $$;

do $$
declare
  v_src text;
  v_blocks int;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.update_consumable_metrics()'::regprocedure;

  if position('is_legacy_import' in v_src) > 0 then
    raise exception 'update_consumable_metrics still filters on is_legacy_import';
  end if;

  -- Four order-scanning blocks must survive. A stray edit that dropped one
  -- would silently stop counting half of consumption, which is the failure
  -- mode this whole pair of migrations exists to fix.
  v_blocks := (length(v_src) - length(replace(v_src, 'o.facility_id = NEW.facility_id', '')))
              / length('o.facility_id = NEW.facility_id');
  if v_blocks <> 4 then
    raise exception 'expected 4 order-scanning blocks, found %', v_blocks;
  end if;
end $$;

commit;
