-- Migration 00099: Auto-propagate price log changes to historical order revenue
--
-- Problem: order_details.total_price is stamped at order creation from products.price.
-- If a product had no price entered at order time (total_price = 0), or a price is
-- corrected retroactively in products_price_log, historical revenues stay wrong.
--
-- Fix: trigger on products_price_log fires AFTER INSERT OR UPDATE OF price/date_updated.
-- It finds all orders for that product whose order_date falls in the price entry's
-- validity window and updates total_price = quantity × new_price.
--
-- Validity window: [date_updated, next_entry.date_updated) per product+facility.
-- Most recent entry covers [date_updated, ∞).
--
-- Also provides backfill_order_total_price() for one-time bulk correction of
-- existing $0-revenue orders.

-- ── Function: propagate_price_log_to_orders ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.propagate_price_log_to_orders()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_date_end date;
BEGIN
    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- Find the end of this entry's validity window:
    -- the date_updated of the next price log entry for this product+facility.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated
      AND (
          (NEW.facility_id IS NULL AND ppl.facility_id IS NULL)
          OR ppl.facility_id = NEW.facility_id
      );

    -- Update total_price for all eligible orders in this price's validity window.
    UPDATE public.order_details od
    SET    total_price = od.quantity * NEW.price
    FROM   public.orders o
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      AND  (NEW.facility_id IS NULL OR o.facility_id = NEW.facility_id)
      AND  COALESCE(od.quantity, 0) > 0;

    RETURN NEW;
END;
$$;

-- ── Trigger ──────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_propagate_price_log_to_orders ON public.products_price_log;

CREATE TRIGGER trg_propagate_price_log_to_orders
    AFTER INSERT OR UPDATE OF price, date_updated
    ON public.products_price_log
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_price_log_to_orders();

-- ── Backfill function ─────────────────────────────────────────────────────────
--
-- One-time (or on-demand) fix for existing $0-revenue orders.
-- For each order_detail where total_price = 0, looks up the applicable price
-- from products_price_log (most recent entry with date_updated <= order_date)
-- and sets total_price = quantity × price.
--
-- Usage:
--   SELECT backfill_order_total_price();                   -- all time, all facilities
--   SELECT backfill_order_total_price('2024-01-01', NULL); -- from Jan 2024 onward
-- Returns count of rows updated.

CREATE OR REPLACE FUNCTION public.backfill_order_total_price(
    p_from_date   date DEFAULT NULL,
    p_to_date     date DEFAULT NULL,
    p_facility_id text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_updated integer := 0;
    v_price   numeric;
    v_rec     record;
BEGIN
    FOR v_rec IN
        SELECT
            od.order_detail_id,
            od.product_id,
            od.quantity,
            o.order_date,
            o.facility_id AS order_facility_id
        FROM  public.order_details od
        JOIN  public.orders o ON o.order_id = od.order_id
        WHERE o.order_status           <> 'Canceled'
          AND COALESCE(od.quantity, 0)  > 0
          AND (od.total_price IS NULL OR od.total_price = 0)
          AND (p_from_date   IS NULL OR o.order_date >= p_from_date)
          AND (p_to_date     IS NULL OR o.order_date <= p_to_date)
          AND (p_facility_id IS NULL OR o.facility_id = p_facility_id)
    LOOP
        -- Most recent price log entry whose date_updated <= order_date
        SELECT ppl.price INTO v_price
        FROM   public.products_price_log ppl
        WHERE  ppl.product_id   = v_rec.product_id
          AND  ppl.date_updated <= v_rec.order_date
          AND  (ppl.facility_id IS NULL OR ppl.facility_id = v_rec.order_facility_id)
        ORDER BY ppl.date_updated DESC
        LIMIT 1;

        IF v_price IS NOT NULL AND v_price > 0 THEN
            UPDATE public.order_details
            SET    total_price = v_rec.quantity * v_price
            WHERE  order_detail_id = v_rec.order_detail_id;

            v_updated := v_updated + 1;
        END IF;
    END LOOP;

    RETURN v_updated;
END;
$$;
