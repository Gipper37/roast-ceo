-- Fix trg_do_product_merge: it set product_type = 'Merged' (a literal string), but
-- since the product_type repurpose, product_type is an FK to product_type.
-- product_type_id and "Merged" exists only as UUIDs (per-company + a global one).
-- So EVERY product merge currently fails with products_product_type_fkey. Resolve
-- the company's 'Merged' marker id (fallback to the global company_id IS NULL one).
-- "Merged" stays an internal marker (is_active=false → hidden from type pickers);
-- it's only for deactivating a merged row / a future "past merges" view.
-- Body reproduced verbatim from the live definition; ONLY the final UPDATE changes.

CREATE OR REPLACE FUNCTION public.trg_do_product_merge()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
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

    -- Deactivate, label type (the 'Merged' marker RESOLVED to its id — company's
    -- own row if present, else the global one), append name suffix.
    UPDATE public.products
    SET is_active    = false,
        product_type = COALESCE(
          (SELECT pt.product_type_id FROM public.product_type pt
             WHERE pt.product_type = 'Merged' AND pt.company_id = public.products.company_id LIMIT 1),
          (SELECT pt.product_type_id FROM public.product_type pt
             WHERE pt.product_type = 'Merged' AND pt.company_id IS NULL LIMIT 1)
        ),
        product_name = product_name || ' - MERGED'
    WHERE product_id = v_kill_id
      AND product_name NOT LIKE '% - MERGED';

    RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
