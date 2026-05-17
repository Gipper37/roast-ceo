-- Migration: Add CHECK constraints (NOT VALID) on numeric business columns
--
-- Issue 12: Several numeric columns have no range guards. Invalid values —
-- negative quantities, zero-weight products, percentages > 1 — flow silently
-- through trigger functions and corrupt derived calculations.
--
-- NOT VALID means:
--   - Existing rows are NOT scanned (no table lock, no downtime).
--   - All future INSERTs and UPDATEs are enforced immediately.
--   - To validate existing data later (run individually in low-traffic windows):
--       ALTER TABLE <table> VALIDATE CONSTRAINT <name>;

-- recipe_components.percentage must be in [0, 1].
-- sync_recipe_component_costs() computes: latest_cost * NEW.percentage
-- A value > 1 would inflate component costs; negative produces nonsense.
ALTER TABLE public.recipe_components
    ADD CONSTRAINT recipe_components_percentage_range
    CHECK (percentage >= 0 AND percentage <= 1) NOT VALID;

-- products.price must be non-negative.
-- Flows into order total calculations via handle_order_detail_logic().
ALTER TABLE public.products
    ADD CONSTRAINT products_price_nonnegative
    CHECK (price >= 0) NOT VALID;

-- products.weight_lbs must be strictly positive.
-- Used in roasted_weight = quantity * weight_lbs; zero weight is physically impossible.
ALTER TABLE public.products
    ADD CONSTRAINT products_weight_lbs_positive
    CHECK (weight_lbs > 0) NOT VALID;

-- order_details.quantity must be strictly positive.
-- Zero or negative quantity corrupts order totals, consumable stock, and roast detail.
ALTER TABLE public.order_details
    ADD CONSTRAINT order_details_quantity_positive
    CHECK (quantity > 0) NOT VALID;

-- coffee_inventory.par must be non-negative.
-- Used in to_order calculation: GREATEST(0, par - in_stock).
ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_par_nonnegative
    CHECK (par >= 0) NOT VALID;

-- coffee_inventory.restock_level must be non-negative.
-- Compared against in_stock to trigger reordering logic.
ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_restock_level_nonnegative
    CHECK (restock_level >= 0) NOT VALID;

-- consumable_inventory.par must be non-negative.
-- Used in update_consumable_metrics(): to_order = GREATEST(0, par - in_stock).
ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_par_nonnegative
    CHECK (par >= 0) NOT VALID;

-- consumable_inventory.restock_level must be non-negative.
-- Compared against in_stock to gate the to_order calculation.
ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_restock_level_nonnegative
    CHECK (restock_level >= 0) NOT VALID;

-- To validate all constraints against existing data:
-- ALTER TABLE public.recipe_components VALIDATE CONSTRAINT recipe_components_percentage_range;
-- ALTER TABLE public.products VALIDATE CONSTRAINT products_price_nonnegative;
-- ALTER TABLE public.products VALIDATE CONSTRAINT products_weight_lbs_positive;
-- ALTER TABLE public.order_details VALIDATE CONSTRAINT order_details_quantity_positive;
-- ALTER TABLE public.coffee_inventory VALIDATE CONSTRAINT coffee_inventory_par_nonnegative;
-- ALTER TABLE public.coffee_inventory VALIDATE CONSTRAINT coffee_inventory_restock_level_nonnegative;
-- ALTER TABLE public.consumable_inventory VALIDATE CONSTRAINT consumable_inventory_par_nonnegative;
-- ALTER TABLE public.consumable_inventory VALIDATE CONSTRAINT consumable_inventory_restock_level_nonnegative;
