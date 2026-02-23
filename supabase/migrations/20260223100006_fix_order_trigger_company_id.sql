-- Migration: Fix update_roast_detail_from_order_trigger() to use company_id
-- for product lookup instead of facility_id
--
-- Issue 7: Products follow a hybrid model:
--   - Company-wide products: facility_id IS NULL, inherited by all facilities
--   - Facility-specific products: facility_id IS SET, unique to one facility
--
-- The current product lookup filters by facility_id:
--
--   WHERE product_id = v_product_id
--     AND facility_id = v_facility_id;   -- BUG: misses company-wide products
--
-- A company-wide product (facility_id = NULL) will never match this filter,
-- so v_recipe_id is always NULL for inherited products, the function hits the
-- RETURN NULL guard, and the roast plan (roast_detail, roast_detail_by_blend)
-- is never updated when orders change.
--
-- Fix: look up the product by company_id instead. Since product_id already
-- uniquely identifies the row, company_id is just a cross-tenant safety guard.
-- This finds both company-wide products (facility_id = NULL) and facility-
-- specific products.
--
-- The downstream UPDATE statements on roast_detail and roast_detail_by_blend
-- remain filtered by facility_id — those tables ARE facility-scoped and the
-- roast plan dashboard is per-facility. Only the initial recipe lookup changes.
--
-- This is an AFTER trigger. By the time it runs, handle_order_detail_logic()
-- (a BEFORE trigger) has already stamped NEW.company_id from the parent order.
-- COALESCE(NEW, OLD) handles DELETE operations where NEW is NULL.

CREATE OR REPLACE FUNCTION public.update_roast_detail_from_order_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_product_id  TEXT;
    v_facility_id TEXT;
    v_company_id  TEXT;  -- [FIX] Added: needed for hybrid product catalog lookup
    v_recipe_id   TEXT;
    r             RECORD;
BEGIN
    -- 1. Identify Context
    v_product_id  := COALESCE(NEW.product_id,  OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);
    v_company_id  := COALESCE(NEW.company_id,  OLD.company_id);  -- [FIX] Added

    -- 2. Look up the Recipe ID from the Product
    -- Products are a hybrid catalog: company-wide products (facility_id = NULL)
    -- are inherited by all facilities; facility-specific products have facility_id set.
    -- Using company_id here finds both, so the roast plan updates correctly
    -- regardless of whether the product is shared or facility-specific.
    SELECT recipe_id INTO v_recipe_id
    FROM products
    WHERE product_id = v_product_id
      AND company_id = v_company_id;  -- [FIX] Was: AND facility_id = v_facility_id

    -- If no recipe found (e.g., shipping fees, merch), stop
    IF v_recipe_id IS NULL THEN RETURN NULL; END IF;

    -- 3. Loop through Coffee Components
    -- "Touch" roast_detail for every bean in the recipe at this facility.
    -- roast_detail IS facility-scoped (per-facility roast plan dashboard).
    FOR r IN
        SELECT coffee_item
        FROM recipe_components
        WHERE recipe_id = v_recipe_id
    LOOP
        UPDATE roast_detail
        SET origin = origin  -- Force recalculation via calculate_roast_detail_origin trigger
        WHERE origin = r.coffee_item
          AND facility_id = v_facility_id;  -- Facility isolation: correct, unchanged
    END LOOP;

    -- 4. Update the Blend Summary Table
    -- roast_detail_by_blend is also facility-scoped.
    UPDATE roast_detail_by_blend
    SET recipe_id = recipe_id  -- Force recalculation via calculate_roast_by_blend trigger
    WHERE recipe_id = v_recipe_id
      AND facility_id = v_facility_id;  -- Facility isolation: correct, unchanged

    RETURN NULL;
END;
$$;
