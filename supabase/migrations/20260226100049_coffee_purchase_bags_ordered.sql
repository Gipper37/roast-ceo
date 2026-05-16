-- Migration 00049: Add bags_ordered to coffee_inventory_purchased
--
-- bags_ordered = user input (how many bags were purchased)
-- amount (lbs) = auto-computed: bags_ordered × green_bean_bag_size (parameter 66526a57, default 154)
-- All downstream functions reading amount are unchanged.

-- ═══════════════════════════════════════════════════════════════
-- A. Add bags_ordered column
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS bags_ordered numeric;

-- ═══════════════════════════════════════════════════════════════
-- B. Backfill bags_ordered for all existing rows
--    Back-calculate: bags_ordered = amount / bag_size (per facility)
-- ═══════════════════════════════════════════════════════════════

UPDATE public.coffee_inventory_purchased p
SET bags_ordered = ROUND(
    p.amount / COALESCE(
        NULLIF((
            SELECT value_number FROM public.company_parameters
            WHERE parameter_id = '66526a57'
              AND facility_id = p.facility_id
        ), 0),
        154
    ),
    4
)
WHERE p.amount IS NOT NULL
  AND p.bags_ordered IS NULL;

-- ═══════════════════════════════════════════════════════════════
-- C. BEFORE trigger function: compute amount from bags_ordered
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        SELECT value_number INTO v_bag_size
        FROM public.company_parameters
        WHERE parameter_id = '66526a57'
          AND facility_id = NEW.facility_id;
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;
        NEW.amount := NEW.bags_ordered * v_bag_size;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
-- D. Create trigger (BEFORE so amount is set before AFTER triggers fire)
-- ═══════════════════════════════════════════════════════════════
-- Fires on bags_ordered OR facility_id change — if facility changes,
-- amount must be recomputed with the new facility's bag size.

CREATE TRIGGER trg_compute_coffee_purchase_amount
    BEFORE INSERT OR UPDATE OF bags_ordered, facility_id
    ON public.coffee_inventory_purchased
    FOR EACH ROW EXECUTE FUNCTION public.compute_coffee_purchase_amount();
