-- Rename archived?/archived columns to is_active on products and customers
-- Logic inverts: archived=true → is_active=false

-- ── 1. Drop dependent views first ───────────────────────────────────────────
DROP VIEW IF EXISTS public.data_quality_issues;
DROP VIEW IF EXISTS public.product_margins;

-- ── 2. Add is_active columns ────────────────────────────────────────────────
ALTER TABLE public.products  ADD COLUMN is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.customers ADD COLUMN is_active boolean NOT NULL DEFAULT true;

-- ── 3. Populate from existing archived columns ───────────────────────────────
UPDATE public.products  SET is_active = NOT COALESCE("archived?", false);
UPDATE public.customers SET is_active = NOT COALESCE(archived, false);

-- ── 4. Drop old columns ──────────────────────────────────────────────────────
ALTER TABLE public.products  DROP COLUMN "archived?";
ALTER TABLE public.customers DROP COLUMN archived;

-- ── 5. Recreate product_margins view ─────────────────────────────────────────
CREATE VIEW public.product_margins AS
SELECT product_id,
       product_name,
       company_id,
       facility_id,
       price,
       total_unit_cogs,
       round((price - total_unit_cogs), 2) AS gross_profit_per_unit,
       round((((price - total_unit_cogs) / NULLIF(price, 0::numeric)) * 100::numeric), 1) AS margin_pct,
       weight_lbs,
       size,
       CASE
           WHEN total_unit_cogs = 0 THEN true
           WHEN (((price - total_unit_cogs) / NULLIF(price, 0::numeric)) * 100::numeric) < 0 THEN true
           WHEN (((price - total_unit_cogs) / NULLIF(price, 0::numeric)) * 100::numeric) > 90 THEN true
           ELSE false
       END AS data_warning
FROM products p
WHERE is_active = true;

-- ── 5. Update update_product_total_cogs ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
    v_total_cogs            numeric;
    v_gross_profit          numeric;
    v_cogs_pct              numeric;
    v_margin_pct            numeric;
BEGIN
    -- ── Already inactive: short-circuit, touch nothing ───────────────────────
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = false THEN
        RETURN NEW;
    END IF;

    -- ── Calculate COGS ───────────────────────────────────────────────────────

    -- 0. Sync weight_lbs from size table
    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;

    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- A. Coffee cost
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM public.recipe_components rc
    JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id   = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id;

    -- B. Consumable cost
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM public.product_consumables pc
    JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id  = NEW.product_id
      AND ci.facility_id = NEW.facility_id;

    -- C. Totals
    v_total_cogs   := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;
    v_gross_profit := COALESCE(NEW.price, 0) - v_total_cogs;
    v_cogs_pct     := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND(v_total_cogs / NEW.price * 100, 1)
                           ELSE NULL END;
    v_margin_pct   := CASE WHEN COALESCE(NEW.price, 0) > 0
                           THEN ROUND((1 - v_total_cogs / NEW.price) * 100, 1)
                           ELSE NULL END;

    -- ── Transitioning to inactive ────────────────────────────────────────────
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = true THEN

        -- Snapshot calculated values into last_active_*
        NEW.last_active_unit_cogs              := v_total_cogs;
        NEW.last_active_cogs_pct               := v_cogs_pct;
        NEW.last_active_gross_profit_per_unit  := v_gross_profit;
        NEW.last_active_margin_pct             := v_margin_pct;

        -- Null out live cost columns
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;

        RETURN NEW;
    END IF;

    -- ── Merged: null everything out ──────────────────────────────────────────
    IF NEW.product_type = 'Merged' THEN
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    -- ── Active: set live columns + keep last_active_* current ────────────────
    NEW.total_coffee_cost                 := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
    NEW.total_consumable_cost             := v_consumable_cost_total;
    NEW.total_unit_cogs                   := v_total_cogs;
    NEW.gross_profit_per_unit             := v_gross_profit;
    NEW.cogs_pct                          := v_cogs_pct;
    NEW.margin_pct                        := v_margin_pct;
    NEW.last_active_unit_cogs             := v_total_cogs;
    NEW.last_active_cogs_pct              := v_cogs_pct;
    NEW.last_active_gross_profit_per_unit := v_gross_profit;
    NEW.last_active_margin_pct            := v_margin_pct;

    RETURN NEW;
