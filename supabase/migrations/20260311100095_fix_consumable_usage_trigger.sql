-- Migration 00095: Fix trg_sync_consumable_usage trigger firing on unit_cost_at_sale updates
--
-- Problem: trg_sync_consumable_usage fires AFTER INSERT OR DELETE OR UPDATE on
--          order_details for ANY change. This causes backfill_order_unit_costs()
--          to run calculate_current_stock_consumables() for every order detail
--          it updates — extremely expensive on 5 years of order history (timeout).
--
-- The consumable stock calculation only needs to re-run when:
--   - A row is INSERTED (new order quantity consumed)
--   - A row is DELETED (order quantity restored)
--   - UPDATE: quantity or product_id changed (consumption amount changed)
--
-- It does NOT need to run when only unit_cost_at_sale or updated_at changes.
--
-- Fix: Split into two triggers (same pattern as 00093's fix for order totals):
--   trg_sync_consumable_usage_ins_del — INSERT OR DELETE, always fires
--   trg_sync_consumable_usage_upd     — UPDATE, only fires when quantity
--                                       or product_id actually changes

DROP TRIGGER IF EXISTS trg_sync_consumable_usage ON public.order_details;

-- INSERT and DELETE always affect consumable stock
CREATE TRIGGER trg_sync_consumable_usage_ins_del
    AFTER INSERT OR DELETE ON public.order_details
    FOR EACH ROW
    EXECUTE FUNCTION public.update_consumable_stock();

-- UPDATE only recalculates stock when consumption-relevant columns change
CREATE TRIGGER trg_sync_consumable_usage_upd
    AFTER UPDATE ON public.order_details
    FOR EACH ROW
    WHEN (
        OLD.quantity   IS DISTINCT FROM NEW.quantity
        OR OLD.product_id IS DISTINCT FROM NEW.product_id
    )
    EXECUTE FUNCTION public.update_consumable_stock();
