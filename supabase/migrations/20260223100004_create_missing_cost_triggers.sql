-- Migration: Create missing triggers for the cost propagation chain
--
-- Issue 1: Three trigger functions were written but never wired to any trigger,
-- breaking the entire downstream cost pipeline:
--
--   1. update_last_consumable_cost()  — consumable purchase cost never reaches consumable_inventory
--   2. propagate_coffee_cost_change() — coffee cost changes never cascade to recipes or products
--   3. update_product_total_cogs()    — products.total_unit_cogs is always stale
--
-- After these triggers exist, the full cost cascade is:
--
--   coffee_inventory_purchased INSERT/UPDATE
--     -> trg_push_last_coffee_cost (existing) -> updates coffee_inventory.latest_cost
--       -> trg_propagate_coffee_cost (NEW) -> touches recipe_components + products
--         -> trg_sync_recipe_costs (existing) -> recalculates component_cost
--         -> trg_update_roasted_cost (existing) -> recalculates cost_lb_roasted
--         -> trg_update_product_cogs (NEW) -> recalculates total_unit_cogs
--
--   consumable_inventory_purchased INSERT/UPDATE
--     -> trg_push_last_consumable_cost (NEW) -> updates consumable_inventory.last_cost_unit

-- ============================================================
-- Trigger 1: Consumable cost propagation (independent chain)
--
-- Fires when a consumable purchase is inserted or updated.
-- Calls update_last_consumable_cost() which looks up the most recent
-- unit cost and writes it back to consumable_inventory.last_cost_unit.
-- Returns NULL (AFTER trigger pattern, already in function body).
-- ============================================================
DROP TRIGGER IF EXISTS trg_push_last_consumable_cost ON public.consumable_inventory_purchased;

CREATE TRIGGER trg_push_last_consumable_cost
    AFTER INSERT OR UPDATE ON public.consumable_inventory_purchased
    FOR EACH ROW
    EXECUTE FUNCTION public.update_last_consumable_cost();

-- ============================================================
-- Trigger 2: Coffee cost propagation (upstream of the chain)
--
-- Fires when coffee_inventory.latest_cost changes.
-- Calls propagate_coffee_cost_change() which touches updated_at on
-- all recipe_components and products that use this coffee origin,
-- causing the downstream trg_sync_recipe_costs and trg_update_product_cogs
-- triggers to fire and recalculate costs.
--
-- Fires only on UPDATE OF latest_cost to avoid unnecessary cascades
-- on every coffee_inventory write.
-- ============================================================
DROP TRIGGER IF EXISTS trg_propagate_coffee_cost ON public.coffee_inventory;

CREATE TRIGGER trg_propagate_coffee_cost
    AFTER UPDATE OF latest_cost ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_coffee_cost_change();

-- ============================================================
-- Trigger 3: Product COGS calculation (downstream of the chain)
--
-- Fires BEFORE INSERT OR UPDATE on products so it can set
-- NEW.total_unit_cogs before the row is written.
-- Calculates: (coffee_cost/lb * weight_lbs) + sum(packaging costs)
--
-- Must be BEFORE because the function assigns to NEW.total_unit_cogs
-- (line 3002 of schema.sql). An AFTER trigger cannot modify the row.
-- ============================================================
DROP TRIGGER IF EXISTS trg_update_product_cogs ON public.products;

CREATE TRIGGER trg_update_product_cogs
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_product_total_cogs();