END;
$$;

-- ── 6. Update merge_products ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.merge_products(p_keep_id text, p_kill_id text)
RETURNS text
LANGUAGE plpgsql
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

    -- 4. Delete old BOM entries (kill product is being deactivated)
    DELETE FROM public.product_consumables
    WHERE product_id = p_kill_id;
    GET DIAGNOSTICS v_bom_deleted = ROW_COUNT;

    -- 5. Deactivate the kill product
    UPDATE public.products
    SET is_active = false
    WHERE product_id = p_kill_id;

    RETURN format(
        'Merged "%s" → "%s": %s order lines remapped, %s price log entries remapped, %s filter entries remapped, %s BOM entries deleted. "%s" deactivated.',
        v_kill_name, v_keep_name,
        v_orders_updated, v_price_log_updated, v_filter_updated, v_bom_deleted,
        v_kill_name
    );
END;
$$;

-- ── 7. Update trg_do_product_merge ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_do_product_merge()
RETURNS trigger
LANGUAGE plpgsql
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

    -- Deactivate, label type, append name suffix
    UPDATE public.products
    SET is_active    = false,
        product_type = 'Merged',
        product_name = product_name || ' - MERGED'
    WHERE product_id = v_kill_id
      AND product_name NOT LIKE '% - MERGED';

    RETURN NEW;
END;
$$;

-- ── 8. Update trg_do_customer_merge ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_do_customer_merge()
RETURNS trigger
LANGUAGE plpgsql
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

    -- Deactivate the kill customer
    UPDATE public.customers
    SET is_active = false
    WHERE customer_id = v_kill_id;

    RETURN NEW;
END;
$$;

-- ── 9. Recreate data_quality_issues view ─────────────────────────────────────
CREATE VIEW public.data_quality_issues AS
SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    p.margin_pct,
    CASE
        WHEN p.margin_pct < 0 THEN 'Selling below cost'::text
        WHEN p.margin_pct > 90 THEN 'Suspiciously high margin'::text
        ELSE NULL::text
    END AS issue
FROM product_margins p
WHERE p.data_warning = true AND p.total_unit_cogs > 0
UNION ALL
SELECT 'coffee'::text,
    ci.origin_id, ci.origin, ci.company_id, ci.facility_id,
    NULL::numeric, 'Missing coffee cost'::text
FROM coffee_inventory ci
WHERE COALESCE(ci.latest_cost, 0) = 0
UNION ALL
SELECT 'coffee'::text,
    ci.origin_id, ci.origin, ci.company_id, ci.facility_id,
    NULL::numeric, 'Fallback cost only – add item to a shipment'::text
FROM coffee_inventory ci
WHERE ci.latest_cost > 0 AND COALESCE(ci.last_cost_lb, 0) = 0
UNION ALL
SELECT 'consumable'::text,
    c.consumable_inventory_id, c.consumable_inventory_item, c.company_id, c.facility_id,
    NULL::numeric, 'Missing consumable cost'::text
FROM consumable_inventory c
WHERE COALESCE(c.last_cost_unit, 0) = 0
UNION ALL
SELECT 'consumable'::text,
    c.consumable_inventory_id, c.consumable_inventory_item, c.company_id, c.facility_id,
    NULL::numeric, 'Fallback cost only – add item to a shipment'::text
FROM consumable_inventory c
WHERE COALESCE(c.fallback_unit_cost, 0) > 0
  AND COALESCE(c.last_cost_unit, 0) > 0
  AND NOT EXISTS (
      SELECT 1 FROM consumable_inventory_purchased cip
      WHERE cip.consumable_inventory_item = c.consumable_inventory_id
        AND cip.facility_id = c.facility_id
        AND cip.cost_unit IS NOT NULL
        AND cip.cost_unit::text <> ''
        AND cip.cost_unit > 0
  )
UNION ALL
SELECT 'product'::text,
    p.product_id, p.product_name, p.company_id, p.facility_id,
    NULL::numeric, 'Missing product price'::text
FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM products_price_log ppl WHERE ppl.product_id = p.product_id
);
