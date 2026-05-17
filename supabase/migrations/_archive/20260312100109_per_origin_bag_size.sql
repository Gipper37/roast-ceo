-- Migration 00109: Per-origin bag_size
--
-- Problem: bag_size (Green Bean Bag Size) is stored as a single value per
-- facility in company_parameters (parameter_id '66526a57', default 154 lbs).
-- This forces every origin at a facility to share the same bag size, which is
-- wrong in principle — different origins arrive in different sack sizes
-- (154 lb, 132 lb, 100 lb, etc.).
--
-- Fix:
--   1. New bag_sizes reference table (for AppSheet dropdown)
--   2. bag_size column on coffee_inventory (per-origin, numeric lbs)
--   3. Backfill all existing rows to 154 (all 5 facilities currently use 154)
--   4. Rewrite 9 active functions to read from coffee_inventory.bag_size
--      instead of company_parameters
--   5. Update calculate_recent_order_totals (dead code) for completeness
--
-- No stock metric backfill needed: all rows backfill to 154 = same as today.


-- ─── 1. bag_sizes reference table ────────────────────────────────────────────

CREATE TABLE public.bag_sizes (
    bag_size_id text        PRIMARY KEY,
    size_lbs    numeric     NOT NULL,
    label       text,
    company_id  text,       -- NULL = system standard; set for custom sizes
    created_at  timestamptz DEFAULT now(),
    updated_at  timestamptz DEFAULT now()
);

INSERT INTO public.bag_sizes (bag_size_id, size_lbs, label) VALUES
    ('bs_154', 154, '154 lbs'),
    ('bs_132', 132, '132 lbs'),
    ('bs_100', 100, '100 lbs');


-- ─── 2. Add bag_size to coffee_inventory ─────────────────────────────────────

ALTER TABLE public.coffee_inventory
    ADD COLUMN IF NOT EXISTS bag_size numeric;


-- ─── 3. Backfill ─────────────────────────────────────────────────────────────
-- All 5 facilities use 154 in company_parameters — exact match.

UPDATE public.coffee_inventory SET bag_size = 154;


-- ─── 4a. calculate_current_stock_bags(p_origin_id) ───────────────────────────
-- Called by: other functions (not directly triggered)
-- Change: combine facility + bag_size lookup into one query from coffee_inventory

-- calculate_current_stock_bags has RETURNS integer in the DB — DROP + recreate
-- because CREATE OR REPLACE cannot change return type.
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
    -- 1. Get facility and bag_size for this origin
    SELECT facility_id, COALESCE(bag_size, 154)
    INTO v_facility_id, v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
    LIMIT 1;

    -- 2. Get current weight in lbs
    v_total_lbs := public.calculate_current_stock_lbs(p_origin_id, v_facility_id);

    -- 3. Calculate bags (round down to nearest whole bag)
    RETURN FLOOR(v_total_lbs / NULLIF(v_bag_size, 0))::integer;
END;
$$;


-- ─── 4b. calculate_current_stock_lbs(p_origin_id, p_facility_id) ─────────────
-- Called by: multiple trigger functions
-- Change: read bag_size from coffee_inventory instead of company_parameters

