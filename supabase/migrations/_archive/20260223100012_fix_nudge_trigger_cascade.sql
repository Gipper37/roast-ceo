-- Migration: Prevent nudge_all_inventory() from cascading into expensive triggers
--
-- Issue 14: nudge_all_inventory() sets updated_at = NOW() on all coffee_inventory
-- and consumable_inventory rows where the facility's local time is midnight.
-- This fires ALL triggers on every matching row, including expensive ones:
--
--   coffee_inventory (5 triggers per row on UPDATE):
--     trg_manual_inventory_update  -> handle_manual_inventory_update()
--       Calls calculate_par(), calculate_restock_level(), plus 2 large subqueries
--       across roast_log and coffee_inventory_purchased. Very expensive per row.
--     trg_update_green_metrics     -> calculate_green_purchasing_metrics()
--       Runs 2 subqueries + UPDATE on recent_coffee_order per row.
--     trigger_calculate_ordered_lbs -> update_actual_ordered_lbs()
--       Has an internal bags_ordered guard but still pays invocation overhead.
--
--   consumable_inventory (3 triggers per row on UPDATE):
--     trg_update_consumable_ordering -> update_consumable_metrics()
--       Runs 2 subqueries (purchases + order usage) per row.
--
-- At scale: 1,000 coffee_inventory rows × 3 expensive triggers = 3,000+ trigger
-- executions per midnight nudge, each running multi-table subqueries.
--
-- THE FIX: Add UPDATE OF column lists to the expensive triggers so they skip
-- firing when only updated_at changes.
--
-- trg_audit_update (-> handle_updated_record()) is intentionally LEFT UNCHANGED —
-- it must continue to fire on all updates to stamp updated_at and protect company_id.
--
-- Column lists are derived from reading each function body to identify which
-- columns the function actually uses to produce its output.

-- ============================================================
-- coffee_inventory: trg_manual_inventory_update
--
-- Original (schema.sql line 9317):
--   BEFORE INSERT OR UPDATE ON coffee_inventory
--
-- handle_manual_inventory_update() reads:
--   origin_id, facility_id, last_inventory, inventory_count_bags
-- Add UPDATE OF those columns — nudge (which changes only updated_at) skipped.
-- ============================================================
DROP TRIGGER IF EXISTS trg_manual_inventory_update ON public.coffee_inventory;

CREATE TRIGGER trg_manual_inventory_update
    BEFORE INSERT OR UPDATE OF origin_id, facility_id, last_inventory, inventory_count_bags
    ON public.coffee_inventory
    FOR EACH ROW EXECUTE FUNCTION public.handle_manual_inventory_update();

-- ============================================================
-- coffee_inventory: trg_update_green_metrics
--
-- Original (schema.sql line 9394):
--   AFTER INSERT OR DELETE OR UPDATE ON coffee_inventory
--
-- PostgreSQL does not allow combining UPDATE OF <cols> with DELETE in one
-- CREATE TRIGGER statement. Split into 3 triggers to preserve all event coverage:
--   _insert : fires on all INSERTs (new row always relevant to metrics)
--   _delete : fires on all DELETEs (row removal affects totals)
--   _update : fires only when the columns calculate_green_purchasing_metrics()
--             actually uses change: facility_id, supplier_id, bags_ordered, to_order_bags
--
-- calculate_green_purchasing_metrics() reads:
--   facility_id, supplier_id, bags_ordered, to_order_bags
-- ============================================================
DROP TRIGGER IF EXISTS trg_update_green_metrics ON public.coffee_inventory;

CREATE TRIGGER trg_update_green_metrics_insert
    AFTER INSERT ON public.coffee_inventory
    FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();

CREATE TRIGGER trg_update_green_metrics_delete
    AFTER DELETE ON public.coffee_inventory
    FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();

CREATE TRIGGER trg_update_green_metrics_update
    AFTER UPDATE OF facility_id, supplier_id, bags_ordered, to_order_bags
    ON public.coffee_inventory
    FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();

-- ============================================================
-- coffee_inventory: trigger_calculate_ordered_lbs
--
-- Original (schema.sql line 9415):
--   BEFORE INSERT OR UPDATE ON coffee_inventory
--
-- update_actual_ordered_lbs() reads: bags_ordered, facility_id
-- (facility_id needed to look up bag size from company_parameters)
-- ============================================================
DROP TRIGGER IF EXISTS trigger_calculate_ordered_lbs ON public.coffee_inventory;

CREATE TRIGGER trigger_calculate_ordered_lbs
    BEFORE INSERT OR UPDATE OF bags_ordered, facility_id
    ON public.coffee_inventory
    FOR EACH ROW EXECUTE FUNCTION public.update_actual_ordered_lbs();

-- ============================================================
-- consumable_inventory: trg_update_consumable_ordering
--
-- Original (schema.sql line 9387):
--   BEFORE INSERT OR UPDATE ON consumable_inventory
--
-- update_consumable_metrics() reads:
--   consumable_inventory_id, facility_id, last_inventory_date,
--   inventory_count, par, restock_level
-- ============================================================
DROP TRIGGER IF EXISTS trg_update_consumable_ordering ON public.consumable_inventory;

CREATE TRIGGER trg_update_consumable_ordering
    BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id,
                                last_inventory_date, inventory_count,
                                par, restock_level
    ON public.consumable_inventory
    FOR EACH ROW EXECUTE FUNCTION public.update_consumable_metrics();
