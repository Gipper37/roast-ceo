-- Fix silent drag-reorder data loss: column-gate the roast_log inventory trigger.
--
-- trigger_roast_log_update_inventory fired on EVERY roast_log UPDATE (no column
-- list, unlike its gated siblings). A staged-queue drag writes sort_order on N
-- rows in parallel; each update ran the full ~0.9s par/stock recompute while
-- holding the origin's coffee_inventory row lock — and staged queues share one
-- origin (live: 17 of 18 rows), so the updates serialized and PostgREST's
-- lock_timeout=8s killed the tail. supabase-js errors were swallowed by the
-- action, so ~9 rows persisted and the rest silently reverted on next mount.
--
-- Gate the trigger to the columns that can actually move stock/par (the same
-- shape as trg_lot_consumption_recompute, + roast_date since the 92-day usage
-- window reads it, + facility_id). sort_order / notes / chaff / session-linking
-- / measured-weight updates no longer run a pointless 0.9s recompute each —
-- this also speeds up the drop/save path, which was paying the same tax.
--
-- Frontend half (same commit set): updateRoastSortOrders stops discarding
-- per-row errors, so any future partial write surfaces instead of hiding.

DROP TRIGGER IF EXISTS trigger_roast_log_update_inventory ON public.roast_log;
CREATE TRIGGER trigger_roast_log_update_inventory
    AFTER INSERT OR DELETE OR UPDATE OF
        "charged?", charge_weight, charge_weight_lbs, origin_id, recipe_id,
        coffee_source_id, borrow_origin_purchase_id, planned_lots,
        roast_date, facility_id
    ON public.roast_log
    FOR EACH ROW EXECUTE FUNCTION public.trg_roast_log_inventory_update();