CREATE OR REPLACE FUNCTION public.calculate_current_stock_lbs(
    p_origin_id   text,
    p_facility_id text
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_purchased_lbs      NUMERIC;
    v_starting_lbs       NUMERIC;
    v_bag_size           NUMERIC;
    v_inventory_bags     NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs  NUMERIC;
BEGIN
    -- 1. Bag size (per-origin, from coffee_inventory)
    SELECT COALESCE(bag_size, 154) INTO v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id
    LIMIT 1;

    -- 2. Baseline (physical count for this facility)
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN
        v_last_inventory_date := '2000-01-01';
    END IF;

    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: purchases (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = p_facility_id;

    -- 4. Outflow A: direct roasts (single origin / post-blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id;

    -- 5. Outflow B: blend roasts (pre-blend via recipe)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    -- 6. Final result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;


-- ─── 4c. calculate_par(p_origin_id) ──────────────────────────────────────────
-- Change: read bag_size from coffee_inventory instead of company_parameters

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
    -- 1. Get the facility ID for this origin
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
    LIMIT 1;

    -- 2. Direct usage (single origin or post-blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    -- 3. Indirect usage (pre-blend via recipe)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    -- 4. Average monthly usage (92 days / 3 months)
    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    -- 5. Parameters
    SELECT value_number INTO v_par_multiple
    FROM company_parameters
    WHERE parameter_id = '3e6f5909' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters
    WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (per-origin, from coffee_inventory)
    SELECT COALESCE(bag_size, 154) INTO v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = v_facility_id
    LIMIT 1;

    IF v_par_multiple IS NULL THEN v_par_multiple := 3;   END IF;
    IF v_buffer       IS NULL THEN v_buffer       := 1.3; END IF;

    -- 6. Final calculation
    RETURN FLOOR((v_monthly_usage * v_par_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;


-- ─── 4d. calculate_restock_level(p_origin_id) ────────────────────────────────
-- Change: read bag_size from coffee_inventory instead of company_parameters

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
    -- 1. Get facility ID from inventory
    SELECT facility_id INTO v_facility_id
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
    LIMIT 1;

    -- 2. Get timezone & date (directly from facilities table)
    SELECT time_zone INTO v_timezone
    FROM facilities
    WHERE facility_id = v_facility_id;

    IF v_timezone IS NULL OR v_timezone = '' THEN
        v_timezone := 'Pacific/Honolulu';
    END IF;

    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    -- 3. Direct usage (single origin or post-blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id;

    -- 4. Indirect usage (pre-blend via recipe)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    -- 5. Average monthly usage
    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    -- 6. Parameters
    SELECT value_number INTO v_trigger_multiple
    FROM company_parameters
    WHERE parameter_id = 'dae6cd4b' AND facility_id = v_facility_id;

    SELECT value_number INTO v_buffer
    FROM company_parameters
    WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag size (per-origin, from coffee_inventory)
    SELECT COALESCE(bag_size, 154) INTO v_bag_size
    FROM coffee_inventory
    WHERE origin_id = p_origin_id AND facility_id = v_facility_id
    LIMIT 1;

    v_trigger_multiple := COALESCE(v_trigger_multiple, 1.5);
    v_buffer           := COALESCE(v_buffer, 1.3);

    -- 7. Final calculation
    RETURN CEILING((v_monthly_usage * v_trigger_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;


-- ─── 4e. compute_coffee_purchase_amount() ────────────────────────────────────
-- BEFORE trigger on coffee_inventory_purchased
-- Change: look up bag_size from coffee_inventory by NEW.origin + facility

CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        SELECT COALESCE(bag_size, 154) INTO v_bag_size
        FROM public.coffee_inventory
        WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id
        LIMIT 1;

        NEW.amount := NEW.bags_ordered * v_bag_size;
    END IF;

    RETURN NEW;
END;
$$;


-- ─── 4f. handle_manual_inventory_update() ────────────────────────────────────
-- BEFORE trigger on coffee_inventory
-- Change: bag_size is now ON the row — use NEW.bag_size directly, no query

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
    -- 1. Bag size (per-origin, directly on this row)
    v_bag_size := COALESCE(NEW.bag_size, 154);

    -- 2. Recalculate rolling metrics
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Establish the baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Inflows (RECEIVED shipments only — date_received IS NOT NULL)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received::DATE > v_last_inventory_date
      AND s.date_received IS NOT NULL
      AND p.facility_id = NEW.facility_id;

    -- 5. Outflows
    -- A. Direct roasts
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- B. Blend roasts
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


-- ─── 4g. trg_roast_log_inventory_update() ────────────────────────────────────
-- AFTER trigger on roast_log (INSERT, UPDATE, DELETE)
-- Change: remove single top-level bag_size lookup; look up per-origin at each use.
-- This also fixes a latent bug: blend recipes could contain origins with different
-- bag sizes, but the old code used one facility-level bag_size for all of them.

CREATE OR REPLACE FUNCTION public.trg_roast_log_inventory_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r               RECORD;
    v_bag_size      NUMERIC;
    v_facility_id   TEXT;
    v_current_lbs   NUMERIC;
    v_current_bags  NUMERIC;
    v_roast_type    TEXT;
    v_par           NUMERIC;
BEGIN
    -- 0. Setup: identify facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- -----------------------------------------------------------
    -- HANDLE DELETES or UPDATES (revert/fix OLD values)
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type
            FROM roast_recipes WHERE recipe_id = OLD.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP

                -- Per-origin bag size
                SELECT COALESCE(bag_size, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = OLD.facility_id
                LIMIT 1;

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

            -- Per-origin bag size
            SELECT COALESCE(bag_size, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = OLD.origin_id AND facility_id = OLD.facility_id
            LIMIT 1;

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

    -- -----------------------------------------------------------
    -- HANDLE INSERTS or UPDATES (apply NEW values)
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN

        v_roast_type := NULL;
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type
            FROM roast_recipes WHERE recipe_id = NEW.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP

                -- Per-origin bag size
                SELECT COALESCE(bag_size, 154) INTO v_bag_size
                FROM coffee_inventory
                WHERE origin_id = r.coffee_item AND facility_id = NEW.facility_id
                LIMIT 1;

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

            -- Per-origin bag size
            SELECT COALESCE(bag_size, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id
            LIMIT 1;

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


-- ─── 4h. update_actual_ordered_lbs() ─────────────────────────────────────────
-- BEFORE trigger on coffee_inventory
-- Change: use NEW.bag_size directly (it's on the row); also add bag_size change
-- to the recalc condition so changing bag_size updates actual_ordered_lbs.

CREATE OR REPLACE FUNCTION public.update_actual_ordered_lbs()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    -- Recalculate when: INSERT, bags_ordered changed, or bag_size changed
    IF (TG_OP = 'INSERT')
        OR (NEW.bags_ordered IS DISTINCT FROM OLD.bags_ordered)
        OR (NEW.bag_size IS DISTINCT FROM OLD.bag_size)
    THEN
        -- Bag size is on this row — no query needed
        v_bag_size := COALESCE(NEW.bag_size, 154);

        NEW.actual_ordered_lbs := COALESCE(NEW.bags_ordered, 0) * v_bag_size;
    END IF;

    RETURN NEW;
END;
$$;


-- ─── 4i. update_coffee_stock_purchased() ─────────────────────────────────────
-- AFTER trigger on coffee_inventory_purchased (INSERT, UPDATE, DELETE)
-- Change: look up bag_size from coffee_inventory by origin + facility
-- (coffee_inventory_purchased uses 'origin' column as the origin_id reference)

CREATE OR REPLACE FUNCTION public.update_coffee_stock_purchased()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size    NUMERIC;
    v_current_lbs NUMERIC;
    v_par         NUMERIC;
BEGIN
    -- -----------------------------------------------------------
    -- HANDLE DELETES
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' THEN

        SELECT COALESCE(bag_size, 154) INTO v_bag_size
        FROM coffee_inventory
        WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id
        LIMIT 1;

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

    -- -----------------------------------------------------------
    -- HANDLE INSERTS
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' THEN

        SELECT COALESCE(bag_size, 154) INTO v_bag_size
        FROM coffee_inventory
        WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id
        LIMIT 1;

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

    -- -----------------------------------------------------------
    -- HANDLE UPDATES
    -- -----------------------------------------------------------
    IF TG_OP = 'UPDATE' THEN

        -- Scenario 1: origin or facility changed — fix both OLD and NEW
        IF OLD.origin IS DISTINCT FROM NEW.origin
            OR OLD.facility_id IS DISTINCT FROM NEW.facility_id
        THEN
            -- A. Fix OLD origin
            SELECT COALESCE(bag_size, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = OLD.origin AND facility_id = OLD.facility_id
            LIMIT 1;

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
            SELECT COALESCE(bag_size, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id
            LIMIT 1;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);
            v_par         := public.calculate_par(NEW.origin);

            UPDATE coffee_inventory SET
                in_stock_lbs  = v_current_lbs,
                in_stock      = v_current_lbs / NULLIF(v_bag_size, 0),
                par           = v_par,
                to_order_bags = GREATEST(0, COALESCE(v_par, 0) - (v_current_lbs / NULLIF(v_bag_size, 0))),
                restock_level = public.calculate_restock_level(NEW.origin)
            WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id;

        -- Scenario 2: same origin/facility — simple update
        ELSE
            SELECT COALESCE(bag_size, 154) INTO v_bag_size
            FROM coffee_inventory
            WHERE origin_id = NEW.origin AND facility_id = NEW.facility_id
            LIMIT 1;

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


-- ─── 4j. calculate_recent_order_totals() — DEAD CODE (no trigger) ─────────────
-- Update for correctness: remove single bag_size variable; use per-origin sum.

CREATE OR REPLACE FUNCTION public.calculate_recent_order_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Calculate lbs ordered (per-origin bag_size, facility filtered)
    UPDATE recent_coffee_order
    SET lbs_ordered = (
        SELECT COALESCE(SUM(ci.bags_ordered * COALESCE(ci.bag_size, 154)), 0)
        FROM coffee_inventory ci
        JOIN supplier s ON ci.supplier_id = s.supplier_id
        WHERE s.supplier_category = 'PlmoC2'
          AND ci.facility_id = NEW.facility_id
    )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    -- Calculate recommended pallets
    UPDATE recent_coffee_order
    SET recommended_pallets = (
        SELECT CEILING(COALESCE(SUM(ci.to_order_bags), 0) / 10.0)
        FROM coffee_inventory ci
        JOIN supplier s ON ci.supplier_id = s.supplier_id
        WHERE s.supplier_category = 'PlmoC2'
          AND ci.facility_id = NEW.facility_id
    )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    -- Calculate bags left
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
