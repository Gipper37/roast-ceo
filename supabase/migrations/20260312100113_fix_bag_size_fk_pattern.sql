-- Migration 00113: Fix bag_size FK pattern — text ID matching bag_sizes.bag_size_id
--
-- Root cause: coffee_inventory.bag_size stored numeric 154, but bag_sizes.bag_size_id
-- = 'bs_154'. AppSheet always matches a column's stored value against the referenced
-- table's primary key → 154 ≠ 'bs_154' → yellow warning on dropdown.
--
-- Best practice for Supabase + AppSheet:
--   • Store the FK text ID in the referencing column (coffee_inventory.bag_size)
--   • Reference table IDs are the natural key users see ('154', '132', '100')
--   • Arithmetic functions cast to numeric at point of use: bag_size::numeric
--
-- Changes:
--   1. Re-seed bag_sizes: IDs become numeric strings ('154', '132', '100')
--   2. Drop the 3 triggers that have UPDATE OF bag_size in their definition
--      (PostgreSQL blocks ALTER COLUMN TYPE when such triggers exist)
--   3. ALTER coffee_inventory.bag_size numeric → text
--      USING bag_size::text converts stored 154 → '154' (matches new IDs)
--   4. Rewrite all 9 active functions + 1 dead-code function to add ::numeric cast
--      wherever bag_size is used arithmetically — zero change to computed values
--   5. Recreate the 3 triggers
--   6. Backfill to verify everything still calculates correctly


-- ─── 1. Re-seed bag_sizes ─────────────────────────────────────────────────────
-- Numeric strings as IDs — natural key users expect to see.

DELETE FROM public.bag_sizes;

INSERT INTO public.bag_sizes (bag_size_id, size_lbs, label) VALUES
    ('154', 154, '154 lbs'),
    ('132', 132, '132 lbs'),
    ('100', 100, '100 lbs');


-- ─── 2. Drop triggers that reference bag_size in UPDATE OF lists ──────────────
-- PostgreSQL blocks ALTER COLUMN TYPE when trigger definitions mention the column.
-- All 3 are recreated in step 5 after the ALTER.

DROP TRIGGER IF EXISTS trg_manual_inventory_update        ON public.coffee_inventory;
DROP TRIGGER IF EXISTS trigger_calculate_ordered_lbs      ON public.coffee_inventory;
DROP TRIGGER IF EXISTS trg_refresh_par_on_bag_size_change ON public.coffee_inventory;


-- ─── 3. Convert coffee_inventory.bag_size numeric → text ─────────────────────
-- USING bag_size::text converts stored 154 → '154', matching bag_size_id above.

ALTER TABLE public.coffee_inventory
    ALTER COLUMN bag_size TYPE text USING bag_size::text;


-- ─── 4. Rewrite functions — add ::numeric casts ───────────────────────────────
-- Logic is identical throughout. Only change: COALESCE(bag_size, 154) becomes
-- COALESCE(bag_size::numeric, 154) everywhere bag_size is used arithmetically.

-- 4a. calculate_current_stock_bags
-- DROP required (cannot change return type with CREATE OR REPLACE on prior version)
DROP FUNCTION IF EXISTS public.calculate_current_stock_bags(text);

CREATE OR REPLACE FUNCTION public.calculate_current_stock_bags(p_origin_id text)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_facility_id TEXT;
    v_total_lbs   NUMERIC;
    v_bag_size    NUMERIC;
BEGIN
    SELECT facility_id, COALESCE(bag_size::numeric, 154)
    INTO v_facility_id, v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
    LIMIT 1;

    v_total_lbs := public.calculate_current_stock_lbs(p_origin_id, v_facility_id);

    RETURN FLOOR(v_total_lbs / NULLIF(v_bag_size, 0))::integer;
END;
$$;


