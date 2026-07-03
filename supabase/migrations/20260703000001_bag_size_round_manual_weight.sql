-- Round the DERIVED per-bag size for manual-weight (amount_manual) coffee
-- purchase lines.
--
-- compute_coffee_purchase_amount() (added 20260626000001) set:
--     NEW.bag_size := (NEW.amount / NEW.bags_ordered)::text
-- so an exact-weight override like 767.2 / 5 stored the FULL Postgres numeric
-- scale ("153.4400000000000") and the shipment UI rendered that float garbage.
--
-- Fix: round to 2 decimals + trim trailing zeros. This ONLY touches the derived
-- per-bag display value — NEW.amount (the operator's exact net weight) and
-- NEW.bags_ordered are unchanged, and stock is seeded from `amount`
-- (initialize_lot_remaining_lbs_on_receive), so nothing downstream shifts.

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
                -- Round to 2 dp + trim trailing zeros so the derived per-bag size
                -- doesn't leak full numeric scale into the UI (was "153.4400000000000").
                NEW.bag_size := trim_scale(round(NEW.amount / NEW.bags_ordered, 2))::text;
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

-- NOTE: existing rows still carry the un-rounded bag_size until re-saved. A
-- targeted cleanup (UPDATE ... SET bag_size = trim_scale(round(bag_size::numeric,2))::text
-- WHERE amount_manual) is deferred: it would fire the coffee_inventory_purchased
-- trigger stack (stock/par recompute) per row, which we don't want to kick off
-- while the shipment-accept inventory issue is still under investigation.
