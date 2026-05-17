-- Migration 00139: Fix sync_product_price_from_log to handle DELETE
-- Previous version only fired on INSERT/UPDATE — deleting all price log
-- entries for a product left products.price stale.

-- ── 1. Replace function to handle DELETE ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_product_price_from_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id   text;
    v_facility_id  text;
    v_latest_price numeric;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_product_id  := OLD.product_id;
        v_facility_id := OLD.facility_id;
    ELSE
        v_product_id  := NEW.product_id;
        v_facility_id := NEW.facility_id;
    END IF;

    -- Get the most recent price log entry for this product + facility
    SELECT price INTO v_latest_price
    FROM public.products_price_log
    WHERE product_id = v_product_id
      AND (
          (v_facility_id IS NULL AND facility_id IS NULL)
          OR facility_id = v_facility_id
      )
      AND price > 0
    ORDER BY date_updated DESC
    LIMIT 1;

    -- Update products.price (NULL if no log entries remain)
    UPDATE public.products
    SET price = v_latest_price
    WHERE product_id = v_product_id
      AND (
          (v_facility_id IS NULL AND facility_id IS NULL)
          OR facility_id = v_facility_id
      );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ── 2. Recreate trigger with DELETE included ──────────────────────────────────
DROP TRIGGER IF EXISTS trg_sync_product_price_from_log ON public.products_price_log;

CREATE TRIGGER trg_sync_product_price_from_log
    AFTER INSERT OR UPDATE OF price, date_updated OR DELETE
    ON public.products_price_log
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_product_price_from_log();

-- ── 3. Clear prices on products that have no remaining price log entries ──────
UPDATE public.products p
SET price = NULL
WHERE p.price IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.products_price_log ppl
      WHERE ppl.product_id = p.product_id
        AND ppl.price > 0
  );
