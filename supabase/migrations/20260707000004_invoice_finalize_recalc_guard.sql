-- Phase 3 (lot-engine rearchitecture): invoice-finalize guard.
--
-- Operator decision 2026-07-07: HARD-BLOCK invoice finalization while the
-- company has pending inventory recalculation (lot_recompute_queue) rather
-- than annotate — an invoice number must never be issued against COGS that a
-- mid-flight replay is about to change. The queue only engages for deep
-- replays (>400 post-count roasts) and drains in ≤~30s, so this trips rarely
-- and clears itself.
--
-- Implemented as an INDEPENDENT trigger on the finalize transition
-- (orders.invoice_number NULL → set) instead of editing finalize_invoice():
-- that function belongs to the invoice-of-record work stream and may be
-- redefined; a separate trigger survives those redefinitions (the same
-- silent-drop failure mode that hit planned_lots — see 20260707000002).
--
-- status='pending' only: a poison 'failed' row needs admin attention but must
-- not hold invoicing hostage indefinitely.

CREATE OR REPLACE FUNCTION public.guard_invoice_finalize_during_recalc()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.company_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.lot_recompute_queue q
         WHERE q.company_id = NEW.company_id AND q.status = 'pending'
    ) THEN
        RAISE EXCEPTION 'Inventory recalculation is in progress — finalizing is held for a moment so the invoice can''t capture mid-recalculation costs. Try again in about 30 seconds.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_invoice_finalize_recalc ON public.orders;
CREATE TRIGGER trg_guard_invoice_finalize_recalc
    BEFORE UPDATE OF invoice_number ON public.orders
    FOR EACH ROW
    WHEN (OLD.invoice_number IS NULL AND NEW.invoice_number IS NOT NULL)
    EXECUTE FUNCTION public.guard_invoice_finalize_during_recalc();
