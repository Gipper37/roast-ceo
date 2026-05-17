-- Fix: remove the AFTER triggers (they cause cascading updates)
-- Instead, use BEFORE triggers that set NEW directly

BEGIN;

-- Remove AFTER triggers
DROP TRIGGER IF EXISTS trg_consumable_restock_category_change ON consumable_inventory;
DROP TRIGGER IF EXISTS trg_coffee_restock_category_change ON coffee_inventory;

-- For consumables: add restock_category_id back to the BEFORE trigger
DROP TRIGGER IF EXISTS trg_update_consumable_ordering ON consumable_inventory;
CREATE TRIGGER trg_update_consumable_ordering
  BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id, last_inventory_date, inventory_count, par, restock_level, restock_category_id
  ON consumable_inventory
  FOR EACH ROW EXECUTE FUNCTION update_consumable_metrics();

-- For coffee: create a BEFORE trigger that uses a workaround
-- First temporarily write the new category, then call calculate functions
CREATE OR REPLACE FUNCTION trg_recalc_coffee_on_category_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_par numeric;
  v_restock numeric;
BEGIN
  IF OLD.restock_category_id IS DISTINCT FROM NEW.restock_category_id THEN
    -- Temporarily set the category so the functions read it
    -- (the functions query coffee_inventory for the category)
    -- We do a raw update that skips this trigger via pg_trigger_depth
    IF pg_trigger_depth() > 1 THEN
      RETURN NEW;
    END IF;

    -- Write category first so functions can read it
    PERFORM set_config('app.skip_coffee_recalc', 'true', true);

    -- Calculate with a direct approach: modify NEW inline
    -- Since we can't easily make the functions read NEW, we'll
    -- do the calculation inline here
    DECLARE
      v_facility_id text := NEW.facility_id;
      v_usage_direct numeric;
      v_usage_blend numeric;
      v_monthly_usage numeric;
      v_target_months numeric;
      v_reorder_months numeric;
      v_buffer numeric;
      v_bag_size numeric;
    BEGIN
      -- 92-day direct usage
      SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
      FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      WHERE rl.origin_id = NEW.origin_id
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
        AND rl.facility_id = v_facility_id;

      -- 92-day blend usage
      SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
      FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
      WHERE rc.coffee_item = NEW.origin_id
        AND rr.roast_type = 'Pre-Blend'
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND rl.facility_id = v_facility_id;

      v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

      -- Read from NEW category
      SELECT COALESCE(rc2.target_months, 3), COALESCE(rc2.reorder_months, 1.5)
      INTO v_target_months, v_reorder_months
      FROM restock_category rc2
      WHERE rc2.restock_category_id = NEW.restock_category_id;

      IF v_target_months IS NULL THEN v_target_months := 3; END IF;
      IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

      -- Buffer
      SELECT COALESCE(
        (SELECT cp.value_number FROM company_parameters cp
         WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
        1.3) INTO v_buffer;

      SELECT COALESCE(NEW.bag_size::numeric, 154) INTO v_bag_size;

      NEW.par := FLOOR((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));

      v_restock := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));
      IF NEW.par <= 0 THEN v_restock := 0; END IF;
      NEW.restock_level := LEAST(v_restock, NEW.par);

      NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
    END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_coffee_restock_category_change
  BEFORE UPDATE OF restock_category_id
  ON coffee_inventory
  FOR EACH ROW EXECUTE FUNCTION trg_recalc_coffee_on_category_change();

COMMIT;
