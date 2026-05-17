-- Migration 00140: Fix product merge to drop conflicting price log entries
-- When dead product has a price log entry on a date the keep product already
-- has, delete the dead product's entry rather than creating duplicates.

-- ── 1. Clean up duplicate from the Crema Blend test merge ────────────────────
-- Keep product (4ed64dc0) now has two entries on 2023-04-01.
-- The $58.50 / 2025-02-24 entry is its own — that stays.
-- $57.38 and $48.38 both on 2023-04-01 came from the dead product.
-- Delete both dead-product entries (price_log_ids that came from a72807f3).
DELETE FROM public.products_price_log
WHERE product_id = '4ed64dc0'
  AND date_updated = '2023-04-01';

-- ── 2. Replace product merge function with conflict-aware version ─────────────
CREATE OR REPLACE FUNCTION public.trg_do_product_merge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_keep_id text := NEW.merge_into_id;
    v_kill_id text := NEW.product_id;
BEGIN
    -- Validate keep product exists
    IF NOT EXISTS (SELECT 1 FROM public.products WHERE product_id = v_keep_id) THEN
        RAISE EXCEPTION 'Merge target product not found: %', v_keep_id;
    END IF;

    -- Remap order_details
    UPDATE public.order_details
    SET product_id = v_keep_id
    WHERE product_id = v_kill_id;

    -- Price log: delete dead product entries that conflict with a keep product
    -- entry on the same date, then remap the rest
    DELETE FROM public.products_price_log
    WHERE product_id = v_kill_id
      AND date_updated IN (
          SELECT date_updated
          FROM public.products_price_log
          WHERE product_id = v_keep_id
      );

    UPDATE public.products_price_log
    SET product_id = v_keep_id
    WHERE product_id = v_kill_id;

    -- Remap product_filter
    UPDATE public.product_filter
    SET product_id = v_keep_id
    WHERE product_id = v_kill_id;

    -- Delete old BOM (keep product's BOM is authoritative)
    DELETE FROM public.product_consumables
    WHERE product_id = v_kill_id;

    -- Archive the kill product
    UPDATE public.products
    SET "archived?" = true
    WHERE product_id = v_kill_id;

    RETURN NEW;
END;
$$;
