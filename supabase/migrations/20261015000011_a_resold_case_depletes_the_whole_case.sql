-- Selling a case of a resold item took ONE unit off the shelf.
--
-- A resold consumable is stock the roaster buys and sells on: the
-- `consumable_inventory` row is the stock, and `products.source_consumable_id`
-- points a variant back at it. When one sells, that many units leave.
--
-- Stock, par, restock level and daily usage all compute a "resold usage" term,
-- and all five of them summed `od.quantity` flat. An order line for a CASE is a
-- count of CASES, so selling one case of 12 jars took 1 jar off the shelf.
--
-- The money side was already right, which is what made it invisible: the case
-- price is the case price, so COGS charged 12 x $15 and nobody noticed stock
-- had moved by one. Eleven jars that left the building stay on the shelf, every
-- sale, forever. After ten cases the count reads 110 jars high, `to_order`
-- reads 0, and the reorder never fires -- the roaster runs out while the system
-- says they are fine.
--
-- ── Why this is unconditional, with no per_case question ──────────────────
--
-- `product_consumables_effective` asks `per_case` because a BOM line genuinely
-- can be either: a box is used once per case, a label once per bag. A RESOLD
-- line is not ambiguous. The variant IS the consumable, so a case of twelve is
-- twelve of them leaving, always. There is nothing to configure and nothing to
-- get wrong.
--
-- The BOM half of the same functions was already correct: it reads
-- `product_consumables_effective`, which does the scaling. Only the resold half
-- was flat, in all five places.
--
-- 🔴 THE BODIES BELOW ARE THE LIVE DEFINITIONS, dumped with pg_get_functiondef
-- and patched by replacing `SUM(od.quantity)` and adding the one join each
-- block needs. Never retyped: CREATE OR REPLACE rewrites the whole function,
-- and these four carry a lot of hard-won exclusions (canceled orders, legacy
-- imports, the facility filter, the count anchor) that a retype would lose.
--
-- LEFT JOIN, not JOIN: a resold product's `size` is NULL on every row today,
-- and an inner join would have silently dropped every resold line instead of
-- scaling it -- turning an undercount into a total blind spot.

begin;

CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
    v_resold_usage        NUMERIC;
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

-- BOM usage (this consumable is an ingredient of a made good).
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

-- ▼▼ RESOLD usage: a product that IS this consumable (source_consumable_id)
    --    depletes 1 unit per unit sold. Same exclusions as BOM usage. ▼▼
    SELECT COALESCE(SUM(od.quantity * COALESCE(s.units_per_case, 1)), 0)
    INTO v_resold_usage
    FROM order_details od
    JOIN orders o   ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
  LEFT JOIN size s ON s.size_id = p.size
    WHERE p.source_consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount - v_resold_usage));
END;
$function$;

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
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

-- ▼▼ RESOLD 92-day usage: a product that IS this consumable (source_consumable_id)
  --    consumes 1 unit per unit sold. Same exclusions as the BOM sum. ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity * COALESCE(s.units_per_case, 1)), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  LEFT JOIN size s ON s.size_id = p.size
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
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

-- ▼▼ RESOLD 92-day usage (mirrors calculate_consumable_par). ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity * COALESCE(s.units_per_case, 1)), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  LEFT JOIN size s ON s.size_id = p.size
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
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

-- ▼▼ RESOLD since baseline: a product that IS this consumable. Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity * COALESCE(s.units_per_case, 1)), 0) INTO v_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  LEFT JOIN size s ON s.size_id = p.size
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
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

-- ▼▼ RESOLD 92-day usage (drives daily_usage → par/restock). Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity * COALESCE(s.units_per_case, 1)), 0) INTO v_92_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  LEFT JOIN size s ON s.size_id = p.size
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

NEW.daily_usage := (v_92day + v_92_resold) / 92.0;

RETURN NEW;
END;
$function$;

do $verify$
declare v_def text; v_fn text; v_n int; v_bad int;
begin
  -- 1. All five resold sums carry the pack count, and each block got its join.
  foreach v_fn in array array['calculate_current_stock_consumables','calculate_consumable_par',
                              'calculate_consumable_restock_level','update_consumable_metrics'] loop
    select pg_get_functiondef(oid) into v_def from pg_proc where proname = v_fn;
    if v_def is null then raise exception '% is gone', v_fn; end if;

    -- No flat resold sum may remain.
    if v_def like '%SUM(od.quantity)%' then
      raise exception '% still has a resold sum that ignores the pack count', v_fn;
    end if;

    v_n := (length(v_def) - length(replace(v_def, 'COALESCE(s.units_per_case, 1)', ''))) / length('COALESCE(s.units_per_case, 1)');
    if v_n = 0 then
      raise exception '% does not scale its resold usage at all', v_fn;
    end if;
    -- Every scaled sum needs the join that defines `s`, or the function would
    -- not even compile -- but assert it, because a half-applied patch is the
    -- failure mode of a scripted edit.
    if (length(v_def) - length(replace(v_def, 'LEFT JOIN size s', ''))) / length('LEFT JOIN size s') <> v_n then
      raise exception '% has % scaled sum(s) and a different number of size joins', v_fn, v_n;
    end if;

    -- 🔴 And the exclusions survived. These are the lines that keep a canceled
    -- order and another facility's trade out of the number.
    if v_def not like '%Canceled%' then
      raise exception '% lost its canceled-order exclusion', v_fn;
    end if;
    -- The legacy-import exclusion is NOT universal, and asserting it on all
    -- four is how the first run of this migration failed: update_consumable_metrics
    -- deliberately COUNTS imports -- its own comments say "Imports count." --
    -- because it computes usage since a baseline rather than stock since a
    -- count. Three exclude them; this one must not be made to.
    if v_fn <> 'update_consumable_metrics' and v_def not like '%is_legacy_import%' then
      raise exception '% lost its legacy-import exclusion', v_fn;
    end if;
    if v_fn = 'update_consumable_metrics' and v_def like '%is_legacy_import%' then
      raise exception 'update_consumable_metrics gained a legacy-import exclusion it is not supposed to have';
    end if;
  end loop;

  -- 2. The scaling is a no-op for every row that exists today: no resold
  --    product carries a case size yet, so nothing moves. Stated as an
  --    assertion rather than a hope, because if one DID exist this migration
  --    would change its stock figure and that should be a deliberate act.
  select count(*) into v_bad
    from public.products p
    join public.size s on s.size_id = p.size
   where p.source_consumable_id is not null
     and coalesce(s.units_per_case, 1) > 1;
  if v_bad > 0 then
    raise notice '🔴 % resold variant(s) ARE sold by the case; their stock figures change with this migration, which is the point', v_bad;
  else
    raise notice 'no resold variant is sold by the case yet; this changes no number today and closes the hole before it opens';
  end if;
end $verify$;

commit;
