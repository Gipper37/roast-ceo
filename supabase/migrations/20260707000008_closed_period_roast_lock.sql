-- Phase 5 of the lot-engine rearchitecture: closed-period roast lock.
--
-- The universal ERP bound (NetSuite periods, BC "Allow Posting From", QB/Xero
-- lock dates): once books are closed through a date, records at or before it
-- stop being editable. The valuation freeze (value_roast_lot_consumption) has
-- honored books_closed_through since it shipped; this adds the missing half —
-- the ROAST RECORD itself. Blocks retro edits of attribution-critical fields
-- and deletes of CHARGED roasts dated in the closed period, with a message
-- that names the escape hatch (move the closing date).
--
-- Deliberately narrow:
--   * charged rows only — stale STAGED junk stays deletable (queue hygiene,
--     same carve-out deleteRoast uses);
--   * only the dispatcher's watched columns + roast_date — post-roast data
--     (chaff, notes, measured weight, ref profile) stays editable;
--   * companies without books_closed_through set are unaffected.

CREATE OR REPLACE FUNCTION public.guard_closed_period_roast()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_closed date;
BEGIN
    SELECT c.books_closed_through INTO v_closed
      FROM public.companies c
     WHERE c.company_id = COALESCE(OLD.company_id, NEW.company_id);
    IF v_closed IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

    IF COALESCE(OLD."charged?", false) = true
       AND OLD.roast_date IS NOT NULL
       AND OLD.roast_date::date <= v_closed THEN
        RAISE EXCEPTION 'This roast is in a closed period (books closed through %) — its record and inventory attribution are locked. Move the closing date in company settings if this change is really needed.', v_closed;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_closed_period_roast_upd ON public.roast_log;
CREATE TRIGGER trg_guard_closed_period_roast_upd
    BEFORE UPDATE OF "charged?", charge_weight, charge_weight_lbs, origin_id,
                     recipe_id, coffee_source_id, borrow_origin_purchase_id,
                     planned_lots, roast_date
    ON public.roast_log
    FOR EACH ROW EXECUTE FUNCTION public.guard_closed_period_roast();

DROP TRIGGER IF EXISTS trg_guard_closed_period_roast_del ON public.roast_log;
CREATE TRIGGER trg_guard_closed_period_roast_del
    BEFORE DELETE ON public.roast_log
    FOR EACH ROW EXECUTE FUNCTION public.guard_closed_period_roast();
