-- ============================================================================
-- Lot-precise COGS — Step 1 of 4 (ADDITIVE / non-destructive)
-- ----------------------------------------------------------------------------
-- Value the FIFO lot-consumption ledger so every roast knows the ACTUAL cost
-- of the green lot(s) it consumed. Today COGS is group-level (recipe % ×
-- coffee_inventory.latest_cost = weighted-avg of the latest shipment), which is
-- imprecise when a group holds multiple lots at different $/lb. The ledger
-- (roast_log_lot_consumption) already records exactly which green purchase each
-- roast drew from — it just carries no cost. This migration adds that cost.
--
-- NON-DESTRUCTIVE: only ADDS columns + a valuation function + triggers that
-- populate them. No existing COGS READ path changes here (that is Step 3); the
-- group rollup (recalculate_inventory_cost -> coffee_inventory.latest_cost)
-- keeps running untouched. Existing ledger rows stay NULL until valued by the
-- backfill script (Step 4 Phase B) or the next roast/replay that touches them.
--
-- This per-(roast × lot) cost row is also the HACCP audit grain that future
-- finished-goods/bag lot tracing will build on.
-- ============================================================================

BEGIN;

-- 1. Per-(roast × lot) cost on the FIFO ledger ------------------------------
ALTER TABLE public.roast_log_lot_consumption
    ADD COLUMN IF NOT EXISTS green_cost_lb    numeric,  -- snapshot of the lot's cost_lb at valuation
    ADD COLUMN IF NOT EXISTS shipping_cost_lb numeric,  -- snapshot of the shipment's shipping_cost_unit (0 if none)
    ADD COLUMN IF NOT EXISTS lot_cost numeric
        GENERATED ALWAYS AS (lbs_consumed * (COALESCE(green_cost_lb,0) + COALESCE(shipping_cost_lb,0))) STORED;

CREATE INDEX IF NOT EXISTS idx_rllc_roast_log       ON public.roast_log_lot_consumption(roast_log_id);
CREATE INDEX IF NOT EXISTS idx_rllc_origin_purchase ON public.roast_log_lot_consumption(origin_purchase_id);

-- 2. Roast-level rolled-up cost ---------------------------------------------
-- green_cost      = total green+freight $ charged into this roast (sum of lots)
-- roasted_cost_lb = landed $/lb of ROASTED output (roast loss baked in by
--                   dividing by ACTUAL roasted lbs out, per-batch yield)
ALTER TABLE public.roast_log
    ADD COLUMN IF NOT EXISTS green_cost      numeric,
    ADD COLUMN IF NOT EXISTS roasted_cost_lb numeric;

-- 3. Valuation function -----------------------------------------------------
-- Snapshot (not live-join) so COGS is immutable as-of-roast; later lot-cost
-- corrections re-value via the triggers below.
CREATE OR REPLACE FUNCTION public.value_roast_lot_consumption(p_roast_log_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_green numeric;
    v_roasted_lbs numeric;
BEGIN
    -- a. snapshot each ledger row's green + shipping cost from its lot
    UPDATE public.roast_log_lot_consumption rlc
    SET green_cost_lb    = cip.cost_lb,
        shipping_cost_lb = COALESCE(sr.shipping_cost_unit, 0)
    FROM public.coffee_inventory_purchased cip
    LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
    WHERE rlc.roast_log_id = p_roast_log_id
      AND cip.origin_purchase_id = rlc.origin_purchase_id;

    -- b. roll up to roast_log (green_cost + roasted $/lb).
    -- NULL (not 0) when the roast has no ledger rows, so "not yet valued / no
    -- lot data" stays distinguishable from a genuine zero — the Step-3 read
    -- fallback ladder relies on NULL meaning "fall back to the old path."
    SELECT SUM(lot_cost)
      INTO v_total_green
      FROM public.roast_log_lot_consumption
     WHERE roast_log_id = p_roast_log_id;

    -- actual roasted lbs out; fall back to charge × retention when unmeasured
    SELECT COALESCE(rl.measured_roasted_weight,
                    rl.roasted_weight,
                    rl.charge_weight_lbs * COALESCE(public.get_retention_factor(rl.facility_id, rl.recipe_id), 0.82))
      INTO v_roasted_lbs
      FROM public.roast_log rl
     WHERE rl.roast_log_id = p_roast_log_id;

    UPDATE public.roast_log rl
    SET green_cost      = v_total_green,
        roasted_cost_lb = CASE WHEN v_total_green IS NOT NULL AND COALESCE(v_roasted_lbs,0) > 0
                               THEN v_total_green / v_roasted_lbs
                               ELSE NULL END
    WHERE rl.roast_log_id = p_roast_log_id;
END;
$$;

-- 4. Re-value when the ledger COMPOSITION changes ---------------------------
-- Fires only on composition columns (insert/delete/lbs/lot/roast change) — NOT
-- on green_cost_lb/shipping_cost_lb which this function writes — so the
-- valuation's own writes do not re-fire it (no recursion). roast_log's own
-- triggers likewise don't watch green_cost/roasted_cost_lb.
CREATE OR REPLACE FUNCTION public.trg_value_lot_consumption()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.value_roast_lot_consumption(COALESCE(NEW.roast_log_id, OLD.roast_log_id));
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_value_lot_consumption ON public.roast_log_lot_consumption;
CREATE TRIGGER trg_value_lot_consumption
    AFTER INSERT OR DELETE OR UPDATE OF lbs_consumed, origin_purchase_id, roast_log_id
    ON public.roast_log_lot_consumption
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_value_lot_consumption();

-- 5. Re-value when a lot's green COST is corrected --------------------------
-- The ledger composition is unchanged on a cost_lb edit, so the composition
-- trigger won't catch it; re-value every roast that consumed this lot.
CREATE OR REPLACE FUNCTION public.trg_revalue_roasts_on_cost_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.cost_lb IS DISTINCT FROM OLD.cost_lb THEN
        PERFORM public.value_roast_lot_consumption(rid)
        FROM (SELECT DISTINCT roast_log_id AS rid
                FROM public.roast_log_lot_consumption
               WHERE origin_purchase_id = NEW.origin_purchase_id) x;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_revalue_roasts_on_cost_change ON public.coffee_inventory_purchased;
CREATE TRIGGER trg_revalue_roasts_on_cost_change
    AFTER UPDATE OF cost_lb ON public.coffee_inventory_purchased
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_revalue_roasts_on_cost_change();

COMMIT;
