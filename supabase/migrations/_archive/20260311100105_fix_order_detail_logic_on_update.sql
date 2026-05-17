-- Migration 00105: Fix handle_order_detail_logic() to not overwrite explicit updates
--
-- Problem: trg_handle_order_details fires BEFORE INSERT OR UPDATE on order_details.
-- On every UPDATE it recalculates:
--   total_price       = quantity * products.price
--   unit_cost_at_sale = quantity * products.total_unit_cogs
-- This overwrites the values set by backfill_order_total_price() and the
-- propagation triggers (00092, 00099) — silently undoing all historical corrections.
-- Products with products.price = NULL (e.g. B-Side House Bulk 5lbs) get
-- total_price reset to 0 on every update.
--
-- Fix: on UPDATE, only recalculate total_price, roasted_weight, and unit_cost_at_sale
-- when quantity or product_id actually changed. Direct column updates from backfill
-- and propagation triggers are left untouched.
-- Metadata (order_date, customer_id, company_id, facility_id) still syncs on every op.

CREATE OR REPLACE FUNCTION public.handle_order_detail_logic()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_company_id      text;
    v_facility_id     text;
    v_product_weight  numeric;
    v_product_price   numeric;
    v_recipe_id       text;
    v_cogs            numeric;
BEGIN
    -- 1. Always sync order metadata from parent
    SELECT order_date, customer_id, company_id, facility_id
    INTO   NEW.order_date, NEW.customer_id, v_company_id, v_facility_id
    FROM   orders
    WHERE  order_id = NEW.order_id;

    NEW.company_id  := v_company_id;
    NEW.facility_id := v_facility_id;

    -- 2. Only recalculate price/weight/cost on INSERT or when quantity/product changes.
    --    On a plain UPDATE (e.g. backfill sets total_price, propagation sets
    --    unit_cost_at_sale), leave those columns exactly as the caller set them.
    IF TG_OP = 'INSERT'
       OR NEW.quantity   IS DISTINCT FROM OLD.quantity
       OR NEW.product_id IS DISTINCT FROM OLD.product_id
    THEN
        SELECT p.weight_lbs,
               p.price,
               p.recipe_id,
               COALESCE(p.total_unit_cogs, 0)
        INTO   v_product_weight, v_product_price, v_recipe_id, v_cogs
        FROM   products p
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        NEW.total_price       := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
