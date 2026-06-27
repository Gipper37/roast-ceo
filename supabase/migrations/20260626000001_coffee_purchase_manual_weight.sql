-- Allow an EXACT net weight (lbs) override per coffee-purchase line, so a
-- shipment's stock reflects the invoice's real net weight instead of the
-- bags × bag_size estimate.
--
-- Today compute_coffee_purchase_amount() force-sets amount = bags_ordered ×
-- bag_size on every INSERT/UPDATE OF bags_ordered (etc.), clobbering any manual
-- amount. We add an `amount_manual` flag: when set, the trigger HONORS the
-- entered amount (the lot total in lbs) and DERIVES bag_size = amount / bags so
-- the bag count stays consistent (e.g. 50 bags = 6,634 lb → 132.68 lb/bag).
-- When the flag is off, behavior is unchanged (recompute bags × bag_size).
--
-- amount feeds stock via remaining_lbs at receive (initialize_lot_remaining_lbs_on_receive
-- seeds remaining_lbs = amount), so the override is what actually lands in stock
-- for a not-yet-received shipment. Received lots already have remaining_lbs set
-- (count is truth) and are untouched here.

ALTER TABLE public.coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS amount_manual boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.coffee_inventory_purchased.amount_manual IS
  'When true, amount (total lbs) is an operator-entered exact net weight; the amount trigger honors it and derives bag_size = amount/bags instead of recomputing bags × bag_size.';

CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount() RETURNS trigger
    LANGUAGE plpgsql
    AS $function$
DECLARE
    v_bag_size NUMERIC;
    v_bag_size_text TEXT;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        IF COALESCE(NEW.amount_manual, false) AND NEW.amount IS NOT NULL AND NEW.amount > 0 THEN
            -- Operator entered an exact net weight: honor amount as the lot total,
            -- derive the per-bag size so the bag count (lbs / bag_size) stays right.
            IF NEW.bags_ordered > 0 THEN
                NEW.bag_size := (NEW.amount / NEW.bags_ordered)::text;
            END IF;
            -- NEW.amount left as the entered value.
        ELSE
            -- Default: recompute the total from bags × resolved bag_size.
            -- 1. coffee_source.bag_size (most specific — the actual coffee)
            -- 2. coffee_inventory.bag_size (operative size for this origin category)
            -- 3. 154 (universal fallback)
            SELECT cs.bag_size
            INTO v_bag_size_text
            FROM public.coffee_source cs
            WHERE cs.coffee_source_id = NEW.coffee_source_id
            LIMIT 1;

            v_bag_size := COALESCE(
                v_bag_size_text::numeric,
                (SELECT ci.bag_size::numeric
                 FROM public.coffee_inventory ci
                 WHERE ci.origin_id = NEW.origin AND ci.facility_id = NEW.facility_id
                 LIMIT 1),
                154
            );

            NEW.bag_size := v_bag_size_text;
            NEW.amount   := NEW.bags_ordered * v_bag_size;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- Add amount_manual to the trigger's watch list so toggling the override (even
-- without a bags change) re-runs the function. amount is intentionally NOT in
-- the list: amount-only updates (e.g. the move RPC's split lots, which carry
-- bags_ordered = NULL) must stay a no-op, exactly as before.
DROP TRIGGER IF EXISTS trg_compute_coffee_purchase_amount ON public.coffee_inventory_purchased;
CREATE TRIGGER trg_compute_coffee_purchase_amount
  BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, coffee_source_id, amount_manual
  ON public.coffee_inventory_purchased
  FOR EACH ROW EXECUTE FUNCTION public.compute_coffee_purchase_amount();
