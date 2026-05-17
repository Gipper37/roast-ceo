-- Migration 00137: Add merge_products() function

CREATE OR REPLACE FUNCTION public.merge_products(
    p_keep_id text,
    p_kill_id text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_orders_updated      integer;
    v_price_log_updated   integer;
    v_filter_updated      integer;
    v_bom_deleted         integer;
    v_keep_name           text;
    v_kill_name           text;
BEGIN
    -- Validate both products exist
    SELECT product_name INTO v_keep_name FROM public.products WHERE product_id = p_keep_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Keep product not found: %', p_keep_id;
    END IF;

    SELECT product_name INTO v_kill_name FROM public.products WHERE product_id = p_kill_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kill product not found: %', p_kill_id;
    END IF;

    IF p_keep_id = p_kill_id THEN
        RAISE EXCEPTION 'Keep and kill product are the same: %', p_keep_id;
    END IF;

    -- 1. Remap order_details
    UPDATE public.order_details
    SET product_id = p_keep_id
    WHERE product_id = p_kill_id;
    GET DIAGNOSTICS v_orders_updated = ROW_COUNT;

    -- 2. Remap products_price_log
    UPDATE public.products_price_log
    SET product_id = p_keep_id
    WHERE product_id = p_kill_id;
    GET DIAGNOSTICS v_price_log_updated = ROW_COUNT;

    -- 3. Remap product_filter
    UPDATE public.product_filter
    SET product_id = p_keep_id
    WHERE product_id = p_kill_id;
    GET DIAGNOSTICS v_filter_updated = ROW_COUNT;

    -- 4. Delete old BOM entries (kill product is being archived)
    DELETE FROM public.product_consumables
    WHERE product_id = p_kill_id;
    GET DIAGNOSTICS v_bom_deleted = ROW_COUNT;

    -- 5. Archive the kill product
    UPDATE public.products
    SET "archived?" = true
    WHERE product_id = p_kill_id;

    RETURN format(
        'Merged "%s" → "%s": %s order lines remapped, %s price log entries remapped, %s filter entries remapped, %s BOM entries deleted. "%s" archived.',
        v_kill_name, v_keep_name,
        v_orders_updated, v_price_log_updated, v_filter_updated, v_bom_deleted,
        v_kill_name
    );
END;
$$;
