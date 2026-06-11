-- ============================================================================
-- Lot-recompute performance fix
-- ============================================================================
-- A single recompute_origin_lot_consumption was taking ~14s for a busy origin,
-- which (a) made LFP time out and roll back (it fired on each of 76 staged
-- inserts) and (b) hung every charge by ~14s.
--
-- Two causes, both fixed here:
--  1. The recompute trigger ran on STAGED roasts (charged? = false), which
--     don't affect deductions at all. Gate it to charged-relevant ops only.
--  2. update_coffee_stock_purchased fired on every per-lot remaining_lbs
--     UPDATE and called calculate_current_stock_lbs (which replays roasts) —
--     O(roasts²) during a replay. But remaining_lbs is NOT an input to that
--     function (it's the manual-anchor stock path), so the trigger should not
--     fire on remaining_lbs changes at all. Narrow it to the columns that
--     actually affect purchase-derived stock.
-- ============================================================================

-- 1. Recompute only when a CHARGED roast is involved. Staged inserts/edits
--    (LFP, copy) don't change lot deductions, so they must not trigger a
--    full O(roasts) replay each.
CREATE OR REPLACE FUNCTION public.roast_log_lot_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    o text;
    v_relevant boolean := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_relevant := (NEW."charged?" = true);
    ELSIF TG_OP = 'DELETE' THEN
        v_relevant := (OLD."charged?" = true);
    ELSE -- UPDATE
        v_relevant := (NEW."charged?" = true OR OLD."charged?" = true);
    END IF;
    IF NOT v_relevant THEN RETURN NULL; END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.facility_id IS NOT NULL THEN
        FOREACH o IN ARRAY public._roast_affected_origins(NEW.recipe_id, NEW.origin_id) LOOP
            PERFORM public.recompute_origin_lot_consumption(o, NEW.facility_id);
        END LOOP;
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.facility_id IS NOT NULL THEN
        FOREACH o IN ARRAY public._roast_affected_origins(OLD.recipe_id, OLD.origin_id) LOOP
            PERFORM public.recompute_origin_lot_consumption(o, OLD.facility_id);
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;

-- 2. Stop update_coffee_stock_purchased from firing on remaining_lbs-only
--    updates. It recomputes in_stock/par from the manual-count anchor +
--    calculate_current_stock_lbs, none of which depend on remaining_lbs — so
--    firing it during the lot replay was pure (expensive) waste. Narrow the
--    trigger to the columns that actually change purchase-derived stock.
DROP TRIGGER IF EXISTS trg_coffee_purchase_add ON public.coffee_inventory_purchased;
CREATE TRIGGER trg_coffee_purchase_add
AFTER INSERT OR DELETE OR
      UPDATE OF amount, bags_ordered, bag_size, origin, facility_id, shipment_id
ON public.coffee_inventory_purchased
FOR EACH ROW EXECUTE FUNCTION public.update_coffee_stock_purchased();
