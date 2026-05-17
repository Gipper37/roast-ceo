-- Migration: Fix sync_recipe_component_costs() to use coffee_item instead of item_id
--
-- Issue 3: Line 2201 of schema.sql joins recipe_components to coffee_inventory using
-- "WHERE origin_id = NEW.item_id". Every other function in the schema uses the
-- coffee_item column for this join (e.g. rc.coffee_item = ci.origin_id at lines
-- 820, 998, 1033, 1135, 1997, 2987). The recipe_components table has both item_id
-- and coffee_item columns; coffee_item is the correct FK to coffee_inventory.origin_id.
-- Using item_id silently returns NULL for component_cost on every insert/update.
--
-- Fix: Change NEW.item_id to NEW.coffee_item.

CREATE OR REPLACE FUNCTION public.sync_recipe_component_costs()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_facility_id text;
BEGIN
    -- 1. Get Facility ID from the Parent Recipe
    SELECT facility_id INTO v_facility_id
    FROM roast_recipes
    WHERE recipe_id = NEW.recipe_id;

    -- 2. Handle Coffee Costs
    SELECT latest_cost * NEW.percentage
    INTO NEW.component_cost
    FROM coffee_inventory
    WHERE origin_id = NEW.coffee_item  -- [FIX] Was NEW.item_id — wrong column
      AND facility_id = v_facility_id;

    -- 3. Propagate the Facility ID to the component row
    NEW.facility_id := v_facility_id;

    RETURN NEW;
END;
$$;