-- 4b. calculate_current_stock_lbs
CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(
    p_origin_id   text,
    p_facility_id text
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_purchased_lbs       NUMERIC;
    v_starting_lbs        NUMERIC;
    v_bag_size            NUMERIC;
    v_inventory_bags      NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
BEGIN
    -- 1. Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id
    LIMIT 1;

    -- 2. Baseline
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: received purchases
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = p_facility_id;

    -- 4. Outflow A: direct roasts
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: blend roasts
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    -- 6. Result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;


-- 4c. calculate_par
CREATE OR REPLACE FUNCTION public.calculate_par(p_origin_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_facility_id   TEXT;
    v_usage_direct  NUMERIC;
    v_usage_blend   NUMERIC;
    v_monthly_usage NUMERIC;
    v_par_multiple  NUMERIC;
    v_buffer        NUMERIC;
    v_bag_size      NUMERIC;
BEGIN
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_par_multiple
    FROM company_parameters WHERE parameter_id = '3e6f5909' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

    IF v_par_multiple IS NULL THEN v_par_multiple := 3;   END IF;
    IF v_buffer       IS NULL THEN v_buffer       := 1.3; END IF;

    RETURN FLOOR((v_monthly_usage * v_par_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;


-- 4d. calculate_restock_level
CREATE OR REPLACE FUNCTION public.calculate_restock_level(p_origin_id text)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_facility_id      TEXT;
    v_usage_direct     NUMERIC;
    v_usage_blend      NUMERIC;
    v_monthly_usage    NUMERIC;
    v_trigger_multiple NUMERIC;
    v_buffer           NUMERIC;
    v_bag_size         NUMERIC;
    v_current_date     DATE;
    v_timezone         TEXT;
BEGIN
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

    SELECT time_zone INTO v_timezone
    FROM facilities WHERE facility_id = v_facility_id;

    IF v_timezone IS NULL OR v_timezone = '' THEN
        v_timezone := 'Pacific/Honolulu';
    END IF;

    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    SELECT value_number INTO v_trigger_multiple
    FROM company_parameters WHERE parameter_id = 'dae6cd4b' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (text → numeric)
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

    v_trigger_multiple := COALESCE(v_trigger_multiple, 1.5);
    v_buffer           := COALESCE(v_buffer, 1.3);

    RETURN CEILING((v_monthly_usage * v_trigger_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;


-- 4e. compute_coffee_purchase_amount (BEFORE trigger on coffee_inventory_purchased)
CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
        FROM public.coffee_inventory
        WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id
        LIMIT 1;

        NEW.amount := NEW.bags_ordered * v_bag_size;
    END IF;

    RETURN NEW;
END;
$$;


-- 4f. handle_manual_inventory_update (BEFORE trigger on coffee_inventory)
-- bag_size is on NEW — cast to numeric at point of use
CREATE OR REPLACE FUNCTION public.handle_manual_inventory_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Bag size (text → numeric)
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);

    -- 2. Rolling metrics
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Inflows
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = NEW.facility_id;

    -- 5a. Direct roasts
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- 5b. Blend roasts
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. In stock
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock     := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);

    -- 7. To order
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$$;


-- 4g. trg_roast_log_inventory_update (AFTER trigger on roast_log)
-- Per-origin bag_size lookup at each use site (4 places), text → numeric cast added
CREATE OR REPLACE FUNCTION public.trg_roast_log_inventory_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r              RECORD;
    v_bag_size     NUMERIC;
    v_facility_id  TEXT;
    v_current_lbs  NUMERIC;
    v_current_bags NUMERIC;
    v_roast_type   TEXT;
    v_par          NUMERIC;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- ── DELETE / UPDATE: revert OLD values ──────────────────────────────────
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = OLD.recipe_id;
        END IF;

        -- Case A: Pre-Blend (per-origin lookup inside loop)
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP

                SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = OLD.facility_id LIMIT 1;

                v_current_lbs  := public.calculate_current_stock_lbs(r.coffee_item, OLD.facility_id);
                v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
                v_par          := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory SET
                    in_stock_lbs  = v_current_lbs,
                    in_stock      = v_current_bags,
                    par           = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item AND facility_id = OLD.facility_id;

            END LOOP;

        -- Case B: Single origin / post-blend
        ELSIF OLD.origin_id IS NOT NULL THEN

            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = OLD.origin_id AND facility_id = OLD.facility_id LIMIT 1;

            v_current_lbs  := public.calculate_current_stock_lbs(OLD.origin_id, OLD.facility_id);
            v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
            v_par          := public.calculate_par(OLD.origin_id);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_bags,
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(OLD.origin_id)
            WHERE origin_id = OLD.origin_id AND facility_id = OLD.facility_id;

        END IF;
    END IF;

    -- ── INSERT / UPDATE: apply NEW values ───────────────────────────────────
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = NEW.recipe_id;
        END IF;

        -- Case A: Pre-Blend (per-origin lookup inside loop)
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP

                SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = NEW.facility_id LIMIT 1;

                v_current_lbs  := public.calculate_current_stock_lbs(r.coffee_item, NEW.facility_id);
                v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
                v_par          := public.calculate_par(r.coffee_item);

                UPDATE coffee_inventory SET
                    in_stock_lbs  = v_current_lbs,
                    in_stock      = v_current_bags,
                    par           = v_par,
                    to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item AND facility_id = NEW.facility_id;

            END LOOP;

        -- Case B: Single origin / post-blend
        ELSIF NEW.origin_id IS NOT NULL THEN

            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id LIMIT 1;

            v_current_lbs  := public.calculate_current_stock_lbs(NEW.origin_id, NEW.facility_id);
            v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
            v_par          := public.calculate_par(NEW.origin_id);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_bags,
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(NEW.origin_id)
            WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id;

        END IF;
    END IF;

    RETURN NULL;
END;
$$;


-- 4h. update_actual_ordered_lbs (BEFORE trigger on coffee_inventory)
-- bag_size is on NEW — cast to numeric at point of use
CREATE OR REPLACE FUNCTION public.update_actual_ordered_lbs()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    IF (TG_OP = 'INSERT')
        OR (NEW.bags_ordered IS DISTINCT FROM OLD.bags_ordered)
        OR (NEW.bag_size IS DISTINCT FROM OLD.bag_size)
    THEN
        v_bag_size := COALESCE(NEW.bag_size::numeric, 154);
        NEW.actual_ordered_lbs := COALESCE(NEW.bags_ordered, 0) * v_bag_size;
    END IF;

    RETURN NEW;
END;
$$;


-- 4i. update_coffee_stock_purchased (AFTER trigger on coffee_inventory_purchased)
CREATE OR REPLACE FUNCTION public.update_coffee_stock_purchased()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size    NUMERIC;
    v_current_lbs NUMERIC;
    v_par         NUMERIC;
BEGIN
    -- ── DELETE ──────────────────────────────────────────────────────────────
    IF TG_OP = 'DELETE' THEN

        SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
        FROM coffee_inventory WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id LIMIT 1;

        v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);
        v_par         := public.calculate_par(OLD.origin);

        UPDATE coffee_inventory SET
            in_stock_lbs  = v_current_lbs,
            in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
            par           = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
            restock_level = public.calculate_restock_level(OLD.origin)
        WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id;

    END IF;

    -- ── INSERT ──────────────────────────────────────────────────────────────
    IF TG_OP = 'INSERT' THEN

        SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
        FROM coffee_inventory WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id LIMIT 1;

        v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
        v_par         := public.calculate_par(NEW.origin);

        UPDATE coffee_inventory SET
            in_stock_lbs  = v_current_lbs,
            in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
            par           = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
            restock_level = public.calculate_restock_level(NEW.origin)
        WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id;

    END IF;

    -- ── UPDATE ──────────────────────────────────────────────────────────────
    IF TG_OP = 'UPDATE' THEN

        -- Origin or facility changed: fix both OLD and NEW
        IF OLD.origin IS DISTINCT FROM NEW.origin
            OR OLD.facility_id IS DISTINCT FROM NEW.facility_id
        THEN
            -- A. Fix OLD origin
            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id LIMIT 1;

            v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);
            v_par         := public.calculate_par(OLD.origin);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
                restock_level = public.calculate_restock_level(OLD.origin)
            WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id;

            -- B. Fix NEW origin
            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id LIMIT 1;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
            v_par         := public.calculate_par(NEW.origin);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
                restock_level = public.calculate_restock_level(NEW.origin)
            WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id;

        -- Same origin/facility: simple update
        ELSE
            SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
            FROM coffee_inventory WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id LIMIT 1;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
            v_par         := public.calculate_par(NEW.origin);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
                restock_level = public.calculate_restock_level(NEW.origin)
            WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id;

        END IF;
    END IF;

    RETURN NULL;
END;
$$;


-- 4j. calculate_recent_order_totals (dead code — updated for correctness)
CREATE OR REPLACE FUNCTION public.calculate_recent_order_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE recent_coffee_order
    SET lbs_ordered = (
        SELECT COALESCE(SUM(ci.bags_ordered * COALESCE(ci.bag_size::numeric, 154)), 0)
        FROM coffee_inventory ci
        JOIN supplier s ON ci.supplier_id = s.supplier_id
        WHERE s.supplier_category = 'PlmoC2'
          AND ci.facility_id = NEW.facility_id
    )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    UPDATE recent_coffee_order
    SET recommended_pallets = (
        SELECT CEILING(COALESCE(SUM(ci.to_order_bags), 0) / 10.0)
        FROM coffee_inventory ci
        JOIN supplier s ON ci.supplier_id = s.supplier_id
        WHERE s.supplier_category = 'PlmoC2'
          AND ci.facility_id = NEW.facility_id
    )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    UPDATE recent_coffee_order
    SET bags_left = (COALESCE(total_pallets, 0) * 10) - (
        SELECT COALESCE(SUM(ci.bags_ordered), 0)
        FROM coffee_inventory ci
        JOIN supplier s ON ci.supplier_id = s.supplier_id
        WHERE s.supplier_category = 'PlmoC2'
          AND ci.facility_id = NEW.facility_id
    )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    RETURN NEW;
END;
$$;


-- ─── 5. Recreate the 3 triggers that were dropped in step 2 ──────────────────

CREATE TRIGGER trg_manual_inventory_update
    BEFORE INSERT OR UPDATE OF origin_id, facility_id, last_inventory,
                                inventory_count_bags, bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_manual_inventory_update();

CREATE TRIGGER trigger_calculate_ordered_lbs
    BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.update_actual_ordered_lbs();

CREATE TRIGGER trg_refresh_par_on_bag_size_change
    AFTER UPDATE OF bag_size
    ON public.coffee_inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.refresh_par_on_bag_size_change();


-- ─── 6. Backfill ──────────────────────────────────────────────────────────────
-- Touch inventory_count_bags to fire trg_manual_inventory_update and confirm
-- all computed metrics resolve correctly with the new text bag_size column.

UPDATE public.coffee_inventory
SET inventory_count_bags = COALESCE(inventory_count_bags, 0);
