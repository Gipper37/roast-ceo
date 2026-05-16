-- Migration 00066: Add last_contact and sales_status to customers
--
-- These were AppSheet Virtual Columns in the old sales app. Moving them to
-- trigger-maintained columns on customers so they are queryable, indexable,
-- and available to the proprietary frontend without recomputation.
--
-- last_contact: MAX(date) from sales_notes for this customer
-- sales_status: derived from deal state + most recent note activity type
--   'yhbGZV' = New  (deal open, no notes yet)
--   'w5qcJV' = Signed (deal closed)
--   otherwise = sales_activity_type from most recent note on last_contact date
--
-- Triggers:
--   trg_update_sales_metrics        — AFTER INSERT/UPDATE/DELETE on sales_notes
--   trg_update_status_on_deal_change — BEFORE UPDATE on customers (deal_open_closed)

-- ── A. Add columns ──────────────────────────────────────────────
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS last_contact  date,
    ADD COLUMN IF NOT EXISTS sales_status  text;

ALTER TABLE public.customers
    ADD CONSTRAINT customers_sales_status_fkey
    FOREIGN KEY (sales_status) REFERENCES public.sales_activity(sales_activity_id)
    NOT VALID;

-- ── B. Function: recalculate on sales_notes change ─────────────
CREATE OR REPLACE FUNCTION public.update_customer_sales_metrics()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id  TEXT;
    v_last_contact DATE;
    v_status       TEXT;
    v_deal_closed  BOOLEAN;
BEGIN
    v_customer_id := COALESCE(NEW.customer_id, OLD.customer_id);

    -- 1. last_contact = most recent note date
    SELECT MAX(date) INTO v_last_contact
    FROM public.sales_notes
    WHERE customer_id = v_customer_id;

    -- 2. Deal state for status logic
    SELECT deal_open_closed INTO v_deal_closed
    FROM public.customers
    WHERE customer_id = v_customer_id;

    -- 3. sales_status logic (mirrors AppSheet VC exactly)
    IF v_deal_closed = FALSE THEN
        v_status := 'w5qcJV';                      -- Signed / closed
    ELSIF v_last_contact IS NULL THEN
        v_status := 'yhbGZV';                      -- New / no activity yet
    ELSE
        SELECT sales_activity_type INTO v_status
        FROM public.sales_notes
        WHERE customer_id = v_customer_id
          AND date = v_last_contact
        ORDER BY created_at DESC NULLS LAST
        LIMIT 1;
    END IF;

    UPDATE public.customers
    SET last_contact = v_last_contact,
        sales_status = v_status
    WHERE customer_id = v_customer_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_update_sales_metrics ON public.sales_notes;
CREATE TRIGGER trg_update_sales_metrics
    AFTER INSERT OR UPDATE OR DELETE ON public.sales_notes
    FOR EACH ROW EXECUTE FUNCTION public.update_customer_sales_metrics();

-- ── C. Function: recalculate on deal_open_closed change ────────
-- BEFORE UPDATE so we set NEW directly — no second round-trip needed.
CREATE OR REPLACE FUNCTION public.update_sales_status_on_deal_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.deal_open_closed IS DISTINCT FROM NEW.deal_open_closed THEN
        IF NEW.deal_open_closed = FALSE THEN
            NEW.sales_status := 'w5qcJV';
        ELSIF NEW.last_contact IS NULL THEN
            NEW.sales_status := 'yhbGZV';
        ELSE
            SELECT sales_activity_type INTO NEW.sales_status
            FROM public.sales_notes
            WHERE customer_id = NEW.customer_id
              AND date = NEW.last_contact
            ORDER BY created_at DESC NULLS LAST
            LIMIT 1;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_status_on_deal_change ON public.customers;
CREATE TRIGGER trg_update_status_on_deal_change
    BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.update_sales_status_on_deal_change();

-- ── D. Backfill existing rows ───────────────────────────────────
UPDATE public.customers c
SET
    last_contact = (
        SELECT MAX(date)
        FROM public.sales_notes
        WHERE customer_id = c.customer_id
    ),
    sales_status = CASE
        WHEN c.deal_open_closed = FALSE
            THEN 'w5qcJV'
        WHEN NOT EXISTS (
            SELECT 1 FROM public.sales_notes
            WHERE customer_id = c.customer_id
        )
            THEN 'yhbGZV'
        ELSE (
            SELECT sn.sales_activity_type
            FROM public.sales_notes sn
            WHERE sn.customer_id = c.customer_id
              AND sn.date = (
                  SELECT MAX(date) FROM public.sales_notes
                  WHERE customer_id = c.customer_id
              )
            ORDER BY sn.created_at DESC NULLS LAST
            LIMIT 1
        )
    END
WHERE c.company_id IS NOT NULL;
