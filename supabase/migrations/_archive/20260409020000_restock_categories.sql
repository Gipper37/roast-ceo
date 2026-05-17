-- Migration: Restock Categories
-- Replace global par/trigger multipliers with per-category settings.
-- Each inventory item (coffee + consumable) gets assigned a category
-- that defines target_months and reorder_months.
-- Global buffer (5131610b) remains as universal safety margin.

BEGIN;

-- ══════════════════════════════════════════════════════════════════════
-- 1. Create restock_category table
-- ══════════════════════════════════════════════════════════════════════

CREATE TABLE restock_category (
  restock_category_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  target_months numeric NOT NULL DEFAULT 3,
  reorder_months numeric NOT NULL DEFAULT 1.5,
  company_id text REFERENCES companies(company_id) ON DELETE CASCADE,
  facility_id text REFERENCES facilities(facility_id) ON DELETE CASCADE,
  is_default boolean DEFAULT false,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_restock_category_facility ON restock_category(facility_id);

-- Auto-stamp updated_at
CREATE OR REPLACE FUNCTION trg_set_restock_category_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
CREATE TRIGGER trg_restock_category_updated_at
  BEFORE UPDATE ON restock_category
  FOR EACH ROW EXECUTE FUNCTION trg_set_restock_category_updated_at();

-- ══════════════════════════════════════════════════════════════════════
-- 2. Seed default categories for every existing facility
-- ══════════════════════════════════════════════════════════════════════

INSERT INTO restock_category (name, description, target_months, reorder_months, company_id, facility_id, is_default, sort_order)
SELECT
  cat.name, cat.description, cat.target_months, cat.reorder_months,
  f.company_id, f.facility_id, cat.is_default, cat.sort_order
FROM facilities f
CROSS JOIN (VALUES
  ('Quick Restock',  'Items available locally within 1-2 weeks',       1,   0.5,  false, 1),
  ('Standard',       'Typical supplies with standard lead times',      3,   1.5,  true,  2),
  ('Extended Lead',  'Imports, custom prints, or specialty items',     6,   3,    false, 3)
) AS cat(name, description, target_months, reorder_months, is_default, sort_order);

-- ══════════════════════════════════════════════════════════════════════
-- 3. Add restock_category_id to inventory tables
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE consumable_inventory
  ADD COLUMN restock_category_id uuid REFERENCES restock_category(restock_category_id);

ALTER TABLE coffee_inventory
  ADD COLUMN restock_category_id uuid REFERENCES restock_category(restock_category_id);

-- Backfill: assign all existing items to their facility's "Standard" (default) category
UPDATE consumable_inventory ci
SET restock_category_id = (
  SELECT rc.restock_category_id FROM restock_category rc
  WHERE rc.facility_id = ci.facility_id AND rc.is_default = true
  LIMIT 1
)
WHERE ci.restock_category_id IS NULL;

UPDATE coffee_inventory ci
SET restock_category_id = (
  SELECT rc.restock_category_id FROM restock_category rc
  WHERE rc.facility_id = ci.facility_id AND rc.is_default = true
  LIMIT 1
)
WHERE ci.restock_category_id IS NULL;

-- ══════════════════════════════════════════════════════════════════════
-- 4. Rewrite consumable par/restock functions
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_consumable_par(
  p_consumable_id text,
  p_facility_id text
) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
  v_92day_usage    numeric;
  v_monthly_usage  numeric;
  v_target_months  numeric;
  v_buffer         numeric;
BEGIN
  -- 92-day usage from order history
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  -- Per-category target months (fallback to 3 if no category assigned)
  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  -- Global buffer
  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  RETURN CEIL(v_monthly_usage * v_target_months * v_buffer);
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_consumable_restock_level(
  p_consumable_id text,
  p_facility_id text
) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
  v_92day_usage       numeric;
  v_monthly_usage     numeric;
  v_reorder_months    numeric;
  v_buffer            numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  -- Per-category reorder months (fallback to 1.5)
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

  RETURN CEIL(v_monthly_usage * v_reorder_months * v_buffer);
END;
$$;

-- ══════════════════════════════════════════════════════════════════════
-- 5. Rewrite coffee par/restock functions
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
  v_facility_id   text;
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_monthly_usage numeric;
  v_target_months numeric;
  v_buffer        numeric;
  v_bag_size      numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  -- Direct roast usage (last 92 days)
  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
    AND rl.facility_id = v_facility_id;

  -- Blend usage (last 92 days)
  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  -- Per-category target months (fallback to 3)
  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  -- Global buffer
  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN FLOOR((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
  v_facility_id      text;
  v_usage_direct     numeric;
  v_usage_blend      numeric;
  v_monthly_usage    numeric;
  v_reorder_months   numeric;
  v_buffer           numeric;
  v_bag_size         numeric;
  v_current_date     date;
  v_timezone         text;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  -- Per-category reorder months (fallback to 1.5)
  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;

  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;

COMMIT;
