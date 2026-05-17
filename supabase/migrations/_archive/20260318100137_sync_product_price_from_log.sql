-- Migration 00137: Trigger to sync products.price from latest products_price_log entry
--                  + backfill 12 products that have log entries but no product price

-- ── 1. Trigger function ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_product_price_from_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_latest_price numeric;
    v_latest_date  date;
BEGIN
    -- Find the most recent price log entry for this product + facility
    SELECT price, date_updated
    INTO v_latest_price, v_latest_date
    FROM public.products_price_log
    WHERE product_id  = NEW.product_id
      AND (
          (NEW.facility_id IS NULL AND facility_id IS NULL)
          OR facility_id = NEW.facility_id
      )
      AND price > 0
    ORDER BY date_updated DESC
    LIMIT 1;

    -- Only update products.price if the inserted/updated row is the latest one
    IF v_latest_price IS NOT NULL AND v_latest_date = NEW.date_updated THEN
        UPDATE public.products
        SET price = v_latest_price
        WHERE product_id  = NEW.product_id
          AND (
              (NEW.facility_id IS NULL AND facility_id IS NULL)
              OR facility_id = NEW.facility_id
          );
    END IF;

    RETURN NEW;
END;
$$;

-- ── 2. Attach trigger ─────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_sync_product_price_from_log ON public.products_price_log;
CREATE TRIGGER trg_sync_product_price_from_log
    AFTER INSERT OR UPDATE OF price, date_updated
    ON public.products_price_log
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_product_price_from_log();

-- ── 3. Backfill 12 products with log entries but no product price ─────────────
UPDATE public.products p
SET price = latest.price
FROM (
    SELECT DISTINCT ON (pl.product_id, pl.facility_id)
        pl.product_id,
        pl.facility_id,
        pl.price
    FROM public.products_price_log pl
    WHERE pl.price > 0
    ORDER BY pl.product_id, pl.facility_id, pl.date_updated DESC
) latest
WHERE p.product_id   = latest.product_id
  AND (p.facility_id = latest.facility_id OR (p.facility_id IS NULL AND latest.facility_id IS NULL))
  AND (p.price IS NULL OR p.price = 0);
