-- Migration 00138: User-facing merge for products and customers
-- User sets merge_into_id on the record to kill → trigger fires automatically

-- ── 1. Add columns ────────────────────────────────────────────────────────────

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS merge_into_id text;

ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS merge_into_id text,
    ADD COLUMN IF NOT EXISTS archived      boolean NOT NULL DEFAULT false;

-- ── 2. Product merge trigger function ────────────────────────────────────────

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

    -- Remap price log
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

-- ── 3. Customer merge trigger function ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_do_customer_merge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_keep_id text := NEW.merge_into_id;
    v_kill_id text := NEW.customer_id;
BEGIN
    -- Validate keep customer exists
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE customer_id = v_keep_id) THEN
        RAISE EXCEPTION 'Merge target customer not found: %', v_keep_id;
    END IF;

    -- Remap orders
    UPDATE public.orders
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap order_details
    UPDATE public.order_details
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap contacts
    UPDATE public.contacts
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap sales_notes
    UPDATE public.sales_notes
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Remap sales_tasks
    UPDATE public.sales_tasks
    SET customer_id = v_keep_id
    WHERE customer_id = v_kill_id;

    -- Archive the kill customer
    UPDATE public.customers
    SET archived = true
    WHERE customer_id = v_kill_id;

    RETURN NEW;
END;
$$;

-- ── 4. Triggers ───────────────────────────────────────────────────────────────

CREATE TRIGGER trg_merge_product
    AFTER UPDATE OF merge_into_id ON public.products
    FOR EACH ROW
    WHEN (NEW.merge_into_id IS NOT NULL AND OLD.merge_into_id IS DISTINCT FROM NEW.merge_into_id)
    EXECUTE FUNCTION trg_do_product_merge();

CREATE TRIGGER trg_merge_customer
    AFTER UPDATE OF merge_into_id ON public.customers
    FOR EACH ROW
    WHEN (NEW.merge_into_id IS NOT NULL AND OLD.merge_into_id IS DISTINCT FROM NEW.merge_into_id)
    EXECUTE FUNCTION trg_do_customer_merge();
