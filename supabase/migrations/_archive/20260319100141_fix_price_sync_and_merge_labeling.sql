-- Migration 00141:
-- 1. Fix sync_product_price_from_log — simplify facility matching so DELETE
--    always clears products.price regardless of facility_id on the log row
-- 2. Update product merge to set product_type = 'Merged' and append ' - MERGED'
-- 3. Clear stuck price on Decaf 5lb - DEAD
-- 4. Fix Crema Blend 4.5lb - DEAD labeling from the test merge

-- ── 1. Fix price sync trigger ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_product_price_from_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id   text;
    v_latest_price numeric;
BEGIN
    v_product_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;

    SELECT price INTO v_latest_price
    FROM public.products_price_log
    WHERE product_id = v_product_id
      AND price > 0
    ORDER BY date_updated DESC
    LIMIT 1;

    -- NULL if no entries remain
    UPDATE public.products
    SET price = v_latest_price
    WHERE product_id = v_product_id;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ── 2. Fix product merge: label with type + name suffix ───────────────────────
CREATE OR REPLACE FUNCTION public.trg_do_product_merge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_keep_id text := NEW.merge_into_id;
    v_kill_id text := NEW.product_id;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.products WHERE product_id = v_keep_id) THEN
        RAISE EXCEPTION 'Merge target product not found: %', v_keep_id;
    END IF;

    -- Remap order_details
    UPDATE public.order_details
    SET product_id = v_keep_id
    WHERE product_id = v_kill_id;

    -- Price log: drop conflicts, remap the rest
    DELETE FROM public.products_price_log
    WHERE product_id = v_kill_id
      AND date_updated IN (
          SELECT date_updated FROM public.products_price_log WHERE product_id = v_keep_id
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

    -- Archive, label type, append name suffix
    UPDATE public.products
    SET "archived?"   = true,
        product_type  = 'Merged',
        product_name  = product_name || ' - MERGED'
    WHERE product_id = v_kill_id
      AND product_name NOT LIKE '% - MERGED';

    RETURN NEW;
END;
$$;

-- ── 3. Clear stuck price on Decaf 5lb - DEAD ─────────────────────────────────
UPDATE public.products
SET price = NULL
WHERE product_id = 'VD5WBWS';

-- ── 4. Fix Crema Blend 4.5lb - DEAD from test merge ──────────────────────────
UPDATE public.products
SET product_type = 'Merged',
    product_name = 'Crema Blend 4.5lb - MERGED'
WHERE product_id = 'a72807f3';
