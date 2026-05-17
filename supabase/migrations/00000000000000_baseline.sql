-- ============================================================
-- BASELINE MIGRATION (squash)
-- ============================================================
-- Generated 2026-05-16 from live prod schema (pwpslalerytymorcodlv).
-- Supersedes 384 historical migrations spanning 2026-02-23 through
-- 2026-05-16. Those files were archived under
-- supabase/migrations/_archive/ for git history + blame.
--
-- Why a squash?
--   The historical migration set had filename-order replay bugs
--   (e.g. 20260223100004 referenced tables created by later
--   migrations). On prod this never showed because migrations were
--   applied manually in author order, not filename order; on a clean
--   rebuild the order is purely chronological and the gaps surfaced
--   immediately.
--
-- Going forward:
--   New migrations sit at later timestamps and apply cleanly on top
--   of this baseline. The CI fire drill (db-push-staging.yml) is the
--   ongoing guarantee that the migration history actually replays.
--
-- Prod state: this baseline reflects what is already in the live
-- DB, so `supabase migration repair --status applied 00000000000000`
-- was run against prod to record it without re-executing.
-- ============================================================

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.8 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: allocate_shop_order_ref(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.allocate_shop_order_ref(p_company_id text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_next bigint;
BEGIN
  -- Upsert-and-return in one shot. ON CONFLICT takes the row lock so
  -- concurrent callers serialize cleanly.
  INSERT INTO shop_order_ref_counter (company_id, next_value)
    VALUES (p_company_id, 2)
  ON CONFLICT (company_id) DO UPDATE
    SET next_value = shop_order_ref_counter.next_value + 1
  RETURNING next_value - 1 INTO v_next;

  RETURN 'SH-' || lpad(v_next::text, 6, '0');
END;
$$;


--
-- Name: auth_company_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_company_ids() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT company_id
  FROM public.team
  WHERE auth_user_id = auth.uid()
    AND COALESCE(is_active, true) = true
    AND company_id IS NOT NULL;
$$;


--
-- Name: auth_customer_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_customer_ids() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT customer_id
  FROM public.customer_users
  WHERE auth_user_id = auth.uid();
$$;


--
-- Name: auth_facility_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_facility_ids() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT facility_id
  FROM public.team
  WHERE auth_user_id = auth.uid()
    AND COALESCE(is_active, true) = true
    AND facility_id IS NOT NULL;
$$;


--
-- Name: auth_is_company_admin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_is_company_admin(p_company_id text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.team
    WHERE auth_user_id = auth.uid()
      AND company_id = p_company_id
      AND role IN ('company_admin', 'facility_admin')
      AND COALESCE(is_active, true) = true
  );
$$;


--
-- Name: backfill_order_total_price(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_order_total_price(p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_facility_id text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_updated integer := 0;
    v_price   numeric;
    v_rec     record;
BEGIN
    FOR v_rec IN
        SELECT
            od.order_detail_id,
            od.product_id,
            od.quantity,
            o.order_date,
            o.facility_id AS order_facility_id
        FROM  public.order_details od
        JOIN  public.orders o ON o.order_id = od.order_id
        WHERE o.order_status           <> 'Canceled'
          AND COALESCE(od.quantity, 0)  > 0
          AND (od.total_price IS NULL OR od.total_price = 0)
          AND (p_from_date   IS NULL OR o.order_date >= p_from_date)
          AND (p_to_date     IS NULL OR o.order_date <= p_to_date)
          AND (p_facility_id IS NULL OR o.facility_id = p_facility_id)
    LOOP
        -- Most recent price log entry whose date_updated <= order_date
        SELECT ppl.price INTO v_price
        FROM   public.products_price_log ppl
        WHERE  ppl.product_id   = v_rec.product_id
          AND  ppl.date_updated <= v_rec.order_date
          AND  (ppl.facility_id IS NULL OR ppl.facility_id = v_rec.order_facility_id)
        ORDER BY ppl.date_updated DESC
        LIMIT 1;

        IF v_price IS NOT NULL AND v_price > 0 THEN
            UPDATE public.order_details
            SET    total_price = v_rec.quantity * v_price
            WHERE  order_detail_id = v_rec.order_detail_id;

            v_updated := v_updated + 1;
        END IF;
    END LOOP;

    RETURN v_updated;
END;
$$;


--
-- Name: backfill_order_unit_costs(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_order_unit_costs(p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date, p_facility_id text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count    integer := 0;
    v_new_cost numeric;
    v_rec      record;
BEGIN
    FOR v_rec IN
        SELECT od.order_detail_id,
               od.product_id,
               od.facility_id,
               od.order_date,
               od.quantity
          FROM public.order_details od
          JOIN public.orders o ON o.order_id = od.order_id
         WHERE o.order_status    != 'Canceled'
           AND COALESCE(od.quantity, 0) > 0
           AND (p_from_date   IS NULL OR od.order_date >= p_from_date)
           AND (p_to_date     IS NULL OR od.order_date <= p_to_date)
           AND (p_facility_id IS NULL OR od.facility_id = p_facility_id)
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;


--
-- Name: build_product_name(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_product_name() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_group_name text;
  v_size_name  text;
  v_channel    text;
  v_parts      text[] := '{}';
BEGIN
  -- Look up group name
  SELECT group_name INTO v_group_name
    FROM product_groups WHERE group_id = NEW.group_id;

  -- Look up size name
  IF NEW.size IS NOT NULL THEN
    SELECT size_name INTO v_size_name
      FROM size WHERE size_id = NEW.size;
  END IF;

  -- Look up channel name and format as Title Case
  IF NEW.channel IS NOT NULL THEN
    SELECT initcap(replace(channel, '_', ' ')) INTO v_channel
      FROM channel WHERE channel_id = NEW.channel;
  END IF;

  -- Build name from non-null parts
  IF v_group_name IS NOT NULL THEN
    v_parts := v_parts || v_group_name;
  END IF;
  IF v_size_name IS NOT NULL AND v_size_name != '' THEN
    v_parts := v_parts || v_size_name;
  END IF;
  IF v_channel IS NOT NULL AND v_channel != '' THEN
    v_parts := v_parts || v_channel;
  END IF;

  NEW.product_name := array_to_string(v_parts, ' - ');
  RETURN NEW;
END;
$$;


--
-- Name: calculate_blend_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_blend_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    final_text text := '';
    comp record;
BEGIN
    -- Loop through components
    FOR comp IN
        SELECT 
            ci.origin, 
            rc.percentage
        FROM recipe_components rc
        LEFT JOIN coffee_inventory ci 
            ON rc.coffee_item = ci.origin_id 
            AND ci.facility_id = NEW.facility_id  -- <--- THIS IS THE FIX
        WHERE rc.recipe_id = NEW.roast_recipe_id
        -- [FIX] Sort by biggest percentage first, then name
        ORDER BY rc.percentage DESC, ci.origin ASC
    LOOP
        -- Build the text safely
        final_text := final_text 
                      || COALESCE(comp.origin, 'Unknown Coffee') 
                      || ' – ' 
                      || COALESCE(ROUND((comp.percentage * NEW.amount_to_blend)::numeric, 2)::text, '0') 
                      || ' lbs, ';
    END LOOP;

    -- Final cleanup
    IF length(final_text) > 0 THEN
        NEW.blend_summary := substring(final_text, 1, length(final_text) - 2);
    ELSE
        NEW.blend_summary := 'No components found for Recipe ID: ' || NEW.roast_recipe_id;
    END IF;

    RETURN NEW;
END;$$;


--
-- Name: calculate_consumable_par(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_consumable_par(p_consumable_id text, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_92day_usage    numeric;
  v_monthly_usage  numeric;
  v_target_months  numeric;
  v_buffer         numeric;
BEGIN
  -- 92-day usage from order history
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  -- Per-category target months (fallback to 3 if no category assigned)
  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  -- Global buffer
  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  RETURN CEIL(v_monthly_usage * v_target_months * v_buffer);
END;
$$;


--
-- Name: calculate_consumable_restock_level(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_consumable_restock_level(p_consumable_id text, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_92day_usage       numeric;
  v_monthly_usage     numeric;
  v_reorder_months    numeric;
  v_buffer            numeric;
  v_par               numeric;
  v_result            numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  v_result := CEIL(v_monthly_usage * v_reorder_months * v_buffer);

  -- Cap at par — restock should never exceed par
  v_par := calculate_consumable_par(p_consumable_id, p_facility_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$$;


--
-- Name: calculate_current_stock_bags(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_current_stock_bags(p_origin_id text) RETURNS integer
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


--
-- Name: calculate_current_stock_consumables(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
BEGIN
    -- 1. Baseline
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    -- 2. Additions (received, non-voided shipments only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cp.facility_id = p_facility_id;

    -- 3. Subtractions (non-canceled orders)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;


--
-- Name: calculate_current_stock_lbs(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) RETURNS numeric
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
    SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id LIMIT 1;

    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;
    v_starting_lbs := v_inventory_bags * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = p_facility_id;

    -- LEFT JOIN + tolerant filter: multi-recipe boundary batches have
    -- recipe_id IS NULL (no FK match) but origin_id IS set; they're
    -- never pre-blend so they SHOULD count toward green-by-origin
    -- consumption. Old INNER JOIN dropped them silently.
    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = p_facility_id;

    -- Blend (pre-blend) path unchanged: pre-blend rows always carry a
    -- single recipe_id (boundary batches are never pre-blend).
    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;


--
-- Name: calculate_green_cost(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_green_cost(recipe_id_param text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$DECLARE
    total_cost NUMERIC := 0;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Get the Facility ID for this Recipe
    -- We need to know WHICH facility is roasting this so we grab the right costs.
    SELECT facility_id INTO v_facility_id
    FROM roast_recipes
    WHERE recipe_id = recipe_id_param;

    -- 2. Sum Ingredient Costs (Facility Specific)
    SELECT SUM(
        COALESCE(i.last_cost_lb, 0) * rc.percentage
    ) INTO total_cost
    FROM recipe_components rc
    JOIN coffee_inventory i ON rc.coffee_item = i.origin_id
    WHERE rc.recipe_id = recipe_id_param
      AND i.facility_id = v_facility_id; -- [CHANGED] Lock to Facility Inventory

    RETURN ROUND(total_cost, 2);
END;$$;


--
-- Name: calculate_green_purchasing_metrics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_green_purchasing_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM public.recalculate_green_purchasing_metrics(
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NEW;
END;
$$;


--
-- Name: calculate_par(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_par(p_origin_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_facility_id   text;
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_monthly_usage numeric;
  v_target_months numeric;
  v_buffer        numeric;
  v_bag_size      numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  RETURN ROUND((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));
END;
$$;


--
-- Name: calculate_recent_order_totals(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_recent_order_totals() RETURNS trigger
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


--
-- Name: calculate_restock_level(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_restock_level(p_origin_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_facility_id      text;
  v_usage_direct     numeric;
  v_usage_blend      numeric;
  v_monthly_usage    numeric;
  v_reorder_months   numeric;
  v_buffer           numeric;
  v_bag_size         numeric;
  v_current_date     date;
  v_timezone         text;
  v_par              numeric;
  v_result           numeric;
BEGIN
  SELECT facility_id INTO v_facility_id
  FROM coffee_inventory WHERE origin_id = p_origin_id LIMIT 1;

  SELECT time_zone INTO v_timezone FROM facilities WHERE facility_id = v_facility_id;
  IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
  v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::date;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = p_origin_id
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = v_facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = p_origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (v_current_date - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = v_facility_id;

  v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

  IF v_monthly_usage <= 0 THEN RETURN 0; END IF;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM coffee_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.origin_id = p_origin_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
  FROM coffee_inventory WHERE origin_id = p_origin_id AND facility_id = v_facility_id LIMIT 1;

  v_result := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));

  v_par := calculate_par(p_origin_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$$;


--
-- Name: calculate_roasted_cost(numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text, p_recipe_id text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_retention numeric;
BEGIN
  v_retention := public.get_retention_factor(p_facility_id, p_recipe_id);
  RETURN ROUND((green_cost / v_retention), 2);
END;
$$;


--
-- Name: calculate_shipment_totals(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_shipment_totals() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_shipment_id TEXT;
    v_facility_id TEXT;
    v_total_weight NUMERIC;
BEGIN
    -- 0. Resolve the correct row reference based on operation type
    --    NEW is NULL on DELETE; OLD is NULL on INSERT.
    IF TG_OP = 'DELETE' THEN
        v_shipment_id := OLD.shipment_id;
        v_facility_id := OLD.facility_id;
    ELSE
        v_shipment_id := NEW.shipment_id;
        v_facility_id := NEW.facility_id;
    END IF;

    -- 1. Calculate Total Weight (Coffee + Consumables)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = v_shipment_id
          AND facility_id = v_facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = v_shipment_id
          AND facility_id = v_facility_id
    );

    -- 2. Update the Shipment Header
    UPDATE shipment_received
    SET
        shipment_total_weight_units = v_total_weight,
        shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN ROUND(shipping_cost / v_total_weight, 3)
            ELSE 0
        END
    WHERE shipment_id = v_shipment_id
      AND facility_id = v_facility_id;

    -- 3. Return appropriate row
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


--
-- Name: calculate_shipping_per_unit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_shipping_per_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Anti-Recursion: Stop if we are already inside this trigger
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    -- 2. Calculate the TRUE Total Weight (Coffee LBS + Consumable UNITS)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    );

    -- 3. Update BOTH the Total Weight and the Cost Per Unit
    UPDATE shipment_received
    SET shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN ROUND(NEW.shipping_cost / v_total_weight, 3)
            ELSE 0
        END,
        shipment_total_weight_units = v_total_weight
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;


--
-- Name: clear_email_bounce_on_email_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_email_bounce_on_email_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    NEW.email_bounced_at := NULL;
    NEW.email_bounce_reason := NULL;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: compute_coffee_purchase_amount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_coffee_purchase_amount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bag_size NUMERIC;
    v_bag_size_text TEXT;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        -- 1. coffee_source.bag_size (most specific — the actual coffee)
        -- 2. coffee_inventory.bag_size (operative size for this origin category)
        -- 3. 154 (universal fallback)
        SELECT cs.bag_size
        INTO v_bag_size_text
        FROM public.coffee_source cs
        WHERE cs.coffee_source_id = NEW.coffee_source_id
        LIMIT 1;

        v_bag_size := COALESCE(
            v_bag_size_text::numeric,
            (SELECT ci.bag_size::numeric
             FROM public.coffee_inventory ci
             WHERE ci.origin_id = NEW.origin AND ci.facility_id = NEW.facility_id
             LIMIT 1),
            154
        );

        NEW.bag_size := v_bag_size_text;
        NEW.amount   := NEW.bags_ordered * v_bag_size;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: compute_recent_coffee_order_calcs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_recent_coffee_order_calcs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_ordered_lbs  NUMERIC;
    v_total_ordered_bags NUMERIC;
BEGIN
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(bags_ordered), 0)
    INTO v_total_ordered_lbs, v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = NEW.current_shipment_id
      AND facility_id = NEW.facility_id;

    NEW.lbs_ordered := v_total_ordered_lbs;
    NEW.bags_left   := (COALESCE(NEW.total_pallets, 0) * 10) - v_total_ordered_bags;
    RETURN NEW;
END;
$$;


--
-- Name: day_of_week_to_number(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.day_of_week_to_number(p_day text) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN CASE LOWER(TRIM(p_day))
        WHEN 'sunday'    THEN 0
        WHEN 'monday'    THEN 1
        WHEN 'tuesday'   THEN 2
        WHEN 'wednesday' THEN 3
        WHEN 'thursday'  THEN 4
        WHEN 'friday'    THEN 5
        WHEN 'saturday'  THEN 6
        ELSE NULL
    END;
END;
$$;


--
-- Name: flag_customer_on_email_bounce(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flag_customer_on_email_bounce() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status IN ('bounced', 'complained')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.customer_id IS NOT NULL
  THEN
    UPDATE public.customers
       SET email_bounced_at = COALESCE(email_bounced_at, NOW()),
           email_bounce_reason = COALESCE(
             NEW.metadata->>'bounce_reason',
             NEW.status
           )
     WHERE customer_id = NEW.customer_id
       AND email_bounced_at IS NULL;  -- don't overwrite an existing flag
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: fn_sync_roaster_charge_weight(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sync_roaster_charge_weight() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.max_charge_weight_id IS NOT NULL THEN
        SELECT charge_weight INTO NEW.max_charge_weight_lbs
          FROM public.charge_weight_options
         WHERE id = NEW.max_charge_weight_id;
    ELSE
        NEW.max_charge_weight_lbs := NULL;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_update_batches_since_chaff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_update_batches_since_chaff() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_batches_since_chaff(OLD.facility_id);
        RETURN OLD;
    END IF;
    PERFORM public.recalculate_batches_since_chaff(NEW.facility_id);
    -- Handle facility_id reassignment (edge case)
    IF TG_OP = 'UPDATE' AND OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN
        PERFORM public.recalculate_batches_since_chaff(OLD.facility_id);
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: get_coffee_cost_on_date(text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_coffee_cost_on_date(p_origin_id text, p_facility_id text, p_order_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_retention     numeric;
    v_cost_lb       numeric;
    v_shipping_cost numeric;
BEGIN
    -- Retention factor (3-tier)
    SELECT value_number INTO v_retention
      FROM public.company_parameters
     WHERE parameter_id = '1de271df' AND facility_id = p_facility_id
     LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM public.standard_parameters
         WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    -- Priority 1: Most recent non-voided received shipment on or before order date
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received <= p_order_date
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 2: Earliest non-voided received shipment (forward fallback)
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 3: User-entered fallback cost
    RETURN (
        SELECT fallback_cost FROM public.coffee_inventory
         WHERE origin_id = p_origin_id AND facility_id = p_facility_id
         LIMIT 1
    );
END;
$$;


--
-- Name: get_consumable_cost_on_date(text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_consumable_cost_on_date(p_consumable_id text, p_facility_id text, p_order_date date) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_cost numeric;
BEGIN
    -- Priority 1: Most recent non-voided received shipment on or before order date
    SELECT cp.cost_unit + COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received             <= p_order_date
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN RETURN v_cost; END IF;

    -- Priority 2: Earliest non-voided received shipment (forward fallback)
    SELECT cp.cost_unit + COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN RETURN v_cost; END IF;

    -- Priority 3: User-entered fallback cost
    RETURN (
        SELECT fallback_unit_cost FROM public.consumable_inventory
         WHERE consumable_inventory_id = p_consumable_id LIMIT 1
    );
END;
$$;


--
-- Name: get_param(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_param(p_facility_id text, p_key text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_val_text TEXT;
    v_val_num NUMERIC;
    v_default TEXT;
BEGIN
    -- A. Check Facility Specific Settings
    -- [CHANGED] We now look up parameters by the specific Facility ID
    SELECT value, value_number 
    INTO v_val_text, v_val_num
    FROM company_parameters 
    WHERE facility_id = p_facility_id 
      AND parameter_id = p_key;

    -- Priority: Return Number if it exists, then Text
    IF v_val_num IS NOT NULL THEN RETURN v_val_num::text; END IF;
    IF v_val_text IS NOT NULL THEN RETURN v_val_text; END IF;

    -- B. Fallback to Global Default (Standard Parameters)
    -- This remains the same (System-wide defaults)
    SELECT COALESCE(text_value, amount::text) INTO v_default 
    FROM standard_parameters 
    WHERE parameters_id = p_key;

    RETURN v_default;
END;
$$;


--
-- Name: get_product_cogs_on_date(text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_product_cogs_on_date(p_product_id text, p_facility_id text, p_order_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_recipe_id       text;
    v_weight_lbs      numeric;
    v_coffee_cost     numeric := 0;
    v_consumable_cost numeric := 0;
    v_component_cost  numeric;
    v_rec             record;
    v_has_any_cost    boolean := false;
BEGIN
    -- Get recipe and weight for this product
    SELECT recipe_id, weight_lbs
      INTO v_recipe_id, v_weight_lbs
      FROM public.products
     WHERE product_id = p_product_id
     LIMIT 1;

    -- Coffee cost: SUM(cost_on_date × percentage) × weight_lbs
    IF v_recipe_id IS NOT NULL AND COALESCE(v_weight_lbs, 0) > 0 THEN
        FOR v_rec IN
            SELECT rc.coffee_item, rc.percentage
              FROM public.recipe_components rc
             WHERE rc.recipe_id   = v_recipe_id
               AND rc.facility_id = p_facility_id
        LOOP
            v_component_cost := public.get_coffee_cost_on_date(
                v_rec.coffee_item, p_facility_id, p_order_date
            );
            IF v_component_cost IS NOT NULL THEN
                v_coffee_cost  := v_coffee_cost + (v_component_cost * COALESCE(v_rec.percentage, 0));
                v_has_any_cost := true;
            END IF;
        END LOOP;
    END IF;

    -- Consumable cost: SUM(cost_on_date × quantity)
    FOR v_rec IN
        SELECT pc.consumable_id, pc.quantity
          FROM public.product_consumables pc
         WHERE pc.product_id   = p_product_id
           AND pc.facility_id  = p_facility_id
    LOOP
        v_component_cost := public.get_consumable_cost_on_date(
            v_rec.consumable_id, p_facility_id, p_order_date
        );
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * COALESCE(v_rec.quantity, 1));
            v_has_any_cost    := true;
        END IF;
    END LOOP;

    -- Return NULL if we found no cost data at all (nothing to update)
    IF NOT v_has_any_cost THEN
        RETURN NULL;
    END IF;

    RETURN (v_coffee_cost * COALESCE(v_weight_lbs, 0)) + v_consumable_cost;
END;
$$;


--
-- Name: get_retention_factor(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_retention_factor(p_facility_id text, p_recipe_id text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_retention numeric;
BEGIN
  -- Tier 1: recipe-level override
  IF p_recipe_id IS NOT NULL THEN
    SELECT retention_factor INTO v_retention
    FROM roast_recipes
    WHERE recipe_id = p_recipe_id
      AND retention_factor IS NOT NULL
      AND retention_factor > 0
    LIMIT 1;
  END IF;

  -- Tier 2: facility/company parameter
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT value_number INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;
  END IF;

  -- Tier 3: standard parameters
  IF v_retention IS NULL OR v_retention = 0 THEN
    SELECT amount INTO v_retention
    FROM standard_parameters
    WHERE parameters_id = '1de271df'
    LIMIT 1;
  END IF;

  -- Tier 4: hardcoded default
  IF v_retention IS NULL OR v_retention = 0 THEN
    v_retention := 0.82;
  END IF;

  RETURN v_retention;
END;
$$;


--
-- Name: get_roast_reset_day(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_roast_reset_day(p_facility_id text) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
    SELECT COALESCE(
        (SELECT cp.value_number::integer FROM company_parameters cp
         WHERE cp.parameter_id = 'RF1iFWjOh7' AND cp.facility_id = p_facility_id LIMIT 1),
        (SELECT sp.amount::integer FROM standard_parameters sp
         WHERE sp.parameters_id = 'RF1iFWjOh7' LIMIT 1),
        4
    );
$$;


--
-- Name: get_smartroast_thresholds(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_smartroast_thresholds(p_roaster_unit_id uuid, p_event_type text, p_sensitivity text DEFAULT 'normal'::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_unit_row    roaster_unit_smartroast_calibration%ROWTYPE;
  v_model_row   roaster_model_smartroast_calibration%ROWTYPE;
  v_brand       text;
  v_model       text;
  v_unit_min_samples constant integer := 5;
  v_model_min_samples constant integer := 50;
  v_min_peak_bt numeric;
  v_drop_rate   numeric;
BEGIN
  -- Layer 1: per-unit
  SELECT * INTO v_unit_row
  FROM roaster_unit_smartroast_calibration
  WHERE roaster_unit_id = p_roaster_unit_id AND event_type = p_event_type;

  IF FOUND AND v_unit_row.sample_count >= v_unit_min_samples THEN
    v_min_peak_bt := v_unit_row.peak_bt_avg - COALESCE(v_unit_row.peak_bt_stddev, 0);
    v_drop_rate   := abs(v_unit_row.cliff_rate_avg) * 0.5;
    RETURN jsonb_build_object(
      'dropRate', v_drop_rate,
      'minPeakBt', v_min_peak_bt,
      'source', 'unit',
      'sampleCount', v_unit_row.sample_count
    );
  END IF;

  -- Layer 2: per-model
  SELECT brand, model INTO v_brand, v_model
  FROM roaster_units WHERE roaster_unit_id = p_roaster_unit_id;

  IF v_brand IS NOT NULL AND v_model IS NOT NULL THEN
    SELECT * INTO v_model_row
    FROM roaster_model_smartroast_calibration
    WHERE brand = v_brand AND model = v_model AND event_type = p_event_type;

    IF FOUND AND v_model_row.sample_count >= v_model_min_samples THEN
      v_min_peak_bt := v_model_row.peak_bt_avg - COALESCE(v_model_row.peak_bt_stddev, 0);
      v_drop_rate   := abs(v_model_row.cliff_rate_avg) * 0.5;
      RETURN jsonb_build_object(
        'dropRate', v_drop_rate,
        'minPeakBt', v_min_peak_bt,
        'source', 'model',
        'sampleCount', v_model_row.sample_count
      );
    END IF;
  END IF;

  -- Layer 3: hardcoded fallback (mirrors lib/roast/autoDetect.ts tiers)
  RETURN jsonb_build_object(
    'source', 'hardcoded',
    'sensitivity', p_sensitivity
  );
END $$;


--
-- Name: guard_coffee_inventory_baseline(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_coffee_inventory_baseline() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Allow writes from the history-to-parent trigger function
    IF current_setting('app.from_history_trigger', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.last_inventory IS DISTINCT FROM NEW.last_inventory
       OR OLD.inventory_count_bags IS DISTINCT FROM NEW.inventory_count_bags THEN
        RAISE EXCEPTION 'Direct edits to last_inventory / inventory_count_bags are not allowed. Insert into coffee_inventory_history instead.';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: guard_consumable_inventory_baseline(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_consumable_inventory_baseline() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF current_setting('app.from_history_trigger', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.last_inventory_date IS DISTINCT FROM NEW.last_inventory_date
       OR OLD.inventory_count IS DISTINCT FROM NEW.inventory_count THEN
        RAISE EXCEPTION 'Direct edits to last_inventory_date / inventory_count are not allowed. Insert into consumable_inventory_history instead.';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: handle_manual_inventory_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_manual_inventory_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    v_bag_size := COALESCE(NEW.bag_size::numeric, 154);
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    NEW.inventory_lbs     := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    NEW.in_stock_lbs  := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock      := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$$;


--
-- Name: handle_new_auth_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_auth_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  UPDATE public.team
  SET auth_user_id = NEW.id
  WHERE email = NEW.email
    AND auth_user_id IS NULL;
  RETURN NEW;
END;
$$;


--
-- Name: handle_new_record(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.created_at IS NULL THEN NEW.created_at := NOW(); END IF;
    IF NEW.updated_at IS NULL THEN NEW.updated_at := NOW(); END IF;
    -- Protect company_id on UPDATE (AppSheet wipeout fix).
    -- Wrapped in EXCEPTION for tables that don't have company_id.
    IF TG_OP = 'UPDATE' THEN
        BEGIN
            IF NEW.company_id IS NULL THEN
                NEW.company_id := OLD.company_id;
            END IF;
        EXCEPTION WHEN undefined_column THEN
            NULL;
        END;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: handle_order_detail_logic(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_order_detail_logic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: handle_updated_at_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_updated_at_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: handle_updated_record(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_updated_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF current_setting('app.skip_audit', TRUE) = 'true' THEN
        RETURN NEW;
    END IF;
    NEW.updated_at := NOW();
    BEGIN
        IF NEW.company_id IS NULL THEN
            NEW.company_id := OLD.company_id;
        END IF;
    EXCEPTION WHEN undefined_column THEN
        NULL;
    END;
    RETURN NEW;
END;
$$;


--
-- Name: merge_products(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.merge_products(p_keep_id text, p_kill_id text) RETURNS text
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


--
-- Name: next_po_number(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_po_number(p_facility_id text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  current_year text := to_char(now(), 'YYYY');
  next_num     integer;
BEGIN
  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(split_part(po_number, '-', 3), '\D', '', 'g'), '')::integer
  ), 0) + 1
    INTO next_num
    FROM shipment_received
   WHERE facility_id = p_facility_id
     AND po_number LIKE 'PO-' || current_year || '-%';

  RETURN 'PO-' || current_year || '-' || lpad(next_num::text, 3, '0');
END;
$$;


--
-- Name: nudge_all_inventory(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.nudge_all_inventory() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 1. Nudge Coffee Inventory based on Facility Time Zone
    -- We only update rows if the current hour in THAT facility is Midnight (0)
    UPDATE public.coffee_inventory ci
    SET updated_at = NOW()
    FROM public.facilities f
    WHERE ci.facility_id = f.facility_id
      -- This check ensures we only nudge if it's currently Midnight at the facility
      AND EXTRACT(HOUR FROM (NOW() AT TIME ZONE f.time_zone)) = 0;

    -- 2. Nudge Consumable Inventory (Bags/Labels) 
    UPDATE public.consumable_inventory c
    SET updated_at = NOW()
    FROM public.facilities f
    WHERE c.facility_id = f.facility_id
      AND EXTRACT(HOUR FROM (NOW() AT TIME ZONE f.time_zone)) = 0;
END;
$$;


--
-- Name: process_company_signup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_company_signup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_company_id    TEXT := gen_random_uuid()::text;
    v_facility_id   TEXT := gen_random_uuid()::text;
    v_team_id       TEXT := gen_random_uuid()::text;
    v_sub_id        TEXT := gen_random_uuid()::text;
    v_param         RECORD;
BEGIN
    -- Safety: ensure defaults for columns AppSheet may send as NULL
    NEW.id        := COALESCE(NEW.id, gen_random_uuid()::text);
    NEW.processed := COALESCE(NEW.processed, FALSE);

    -- 1. Create company
    INSERT INTO public.companies (company_id, company_name, created_by)
    VALUES (v_company_id, NEW.company_name, v_team_id);

    -- 2. Create facility
    INSERT INTO public.facilities (facility_id, company_id, facility_name, time_zone, country_code, created_by)
    VALUES (v_facility_id, v_company_id, NEW.facility_name, NEW.timezone, NEW.country_code, v_team_id);

    -- 3. Create team member (company_admin)
    INSERT INTO public.team (team_member_id, name, email, company_id, facility_id, role, onboarding_completed, first_app_open_at, created_by)
    VALUES (v_team_id, NEW.admin_name, NEW.email, v_company_id, v_facility_id, 'company_admin', FALSE, NULL, v_team_id);

    -- 4. Seed company_parameters from standard_parameters
    FOR v_param IN SELECT parameters_id, text_value, amount, parameter FROM public.standard_parameters
    LOOP
        INSERT INTO public.company_parameters
          (company_id, facility_id, parameter_id, value, value_number, display_name, created_by)
        VALUES
          (v_company_id, v_facility_id, v_param.parameters_id,
           v_param.text_value, v_param.amount, v_param.parameter, v_team_id);
    END LOOP;

    -- 5. Provision Shipment Order Guide singleton row for this facility
    INSERT INTO public.recent_coffee_order
      (recent_coffee_order_id, company_id, facility_id,
       total_pallets, lbs_ordered, recommended_pallets, bags_left, created_by)
    VALUES
      (gen_random_uuid()::text, v_company_id, v_facility_id,
       0, 0, 0, 0, v_team_id);

    -- 6. Create 14-day trialing subscription (no Stripe customer yet)
    INSERT INTO public.subscriptions
      (subscription_id, company_id, plan_id, status, trial_end, created_by)
    VALUES
      (v_sub_id, v_company_id, 'starter', 'trialing',
       now() + interval '14 days', v_team_id);

    -- 7. Mark processed
    NEW.processed := TRUE;
    RETURN NEW;

EXCEPTION WHEN OTHERS THEN
    NEW.error_message := SQLERRM;
    NEW.processed := FALSE;
    RETURN NEW;
END;
$$;


--
-- Name: process_staged_imports(text, text, text, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_staged_imports(p_import_id text, p_facility_id text, p_company_id text, p_create_roast_log_entries boolean DEFAULT true, p_batch_size integer DEFAULT 25) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row               RECORD;
  v_payload           jsonb;
  v_session_id        text;
  v_imported          int := 0;
  v_linked            int := 0;
  v_skipped           int := 0;
  v_profiles_imported int := 0;
  v_profiles_skipped  int := 0;
  v_errors            text[] := '{}';
  v_existing_count    int;
  v_session_ids       text[] := '{}';
  v_created_log_ids   text[] := '{}';
  v_new_log_id        text;
  v_remaining         int;
BEGIN
  -- Count rows still to process BEFORE we pick this batch (including the batch
  -- itself — we'll subtract after to decide whether there are more).
  SELECT COUNT(*) INTO v_remaining
  FROM staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  IF v_remaining = 0 THEN
    -- Nothing left — mark completed (idempotent finish).
    UPDATE roastmaster_imports SET
      status = 'completed',
      completed_at = COALESCE(completed_at, now())
    WHERE import_id = p_import_id AND status <> 'completed';

    RETURN jsonb_build_object(
      'has_more',           false,
      'batch_processed',    0,
      'imported',           0,
      'linked',             0,
      'skipped',            0,
      'profiles_imported',  0,
      'profiles_skipped',   0,
      'errors',             0
    );
  END IF;

  FOR v_row IN
    SELECT id, payload FROM staged_import_sessions
    WHERE import_id = p_import_id AND processed = false
    ORDER BY id
    LIMIT p_batch_size
  LOOP
    v_payload := v_row.payload;

    BEGIN

      IF v_payload->>'type' = 'profile_template' THEN
        SELECT COUNT(*) INTO v_existing_count
        FROM roast_sessions
        WHERE facility_id = p_facility_id
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_profiles_skipped := v_profiles_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at, roaster_unit_id, profile_name,
            is_profile_template, notes
          ) VALUES (
            v_session_id, p_facility_id, p_company_id, 'completed',
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
            v_payload->>'name',
            true,
            'Profile template imported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
          );

          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              p_facility_id,
              now()
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          v_session_ids := array_append(v_session_ids, v_session_id);
          v_profiles_imported := v_profiles_imported + 1;
        END IF;

      ELSE
        SELECT COUNT(*) INTO v_existing_count
        FROM roast_sessions
        WHERE facility_id = p_facility_id
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_skipped := v_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at,
            green_weight_lbs, roasted_weight_lbs,
            charge_weight_id, origin_id, roaster_unit_id, profile_name,
            agtron_color, ambient_temp, ambient_humidity,
            post_moisture, post_density, roast_degree, rating,
            notes
          ) VALUES (
            v_session_id, p_facility_id, p_company_id, 'completed',
            (v_payload->>'started_at')::timestamptz,
            COALESCE((v_payload->>'ended_at')::timestamptz, (v_payload->>'started_at')::timestamptz),
            (v_payload->>'charge_weight_lbs')::numeric,
            (v_payload->>'roasted_weight_lbs')::numeric,
            v_payload->>'charge_weight_id',
            v_payload->>'origin_id',
            NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
            v_payload->>'profile_name',
            (v_payload->>'agtron_color')::numeric,
            (v_payload->>'ambient_temp')::numeric,
            (v_payload->>'ambient_humidity')::numeric,
            (v_payload->>'post_moisture')::numeric,
            (v_payload->>'post_density')::numeric,
            v_payload->>'roast_degree',
            (v_payload->>'rating')::integer,
            CASE
              WHEN v_payload->>'roast_notes' IS NOT NULL AND v_payload->>'roast_notes' != ''
              THEN (v_payload->>'roast_notes') || E'\n\nImported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
              ELSE 'Imported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
            END
          );

          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              p_facility_id,
              (v_payload->>'started_at')::timestamptz + ((n->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          IF v_payload->'events' IS NOT NULL AND jsonb_array_length(v_payload->'events') > 0 THEN
            INSERT INTO roast_events (session_id, elapsed_secs, event_type, label, facility_id, recorded_at)
            SELECT
              v_session_id,
              (e->>'elapsed_secs')::numeric,
              CASE lower(trim(e->>'label'))
                WHEN 'first crack'       THEN 'first_crack_start'
                WHEN '1c start'          THEN 'first_crack_start'
                WHEN 'first crack start' THEN 'first_crack_start'
                WHEN 'first crack end'   THEN 'first_crack_end'
                WHEN '1c end'            THEN 'first_crack_end'
                WHEN 'second crack'      THEN 'second_crack_start'
                WHEN '2c start'          THEN 'second_crack_start'
                WHEN 'second crack start' THEN 'second_crack_start'
                WHEN 'second crack end'  THEN 'second_crack_end'
                WHEN '2c end'            THEN 'second_crack_end'
                WHEN 'turning point'     THEN 'turning_point'
                WHEN 'charge'            THEN 'charge'
                WHEN 'drop'              THEN 'drop'
                WHEN 'yellowing'         THEN 'yellowing'
                WHEN 'maillard'          THEN 'maillard'
                ELSE 'custom'
              END,
              e->>'label',
              p_facility_id,
              (v_payload->>'started_at')::timestamptz + ((e->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'events') AS e;
          END IF;

          IF v_payload->>'roast_log_id' IS NOT NULL AND v_payload->>'roast_log_id' != '' THEN
            UPDATE roast_log SET session_id = v_session_id
            WHERE roast_log_id = v_payload->>'roast_log_id';
            IF v_payload->>'coffee_source_id' IS NOT NULL AND v_payload->>'coffee_source_id' != '' THEN
              UPDATE roast_log SET coffee_source_id = v_payload->>'coffee_source_id'
              WHERE roast_log_id = v_payload->>'roast_log_id';
            END IF;
            v_linked := v_linked + 1;
          ELSIF p_create_roast_log_entries AND COALESCE((v_payload->>'create_log_entry')::boolean, true) THEN
            v_new_log_id := gen_random_uuid()::text;
            INSERT INTO roast_log (
              roast_log_id, origin_id, coffee_source_id,
              charge_weight, charge_weight_lbs,
              roast_date, "charged?", roaster_unit_id, session_id,
              measured_roasted_weight, profile_name,
              facility_id, company_id
            ) VALUES (
              v_new_log_id,
              v_payload->>'origin_id',
              NULLIF(v_payload->>'coffee_source_id', ''),
              v_payload->>'charge_weight_id',
              (v_payload->>'charge_weight_lbs')::numeric,
              ((v_payload->>'started_at')::timestamptz)::date,
              true,
              NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
              v_session_id,
              (v_payload->>'roasted_weight_lbs')::numeric,
              v_payload->>'profile_name',
              p_facility_id,
              p_company_id
            );
            v_created_log_ids := array_append(v_created_log_ids, v_new_log_id);
          END IF;

          v_session_ids := array_append(v_session_ids, v_session_id);
          v_imported := v_imported + 1;
        END IF;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'rm_pk=' || COALESCE(v_payload->>'rm_pk', '?') || ': ' || SQLERRM);
    END;

    UPDATE staged_import_sessions SET processed = true WHERE id = v_row.id;
  END LOOP;

  -- How many unprocessed rows remain after this batch?
  SELECT COUNT(*) INTO v_remaining
  FROM staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  -- Accumulate counts and arrays into roastmaster_imports.
  -- If this is the last batch (v_remaining = 0), mark completed and clean up.
  UPDATE roastmaster_imports SET
    sessions_imported   = COALESCE(sessions_imported,   0) + v_imported,
    sessions_linked     = COALESCE(sessions_linked,     0) + v_linked,
    sessions_skipped    = COALESCE(sessions_skipped,    0) + v_skipped,
    profiles_imported   = COALESCE(profiles_imported,   0) + v_profiles_imported,
    profiles_skipped    = COALESCE(profiles_skipped,    0) + v_profiles_skipped,
    error_count         = COALESCE(error_count,         0) + COALESCE(array_length(v_errors, 1), 0),
    errors              = CASE
                            WHEN array_length(v_errors, 1) > 0
                            THEN to_jsonb((
                              SELECT array_agg(e) FROM (
                                SELECT jsonb_array_elements_text(COALESCE(errors, '[]'::jsonb))
                                UNION ALL
                                SELECT unnest(v_errors)
                              ) t(e)
                              LIMIT 50
                            ))
                            ELSE COALESCE(errors, '[]'::jsonb)
                          END,
    session_ids         = CASE
                            WHEN array_length(v_session_ids, 1) > 0
                            THEN COALESCE(session_ids, ARRAY[]::text[]) || v_session_ids
                            ELSE session_ids
                          END,
    created_log_ids     = CASE
                            WHEN array_length(v_created_log_ids, 1) > 0
                            THEN COALESCE(created_log_ids, ARRAY[]::text[]) || v_created_log_ids
                            ELSE created_log_ids
                          END,
    status              = CASE WHEN v_remaining = 0 THEN 'completed' ELSE status END,
    completed_at        = CASE WHEN v_remaining = 0 THEN now() ELSE completed_at END
  WHERE import_id = p_import_id;

  -- Clean up staged rows only when fully done.
  IF v_remaining = 0 THEN
    DELETE FROM staged_import_sessions WHERE import_id = p_import_id;
  END IF;

  RETURN jsonb_build_object(
    'has_more',          v_remaining > 0,
    'batch_processed',   v_imported + v_skipped + v_profiles_imported + v_profiles_skipped,
    'imported',          v_imported,
    'linked',            v_linked,
    'skipped',           v_skipped,
    'profiles_imported', v_profiles_imported,
    'profiles_skipped',  v_profiles_skipped,
    'errors',            COALESCE(array_length(v_errors, 1), 0)
  );
END;
$$;


--
-- Name: propagate_coffee_cost_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_coffee_cost_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    -- 1. Performance Check
    IF NEW.latest_cost IS NOT DISTINCT FROM OLD.latest_cost THEN
        RETURN NEW;
    END IF;

    -- 2. "Touch" the Components
    -- We just update 'updated_at'. This is enough to fire the 
    -- 'sync_recipe_component_costs' trigger, which will see the 
    -- new inventory cost and recalculate the math automatically.
    UPDATE recipe_components rc
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE rc.recipe_id = rr.recipe_id
      AND rc.coffee_item = NEW.origin_id
      AND rr.facility_id = NEW.facility_id; -- [FIX] Facility Scope

    -- 3. Touch the Products (to sum up the new component costs)
    UPDATE products p
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE p.recipe_id = rr.recipe_id
      AND rr.facility_id = NEW.facility_id
      AND p.company_id = NEW.company_id;

    RETURN NEW;
END;$$;


--
-- Name: propagate_coffee_purchase_to_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_coffee_purchase_to_orders() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.cost_lb IS NOT DISTINCT FROM NEW.cost_lb THEN
        RETURN NULL;
    END IF;

    IF COALESCE(NEW.cost_lb, 0) = 0 THEN RETURN NULL; END IF;

    -- Get date_received — skip if shipment is voided
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;

    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    -- Find the NEXT non-voided received shipment for this origin + facility
    SELECT sr.date_received INTO v_next_date
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = NEW.origin
       AND cp.facility_id   = NEW.facility_id
       AND sr.date_received  IS NOT NULL
       AND sr.date_received   > v_this_date
       AND cp.origin_purchase_id != NEW.origin_purchase_id
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC
     LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id,
                        od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o          ON o.order_id   = od.order_id
          JOIN public.products p        ON p.product_id = od.product_id
          JOIN public.recipe_components rc
               ON rc.recipe_id   = p.recipe_id AND rc.facility_id = od.facility_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND rc.coffee_item     = NEW.origin
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id, v_rec.facility_id, v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;


--
-- Name: propagate_coffee_source_bag_size(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_coffee_source_bag_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN
    -- Skip if bag_size didn't change or has no value to propagate
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NEW;
    END IF;
    IF NEW.bag_size IS NULL THEN
        RETURN NEW;
    END IF;

    -- Update coffee_inventory (operative bag size for the origin category)
    FOR r IN
        SELECT DISTINCT p.origin, p.facility_id
        FROM public.coffee_inventory_purchased p
        WHERE p.coffee_source_id = NEW.coffee_source_id
          AND p.facility_id IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = NEW.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    -- Update all historical purchases: fix display bag_size and recalculate lbs ordered.
    -- amount = bags_ordered * bag_size is the source of truth for lbs.
    -- This also triggers the cost cascade (shipping allocation recalculates across corrected lbs).
    UPDATE public.coffee_inventory_purchased
    SET bag_size = NEW.bag_size,
        amount   = bags_ordered * NEW.bag_size::numeric
    WHERE coffee_source_id = NEW.coffee_source_id
      AND bags_ordered IS NOT NULL;

    RETURN NEW;
END;
$$;


--
-- Name: propagate_consumable_bom_to_product(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_consumable_bom_to_product() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_product_id text;
BEGIN
    -- On DELETE, NEW is null — use OLD. Otherwise use NEW.
    IF TG_OP = 'DELETE' THEN
        v_product_id := OLD.product_id;
    ELSE
        v_product_id := NEW.product_id;
    END IF;

    -- Touch the parent product row. This fires trg_update_product_cogs
    -- (BEFORE UPDATE on products), which recalculates total_unit_cogs.
    UPDATE public.products
    SET updated_at = now()
    WHERE product_id = v_product_id;

    RETURN NULL;
END;
$$;


--
-- Name: propagate_consumable_cost_to_products(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_consumable_cost_to_products() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act when the unit cost actually changed
    IF OLD.last_cost_unit IS DISTINCT FROM NEW.last_cost_unit THEN
        UPDATE public.products p
        SET updated_at = now()
        FROM public.product_consumables pc
        WHERE pc.consumable_id = NEW.consumable_inventory_id
          AND pc.product_id    = p.product_id;
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: propagate_consumable_purchase_to_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_consumable_purchase_to_orders() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_this_date  date;
    v_next_date  date;
    v_new_cost   numeric;
    v_rec        record;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.cost_unit IS NOT DISTINCT FROM NEW.cost_unit THEN
        RETURN NULL;
    END IF;

    IF COALESCE(NEW.cost_unit, 0) = 0 THEN RETURN NULL; END IF;

    -- Get date_received — skip if shipment is voided
    SELECT sr.date_received INTO v_this_date
      FROM public.shipment_received sr
     WHERE sr.shipment_id = NEW.shipment_id
       AND COALESCE(sr.voided, false) = false
     LIMIT 1;

    IF v_this_date IS NULL THEN RETURN NULL; END IF;

    -- Find the NEXT non-voided received shipment for this consumable + facility
    SELECT sr.date_received INTO v_next_date
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = NEW.consumable_inventory_item
       AND cp.facility_id               = NEW.facility_id
       AND sr.date_received              IS NOT NULL
       AND sr.date_received               > v_this_date
       AND cp.consumable_purchase_id    != NEW.consumable_purchase_id
       AND COALESCE(sr.voided, false) = false
     ORDER BY sr.date_received ASC
     LIMIT 1;

    FOR v_rec IN
        SELECT DISTINCT od.order_detail_id, od.product_id, od.facility_id,
                        od.order_date, od.quantity
          FROM public.order_details od
          JOIN public.orders o           ON o.order_id   = od.order_id
          JOIN public.product_consumables pc
               ON pc.product_id  = od.product_id AND pc.facility_id = od.facility_id
         WHERE o.order_status    != 'Canceled'
           AND od.order_date     >= v_this_date
           AND (v_next_date IS NULL OR od.order_date < v_next_date)
           AND pc.consumable_id   = NEW.consumable_inventory_item
           AND COALESCE(od.quantity, 0) > 0
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id, v_rec.facility_id, v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost * v_rec.quantity,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;


--
-- Name: propagate_price_log_to_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.propagate_price_log_to_orders() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_date_end date;
BEGIN
    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- Find the end of this entry's validity window:
    -- the date_updated of the next price log entry for this product+facility.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated
      AND (
          (NEW.facility_id IS NULL AND ppl.facility_id IS NULL)
          OR ppl.facility_id = NEW.facility_id
      );

    -- Update total_price for all eligible orders in this price's validity window.
    UPDATE public.order_details od
    SET    total_price = od.quantity * NEW.price
    FROM   public.orders o
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      AND  (NEW.facility_id IS NULL OR o.facility_id = NEW.facility_id)
      AND  COALESCE(od.quantity, 0) > 0;

    RETURN NEW;
END;
$$;


--
-- Name: provision_user_filter_rows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.provision_user_filter_rows() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Skip if no email (can't scope user rows without it)
    IF NEW.email IS NULL THEN RETURN NEW; END IF;

    -- product_filter
    INSERT INTO public.product_filter
        (products_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- sales_data_filter
    INSERT INTO public.sales_data_filter
        (sales_data_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- customer_sales_filter
    INSERT INTO public.customer_sales_filter
        (sales_filter_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    -- blending_worksheet
    INSERT INTO public.blending_worksheet
        (blending_id, company_id, facility_id, user_email, created_by)
    VALUES
        (gen_random_uuid()::text, NEW.company_id, NEW.facility_id, NEW.email, NEW.team_member_id)
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;


--
-- Name: provision_user_roaster_settings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.provision_user_roaster_settings() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_default_roaster uuid;
BEGIN
    IF NEW.email IS NOT NULL THEN
        SELECT roaster_unit_id INTO v_default_roaster
          FROM public.roaster_units
         WHERE facility_id = NEW.facility_id AND is_active = true
         ORDER BY created_at
         LIMIT 1;

        INSERT INTO public.user_roaster_settings
            (email, facility_id, company_id, roaster_unit_id)
        VALUES
            (NEW.email, NEW.facility_id, NEW.company_id, v_default_roaster)
        ON CONFLICT (email) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: push_coffee_history_to_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_coffee_history_to_parent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Set flag so the guard trigger allows this write
    PERFORM set_config('app.from_history_trigger', 'true', true);

    UPDATE coffee_inventory
    SET
        last_inventory = NEW.inventory_date,
        inventory_count_bags = NEW.bag_count,
        updated_at = NOW()
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;


--
-- Name: push_consumable_history_to_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_consumable_history_to_parent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.from_history_trigger', 'true', true);

    UPDATE consumable_inventory
    SET
        last_inventory_date = NEW.inventory_date,
        inventory_count = NEW.inventory_count,
        updated_at = NOW()
    WHERE consumable_inventory_id = NEW.consumable_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$$;


--
-- Name: recalculate_batches_since_chaff(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_batches_since_chaff(p_facility_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_last_chaff_date timestamp without time zone;
    v_count           integer;
    v_threshold       numeric;
BEGIN
    PERFORM set_config('app.skip_audit', 'true', true);

    -- 2-tier threshold lookup: company_parameters → standard_parameters
    SELECT COALESCE(
        (SELECT value_number
           FROM public.company_parameters
          WHERE parameter_id = 'xd38srqb'
            AND facility_id  = p_facility_id
            AND value_number IS NOT NULL
          LIMIT 1),
        (SELECT amount
           FROM public.standard_parameters
          WHERE parameters_id = 'xd38srqb'),
        15
    ) INTO v_threshold;

    SELECT MAX(roast_date) INTO v_last_chaff_date
    FROM public.roast_log
    WHERE facility_id = p_facility_id AND "chaff_cleaned?" = TRUE;

    IF v_last_chaff_date IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM public.roast_log
        WHERE facility_id = p_facility_id
          AND "charged?"  = TRUE
          AND roast_date  > v_last_chaff_date;

        UPDATE public.roast_log
        SET batches_since_chaff = CASE
                WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
                ELSE NULL
            END,
            chaff_due = CASE
                WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date
                     THEN (v_count >= v_threshold)
                ELSE NULL
            END
        WHERE facility_id = p_facility_id
          AND (
              batches_since_chaff IS DISTINCT FROM CASE
                  WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date THEN v_count
                  ELSE NULL
              END
              OR
              chaff_due IS DISTINCT FROM CASE
                  WHEN "charged?" = TRUE AND roast_date > v_last_chaff_date
                       THEN (v_count >= v_threshold)
                  ELSE NULL
              END
          );
    ELSE
        UPDATE public.roast_log
        SET batches_since_chaff = NULL,
            chaff_due           = NULL
        WHERE facility_id = p_facility_id
          AND (batches_since_chaff IS NOT NULL OR chaff_due IS NOT NULL);
    END IF;
END;
$$;


--
-- Name: recalculate_consumables_on_order_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_consumables_on_order_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
    v_facility_id TEXT;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Only recalculate when cancellation status actually changes
    IF (OLD.order_status = 'Canceled' AND NEW.order_status != 'Canceled')
       OR (OLD.order_status != 'Canceled' AND NEW.order_status = 'Canceled') THEN

        -- Find all consumables affected by products in this order
        FOR r IN
            SELECT DISTINCT pc.consumable_id
            FROM order_details od
            JOIN product_consumables pc ON od.product_id = pc.product_id
            WHERE od.order_id = NEW.order_id
        LOOP
            -- Touch the row to fire trg_update_consumable_ordering
            -- which recalculates in_stock and to_order from scratch
            UPDATE consumable_inventory
            SET updated_at = NOW()
            WHERE consumable_inventory_id = r.consumable_id
              AND facility_id = v_facility_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: recalculate_green_purchasing_metrics(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_green_purchasing_metrics(p_facility_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_ordered_lbs     NUMERIC;
    v_total_ordered_bags    NUMERIC;
    v_total_to_order_bags   NUMERIC;
    v_current_shipment_id   TEXT;
BEGIN
    -- 1. Get current_shipment_id from recent_coffee_order
    SELECT current_shipment_id INTO v_current_shipment_id
    FROM public.recent_coffee_order
    WHERE facility_id = p_facility_id;

    -- 2. Sum lbs and bags from coffee_inventory_purchased for that shipment
    SELECT
        COALESCE(SUM(amount), 0),
        COALESCE(SUM(bags_ordered), 0)
    INTO v_total_ordered_lbs, v_total_ordered_bags
    FROM public.coffee_inventory_purchased
    WHERE shipment_id = v_current_shipment_id
      AND facility_id = p_facility_id;

    -- 3. Sum to_order_bags from coffee_inventory (recommended_pallets unchanged)
    SELECT COALESCE(SUM(to_order_bags), 0)
    INTO v_total_to_order_bags
    FROM public.coffee_inventory
    WHERE facility_id = p_facility_id;

    -- 4. Update recent_coffee_order
    UPDATE public.recent_coffee_order
    SET
        lbs_ordered         = v_total_ordered_lbs,
        recommended_pallets = CEIL(v_total_to_order_bags / 10.0),
        bags_left           = (COALESCE(total_pallets, 0) * 10) - v_total_ordered_bags
    WHERE facility_id = p_facility_id;
END;
$$;


--
-- Name: recalculate_inventory_cost(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
    v_fallback_cost         numeric;
BEGIN
    -- 1. Resolve retention factor (facility-level via helper)
    v_retention := public.get_retention_factor(p_facility_id);

    -- 2. Weighted average green cost from most recent non-voided shipment
    WITH latest_shipment AS (
        SELECT cp.shipment_id
        FROM coffee_inventory_purchased cp
        LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
        WHERE cp.origin        = p_origin_id
          AND cp.cost_lb       > 0
          AND cp.facility_id   = p_facility_id
          AND COALESCE(sr.voided, false) = false
        ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
        LIMIT 1
    )
    SELECT
        SUM(cp.cost_lb * COALESCE(cp.amount, 0))
        / NULLIF(SUM(COALESCE(cp.amount, 0)), 0)
    INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    JOIN latest_shipment ls
      ON (cp.shipment_id = ls.shipment_id)
      OR (cp.shipment_id IS NULL AND ls.shipment_id IS NULL)
    WHERE cp.origin      = p_origin_id
      AND cp.cost_lb     > 0
      AND cp.facility_id = p_facility_id;

    -- 3. Most recent non-voided shipment shipping cost
    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin      = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
      AND COALESCE(sr.voided, false) = false
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    -- 4. Fallback cost if no shipment green cost found
    IF v_latest_green_cost = 0 THEN
        SELECT ci.fallback_cost INTO v_fallback_cost
        FROM public.coffee_inventory ci
        WHERE ci.origin_id   = p_origin_id
          AND ci.facility_id = p_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            UPDATE public.coffee_inventory
               SET last_cost_lb       = NULL,
                   last_shipping_cost = NULL,
                   latest_cost        = v_fallback_cost
             WHERE origin_id   = p_origin_id
               AND facility_id = p_facility_id;
            RETURN;
        END IF;
    END IF;

    -- 5. Normal shipment path
    IF v_retention > 0 THEN
      v_final_landed_cost := (v_latest_green_cost + v_latest_shipping_cost) / v_retention;
    ELSE
      v_final_landed_cost := 0;
    END IF;

    UPDATE public.coffee_inventory
       SET last_cost_lb        = v_latest_green_cost,
           last_shipping_cost  = v_latest_shipping_cost,
           latest_cost         = v_final_landed_cost
     WHERE origin_id   = p_origin_id
       AND facility_id = p_facility_id;
END;
$$;


--
-- Name: recompute_all_customer_cadence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recompute_all_customer_cadence() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  WITH per_customer AS (
    SELECT
      c.customer_id,
      c.facility_id,
      -- avg gap in weeks across 180d window, NULL when <2 orders.
      COALESCE(
        (
          SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1)
          FROM (
            SELECT order_date,
                   LAG(order_date) OVER (ORDER BY order_date) AS prev_date
            FROM public.orders
            WHERE orders.customer_id = c.customer_id
              AND orders.facility_id = c.facility_id
              AND orders.order_status != 'Canceled'
              AND orders.order_date > (CURRENT_DATE - INTERVAL '180 days')
          ) sub
          WHERE prev_date IS NOT NULL
        ),
        0
      ) AS avg_int,
      -- latest non-Canceled order at this facility, all-time
      (
        SELECT order_date
        FROM public.orders
        WHERE orders.customer_id = c.customer_id
          AND orders.facility_id = c.facility_id
          AND orders.order_status != 'Canceled'
        ORDER BY order_date DESC
        LIMIT 1
      ) AS latest_order_date,
      (
        SELECT order_id
        FROM public.orders
        WHERE orders.customer_id = c.customer_id
          AND orders.facility_id = c.facility_id
          AND orders.order_status != 'Canceled'
        ORDER BY order_date DESC
        LIMIT 1
      ) AS latest_order_id
    FROM public.customers c
    WHERE c.is_active = true
  )
  UPDATE public.customers c
  SET
    avg_interval_wks = pc.avg_int,
    effective_interval_wks = COALESCE(
      c.acct_management_interval_wks,
      CASE WHEN pc.avg_int > 0 THEN GREATEST(1, pc.avg_int) ELSE NULL END
    ),
    last_order_date = pc.latest_order_date,
    last_order_id = pc.latest_order_id,
    days_since_last_order = CASE WHEN pc.latest_order_date IS NULL THEN NULL
                                 ELSE (CURRENT_DATE - pc.latest_order_date)::numeric END,
    weeks_since_last_order = CASE WHEN pc.latest_order_date IS NULL THEN NULL
                                  ELSE CEIL((CURRENT_DATE - pc.latest_order_date) / 7.0) END
  FROM per_customer pc
  WHERE c.customer_id = pc.customer_id
    AND c.facility_id = pc.facility_id;
END;
$$;


--
-- Name: refresh_consumable_cost_from_fallback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_consumable_cost_from_fallback() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act when no real purchase cost exists for this consumable+facility
    IF NOT EXISTS (
        SELECT 1
        FROM   consumable_inventory_purchased cp
        WHERE  cp.consumable_inventory_item = NEW.consumable_inventory_id
          AND  cp.facility_id = NEW.facility_id
          AND  cp.cost_unit IS NOT NULL
          AND  cp.cost_unit::text <> ''
          AND  cp.cost_unit::numeric > 0
    ) THEN
        UPDATE consumable_inventory
        SET    last_cost_unit = NULLIF(NEW.fallback_unit_cost, 0),
               updated_at     = NOW()
        WHERE  consumable_inventory_id = NEW.consumable_inventory_id
          AND  facility_id = NEW.facility_id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: refresh_demo_dates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_demo_dates() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_max_order_date   date;
  v_days             integer;    -- offset in whole days
  v_offset           interval;   -- same offset as interval (for timestamp columns)
BEGIN
  -- Skip triggers and audit for bulk date updates
  SET LOCAL session_replication_role = 'replica';
  SET LOCAL app.skip_audit = 'true';

  -- Find the most recent order_date in demo orders
  SELECT MAX(order_date) INTO v_max_order_date
  FROM public.orders
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- If no demo orders exist, nothing to do
  IF v_max_order_date IS NULL THEN
    RETURN;
  END IF;

  -- Compute offset: how many days to shift forward so the newest order is today
  v_days   := CURRENT_DATE - v_max_order_date;  -- integer subtraction on date columns
  v_offset := v_days * INTERVAL '1 day';

  -- If offset is zero (already fresh), skip everything
  IF v_days = 0 THEN
    RETURN;
  END IF;

  -- ── orders ────────────────────────────────────────────────────────────────
  -- order_date is date; created_at and status_changed_at are timestamptz
  UPDATE public.orders
  SET order_date        = order_date + v_days,
      created_at        = created_at + v_offset,
      status_changed_at = status_changed_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── order_details ─────────────────────────────────────────────────────────
  -- order_date is date; created_at is timestamptz
  UPDATE public.order_details
  SET order_date  = order_date + v_days,
      created_at  = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── roast_log ─────────────────────────────────────────────────────────────
  -- roast_date is timestamp without time zone (local facility time)
  -- roast_date_utc is timestamptz; created_at is timestamptz
  UPDATE public.roast_log
  SET roast_date     = roast_date + v_offset,
      roast_date_utc = roast_date_utc + v_offset,
      created_at     = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── shipment_received ─────────────────────────────────────────────────────
  -- order_date is date; date_received is date
  UPDATE public.shipment_received
  SET order_date    = order_date + v_days,
      date_received = date_received + v_days
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── coffee_inventory_purchased ────────────────────────────────────────────
  -- created_at is timestamptz
  UPDATE public.coffee_inventory_purchased
  SET created_at = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

  -- ── coffee_inventory (last_inventory is date, set via history trigger) ────
  UPDATE public.coffee_inventory
  SET last_inventory = last_inventory + v_days
  WHERE facility_id = 'demo-kailua-roastery'
    AND last_inventory IS NOT NULL;

  -- ── consumable_inventory ──────────────────────────────────────────────────
  -- last_inventory_date is date
  UPDATE public.consumable_inventory
  SET last_inventory_date = last_inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery'
    AND last_inventory_date IS NOT NULL;

  -- ── coffee_inventory_history ──────────────────────────────────────────────
  -- inventory_date is date
  UPDATE public.coffee_inventory_history
  SET inventory_date = inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery';

  -- ── consumable_inventory_history ──────────────────────────────────────────
  -- inventory_date is date
  UPDATE public.consumable_inventory_history
  SET inventory_date = inventory_date + v_days
  WHERE facility_id = 'demo-kailua-roastery';

  -- ── products_price_log ────────────────────────────────────────────────────
  -- date_updated is date; created_at is timestamp without time zone
  UPDATE public.products_price_log
  SET date_updated = date_updated + v_days,
      created_at   = created_at + v_offset
  WHERE company_id = 'demo-aloha-coffee-roasters';

END;
$$;


--
-- Name: refresh_latest_cost_from_fallback(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_latest_cost_from_fallback() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM public.recalculate_inventory_cost(NEW.origin_id, NEW.facility_id);
    RETURN NEW;
END;
$$;


--
-- Name: refresh_needs_follow_up(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_needs_follow_up() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.customers c
    SET needs_follow_up = (
        sa.activity_category IN ('Personal Action', 'Follow Up Action')
        AND c.last_contact IS NOT NULL
        AND c.sales_person IS NOT NULL
        AND c.last_contact < CURRENT_DATE - (
            (SELECT sp.follow_up_reminder_weeks
             FROM public.sales_parameters sp
             WHERE sp.sales_person = c.sales_person
               AND sp.company_id  = c.company_id
             LIMIT 1) * 7
        )::integer
    )
    FROM public.sales_activity sa
    WHERE sa.sales_activity_id = c.sales_status;

    -- Customers with no sales_status (NULL) are never overdue
    UPDATE public.customers
    SET needs_follow_up = FALSE
    WHERE sales_status IS NULL
      AND needs_follow_up = TRUE;
END;
$$;


--
-- Name: refresh_order_graphs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_order_graphs() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY order_graphs_week;
END;
$$;


--
-- Name: refresh_par_on_bag_size_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_par_on_bag_size_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_par         NUMERIC;
    v_restock     NUMERIC;
BEGIN
    -- Only run when bag_size actually changed
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NULL;
    END IF;

    v_par     := public.calculate_par(NEW.origin_id);
    v_restock := public.calculate_restock_level(NEW.origin_id);

    UPDATE public.coffee_inventory
    SET
        par           = v_par,
        restock_level = v_restock,
        to_order_bags = GREATEST(0, COALESCE(v_par, 0) - NEW.in_stock)
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id;

    RETURN NULL;
END;
$$;


--
-- Name: refresh_sales_tracking_row(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_sales_tracking_row(p_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    r           public.sales_tracking%ROWTYPE;
    v_start     date;
    v_end       date;
    v_goal_fa   numeric;
    v_goal_pa   numeric;
    v_goal_sa   numeric;
    v_goal_fu   numeric;
    v_act_fa    integer;
    v_act_pa    integer;
    v_act_sa    integer;
    v_act_fu    integer;
    v_denials   integer;
    v_wins      integer;
BEGIN
    SELECT * INTO r FROM public.sales_tracking WHERE sales_tracking_id = p_id;

    v_start := CASE r.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN date_trunc('week', CURRENT_DATE)::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '7 days')::date
        WHEN 'This Month' THEN date_trunc('month', CURRENT_DATE)::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 month')::date
        WHEN 'This Year'  THEN date_trunc('year', CURRENT_DATE)::date
    END;

    v_end := CASE r.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN (date_trunc('week', CURRENT_DATE) + interval '6 days')::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Month' THEN (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Year'  THEN (date_trunc('year', CURRENT_DATE) + interval '1 year' - interval '1 day')::date
    END;

    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = r.sales_person AND company_id = r.company_id
    ORDER BY sales_goal_id LIMIT 1;

    SELECT COUNT(*) INTO v_act_fa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'First Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_pa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Personal Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_sa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Signed Account'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_fu
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Follow Up Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_denials
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Denial'
      AND sn.date BETWEEN v_start AND v_end;

    -- win_count: all-time signed accounts (no period filter)
    SELECT COUNT(*) INTO v_wins
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Signed Account';

    UPDATE public.sales_tracking SET
        first_actions_taken     = v_act_fa::text || '/' ||
                                  ROUND(v_goal_fa * CASE r.period
                                      WHEN 'Today'      THEN 1
                                      WHEN 'This Week'  THEN 5
                                      WHEN 'Last Week'  THEN 5
                                      WHEN 'This Month' THEN 5.0 * 52 / 12
                                      WHEN 'Last Month' THEN 5.0 * 52 / 12
                                      WHEN 'This Year'  THEN 5.0 * 52
                                  END)::text,
        personal_actions_taken  = v_act_pa::text || '/' ||
                                  ROUND(v_goal_pa * CASE r.period
                                      WHEN 'Today'      THEN 1.0 / 5
                                      WHEN 'This Week'  THEN 1
                                      WHEN 'Last Week'  THEN 1
                                      WHEN 'This Month' THEN 52.0 / 12
                                      WHEN 'Last Month' THEN 52.0 / 12
                                      WHEN 'This Year'  THEN 52
                                  END)::text,
        deals_signed            = v_act_sa::text || '/' ||
                                  ROUND(v_goal_sa * CASE r.period
                                      WHEN 'Today'      THEN 1.0 / 5
                                      WHEN 'This Week'  THEN 1
                                      WHEN 'Last Week'  THEN 1
                                      WHEN 'This Month' THEN 52.0 / 12
                                      WHEN 'Last Month' THEN 52.0 / 12
                                      WHEN 'This Year'  THEN 52
                                  END)::text,
        follow_up_actions_taken = v_act_fu::text || '/' ||
                                  ROUND(v_goal_fu * CASE r.period
                                      WHEN 'Today'      THEN 1
                                      WHEN 'This Week'  THEN 5
                                      WHEN 'Last Week'  THEN 5
                                      WHEN 'This Month' THEN 5.0 * 52 / 12
                                      WHEN 'Last Month' THEN 5.0 * 52 / 12
                                      WHEN 'This Year'  THEN 5.0 * 52
                                  END)::text,
        denials                 = v_denials,
        win_count               = v_wins
    WHERE sales_tracking_id = p_id;
END;
$$;


--
-- Name: reminder_candidates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reminder_candidates() RETURNS TABLE(customer_id text, company_id text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT c.customer_id, c.company_id
  FROM public.customers c
  WHERE c.management_type = 'Customer-Initiated with Reminders'
    AND c.order_reminders_unsubscribed IS NULL
    AND (c.reminder_snoozed_until IS NULL OR c.reminder_snoozed_until < CURRENT_DATE)
    AND (c.last_reminder_sent_at IS NULL OR c.last_reminder_sent_at < now() - interval '24 hours')
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.is_active = true
    AND c.email IS NOT NULL
    AND c.email_bounced_at IS NULL  -- NEW: skip bouncing addresses
    AND c.company_id IS NOT NULL
    AND c.last_order_date
        + (c.effective_interval_wks || ' weeks')::interval
        - (
            COALESCE(
              (SELECT cp.value_number::integer FROM public.company_parameters cp
                 WHERE cp.parameter_id = 'reminder_lead_days'
                   AND cp.facility_id = c.facility_id
                   AND cp.value_number IS NOT NULL LIMIT 1),
              (SELECT sp.amount::integer FROM public.standard_parameters sp
                 WHERE sp.parameters_id = 'reminder_lead_days' LIMIT 1),
              3
            ) || ' days'
        )::interval
        <= CURRENT_DATE;
$$;


--
-- Name: set_order_status_changed_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_order_status_changed_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN
        NEW.status_changed_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: set_roast_measured_weight(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_roast_measured_weight(p_roast_log_id text, p_measured_weight numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_session_id text;
BEGIN
  -- Update the log row
  UPDATE public.roast_log
     SET measured_roasted_weight = p_measured_weight
   WHERE roast_log_id = p_roast_log_id
  RETURNING session_id INTO v_session_id;

  -- Mirror onto the linked session so downstream queries that read from
  -- roast_sessions (reports, AppSheet, etc.) see the same value.
  IF v_session_id IS NOT NULL THEN
    UPDATE public.roast_sessions
       SET roasted_weight_lbs = p_measured_weight
     WHERE session_id = v_session_id;
  END IF;
END;
$$;


--
-- Name: snapshot_completed_roast_weeks(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.snapshot_completed_roast_weeks() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_fac              RECORD;
    v_tz               text;
    v_reset_day        integer;
    v_today            date;
    v_week_start       date;
    v_prev_week_start  date;
    v_prev_order_start date;
    v_capacity_hrs     numeric;
    v_retention        numeric;
BEGIN
    FOR v_fac IN SELECT facility_id, company_id FROM public.facilities LOOP

        v_tz := COALESCE(
            (SELECT NULLIF(time_zone, '') FROM public.facilities WHERE facility_id = v_fac.facility_id),
            'UTC');

        v_today := (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date;

        -- Roast week reset day (default Thursday = 4)
        v_reset_day := COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = v_fac.facility_id
              LIMIT 1),
            (SELECT amount::integer FROM public.standard_parameters
              WHERE parameters_id = 'RF1iFWjOh7' LIMIT 1),
            4);

        -- Current roast week start
        v_week_start := v_today
            - ((EXTRACT(dow FROM v_today)::integer - v_reset_day + 7) % 7);

        -- Only proceed if today IS the first day of a new week (week just flipped)
        IF v_today <> v_week_start THEN CONTINUE; END IF;

        v_prev_week_start := v_week_start - 7;

        -- Skip if already snapshotted
        IF EXISTS (
            SELECT 1 FROM public.weekly_roast_snapshot
             WHERE facility_id = v_fac.facility_id AND week_start = v_prev_week_start
        ) THEN CONTINUE; END IF;

        -- Order week reset day (default Saturday = 6)
        v_prev_order_start := v_prev_week_start
            - ((EXTRACT(dow FROM v_prev_week_start)::integer
                - COALESCE(
                    (SELECT value_number::integer FROM public.company_parameters
                      WHERE parameter_id = 'orders_reset_day' AND facility_id = v_fac.facility_id LIMIT 1),
                    (SELECT amount::integer FROM public.standard_parameters
                      WHERE parameters_id = 'orders_reset_day' LIMIT 1),
                    6)
                + 7) % 7);

        v_retention := COALESCE(
            (SELECT value_number FROM public.company_parameters
              WHERE parameter_id = '1de271df' AND facility_id = v_fac.facility_id LIMIT 1),
            0.82);

        v_capacity_hrs := COALESCE(
            (SELECT value_number FROM public.company_parameters
              WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = v_fac.facility_id LIMIT 1),
            (SELECT amount FROM public.standard_parameters
              WHERE parameters_id = 'roast_capacity_hrs' LIMIT 1),
            35);

        INSERT INTO public.weekly_roast_snapshot (
            facility_id, company_id, week_start,
            total_roasted, total_roasted_green,
            total_ordered_roasted, total_ordered_green,
            order_count, products_sold,
            roast_count, roasting_hours, capacity_pct,
            batches_since_chaff
        )
        SELECT
            v_fac.facility_id,
            v_fac.company_id,
            v_prev_week_start,
            -- roasted lbs
            COALESCE((SELECT sum(roasted_weight) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- green lbs
            COALESCE((SELECT sum(charge_weight_lbs) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- ordered roasted
            COALESCE((SELECT sum(od.roasted_weight)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0),
            -- ordered green
            COALESCE((SELECT sum(od.roasted_weight)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0)
                / NULLIF(v_retention, 0),
            -- order count
            COALESCE((SELECT count(DISTINCT order_id) FROM public.orders
                       WHERE facility_id = v_fac.facility_id
                         AND order_date >= v_prev_order_start AND order_date < v_prev_order_start + 7
                         AND order_status <> 'Canceled'), 0),
            -- products sold
            COALESCE((SELECT sum(od.quantity)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0),
            -- roast count
            COALESCE((SELECT count(*) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- roasting hours
            ROUND(
                COALESCE((SELECT count(*) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0)
                * COALESCE((
                    SELECT AVG(gap_minutes) FROM (
                        SELECT EXTRACT(EPOCH FROM (
                            roast_date - LAG(roast_date) OVER (ORDER BY roast_date)
                        )) / 60.0 AS gap_minutes
                          FROM public.roast_log
                         WHERE "charged?" = true AND facility_id = v_fac.facility_id
                           AND roast_date >= v_prev_week_start AND roast_date < v_week_start
                    ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                ), 0) / 60.0
            , 2),
            -- capacity pct
            ROUND(
                COALESCE((SELECT count(*) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0)
                * COALESCE((
                    SELECT AVG(gap_minutes) FROM (
                        SELECT EXTRACT(EPOCH FROM (
                            roast_date - LAG(roast_date) OVER (ORDER BY roast_date)
                        )) / 60.0 AS gap_minutes
                          FROM public.roast_log
                         WHERE "charged?" = true AND facility_id = v_fac.facility_id
                           AND roast_date >= v_prev_week_start AND roast_date < v_week_start
                    ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                ), 0) / 60.0
                / NULLIF(v_capacity_hrs, 0) * 100
            , 1),
            -- batches_since_chaff at week end
            (SELECT MAX(batches_since_chaff) FROM public.roast_log
              WHERE facility_id = v_fac.facility_id);

    END LOOP;
END;
$$;


--
-- Name: standing_order_candidates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.standing_order_candidates() RETURNS TABLE(customer_id text, company_id text, facility_id text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT c.customer_id, c.company_id, c.facility_id
  FROM public.customers c
  JOIN public.facilities f ON f.facility_id = c.facility_id
  WHERE c.management_type = 'Standing Order'
    AND c.is_active = true
    AND c.company_id IS NOT NULL
    AND c.facility_id IS NOT NULL
    -- Facility is currently AT midnight local time (the hour 0 in
    -- its own timezone). Default Pacific/Honolulu mirrors the
    -- existing facility_params pattern in roast_detail_by_blend.
    AND EXTRACT(HOUR FROM (now() AT TIME ZONE COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu'))) = 0
    -- Cadence reached. Same math as the reminder cron.
    AND c.last_order_date IS NOT NULL
    AND c.effective_interval_wks IS NOT NULL
    AND c.last_order_date + (c.effective_interval_wks || ' weeks')::interval <= CURRENT_DATE
    -- Skip customers that already have a Draft pending for them.
    -- One Draft at a time; operator must Confirm or Deny before
    -- another auto-create runs.
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.customer_id = c.customer_id
        AND o.facility_id = c.facility_id
        AND o.order_status = 'Draft'
    );
$$;


--
-- Name: sync_bag_size_on_shipment_received(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_bag_size_on_shipment_received() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN
    -- Only act when date_received transitions NULL → a date (shipment just received)
    IF NEW.date_received IS NULL OR OLD.date_received IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- For each coffee purchase in this shipment with a coffee_source bag_size,
    -- update the operative bag_size on the matching coffee_inventory row
    FOR r IN
        SELECT p.origin, p.facility_id, cs.bag_size
        FROM public.coffee_inventory_purchased p
        JOIN public.coffee_source cs ON p.coffee_source_id = cs.coffee_source_id
        WHERE p.shipment_id  = NEW.shipment_id
          AND p.facility_id  = NEW.facility_id
          AND cs.bag_size    IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = r.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    RETURN NEW;
END;
$$;


--
-- Name: sync_current_shipment_from_coffee_purchase(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_current_shipment_from_coffee_purchase() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_shipment_id  TEXT;
    v_new_order_date       DATE;
    v_new_created_at       TIMESTAMPTZ;
    v_cur_order_date       DATE;
    v_cur_created_at       TIMESTAMPTZ;
BEGIN
    -- Get this facility's current shipment reference
    SELECT current_shipment_id
    INTO v_current_shipment_id
    FROM public.recent_coffee_order
    WHERE facility_id = NEW.facility_id;

    -- Same shipment: adding more lines to the current one — no switch needed,
    -- trg_update_green_metrics_from_purchased handles the recalc
    IF v_current_shipment_id IS NOT DISTINCT FROM NEW.shipment_id THEN
        RETURN NEW;
    END IF;

    -- Look up new shipment's date info
    SELECT order_date, created_at
    INTO v_new_order_date, v_new_created_at
    FROM public.shipment_received
    WHERE shipment_id = NEW.shipment_id;

    -- Look up current shipment's date info (skip if no current shipment yet)
    IF v_current_shipment_id IS NOT NULL THEN
        SELECT order_date, created_at
        INTO v_cur_order_date, v_cur_created_at
        FROM public.shipment_received
        WHERE shipment_id = v_current_shipment_id;
    END IF;

    -- Switch only if new shipment is >= current (or there is no current shipment).
    -- Falls back to created_at::date when order_date is NULL.
    IF v_current_shipment_id IS NULL
       OR COALESCE(v_new_order_date, v_new_created_at::date)
          >= COALESCE(v_cur_order_date, v_cur_created_at::date)
    THEN
        UPDATE public.recent_coffee_order
        SET current_shipment_id = NEW.shipment_id
        WHERE facility_id = NEW.facility_id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: sync_item_status_on_order_status_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_item_status_on_order_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE order_details
  SET item_status = NEW.order_status
  WHERE order_id = NEW.order_id;
  RETURN NEW;
END;
$$;


--
-- Name: sync_primary_from_contact(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_primary_from_contact() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Guard against recursive trigger firing
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    IF NEW.is_primary = TRUE
       AND (OLD.is_primary IS DISTINCT FROM TRUE)
       AND NEW.customer_id IS NOT NULL
    THEN
        -- Update customer's primary_contact_id
        UPDATE public.customers
        SET primary_contact_id = NEW.contact_id
        WHERE customer_id = NEW.customer_id;

        -- Clear is_primary on all other contacts for same customer
        UPDATE public.contacts
        SET is_primary = FALSE
        WHERE customer_id = NEW.customer_id
          AND contact_id  != NEW.contact_id
          AND is_primary   = TRUE;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: sync_primary_from_customer(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_primary_from_customer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    IF NEW.primary_contact_id IS DISTINCT FROM OLD.primary_contact_id THEN
        -- Set new primary contact
        IF NEW.primary_contact_id IS NOT NULL THEN
            UPDATE public.contacts
            SET is_primary = TRUE
            WHERE contact_id = NEW.primary_contact_id;
        END IF;

        -- Clear old primary contact
        IF OLD.primary_contact_id IS NOT NULL THEN
            UPDATE public.contacts
            SET is_primary = FALSE
            WHERE contact_id = OLD.primary_contact_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: sync_product_price_from_log(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_product_price_from_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: sync_recipe_component_costs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_recipe_component_costs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_facility_id text;
BEGIN
    -- 1. Get Facility ID from the Parent Recipe
    SELECT facility_id INTO v_facility_id
    FROM roast_recipes
    WHERE recipe_id = NEW.recipe_id;

    -- 2. Handle Coffee Costs
    SELECT latest_cost * NEW.percentage
    INTO NEW.component_cost
    FROM coffee_inventory
    WHERE origin_id = NEW.coffee_item  -- [FIX] Was NEW.item_id — wrong column
      AND facility_id = v_facility_id;

    -- 3. Propagate the Facility ID to the component row
    NEW.facility_id := v_facility_id;

    RETURN NEW;
END;
$$;


--
-- Name: touch_recipe_weekly_targets_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_recipe_weekly_targets_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: touch_vmi_checkin_on_item_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_vmi_checkin_on_item_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public.vmi_checkins
     SET updated_at = NOW()
   WHERE vmi_checkin_id = COALESCE(NEW.vmi_checkin_id, OLD.vmi_checkin_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: trg_coffee_purchase_cost_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_coffee_purchase_cost_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- [FIX] Now passes (origin, facility_id) to match your new code
    PERFORM public.recalculate_inventory_cost(
        COALESCE(NEW.origin, OLD.origin),
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NEW;
END;
$$;


--
-- Name: trg_delete_session_on_log_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_delete_session_on_log_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.session_id IS NOT NULL THEN
    DELETE FROM public.roast_sessions WHERE session_id = OLD.session_id;
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: trg_do_customer_merge(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_do_customer_merge() RETURNS trigger
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


--
-- Name: trg_do_product_merge(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_do_product_merge() RETURNS trigger
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


--
-- Name: trg_fn_note_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_note_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_sales_person text;
    v_company_id   text;
    v_id           text;
BEGIN
    v_sales_person := COALESCE(NEW.sales_person, OLD.sales_person);
    v_company_id   := COALESCE(NEW.company_id,   OLD.company_id);

    SELECT sales_tracking_id INTO v_id
    FROM public.sales_tracking
    WHERE sales_person = v_sales_person AND company_id = v_company_id
    LIMIT 1;

    IF v_id IS NOT NULL THEN
        PERFORM public.refresh_sales_tracking_row(v_id);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: trg_fn_period_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_period_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start   date;
    v_end     date;
    v_goal_fa numeric;
    v_goal_pa numeric;
    v_goal_sa numeric;
    v_goal_fu numeric;
BEGIN
    v_start := CASE NEW.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN date_trunc('week', CURRENT_DATE)::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '7 days')::date
        WHEN 'This Month' THEN date_trunc('month', CURRENT_DATE)::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 month')::date
        WHEN 'This Year'  THEN date_trunc('year', CURRENT_DATE)::date
    END;

    v_end := CASE NEW.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN (date_trunc('week', CURRENT_DATE) + interval '6 days')::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Month' THEN (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Year'  THEN (date_trunc('year', CURRENT_DATE) + interval '1 year' - interval '1 day')::date
    END;

    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = NEW.sales_person AND company_id = NEW.company_id
    ORDER BY sales_goal_id LIMIT 1;

    NEW.first_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'First Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_fa * CASE NEW.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
        END)::text;

    NEW.personal_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Personal Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_pa * CASE NEW.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
        END)::text;

    NEW.deals_signed := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_sa * CASE NEW.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
        END)::text;

    NEW.follow_up_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Follow Up Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_fu * CASE NEW.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
        END)::text;

    NEW.denials := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Denial'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.win_count := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account');

    RETURN NEW;
END;
$$;


--
-- Name: trg_green_metrics_from_purchased(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_green_metrics_from_purchased() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM public.recalculate_green_purchasing_metrics(
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NULL;
END;
$$;


--
-- Name: trg_recalc_coffee_on_category_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_recalc_coffee_on_category_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_par numeric;
  v_restock numeric;
BEGIN
  IF OLD.restock_category_id IS DISTINCT FROM NEW.restock_category_id THEN
    IF pg_trigger_depth() > 1 THEN
      RETURN NEW;
    END IF;

    PERFORM set_config('app.skip_coffee_recalc', 'true', true);

    DECLARE
      v_facility_id text := NEW.facility_id;
      v_usage_direct numeric;
      v_usage_blend numeric;
      v_monthly_usage numeric;
      v_target_months numeric;
      v_reorder_months numeric;
      v_buffer numeric;
      v_bag_size numeric;
    BEGIN
      SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
      FROM roast_log rl LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      WHERE rl.origin_id = NEW.origin_id
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
        AND rl.facility_id = v_facility_id;

      SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
      FROM roast_log rl JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
      JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
      WHERE rc.coffee_item = NEW.origin_id
        AND rr.roast_type = 'Pre-Blend'
        AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
        AND rl."charged?" = true
        AND rl.facility_id = v_facility_id;

      v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

      SELECT COALESCE(rc2.target_months, 3), COALESCE(rc2.reorder_months, 1.5)
      INTO v_target_months, v_reorder_months
      FROM restock_category rc2
      WHERE rc2.restock_category_id = NEW.restock_category_id;

      IF v_target_months IS NULL THEN v_target_months := 3; END IF;
      IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

      SELECT COALESCE(
        (SELECT cp.value_number FROM company_parameters cp
         WHERE cp.parameter_id = '5131610b' AND cp.facility_id = v_facility_id LIMIT 1),
        1.3) INTO v_buffer;

      SELECT COALESCE(NEW.bag_size::numeric, 154) INTO v_bag_size;

      NEW.par := FLOOR((v_monthly_usage * v_target_months * v_buffer) / NULLIF(v_bag_size, 0));

      v_restock := CEILING((v_monthly_usage * v_reorder_months * v_buffer) / NULLIF(v_bag_size, 0));
      IF NEW.par <= 0 THEN v_restock := 0; END IF;
      NEW.restock_level := LEAST(v_restock, NEW.par);

      NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
    END;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: trg_recalc_coffee_on_nudge(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_recalc_coffee_on_nudge() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_usage_direct  numeric;
  v_usage_blend   numeric;
  v_total_usage   numeric;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_usage_direct
  FROM roast_log rl
  LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  WHERE rl.origin_id = NEW.origin_id
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
    AND rl.facility_id = NEW.facility_id;

  SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_usage_blend
  FROM roast_log rl
  JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
  JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
  WHERE rc.coffee_item = NEW.origin_id
    AND rr.roast_type = 'Pre-Blend'
    AND rl.roast_date::date >= (CURRENT_DATE - interval '92 days')
    AND rl."charged?" = true
    AND rl.facility_id = NEW.facility_id;

  v_total_usage := v_usage_direct + v_usage_blend;
  NEW.daily_usage_lbs := v_total_usage / 92.0;

  NEW.par := calculate_par(NEW.origin_id);
  NEW.restock_level := calculate_restock_level(NEW.origin_id);
  NEW.to_order := GREATEST(0, NEW.par - COALESCE(NEW.in_stock, 0));
  RETURN NEW;
END;
$$;


--
-- Name: trg_recalc_consumable_on_category_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_recalc_consumable_on_category_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Row is already committed, so calculate_consumable_par reads new category
  UPDATE consumable_inventory SET
    par = calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id),
    restock_level = calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id)
  WHERE consumable_inventory_id = NEW.consumable_inventory_id;
  RETURN NULL; -- AFTER trigger returns NULL
END;
$$;


--
-- Name: trg_roast_log_inventory_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_roast_log_inventory_update() RETURNS trigger
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


--
-- Name: trg_set_company_kyc_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_company_kyc_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;


--
-- Name: trg_set_payment_txn_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_payment_txn_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_set_product_groups_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_product_groups_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_set_restock_category_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_restock_category_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


--
-- Name: trg_set_shop_config_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_set_shop_config_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: trg_shipment_cost_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_shipment_cost_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN
    -- Only run if the cost actually changed
    IF OLD.shipping_cost_unit IS DISTINCT FROM NEW.shipping_cost_unit THEN
        
        -- [FIX] Loop through items in this shipment AND get their facility_id
        FOR r IN SELECT DISTINCT origin, facility_id 
                 FROM coffee_inventory_purchased 
                 WHERE shipment_id = NEW.shipment_id 
                   AND facility_id = NEW.facility_id
        LOOP
            -- [FIX] Pass both IDs to the calculator
            PERFORM public.recalculate_inventory_cost(r.origin, r.facility_id);
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_stamp_roasted_weight(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_stamp_roasted_weight() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_retention     numeric;
    v_charge_weight numeric;
    v_tz            text;
BEGIN
    -- Resolve charge_weight UUID → numeric
    SELECT cwo.charge_weight INTO v_charge_weight
    FROM public.charge_weight_options cwo
    WHERE cwo.id = NEW.charge_weight LIMIT 1;

    IF v_charge_weight IS NULL AND NEW.charge_weight ~ '^[0-9]+(\.[0-9]+)?$' THEN
        v_charge_weight := NEW.charge_weight::numeric;
    END IF;

    -- Stamp resolved value back onto the row
    NEW.charge_weight_lbs := v_charge_weight;

    -- Retention factor (3-tier)
    SELECT value_number INTO v_retention FROM company_parameters
    WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id LIMIT 1;
    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount INTO v_retention FROM standard_parameters WHERE parameters_id = '1de271df' LIMIT 1;
    END IF;
    IF v_retention IS NULL OR v_retention = 0 THEN v_retention := 0.82; END IF;

    NEW.roasted_weight := ROUND(COALESCE(v_charge_weight, 0) * v_retention, 2);

    -- Facility timezone
    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
    FROM public.facilities WHERE facility_id = NEW.facility_id;

    -- Stamp roast_date as facility-local time; never trust value sent by app
    IF NEW."charged?" = true AND (TG_OP = 'INSERT' OR OLD."charged?" IS DISTINCT FROM true) THEN
        NEW.roast_date     := (NOW() AT TIME ZONE v_tz)::timestamp without time zone;
        NEW.roast_date_utc := NOW();
    ELSIF NEW."charged?" = false THEN
        NEW.roast_date     := NULL;
        NEW.roast_date_utc := NULL;
    ELSIF NEW.roast_date IS NOT NULL THEN
        NEW.roast_date_utc := NEW.roast_date AT TIME ZONE v_tz;
    END IF;

    RETURN NEW;
END;
$_$;


--
-- Name: trg_sync_day_of_week_company(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_sync_day_of_week_company() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_num integer;
BEGIN
    IF NEW.day_of_week IS NOT NULL THEN
        v_num := public.day_of_week_to_number(NEW.day_of_week);
        IF v_num IS NOT NULL THEN
            NEW.value_number := v_num;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_sync_day_of_week_standard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_sync_day_of_week_standard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_num integer;
BEGIN
    IF NEW.day_of_week IS NOT NULL THEN
        v_num := public.day_of_week_to_number(NEW.day_of_week);
        IF v_num IS NOT NULL THEN
            NEW.amount := v_num;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trigger_sync_roasted_cost(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_sync_roasted_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Calculate and stamp the roasted cost using NEW values directly.
    -- In a BEFORE trigger NEW holds the incoming (not-yet-written) row data.
    -- Querying the table here would return stale (old) values.
    NEW.cost_lb_roasted := calculate_roasted_cost(
        NEW.cost_lb_green,
        COALESCE(NEW.facility_id, OLD.facility_id)
    );

    RETURN NEW;
END;
$$;


--
-- Name: trim_marketing_pageview(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trim_marketing_pageview() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.marketing_pageview
  WHERE viewed_at < NOW() - INTERVAL '180 days';
$$;


--
-- Name: update_actual_ordered_lbs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_actual_ordered_lbs() RETURNS trigger
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


--
-- Name: update_coffee_stock_purchased(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_coffee_stock_purchased() RETURNS trigger
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


--
-- Name: update_consumable_metrics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_consumable_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_baseline   DATE;
  v_received   NUMERIC;
  v_used       NUMERIC;
  v_in_stock   NUMERIC;
  v_par        NUMERIC;
  v_restock    NUMERIC;
  v_92day      NUMERIC;
BEGIN
  v_baseline := COALESCE(NEW.last_inventory_date, '2000-01-01');

  -- Units received since baseline
  SELECT COALESCE(SUM(cip.amount), 0) INTO v_received
  FROM consumable_inventory_purchased cip
  JOIN shipment_received sr ON cip.shipment_id = sr.shipment_id
  WHERE cip.consumable_inventory_item = NEW.consumable_inventory_id
    AND sr.date_received >= v_baseline
    AND (sr.voided IS NULL OR sr.voided = false);

  -- Units consumed since baseline (from order details × product BOM)
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_used
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  v_in_stock := GREATEST(0, COALESCE(NEW.inventory_count, 0) + v_received - v_used);
  NEW.in_stock := v_in_stock;

  v_par := calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id);
  v_restock := calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id);
  NEW.par := v_par;
  NEW.restock_level := v_restock;
  NEW.to_order := CASE WHEN v_in_stock <= v_restock THEN GREATEST(0, v_par - v_in_stock) ELSE 0 END;

  -- Daily usage from 92-day order history
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_92day
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN product_consumables pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := v_92day / 92.0;

  RETURN NEW;
END;
$$;


--
-- Name: update_consumable_stock(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_consumable_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r               RECORD;
    v_product_id    TEXT;
    v_facility_id   TEXT;
    v_current_stock NUMERIC;
    v_par           NUMERIC;
    v_restock_level NUMERIC;
BEGIN
    v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    FOR r IN
        SELECT consumable_id
        FROM public.product_consumables
        WHERE product_id = v_product_id
    LOOP
        v_current_stock := public.calculate_current_stock_consumables(r.consumable_id, v_facility_id);
        v_par           := public.calculate_consumable_par(r.consumable_id, v_facility_id);
        v_restock_level := public.calculate_consumable_restock_level(r.consumable_id, v_facility_id);

        UPDATE public.consumable_inventory
        SET
            in_stock      = v_current_stock,
            par           = v_par,
            restock_level = v_restock_level,
            to_order      = CASE
                                WHEN v_current_stock <= v_restock_level
                                THEN GREATEST(0, v_par - v_current_stock)
                                ELSE 0
                            END,
            updated_at    = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = v_facility_id;
    END LOOP;

    RETURN NULL;
END;
$$;


--
-- Name: update_consumable_stock_purchased(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_consumable_stock_purchased() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_stock  NUMERIC;
    v_par            NUMERIC;
    v_restock_level  NUMERIC;
    v_target_id      TEXT;
    v_facility_id    TEXT;
BEGIN
    v_target_id   := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    v_current_stock := public.calculate_current_stock_consumables(v_target_id, v_facility_id);
    v_par           := public.calculate_consumable_par(v_target_id, v_facility_id);
    v_restock_level := public.calculate_consumable_restock_level(v_target_id, v_facility_id);

    UPDATE public.consumable_inventory
    SET
        in_stock      = v_current_stock,
        par           = v_par,
        restock_level = v_restock_level,
        to_order      = CASE
                            WHEN v_current_stock <= v_restock_level
                            THEN GREATEST(0, v_par - v_current_stock)
                            ELSE 0
                        END,
        updated_at    = NOW()
    WHERE consumable_inventory_id = v_target_id
      AND facility_id = v_facility_id;

    RETURN NULL;
END;
$$;


--
-- Name: update_customer_metrics_on_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_customer_metrics_on_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_avg_interval NUMERIC;
    v_latest_order_date DATE;
    v_latest_order_id TEXT;
    v_facility_id TEXT;
BEGIN
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1)
    INTO v_avg_interval
    FROM (
        SELECT order_date, LAG(order_date) OVER (ORDER BY order_date) AS prev_date
        FROM orders
        WHERE customer_id = NEW.customer_id
          AND order_status != 'Canceled'
          AND order_date > (CURRENT_DATE - INTERVAL '180 days')
          AND facility_id = v_facility_id
    ) sub
    WHERE prev_date IS NOT NULL;

    v_avg_interval := COALESCE(v_avg_interval, 0);

    SELECT order_date, order_id
    INTO v_latest_order_date, v_latest_order_id
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id
    ORDER BY order_date DESC
    LIMIT 1;

    UPDATE customers
    SET
        last_order_id = v_latest_order_id,
        last_order_date = v_latest_order_date,
        days_since_last_order = (CURRENT_DATE - v_latest_order_date),
        weeks_since_last_order = CEIL((CURRENT_DATE - v_latest_order_date) / 7.0),
        avg_interval_wks = v_avg_interval,
        -- v_avg_interval = 0 means "no computable cadence" (0 or 1
        -- orders in 180d). Don't fake a 1-week floor — leave NULL
        -- so cadence-aware paths skip the customer.
        effective_interval_wks = COALESCE(
            acct_management_interval_wks,
            CASE WHEN v_avg_interval > 0 THEN GREATEST(1, v_avg_interval) ELSE NULL END
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id;

    RETURN NEW;
END;
$$;


--
-- Name: update_customer_sales_metrics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_customer_sales_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_customer_id  TEXT;
    v_last_contact DATE;
    v_status       TEXT;
    v_deal_closed  BOOLEAN;
BEGIN
    v_customer_id := COALESCE(NEW.customer_id, OLD.customer_id);

    -- 1. last_contact = most recent note date
    SELECT MAX(date) INTO v_last_contact
    FROM public.sales_notes
    WHERE customer_id = v_customer_id;

    -- 2. Deal state for status logic
    SELECT deal_open_closed INTO v_deal_closed
    FROM public.customers
    WHERE customer_id = v_customer_id;

    -- 3. sales_status logic (mirrors AppSheet VC exactly)
    IF v_deal_closed = FALSE THEN
        v_status := 'w5qcJV';                      -- Signed / closed
    ELSIF v_last_contact IS NULL THEN
        v_status := 'yhbGZV';                      -- New / no activity yet
    ELSE
        SELECT sales_activity_type INTO v_status
        FROM public.sales_notes
        WHERE customer_id = v_customer_id
          AND date = v_last_contact
        ORDER BY created_at DESC NULLS LAST
        LIMIT 1;
    END IF;

    UPDATE public.customers
    SET last_contact = v_last_contact,
        sales_status = v_status
    WHERE customer_id = v_customer_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: update_effective_interval_on_manual_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_effective_interval_on_manual_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Recompute when EITHER the operator override or the observed
    -- average changes. Output unit is weeks (both inputs are weeks).
    IF (OLD.acct_management_interval_wks IS DISTINCT FROM NEW.acct_management_interval_wks)
       OR (OLD.avg_interval_wks IS DISTINCT FROM NEW.avg_interval_wks) THEN

        NEW.effective_interval_wks := COALESCE(
            NEW.acct_management_interval_wks,
            GREATEST(1, FLOOR(COALESCE(NEW.avg_interval_wks, 0)))
        );

    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: update_last_coffee_cost(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_last_coffee_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_origin_id TEXT;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Identify Variables (Handles Insert/Update vs Delete)
    v_origin_id := COALESCE(NEW.origin, OLD.origin);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Call the Calculator (Passing the specific Facility ID)
    -- This matches the 2-argument version we vetted earlier.
    PERFORM public.recalculate_inventory_cost(v_origin_id, v_facility_id);
    
    RETURN NULL;
END;$$;


--
-- Name: update_last_consumable_cost(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_last_consumable_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_item_id       TEXT;
    v_facility_id   TEXT;
    v_latest_cost   NUMERIC;
    v_fallback_cost NUMERIC;
BEGIN
    v_item_id     := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Most recent landed cost (unit price + per-unit shipping) from non-voided shipment
    SELECT cp.cost_unit::numeric + COALESCE(sr.shipping_cost_unit, 0)
    INTO   v_latest_cost
    FROM   consumable_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE  cp.consumable_inventory_item = v_item_id
      AND  cp.facility_id = v_facility_id
      AND  cp.cost_unit IS NOT NULL
      AND  cp.cost_unit::text <> ''
      AND  cp.cost_unit::numeric > 0
      AND  COALESCE(sr.voided, false) = false
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC
    LIMIT 1;

    IF v_latest_cost IS NOT NULL THEN
        UPDATE consumable_inventory
        SET    last_cost_unit = v_latest_cost, updated_at = NOW()
        WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;
    ELSE
        SELECT fallback_unit_cost INTO v_fallback_cost
        FROM   consumable_inventory
        WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            UPDATE consumable_inventory
            SET    last_cost_unit = v_fallback_cost, updated_at = NOW()
            WHERE  consumable_inventory_id = v_item_id AND facility_id = v_facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: update_order_aggregates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_order_aggregates() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    target_order_id text;
    v_facility_id text; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Identify Context (Handle Insert/Update vs Delete)
    target_order_id := COALESCE(NEW.order_id, OLD.order_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Update Parent Order
    -- We re-sum the details to get the new accurate totals for THIS facility
    UPDATE public.orders
    SET 
        order_total = ( 
             SELECT COALESCE(SUM(total_price), 0) 
             FROM public.order_details 
             WHERE order_id = target_order_id
         ),
        total_weight = ( 
             SELECT COALESCE(SUM(roasted_weight), 0) 
             FROM public.order_details 
             WHERE order_id = target_order_id
         )
    WHERE order_id = target_order_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NULL;
END;
$$;


--
-- Name: update_order_metrics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_order_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    prev_date DATE;
    v_cat TEXT;
    v_area TEXT;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Grab from Customer record (Isolated by Facility)
    SELECT customer_category, sales_area 
    INTO v_cat, v_area
    FROM customers
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    NEW.customer_category := v_cat;
    NEW.area := v_area;

    -- 2. Sum up totals from "Order Details"
    -- This ensures the header is always in sync with the line items
    SELECT 
        COALESCE(SUM(total_price), 0),
        COALESCE(SUM(roasted_weight), 0)
    INTO NEW.order_total, NEW.total_weight
    FROM order_details
    WHERE order_id = NEW.order_id;

    -- 3. Find previous order date for interval calculation (Isolated by Facility)
    SELECT MAX(order_date) INTO prev_date
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_date < NEW.order_date
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    -- 4. Calculate interval math
    IF prev_date IS NOT NULL THEN
        NEW.interval_days := (NEW.order_date - prev_date);
        -- Weeks rounded to 1 decimal, minimum 1 week for managed account logic
        NEW.interval_wks := GREATEST(1, ROUND(CAST((NEW.order_date - prev_date) AS numeric) / 7.0, 1));
    ELSE
        NEW.interval_days := 0;
        NEW.interval_wks := 0;
    END IF;

    RETURN NEW;
END;$$;


--
-- Name: update_product_total_cogs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_product_total_cogs() RETURNS trigger
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


--
-- Name: update_sales_status_on_deal_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_sales_status_on_deal_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.deal_open_closed IS DISTINCT FROM NEW.deal_open_closed THEN
        IF NEW.deal_open_closed = FALSE THEN
            NEW.sales_status := 'w5qcJV';
        ELSIF NEW.last_contact IS NULL THEN
            NEW.sales_status := 'yhbGZV';
        ELSE
            SELECT sales_activity_type INTO NEW.sales_status
            FROM public.sales_notes
            WHERE customer_id = NEW.customer_id
              AND date = NEW.last_contact
            ORDER BY created_at DESC NULLS LAST
            LIMIT 1;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: update_smartroast_calibrations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_smartroast_calibrations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_brand text;
  v_model text;
  v_old_count integer;
  v_old_mean numeric;
  v_old_m2 numeric;
  v_delta numeric;
  v_delta2 numeric;
  v_company_already_contributed boolean;
BEGIN
  -- Only confirmed fires teach the model. Cancelled auto-fires are
  -- the operator saying "wrong" — they tune in the OPPOSITE direction
  -- and we don't have a great way to weight that yet.
  IF NEW.source = 'auto_cancelled' THEN RETURN NEW; END IF;
  IF NEW.peak_bt IS NULL OR NEW.cliff_rate IS NULL THEN RETURN NEW; END IF;
  IF NEW.roaster_unit_id IS NULL THEN RETURN NEW; END IF;

  -- ── Per-unit update ───────────────────────────────────────────
  -- Welford: count_new = count + 1; mean_new = mean + delta/count_new
  -- M2_new = M2 + delta * (x - mean_new); stddev = sqrt(M2 / (count-1))
  INSERT INTO roaster_unit_smartroast_calibration (
    roaster_unit_id, event_type, company_id,
    sample_count, peak_bt_avg, peak_bt_m2, cliff_rate_avg, cliff_rate_m2, last_updated
  ) VALUES (
    NEW.roaster_unit_id, NEW.event_type, NEW.company_id,
    1, NEW.peak_bt, 0, NEW.cliff_rate, 0, now()
  )
  ON CONFLICT (roaster_unit_id, event_type) DO UPDATE
  SET
    sample_count   = roaster_unit_smartroast_calibration.sample_count + 1,
    peak_bt_avg    = roaster_unit_smartroast_calibration.peak_bt_avg
                     + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                       / (roaster_unit_smartroast_calibration.sample_count + 1),
    peak_bt_m2     = roaster_unit_smartroast_calibration.peak_bt_m2
                     + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                       * (NEW.peak_bt - (
                           roaster_unit_smartroast_calibration.peak_bt_avg
                           + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                             / (roaster_unit_smartroast_calibration.sample_count + 1)
                         )),
    cliff_rate_avg = roaster_unit_smartroast_calibration.cliff_rate_avg
                     + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                       / (roaster_unit_smartroast_calibration.sample_count + 1),
    cliff_rate_m2  = roaster_unit_smartroast_calibration.cliff_rate_m2
                     + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                       * (NEW.cliff_rate - (
                           roaster_unit_smartroast_calibration.cliff_rate_avg
                           + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                             / (roaster_unit_smartroast_calibration.sample_count + 1)
                         )),
    last_updated   = now();

  -- Recompute stddev from M2 (separate update since it depends on the
  -- just-updated count + M2).
  UPDATE roaster_unit_smartroast_calibration
  SET
    peak_bt_stddev = CASE WHEN sample_count > 1
                          THEN sqrt(peak_bt_m2 / (sample_count - 1))
                          ELSE NULL END
  WHERE roaster_unit_id = NEW.roaster_unit_id AND event_type = NEW.event_type;

  -- ── Per-model update ─────────────────────────────────────────
  SELECT brand, model INTO v_brand, v_model
  FROM roaster_units WHERE roaster_unit_id = NEW.roaster_unit_id;

  IF v_brand IS NOT NULL AND v_model IS NOT NULL THEN
    -- Track contributing_companies — only bump when this company isn't
    -- already in the pool for this (brand, model, event_type).
    SELECT EXISTS (
      SELECT 1 FROM roast_smartroast_log al
      JOIN roaster_units ru ON ru.roaster_unit_id = al.roaster_unit_id
      WHERE ru.brand = v_brand AND ru.model = v_model
        AND al.event_type = NEW.event_type
        AND al.company_id = NEW.company_id
        AND al.source IN ('auto', 'manual')
        AND al.log_id <> NEW.log_id
    ) INTO v_company_already_contributed;

    INSERT INTO roaster_model_smartroast_calibration (
      brand, model, event_type,
      sample_count, peak_bt_avg, peak_bt_m2, cliff_rate_avg, cliff_rate_m2,
      contributing_companies, last_updated
    ) VALUES (
      v_brand, v_model, NEW.event_type,
      1, NEW.peak_bt, 0, NEW.cliff_rate, 0,
      1, now()
    )
    ON CONFLICT (brand, model, event_type) DO UPDATE
    SET
      sample_count   = roaster_model_smartroast_calibration.sample_count + 1,
      peak_bt_avg    = roaster_model_smartroast_calibration.peak_bt_avg
                       + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                         / (roaster_model_smartroast_calibration.sample_count + 1),
      peak_bt_m2     = roaster_model_smartroast_calibration.peak_bt_m2
                       + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                         * (NEW.peak_bt - (
                             roaster_model_smartroast_calibration.peak_bt_avg
                             + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                               / (roaster_model_smartroast_calibration.sample_count + 1)
                           )),
      cliff_rate_avg = roaster_model_smartroast_calibration.cliff_rate_avg
                       + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                         / (roaster_model_smartroast_calibration.sample_count + 1),
      cliff_rate_m2  = roaster_model_smartroast_calibration.cliff_rate_m2
                       + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                         * (NEW.cliff_rate - (
                             roaster_model_smartroast_calibration.cliff_rate_avg
                             + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                               / (roaster_model_smartroast_calibration.sample_count + 1)
                           )),
      contributing_companies = roaster_model_smartroast_calibration.contributing_companies
                                + CASE WHEN v_company_already_contributed THEN 0 ELSE 1 END,
      last_updated   = now();

    UPDATE roaster_model_smartroast_calibration
    SET
      peak_bt_stddev = CASE WHEN sample_count > 1
                            THEN sqrt(peak_bt_m2 / (sample_count - 1))
                            ELSE NULL END
    WHERE brand = v_brand AND model = v_model AND event_type = NEW.event_type;
  END IF;

  RETURN NEW;
END $$;


--
-- Name: user_facility_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.user_facility_ids() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT facility_id FROM public.team WHERE auth_user_id = auth.uid();
$$;


--
-- Name: void_shipment_cascade(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.void_shipment_cascade() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r              RECORD;
    v_bag_size     NUMERIC;
    v_current_lbs  NUMERIC;
    v_current_bags NUMERIC;
    v_par          NUMERIC;
    v_stock        NUMERIC;
BEGIN
    -- Recalculate coffee stock + COGS for all origins in this shipment
    FOR r IN
        SELECT DISTINCT origin AS origin_id, facility_id
        FROM public.coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
    LOOP
        SELECT COALESCE(bag_size::numeric, 154) INTO v_bag_size
        FROM public.coffee_inventory
        WHERE origin_id = r.origin_id AND facility_id = r.facility_id LIMIT 1;

        v_current_lbs  := public.calculate_current_stock_lbs(r.origin_id, r.facility_id);
        v_current_bags := v_current_lbs / NULLIF(v_bag_size, 0);
        v_par          := public.calculate_par(r.origin_id);

        UPDATE public.coffee_inventory SET
            in_stock_lbs  = v_current_lbs,
            in_stock      = v_current_bags,
            par           = v_par,
            to_order_bags = GREATEST(0, COALESCE(v_par, 0) - v_current_bags),
            restock_level = public.calculate_restock_level(r.origin_id),
            updated_at    = NOW()
        WHERE origin_id = r.origin_id AND facility_id = r.facility_id;

        PERFORM public.recalculate_inventory_cost(r.origin_id, r.facility_id);
    END LOOP;

    -- Recalculate consumable stock for all items in this shipment
    FOR r IN
        SELECT DISTINCT consumable_inventory_item AS consumable_id, facility_id
        FROM public.consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
    LOOP
        v_stock := public.calculate_current_stock_consumables(r.consumable_id, r.facility_id);

        UPDATE public.consumable_inventory SET
            in_stock   = v_stock,
            updated_at = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = r.facility_id;
    END LOOP;

    RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_menu (
    menu_item_id text NOT NULL,
    section text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    label text NOT NULL,
    icon text,
    target_view text NOT NULL
);


--
-- Name: bag_sizes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bag_sizes (
    bag_size_id text NOT NULL,
    label text,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    facility_id text,
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: blending_worksheet; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blending_worksheet (
    blending_id text NOT NULL,
    roast_recipe_id text,
    amount_to_blend numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    user_email text,
    blend_summary text,
    facility_id text
);


--
-- Name: channel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel (
    channel_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    channel text NOT NULL,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: charge_weight_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.charge_weight_options (
    charge_weight numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    roaster_unit_id uuid,
    label text
);


--
-- Name: chargebacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chargebacks (
    chargeback_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    payment_transaction_id uuid NOT NULL,
    order_id text,
    provider text DEFAULT 'activitypay'::text NOT NULL,
    provider_case_id text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    reason_code text,
    reason_text text,
    amount_cents bigint NOT NULL,
    due_by timestamp with time zone,
    submitted_at timestamp with time zone,
    resolved_at timestamp with time zone,
    evidence_storage_path text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT chargebacks_status_chk CHECK ((status = ANY (ARRAY['open'::text, 'evidence_submitted'::text, 'won'::text, 'lost'::text, 'accepted'::text])))
);


--
-- Name: coffee_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coffee_inventory (
    origin_id text NOT NULL,
    origin text,
    supplier_id text,
    last_inventory date,
    inventory_count_bags numeric,
    bags_ordered numeric,
    in_stock numeric,
    par numeric,
    restock_level numeric,
    inventory_lbs numeric,
    to_order numeric,
    to_order_bags numeric,
    actual_ordered_lbs numeric,
    last_cost_lb numeric,
    last_shipping_cost numeric,
    in_stock_lbs numeric,
    latest_cost numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    fallback_cost numeric,
    bag_size text,
    is_active boolean DEFAULT true NOT NULL,
    restock_category_id uuid,
    daily_usage_lbs numeric DEFAULT 0
);


--
-- Name: coffee_inventory_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coffee_inventory_history (
    history_id text NOT NULL,
    origin_id text,
    inventory_date date DEFAULT CURRENT_DATE NOT NULL,
    bag_count numeric NOT NULL,
    notes text,
    company_id text,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    updated_by text,
    facility_id text
);


--
-- Name: coffee_inventory_purchased; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coffee_inventory_purchased (
    origin_purchase_id text NOT NULL,
    shipment_id text,
    origin text,
    lot_id text,
    cost_lb numeric,
    amount numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    bags_ordered numeric,
    coffee_source_id text,
    harvest_year integer,
    bag_size text,
    ai_match_reason text,
    ai_confidence numeric,
    proposed_lot_url text,
    supplier_response_notes text,
    target_cost_lb numeric
);


--
-- Name: coffee_source; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coffee_source (
    coffee_source_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    coffee_name text NOT NULL,
    origin_id text,
    bag_size text,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    process text,
    region text,
    farm text,
    elevation text,
    certifications text[] DEFAULT '{}'::text[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    supplier_lot_url text,
    cupping_score numeric,
    varietals text[] DEFAULT '{}'::text[] NOT NULL,
    flavor_notes text[] DEFAULT '{}'::text[] NOT NULL,
    country_of_origin text,
    grade_quality text,
    grade_classification text,
    grade_screen text,
    grade_prep text,
    is_peaberry boolean DEFAULT false NOT NULL,
    grade_label text
);


--
-- Name: coffee_usage_by_month; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coffee_usage_by_month (
    coffee_usage_id text NOT NULL,
    origin text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    company_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    company_name text,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    stripe_customer_id text,
    is_demo boolean DEFAULT false NOT NULL,
    stripe_connect_account_id text
);


--
-- Name: company_kyc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_kyc (
    company_id text NOT NULL,
    status text DEFAULT 'not_started'::text NOT NULL,
    legal_name text,
    dba text,
    business_type text,
    ein_encrypted bytea,
    ein_last4 text,
    business_phone text,
    business_website text,
    industry_mcc text,
    business_address_line1 text,
    business_address_line2 text,
    business_address_city text,
    business_address_state text,
    business_address_postal text,
    business_address_country text DEFAULT 'US'::text,
    expected_monthly_volume_cents bigint,
    expected_average_ticket_cents bigint,
    rolling_reserve_pct numeric DEFAULT 0 NOT NULL,
    rolling_reserve_days integer DEFAULT 0 NOT NULL,
    submitted_at timestamp with time zone,
    reviewed_at timestamp with time zone,
    reviewed_by text,
    rejection_reason text,
    provider_submerchant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT company_kyc_business_type_chk CHECK (((business_type IS NULL) OR (business_type = ANY (ARRAY['sole_prop'::text, 'llc'::text, 's_corp'::text, 'c_corp'::text, 'partnership'::text, 'nonprofit'::text])))),
    CONSTRAINT company_kyc_reserve_pct_chk CHECK (((rolling_reserve_pct >= (0)::numeric) AND (rolling_reserve_pct <= (1)::numeric))),
    CONSTRAINT company_kyc_status_chk CHECK ((status = ANY (ARRAY['not_started'::text, 'submitted'::text, 'under_review'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: company_kyc_beneficial_owners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_kyc_beneficial_owners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    role text DEFAULT 'owner'::text NOT NULL,
    full_name text NOT NULL,
    date_of_birth date NOT NULL,
    ssn_encrypted bytea,
    ssn_last4 text,
    id_document_type text,
    id_document_country text,
    ownership_pct numeric DEFAULT 0 NOT NULL,
    address_line1 text,
    address_line2 text,
    address_city text,
    address_state text,
    address_postal text,
    address_country text DEFAULT 'US'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT company_kyc_bo_ownership_chk CHECK (((ownership_pct >= (0)::numeric) AND (ownership_pct <= (1)::numeric))),
    CONSTRAINT company_kyc_bo_role_chk CHECK ((role = ANY (ARRAY['owner'::text, 'control'::text])))
);


--
-- Name: company_kyc_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_kyc_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    document_type text NOT NULL,
    storage_path text NOT NULL,
    file_name text,
    file_size integer,
    mime_type text,
    uploaded_by text,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text
);


--
-- Name: company_parameters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_parameters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    parameter_id text,
    value text,
    value_number numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    facility_id text,
    display_name text,
    day_of_week text
);


--
-- Name: company_signup_form; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_signup_form (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    company_name text NOT NULL,
    facility_name text NOT NULL,
    timezone text NOT NULL,
    country_code text,
    admin_name text NOT NULL,
    email text NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    plan_id text NOT NULL,
    plan_name text NOT NULL,
    stripe_price_id text,
    price_monthly numeric,
    max_facilities integer,
    max_team_members integer,
    features jsonb,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    stripe_annual_price_id text,
    price_annual numeric,
    stripe_product_id text,
    can_accept_payments boolean DEFAULT false NOT NULL,
    max_roaster_units integer
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    subscription_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    company_id text NOT NULL,
    stripe_subscription_id text,
    stripe_customer_id text,
    plan_id text,
    status text DEFAULT 'trialing'::text NOT NULL,
    trial_end timestamp with time zone,
    current_period_start timestamp with time zone,
    current_period_end timestamp with time zone,
    cancel_at_period_end boolean DEFAULT false NOT NULL,
    canceled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    billing_interval text DEFAULT 'monthly'::text,
    CONSTRAINT subscriptions_status_check CHECK ((status = ANY (ARRAY['trialing'::text, 'active'::text, 'past_due'::text, 'canceled'::text, 'unpaid'::text, 'paused'::text, 'incomplete'::text])))
);


--
-- Name: company_subscription_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.company_subscription_status AS
 SELECT c.company_id,
    c.company_name,
    c.stripe_customer_id,
    s.subscription_id,
    s.plan_id,
    sp.plan_name,
    s.status,
    s.trial_end,
    s.current_period_end,
    s.cancel_at_period_end,
    s.billing_interval,
        CASE
            WHEN (s.status = ANY (ARRAY['active'::text, 'trialing'::text])) THEN true
            ELSE false
        END AS is_active
   FROM ((public.companies c
     LEFT JOIN public.subscriptions s ON ((s.company_id = c.company_id)))
     LEFT JOIN public.subscription_plans sp ON ((sp.plan_id = s.plan_id)));


--
-- Name: consumable_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumable_inventory (
    consumable_inventory_id text NOT NULL,
    consumable_inventory_item text,
    last_inventory_date date,
    inventory_count numeric,
    in_stock numeric DEFAULT 0,
    par numeric DEFAULT 0,
    restock_level numeric DEFAULT 0,
    to_order numeric DEFAULT 0,
    last_cost_unit numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    fallback_unit_cost numeric,
    is_active boolean DEFAULT true NOT NULL,
    consumable_type text,
    restock_category_id uuid,
    daily_usage numeric DEFAULT 0
);


--
-- Name: consumable_inventory_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumable_inventory_history (
    history_id text NOT NULL,
    consumable_id text,
    inventory_date date DEFAULT CURRENT_DATE NOT NULL,
    inventory_count numeric NOT NULL,
    notes text,
    company_id text,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    updated_by text,
    facility_id text
);


--
-- Name: consumable_inventory_purchased; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumable_inventory_purchased (
    consumable_purchase_id text NOT NULL,
    shipment_id text,
    consumable_inventory_item text,
    cost_unit numeric,
    amount bigint,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: consumable_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumable_type (
    consumable_type_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    consumable_type text NOT NULL,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: contact_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_role (
    contact_role_id text NOT NULL,
    contact_role text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    contact_id text NOT NULL,
    contact text,
    role text,
    email text,
    phone text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    customer_id text,
    is_primary boolean DEFAULT false,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    customer_id text NOT NULL,
    customer_category text,
    name_company text,
    acct_management_interval_wks numeric,
    management_type text,
    order_reminders_unsubscribed text,
    deal_open_closed boolean,
    sales_area text,
    sales_person text,
    email text,
    phone text,
    street text,
    city text,
    state text,
    zip text,
    tags text,
    customer_since date,
    flag boolean,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    avg_interval_wks numeric,
    last_order_id text,
    last_order_date date,
    effective_interval_wks numeric,
    days_since_last_order numeric,
    weeks_since_last_order numeric,
    country_id text,
    facility_id text,
    last_contact date,
    sales_status text,
    primary_contact_id text,
    needs_follow_up boolean DEFAULT false,
    merge_into_id text,
    is_active boolean DEFAULT true NOT NULL,
    shop_access text[],
    resale_cert_received boolean DEFAULT true NOT NULL,
    payment_terms text DEFAULT 'card'::text NOT NULL,
    street_2 text,
    billing_same_as_shipping boolean DEFAULT true NOT NULL,
    billing_address text,
    billing_address_2 text,
    billing_city text,
    billing_state text,
    billing_zip text,
    billing_country text DEFAULT 'US'::text NOT NULL,
    last_reminder_sent_at timestamp with time zone,
    reminder_snoozed_until date,
    email_bounced_at timestamp with time zone,
    email_bounce_reason text,
    CONSTRAINT customers_payment_terms_chk CHECK ((payment_terms = ANY (ARRAY['card'::text, 'net_15'::text, 'net_30'::text, 'net_60'::text])))
);


--
-- Name: contacts_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contacts_view AS
 SELECT ct.contact_id,
    ct.contact,
    ct.role,
    ct.email,
    ct.phone,
    ct.notes,
    ct.created_at,
    ct.updated_at,
    ct.created_by,
    ct.updated_by,
    ct.company_id,
    ct.facility_id,
    ct.customer_id,
    ct.is_primary,
    cust.flag AS customer_flag
   FROM (public.contacts ct
     LEFT JOIN public.customers cust ON ((cust.customer_id = ct.customer_id)));


--
-- Name: customer_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_category (
    customer_category text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text
);


--
-- Name: customer_notes_detail; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_notes_detail (
    notes_detail_id text NOT NULL,
    customer_id text,
    note text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: order_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_details (
    order_detail_id text NOT NULL,
    order_id text,
    product_id text,
    coffee_prep text,
    quantity numeric,
    item_status text DEFAULT 'Open'::text,
    previous_order_details text,
    next_order_details text,
    company_id text,
    roasted_weight double precision,
    total_price numeric,
    recipe_id text,
    order_date date,
    customer_id text,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    unit_cost_at_sale numeric,
    facility_id text,
    product_name_snapshot text
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    order_id text NOT NULL,
    customer_id text,
    order_date date,
    order_status text,
    order_notes text,
    previous_order text,
    next_order text,
    delivery_photo text,
    signature text,
    "update column" text,
    order_total numeric,
    total_weight numeric,
    interval_days integer,
    interval_wks real,
    customer_category text,
    area text,
    company_id text,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    facility_id text,
    status_changed_at timestamp with time zone,
    shopify_order_id text,
    shop_order_id text,
    tax_rate numeric,
    tax_amount numeric,
    shop_order_ref text,
    payment_status text,
    payment_transaction_id text,
    payment_amount_cents integer,
    paid_at timestamp with time zone,
    payment_failed_at timestamp with time zone,
    payment_failure_reason text,
    ship_to_name text,
    ship_to_phone text,
    ship_to_email text,
    ship_to_street text,
    ship_to_street_2 text,
    ship_to_city text,
    ship_to_state text,
    ship_to_zip text,
    ship_to_country text,
    bill_to_name text,
    bill_to_phone text,
    bill_to_email text,
    bill_to_address text,
    bill_to_address_2 text,
    bill_to_city text,
    bill_to_state text,
    bill_to_zip text,
    bill_to_country text,
    receipt_token text,
    created_from_vmi_checkin_id uuid,
    CONSTRAINT orders_payment_status_chk CHECK (((payment_status IS NULL) OR (payment_status = ANY (ARRAY['pending'::text, 'authorized'::text, 'captured'::text, 'failed'::text, 'refunded'::text, 'partially_refunded'::text, 'voided'::text]))))
);


--
-- Name: customer_profitability; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.customer_profitability WITH (security_invoker='true') AS
 WITH order_revenue AS (
         SELECT order_details.order_id,
            sum(order_details.total_price) AS order_total,
            sum(order_details.unit_cost_at_sale) AS order_cogs
           FROM public.order_details
          GROUP BY order_details.order_id
        )
 SELECT c.customer_id,
    c.name_company AS customer_name,
    c.company_id,
    count(DISTINCT o.order_id) AS total_orders,
    COALESCE(sum(od.total_price), (0)::numeric) AS revenue,
    COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) AS cogs,
    (COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) AS gross_profit,
    round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
        CASE
            WHEN (COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) = (0)::numeric) THEN true
            WHEN (round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) < (0)::numeric) THEN true
            WHEN (round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) > (90)::numeric) THEN true
            ELSE false
        END AS data_warning
   FROM (((public.customers c
     JOIN public.orders o ON ((o.customer_id = c.customer_id)))
     JOIN order_revenue orv ON (((orv.order_id = o.order_id) AND (orv.order_total > (0)::numeric) AND (orv.order_cogs > (0)::numeric))))
     JOIN public.order_details od ON ((od.order_id = o.order_id)))
  WHERE (o.order_status <> 'Canceled'::text)
  GROUP BY c.customer_id, c.name_company, c.company_id;


--
-- Name: customer_sales_filter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_sales_filter (
    sales_filter_id text NOT NULL,
    user_email text,
    flagged boolean,
    contact_info boolean,
    sales_person text,
    sales_category text,
    sales_area text,
    sales_state text,
    customer_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    blank_1 text,
    blank_2 text
);


--
-- Name: customer_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_users (
    customer_user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id text NOT NULL,
    auth_user_id uuid NOT NULL,
    email text NOT NULL,
    shop_display_name text,
    role text DEFAULT 'buyer'::text NOT NULL,
    invited_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text
);


--
-- Name: data_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_imports (
    import_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    facility_id text NOT NULL,
    company_id text NOT NULL,
    import_mode text DEFAULT 'new'::text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    total_in_file integer DEFAULT 0 NOT NULL,
    sessions_imported integer DEFAULT 0 NOT NULL,
    sessions_linked integer DEFAULT 0 NOT NULL,
    sessions_skipped integer DEFAULT 0 NOT NULL,
    profiles_imported integer DEFAULT 0 NOT NULL,
    profiles_skipped integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    errors jsonb DEFAULT '[]'::jsonb,
    session_ids text[] DEFAULT '{}'::text[],
    created_log_ids text[] DEFAULT '{}'::text[],
    imported_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    reverted_at timestamp with time zone,
    date_from date,
    date_to date,
    source text DEFAULT 'roastmaster'::text NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    product_id text NOT NULL,
    product_name text,
    recipe_id text,
    product_type text,
    size text,
    image text,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    weight_lbs numeric,
    price numeric,
    total_unit_cogs numeric,
    facility_id text,
    gross_profit_per_unit numeric,
    cogs_pct numeric,
    margin_pct numeric,
    total_coffee_cost numeric,
    total_consumable_cost numeric,
    new_price_input numeric,
    projected_cogs_pct numeric GENERATED ALWAYS AS (round(((total_unit_cogs / NULLIF(new_price_input, (0)::numeric)) * (100)::numeric), 1)) STORED,
    price_update_date date,
    merge_into_id text,
    last_active_unit_cogs numeric,
    last_active_cogs_pct numeric,
    last_active_gross_profit_per_unit numeric,
    last_active_margin_pct numeric,
    is_active boolean DEFAULT true NOT NULL,
    group_id uuid,
    channel text
);


--
-- Name: product_margins; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.product_margins AS
 SELECT product_id,
    product_name,
    company_id,
    facility_id,
    price,
    total_unit_cogs,
    round((price - total_unit_cogs), 2) AS gross_profit_per_unit,
    round((((price - total_unit_cogs) / NULLIF(price, (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
    weight_lbs,
    size,
        CASE
            WHEN (total_unit_cogs = (0)::numeric) THEN true
            WHEN ((((price - total_unit_cogs) / NULLIF(price, (0)::numeric)) * (100)::numeric) < (0)::numeric) THEN true
            WHEN ((((price - total_unit_cogs) / NULLIF(price, (0)::numeric)) * (100)::numeric) > (90)::numeric) THEN true
            ELSE false
        END AS data_warning
   FROM public.products p
  WHERE (is_active = true);


--
-- Name: products_price_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products_price_log (
    price_log_id text NOT NULL,
    product_id text,
    price numeric,
    date_updated date,
    end_date date,
    created_at timestamp without time zone,
    created_by text,
    updated_at timestamp without time zone,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: data_quality_issues; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.data_quality_issues AS
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    p.margin_pct,
        CASE
            WHEN (p.margin_pct < (0)::numeric) THEN 'Selling below cost'::text
            WHEN (p.margin_pct > (90)::numeric) THEN 'Suspiciously high margin'::text
            ELSE NULL::text
        END AS issue
   FROM public.product_margins p
  WHERE ((p.data_warning = true) AND (p.total_unit_cogs > (0)::numeric))
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Missing coffee cost'::text AS issue
   FROM public.coffee_inventory ci
  WHERE (COALESCE(ci.latest_cost, (0)::numeric) = (0)::numeric)
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM public.coffee_inventory ci
  WHERE ((ci.latest_cost > (0)::numeric) AND (COALESCE(ci.last_cost_lb, (0)::numeric) = (0)::numeric))
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Missing consumable cost'::text AS issue
   FROM public.consumable_inventory c
  WHERE (COALESCE(c.last_cost_unit, (0)::numeric) = (0)::numeric)
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM public.consumable_inventory c
  WHERE ((COALESCE(c.fallback_unit_cost, (0)::numeric) > (0)::numeric) AND (COALESCE(c.last_cost_unit, (0)::numeric) > (0)::numeric) AND (NOT (EXISTS ( SELECT 1
           FROM public.consumable_inventory_purchased cip
          WHERE ((cip.consumable_inventory_item = c.consumable_inventory_id) AND (cip.facility_id = c.facility_id) AND (cip.cost_unit IS NOT NULL) AND ((cip.cost_unit)::text <> ''::text) AND (cip.cost_unit > (0)::numeric))))))
UNION ALL
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    NULL::numeric AS margin_pct,
    'Missing product price'::text AS issue
   FROM public.products p
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.products_price_log ppl
          WHERE (ppl.product_id = p.product_id))));


--
-- Name: developer_impersonation_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.developer_impersonation_log (
    log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    developer_id uuid NOT NULL,
    company_id text NOT NULL,
    facility_id text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    reason text,
    ip_address inet,
    user_agent text
);


--
-- Name: developer_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.developer_users (
    auth_user_id uuid NOT NULL,
    granted_by text,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    is_active boolean DEFAULT true NOT NULL,
    revoked_at timestamp with time zone
);


--
-- Name: email_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_log (
    email_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text,
    customer_id text,
    event_type text NOT NULL,
    to_email text NOT NULL,
    subject text,
    resend_message_id text,
    status text DEFAULT 'sent'::text NOT NULL,
    error_message text,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb,
    CONSTRAINT email_log_status_check CHECK ((status = ANY (ARRAY['sent'::text, 'delivered'::text, 'bounced'::text, 'opened'::text, 'complained'::text, 'failed'::text])))
);


--
-- Name: facilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facilities (
    facility_id text NOT NULL,
    company_id text,
    facility_name text NOT NULL,
    country_code text,
    time_zone text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: get_started; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.get_started (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    sort_order integer NOT NULL,
    title text NOT NULL,
    short_text text,
    detail_text text,
    image_url text,
    action_url text,
    action_label text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    invitation_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    company_id text NOT NULL,
    facility_id text,
    invited_email text NOT NULL,
    role_id text NOT NULL,
    invited_by text,
    token text DEFAULT (gen_random_uuid())::text NOT NULL,
    accepted_at timestamp with time zone,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text
);


--
-- Name: invoice_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_documents (
    invoice_document_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    staged_shipment_id text,
    file_path text NOT NULL,
    file_name text,
    file_type text,
    source text DEFAULT 'upload'::text NOT NULL,
    email_from text,
    email_subject text,
    company_id text NOT NULL,
    facility_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


--
-- Name: management_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.management_type (
    management_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: marketing_pageview; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketing_pageview (
    id bigint NOT NULL,
    path text NOT NULL,
    referrer text,
    country text,
    ua_class text,
    session_hash text,
    viewed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: marketing_pageview_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.marketing_pageview_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: marketing_pageview_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.marketing_pageview_id_seq OWNED BY public.marketing_pageview.id;


--
-- Name: roast_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_log (
    roast_log_id text NOT NULL,
    roast_date timestamp without time zone,
    origin_id text,
    recipe_id text,
    charge_weight text,
    roasted_weight numeric,
    "charged?" boolean,
    "chaff_cleaned?" boolean,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    facility_id text,
    recipe_name_snapshot text,
    coffee_name_snapshot text,
    roast_date_utc timestamp with time zone,
    charge_weight_lbs numeric,
    batches_since_chaff integer,
    chaff_due boolean,
    roaster_unit_id uuid,
    roast_type text,
    sort_order integer,
    session_id text,
    measured_roasted_weight numeric,
    reference_profile_id text,
    coffee_source_id text,
    actual_retention_factor numeric GENERATED ALWAYS AS (
CASE
    WHEN ((charge_weight_lbs IS NULL) OR (charge_weight_lbs <= (0)::numeric)) THEN NULL::numeric
    ELSE (COALESCE(measured_roasted_weight, roasted_weight) / charge_weight_lbs)
END) STORED,
    is_buffer boolean DEFAULT false NOT NULL,
    target_dev_secs numeric,
    target_dev_pct numeric
);


--
-- Name: monthly_coffee_usage; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.monthly_coffee_usage AS
 SELECT ((facility_id || '_'::text) || (date_trunc('month'::text, roast_date))::date) AS month_usage_id,
    (date_trunc('month'::text, roast_date))::date AS month_start,
    facility_id,
    company_id,
    round(sum(charge_weight_lbs), 2) AS green_used_lbs,
    round(sum(roasted_weight), 2) AS lbs_roasted,
    (count(*))::integer AS batch_count,
    round(((sum(roasted_weight) / NULLIF(sum(charge_weight_lbs), (0)::numeric)) * (100)::numeric), 1) AS retention_pct
   FROM public.roast_log rl
  WHERE ("charged?" = true)
  GROUP BY (date_trunc('month'::text, roast_date)), facility_id, company_id;


--
-- Name: recipe_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipe_components (
    component_id text NOT NULL,
    recipe_id text,
    percentage numeric,
    coffee_item text,
    component_cost numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: monthly_coffee_usage_by_origin; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.monthly_coffee_usage_by_origin AS
 WITH roast_by_origin AS (
         SELECT rl.roast_date,
            rl.origin_id,
            rl.charge_weight_lbs AS green_used_lbs,
            rl.roasted_weight AS lbs_roasted,
            rl.facility_id,
            rl.company_id
           FROM public.roast_log rl
          WHERE ((rl.origin_id IS NOT NULL) AND (rl."charged?" = true))
        UNION ALL
         SELECT rl.roast_date,
            rc.coffee_item AS origin_id,
            (rl.charge_weight_lbs * rc.percentage) AS green_used_lbs,
            (rl.roasted_weight * rc.percentage) AS lbs_roasted,
            rl.facility_id,
            rl.company_id
           FROM (public.roast_log rl
             JOIN public.recipe_components rc ON ((rc.recipe_id = rl.recipe_id)))
          WHERE ((rl.origin_id IS NULL) AND (rl.recipe_id IS NOT NULL) AND (rl."charged?" = true))
        )
 SELECT ((((r.facility_id || '_'::text) || r.origin_id) || '_'::text) || (date_trunc('month'::text, r.roast_date))::date) AS month_origin_id,
    (date_trunc('month'::text, r.roast_date))::date AS month_start,
    r.origin_id,
    ci.origin AS origin_name,
    r.facility_id,
    r.company_id,
    round(sum(r.green_used_lbs), 2) AS green_used_lbs,
    round(sum(r.lbs_roasted), 2) AS lbs_roasted
   FROM (roast_by_origin r
     LEFT JOIN public.coffee_inventory ci ON (((ci.origin_id = r.origin_id) AND (ci.facility_id = r.facility_id))))
  GROUP BY (date_trunc('month'::text, r.roast_date)), r.origin_id, ci.origin, r.facility_id, r.company_id;


--
-- Name: product_consumables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_consumables (
    product_consumable_id text NOT NULL,
    product_id text,
    consumable_id text,
    quantity numeric DEFAULT 1,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_id text,
    created_by text,
    updated_by text,
    facility_id text
);


--
-- Name: shipment_received; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipment_received (
    shipment_id text NOT NULL,
    supplier_id text,
    shipping_cost numeric,
    date_received date,
    order_date date,
    shipment_total_weight_units numeric,
    shipping_cost_unit numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    voided boolean DEFAULT false NOT NULL,
    invoice_number text,
    po_number text,
    status text DEFAULT 'received'::text NOT NULL,
    email_sent_at timestamp with time zone,
    email_sent_to text,
    email_subject text,
    notes text,
    ai_generation_log jsonb,
    estimated_total numeric,
    CONSTRAINT shipment_received_status_check CHECK ((status = ANY (ARRAY['po_draft'::text, 'po_sent'::text, 'received'::text])))
);


--
-- Name: monthly_consumable_stock_by_item; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.monthly_consumable_stock_by_item AS
 WITH all_usage AS (
         SELECT o.order_date AS usage_date,
            pc.consumable_id,
            od.facility_id,
            sum((od.quantity * pc.quantity)) AS units_used
           FROM ((public.order_details od
             JOIN public.orders o ON ((o.order_id = od.order_id)))
             JOIN public.product_consumables pc ON ((pc.product_id = od.product_id)))
          WHERE (o.order_status <> 'Canceled'::text)
          GROUP BY o.order_date, pc.consumable_id, od.facility_id
        ), all_purchases AS (
         SELECT sr.date_received AS received_date,
            p.consumable_inventory_item AS consumable_id,
            p.facility_id,
            (p.amount)::numeric AS purchased_units
           FROM (public.consumable_inventory_purchased p
             JOIN public.shipment_received sr ON ((sr.shipment_id = p.shipment_id)))
          WHERE ((sr.date_received IS NOT NULL) AND (COALESCE(sr.voided, false) = false))
        ), consumables AS (
         SELECT DISTINCT consumable_inventory.consumable_inventory_id AS consumable_id,
            consumable_inventory.facility_id,
            consumable_inventory.company_id,
            consumable_inventory.consumable_inventory_item AS item_name
           FROM public.consumable_inventory
        ), consumable_first_event AS (
         SELECT events.consumable_id,
            events.facility_id,
            min(events.event_date) AS first_event
           FROM ( SELECT consumable_inventory_history.consumable_id,
                    consumable_inventory_history.facility_id,
                    consumable_inventory_history.inventory_date AS event_date
                   FROM public.consumable_inventory_history
                UNION ALL
                 SELECT all_purchases.consumable_id,
                    all_purchases.facility_id,
                    all_purchases.received_date
                   FROM all_purchases
                UNION ALL
                 SELECT all_usage.consumable_id,
                    all_usage.facility_id,
                    all_usage.usage_date
                   FROM all_usage) events
          GROUP BY events.consumable_id, events.facility_id
        ), date_spine AS (
         SELECT c.consumable_id,
            c.facility_id,
            c.company_id,
            c.item_name,
            (gs.month_start)::date AS month_start
           FROM ((consumables c
             JOIN consumable_first_event fe ON (((fe.consumable_id = c.consumable_id) AND (fe.facility_id = c.facility_id))))
             JOIN LATERAL generate_series((date_trunc('month'::text, (fe.first_event)::timestamp without time zone))::timestamp with time zone, date_trunc('month'::text, now()), '1 mon'::interval) gs(month_start) ON (true))
          WHERE (fe.first_event < 'infinity'::date)
        )
 SELECT ((((ds.facility_id || '_'::text) || ds.consumable_id) || '_'::text) || ds.month_start) AS month_stock_id,
    ds.month_start,
    ds.consumable_id,
    ds.item_name,
    ds.facility_id,
    ds.company_id,
    GREATEST((0)::numeric, round(((COALESCE(anchor.anchor_count, (0)::numeric) + COALESCE(purch.purchased_units, (0)::numeric)) - COALESCE(used.units_used, (0)::numeric)), 0)) AS in_stock
   FROM (((date_spine ds
     LEFT JOIN LATERAL ( SELECT h.inventory_date AS anchor_date,
            h.inventory_count AS anchor_count
           FROM public.consumable_inventory_history h
          WHERE ((h.consumable_id = ds.consumable_id) AND (h.facility_id = ds.facility_id) AND (h.inventory_date < ((ds.month_start + '1 mon'::interval))::date))
          ORDER BY h.inventory_date DESC
         LIMIT 1) anchor ON (true))
     LEFT JOIN LATERAL ( SELECT COALESCE(sum(ap.purchased_units), (0)::numeric) AS purchased_units
           FROM all_purchases ap
          WHERE ((ap.consumable_id = ds.consumable_id) AND (ap.facility_id = ds.facility_id) AND (ap.received_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)) AND (ap.received_date < ((ds.month_start + '1 mon'::interval))::date))) purch ON (true))
     LEFT JOIN LATERAL ( SELECT COALESCE(sum(au.units_used), (0)::numeric) AS units_used
           FROM all_usage au
          WHERE ((au.consumable_id = ds.consumable_id) AND (au.facility_id = ds.facility_id) AND (au.usage_date > COALESCE(anchor.anchor_date, '2000-01-01'::date)) AND (au.usage_date < ((ds.month_start + '1 mon'::interval))::date))) used ON (true))
  WITH NO DATA;


--
-- Name: monthly_consumable_usage_by_item; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.monthly_consumable_usage_by_item AS
 SELECT ((((od.facility_id || '_'::text) || pc.consumable_id) || '_'::text) || (date_trunc('month'::text, (o.order_date)::timestamp with time zone))::date) AS month_item_id,
    (date_trunc('month'::text, (o.order_date)::timestamp with time zone))::date AS month_start,
    pc.consumable_id,
    ci.consumable_inventory_item AS item_name,
    od.facility_id,
    od.company_id,
    round(sum((od.quantity * pc.quantity)), 2) AS units_used
   FROM (((public.order_details od
     JOIN public.orders o ON ((o.order_id = od.order_id)))
     JOIN public.product_consumables pc ON ((pc.product_id = od.product_id)))
     JOIN public.consumable_inventory ci ON (((ci.consumable_inventory_id = pc.consumable_id) AND (ci.facility_id = od.facility_id))))
  WHERE (o.order_status <> 'Canceled'::text)
  GROUP BY (date_trunc('month'::text, (o.order_date)::timestamp with time zone)), pc.consumable_id, ci.consumable_inventory_item, od.facility_id, od.company_id;


--
-- Name: onboarding_slides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.onboarding_slides (
    id text DEFAULT (gen_random_uuid())::text NOT NULL,
    sort_order integer NOT NULL,
    title text NOT NULL,
    short_text text,
    detail_text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    image text
);


--
-- Name: open_order_totals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.open_order_totals (
    open_order_total_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: standard_parameters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.standard_parameters (
    parameters_id text NOT NULL,
    parameter text,
    amount numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    text_value text,
    data_type text,
    day_of_week text,
    CONSTRAINT standard_parameters_data_type_check CHECK ((data_type = ANY (ARRAY['text'::text, 'number'::text, 'decimal'::text, 'timezone'::text, 'boolean'::text, 'day'::text])))
);


--
-- Name: order_graphs_week; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.order_graphs_week AS
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'orders_reset_day'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS orders_reset_day,
            ( SELECT min(o.order_date) AS min
                   FROM public.orders o
                  WHERE ((o.facility_id = f.facility_id) AND (o.order_status <> 'Canceled'::text))) AS first_order_date
           FROM public.facilities f
        ), spine AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.orders_reset_day,
            (gs.gs)::date AS week_start
           FROM facility_params fp,
            LATERAL generate_series(((fp.first_order_date - ((((EXTRACT(dow FROM fp.first_order_date))::integer - fp.orders_reset_day) + 7) % 7)))::timestamp without time zone, (CURRENT_DATE + '364 days'::interval), '7 days'::interval) gs(gs)
          WHERE (fp.first_order_date IS NOT NULL)
        ), agg AS (
         SELECT s.facility_id,
            s.company_id,
            s.week_start,
            COALESCE(sum(od.total_price), (0)::numeric) AS revenue,
            COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) AS cogs,
            COALESCE((sum(od.total_price) - sum(od.unit_cost_at_sale)), (0)::numeric) AS gross_profit,
            round(((COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) / NULLIF(sum(od.total_price), (0)::numeric)) * (100)::numeric), 1) AS cogs_pct,
            round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(sum(od.total_price), (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
            count(DISTINCT o.order_id) AS order_count,
            round((COALESCE(sum(od.roasted_weight), (0)::double precision))::numeric, 2) AS total_roasted_weight
           FROM ((spine s
             LEFT JOIN public.orders o ON (((o.facility_id = s.facility_id) AND ((o.order_date - ((((EXTRACT(dow FROM o.order_date))::integer - s.orders_reset_day) + 7) % 7)) = s.week_start) AND (o.order_status <> 'Canceled'::text))))
             LEFT JOIN public.order_details od ON ((od.order_id = o.order_id)))
          GROUP BY s.facility_id, s.company_id, s.week_start
        )
 SELECT ((facility_id || '_'::text) || week_start) AS week_report_id,
    week_start,
    facility_id,
    company_id,
    revenue,
    cogs,
    gross_profit,
    cogs_pct,
    margin_pct,
    order_count,
    total_roasted_weight,
    round(avg(revenue) OVER w26, 2) AS revenue_6mo_avg,
    round(avg(cogs) OVER w26, 2) AS cogs_6mo_avg,
    round(avg(gross_profit) OVER w26, 2) AS gross_profit_6mo_avg,
    round(avg(cogs_pct) OVER w26, 1) AS cogs_pct_6mo_avg,
    round(avg(margin_pct) OVER w26, 1) AS margin_pct_6mo_avg,
    round(avg(total_roasted_weight) OVER w26, 2) AS roasted_weight_6mo_avg
   FROM agg
  WINDOW w26 AS (PARTITION BY facility_id ORDER BY week_start ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
  ORDER BY week_start DESC, facility_id
  WITH NO DATA;


--
-- Name: order_graphs_weekly_avg_by_month; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.order_graphs_weekly_avg_by_month AS
 WITH monthly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (date_trunc('month'::text, (order_graphs_week.week_start)::timestamp with time zone))::date AS month_start,
            round(sum(order_graphs_week.revenue), 2) AS total_revenue,
            round(sum(order_graphs_week.cogs), 2) AS total_cogs,
            round(sum(order_graphs_week.gross_profit), 2) AS total_gross_profit,
            round(((sum(order_graphs_week.cogs) / NULLIF(sum(order_graphs_week.revenue), (0)::numeric)) * (100)::numeric), 1) AS cogs_pct,
            round(((sum(order_graphs_week.gross_profit) / NULLIF(sum(order_graphs_week.revenue), (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
            sum(order_graphs_week.order_count) AS total_orders,
            round(avg(order_graphs_week.total_roasted_weight), 2) AS avg_weekly_roasted_weight,
            count(*) AS weeks_in_month
           FROM public.order_graphs_week
          WHERE (order_graphs_week.week_start <= CURRENT_DATE)
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (date_trunc('month'::text, (order_graphs_week.week_start)::timestamp with time zone))
        )
 SELECT ((facility_id || '_'::text) || month_start) AS month_report_id,
    month_start,
    facility_id,
    company_id,
    total_revenue,
    total_cogs,
    total_gross_profit,
    cogs_pct,
    margin_pct,
    total_orders,
    avg_weekly_roasted_weight,
    weeks_in_month,
    round(avg(total_revenue) OVER w12, 2) AS revenue_12mo_avg,
    round(avg(total_cogs) OVER w12, 2) AS cogs_12mo_avg,
    round(avg(total_gross_profit) OVER w12, 2) AS gross_profit_12mo_avg,
    round(avg(cogs_pct) OVER w12, 1) AS cogs_pct_12mo_avg,
    round(avg(margin_pct) OVER w12, 1) AS margin_pct_12mo_avg,
    round(avg(avg_weekly_roasted_weight) OVER w12, 2) AS roasted_weight_12mo_avg
   FROM monthly
  WINDOW w12 AS (PARTITION BY facility_id ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
  ORDER BY month_start DESC, facility_id;


--
-- Name: order_graphs_weekly_avg_by_year; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.order_graphs_weekly_avg_by_year AS
 WITH monthly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (EXTRACT(year FROM order_graphs_week.week_start))::integer AS year_start,
            date_trunc('month'::text, (order_graphs_week.week_start)::timestamp with time zone) AS month_start,
            sum(order_graphs_week.revenue) AS monthly_revenue,
            sum(order_graphs_week.gross_profit) AS monthly_gross_profit
           FROM public.order_graphs_week
          WHERE (order_graphs_week.week_start <= CURRENT_DATE)
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (EXTRACT(year FROM order_graphs_week.week_start)), (date_trunc('month'::text, (order_graphs_week.week_start)::timestamp with time zone))
        ), weekly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (EXTRACT(year FROM order_graphs_week.week_start))::integer AS year_start,
            round(avg(order_graphs_week.total_roasted_weight), 2) AS avg_weekly_roasted_weight
           FROM public.order_graphs_week
          WHERE (order_graphs_week.week_start <= CURRENT_DATE)
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (EXTRACT(year FROM order_graphs_week.week_start))
        ), yearly AS (
         SELECT m.facility_id,
            m.company_id,
            m.year_start,
            round(avg(m.monthly_revenue), 2) AS avg_monthly_revenue,
            round(avg(m.monthly_gross_profit), 2) AS avg_monthly_gross_profit
           FROM monthly m
          GROUP BY m.facility_id, m.company_id, m.year_start
        )
 SELECT ((y.facility_id || '_'::text) || y.year_start) AS year_report_id,
    y.year_start,
    y.facility_id,
    y.company_id,
    y.avg_monthly_revenue,
    y.avg_monthly_gross_profit,
    w.avg_weekly_roasted_weight
   FROM (yearly y
     JOIN weekly w ON (((w.facility_id = y.facility_id) AND (w.year_start = y.year_start))))
  ORDER BY y.year_start DESC, y.facility_id;


--
-- Name: order_graphs_year; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.order_graphs_year AS
 WITH yearly AS (
         SELECT order_graphs_week.facility_id,
            order_graphs_week.company_id,
            (EXTRACT(year FROM order_graphs_week.week_start))::integer AS year_start,
            round(sum(order_graphs_week.revenue), 2) AS total_revenue,
            round(sum(order_graphs_week.cogs), 2) AS total_cogs,
            round(sum(order_graphs_week.gross_profit), 2) AS total_gross_profit,
            round(((sum(order_graphs_week.cogs) / NULLIF(sum(order_graphs_week.revenue), (0)::numeric)) * (100)::numeric), 1) AS cogs_pct,
            round(((sum(order_graphs_week.gross_profit) / NULLIF(sum(order_graphs_week.revenue), (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
            sum(order_graphs_week.order_count) AS total_orders,
            round(sum(order_graphs_week.total_roasted_weight), 2) AS total_roasted_weight
           FROM public.order_graphs_week
          WHERE (order_graphs_week.week_start <= CURRENT_DATE)
          GROUP BY order_graphs_week.facility_id, order_graphs_week.company_id, (EXTRACT(year FROM order_graphs_week.week_start))
        )
 SELECT ((facility_id || '_'::text) || year_start) AS year_report_id,
    year_start,
    facility_id,
    company_id,
    total_revenue,
    total_cogs,
    total_gross_profit,
    cogs_pct,
    margin_pct,
    total_orders,
    total_roasted_weight,
    round(avg(total_revenue) OVER w3, 2) AS revenue_3yr_avg,
    round(avg(margin_pct) OVER w3, 1) AS margin_pct_3yr_avg
   FROM yearly
  WINDOW w3 AS (PARTITION BY facility_id ORDER BY year_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
  ORDER BY year_start DESC, facility_id;


--
-- Name: order_profitability; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.order_profitability AS
 SELECT o.order_id,
    o.facility_id,
    o.company_id,
    o.order_date,
    o.order_status,
    o.customer_id,
    COALESCE(sum(od.total_price), (0)::numeric) AS revenue,
    COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) AS cogs,
    (COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) AS gross_profit,
    round(((COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) AS cogs_pct,
    round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) AS margin_pct,
        CASE
            WHEN (COALESCE(sum(od.unit_cost_at_sale), (0)::numeric) = (0)::numeric) THEN true
            WHEN (round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) < (0)::numeric) THEN true
            WHEN (round((((COALESCE(sum(od.total_price), (0)::numeric) - COALESCE(sum(od.unit_cost_at_sale), (0)::numeric)) / NULLIF(COALESCE(sum(od.total_price), (0)::numeric), (0)::numeric)) * (100)::numeric), 1) > (90)::numeric) THEN true
            ELSE false
        END AS data_warning
   FROM (public.orders o
     JOIN public.order_details od ON ((od.order_id = o.order_id)))
  WHERE (o.order_status <> 'Canceled'::text)
  GROUP BY o.order_id, o.facility_id, o.company_id, o.order_date, o.order_status, o.customer_id;


--
-- Name: order_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_statuses (
    status_id text NOT NULL,
    display_name text NOT NULL,
    sort_order integer DEFAULT 0,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payment_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_transactions (
    payment_transaction_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    order_id text,
    provider text DEFAULT 'activitypay'::text NOT NULL,
    provider_transaction_id text,
    idempotency_key text,
    type text NOT NULL,
    status text NOT NULL,
    gross_amount_cents integer NOT NULL,
    gateway_fee_cents integer,
    platform_fee_cents integer,
    roaster_payout_cents integer,
    response_code text,
    response_text text,
    raw_response jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    threeds_status text,
    threeds_eci text,
    threeds_cavv text,
    threeds_xid text,
    risk_score numeric,
    settled boolean DEFAULT false NOT NULL,
    settled_at timestamp with time zone,
    paid_out boolean DEFAULT false NOT NULL,
    payout_id uuid,
    threeds_liability_shifted boolean GENERATED ALWAYS AS ((threeds_status = ANY (ARRAY['Y'::text, 'A'::text]))) STORED,
    CONSTRAINT payment_transactions_status_chk CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text, 'failed'::text, 'voided'::text]))),
    CONSTRAINT payment_transactions_type_chk CHECK ((type = ANY (ARRAY['sale'::text, 'auth'::text, 'capture'::text, 'refund'::text, 'void'::text])))
);


--
-- Name: payment_webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_webhook_events (
    webhook_event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider text DEFAULT 'activitypay'::text NOT NULL,
    provider_event_id text NOT NULL,
    event_type text NOT NULL,
    provider_transaction_id text,
    signature_valid boolean NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    processed_at timestamp with time zone,
    processing_error text,
    payload jsonb NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payouts (
    payout_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    bank_account_id uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    gross_cents bigint NOT NULL,
    gateway_fees_cents bigint DEFAULT 0 NOT NULL,
    platform_fees_cents bigint DEFAULT 0 NOT NULL,
    refunds_cents bigint DEFAULT 0 NOT NULL,
    chargebacks_cents bigint DEFAULT 0 NOT NULL,
    reserve_held_cents bigint DEFAULT 0 NOT NULL,
    net_cents bigint NOT NULL,
    ach_provider text,
    ach_transfer_id text,
    return_code text,
    return_reason text,
    period_start date NOT NULL,
    period_end date NOT NULL,
    submitted_at timestamp with time zone,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT payouts_status_chk CHECK ((status = ANY (ARRAY['pending'::text, 'submitted'::text, 'in_transit'::text, 'paid'::text, 'returned'::text, 'canceled'::text])))
);


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    permission_id text NOT NULL,
    category text NOT NULL,
    label text NOT NULL,
    description text,
    default_deny_message text DEFAULT 'You don''t have permission to do that. Contact your administrator if you need access.'::text NOT NULL,
    is_plan_gated boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: plan_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_permissions (
    plan_id text NOT NULL,
    permission_id text NOT NULL,
    granted boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_reason text
);


--
-- Name: prep_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prep_type (
    prep_type_id uuid DEFAULT gen_random_uuid() NOT NULL,
    prep_type text NOT NULL,
    company_id text,
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: product_filter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_filter (
    products_filter_id text NOT NULL,
    product_id text,
    recipe_id text,
    size text,
    order_status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    user_email text
);


--
-- Name: product_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_groups (
    group_id uuid DEFAULT gen_random_uuid() NOT NULL,
    group_name text NOT NULL,
    description text,
    company_id text,
    facility_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    image text,
    is_visible boolean DEFAULT true NOT NULL,
    sort_order integer,
    exclusive_to_customer_ids text[],
    excluded_from_customer_ids text[]
);


--
-- Name: product_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_type (
    product_type_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    product_type text NOT NULL,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: quarterly_green_coffee_price; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.quarterly_green_coffee_price AS
 SELECT ((((((((date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone))::date)::text || '_'::text) || cip.company_id) || '_'::text) || cip.facility_id) || '_'::text) || cip.origin) AS row_id,
    (date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone))::date AS quarter_start,
    to_char(date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone), 'YYYY "Q"Q'::text) AS quarter_label,
    cip.company_id,
    cip.facility_id,
    cip.origin AS origin_id,
    ci_name.origin AS origin_name,
    count(cip.origin_purchase_id) AS purchase_count,
    round(sum(cip.amount), 2) AS total_lbs_purchased,
    round((sum((cip.cost_lb * cip.amount)) / NULLIF(sum(cip.amount), (0)::numeric)), 2) AS avg_cost_lb,
    round((sum(((cip.cost_lb + COALESCE(sr.shipping_cost_unit, (0)::numeric)) * cip.amount)) / NULLIF(sum(cip.amount), (0)::numeric)), 2) AS avg_landed_cost_lb
   FROM ((public.coffee_inventory_purchased cip
     JOIN public.shipment_received sr ON ((cip.shipment_id = sr.shipment_id)))
     LEFT JOIN LATERAL ( SELECT coffee_inventory.origin
           FROM public.coffee_inventory
          WHERE ((coffee_inventory.origin_id = cip.origin) AND (coffee_inventory.facility_id = cip.facility_id))
         LIMIT 1) ci_name ON (true))
  WHERE ((sr.date_received IS NOT NULL) AND (COALESCE(sr.voided, false) = false) AND (cip.cost_lb IS NOT NULL))
  GROUP BY (date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone)), cip.company_id, cip.facility_id, cip.origin, ci_name.origin
  ORDER BY ((date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone))::date), ci_name.origin;


--
-- Name: quarterly_green_coffee_price_aggregate; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.quarterly_green_coffee_price_aggregate AS
 WITH per_origin AS (
         SELECT (date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone))::date AS quarter_start,
            to_char(date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone), 'YYYY "Q"Q'::text) AS quarter_label,
            cip.company_id,
            cip.facility_id,
            round(sum(cip.amount), 2) AS total_lbs_purchased,
            sum((cip.cost_lb * cip.amount)) AS cost_x_lbs,
            sum(((cip.cost_lb + COALESCE(sr.shipping_cost_unit, (0)::numeric)) * cip.amount)) AS landed_cost_x_lbs,
            count(cip.origin_purchase_id) AS purchase_count
           FROM (public.coffee_inventory_purchased cip
             JOIN public.shipment_received sr ON ((cip.shipment_id = sr.shipment_id)))
          WHERE ((sr.date_received IS NOT NULL) AND (COALESCE(sr.voided, false) = false) AND (cip.cost_lb IS NOT NULL))
          GROUP BY (date_trunc('quarter'::text, (sr.date_received)::timestamp with time zone)), cip.company_id, cip.facility_id, cip.origin
        )
 SELECT (((((quarter_start)::text || '_'::text) || company_id) || '_'::text) || facility_id) AS row_id,
    quarter_start,
    quarter_label,
    company_id,
    facility_id,
    sum(purchase_count) AS purchase_count,
    round(sum(total_lbs_purchased), 2) AS total_lbs_purchased,
    round((sum(cost_x_lbs) / NULLIF(sum(total_lbs_purchased), (0)::numeric)), 2) AS avg_cost_lb,
    round((sum(landed_cost_x_lbs) / NULLIF(sum(total_lbs_purchased), (0)::numeric)), 2) AS avg_landed_cost_lb
   FROM per_origin
  GROUP BY quarter_start, quarter_label, company_id, facility_id
  ORDER BY quarter_start;


--
-- Name: recent_coffee_order; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recent_coffee_order (
    recent_coffee_order_id text NOT NULL,
    total_pallets numeric,
    lbs_ordered numeric(10,2) DEFAULT 0,
    recommended_pallets numeric(10,2) DEFAULT 0,
    bags_left numeric(10,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    current_shipment_id text
);


--
-- Name: recipe_weekly_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipe_weekly_targets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipe_id text NOT NULL,
    facility_id text NOT NULL,
    week_start date NOT NULL,
    target_lbs numeric NOT NULL,
    notes text,
    created_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT recipe_weekly_targets_target_lbs_check CHECK ((target_lbs >= (0)::numeric))
);


--
-- Name: restock_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restock_category (
    restock_category_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    target_months numeric DEFAULT 3 NOT NULL,
    reorder_months numeric DEFAULT 1.5 NOT NULL,
    company_id text,
    facility_id text,
    is_default boolean DEFAULT false,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_global boolean DEFAULT false NOT NULL
);


--
-- Name: roast_recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_recipes (
    recipe_id text NOT NULL,
    recipe_name text,
    image text,
    cost_lb_green numeric,
    cost_lb_roasted numeric,
    shipping_lb numeric,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    roast_type text DEFAULT 'Single Origin/Post-Blend'::text,
    facility_id text,
    is_active boolean DEFAULT true NOT NULL,
    retention_factor numeric,
    CONSTRAINT roast_recipes_roast_type_check CHECK ((roast_type = ANY (ARRAY['Single Origin'::text, 'Post-Blend'::text, 'Pre-Blend'::text])))
);


--
-- Name: roast_stock_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_stock_log (
    stock_log_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    stock_type text NOT NULL,
    blend_id text,
    origin_id text,
    facility_id text NOT NULL,
    company_id text,
    lbs_in_stock numeric DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT roast_stock_log_ids_check CHECK ((((stock_type = 'blend'::text) AND (blend_id IS NOT NULL) AND (origin_id IS NULL)) OR ((stock_type = 'origin'::text) AND (origin_id IS NOT NULL) AND (blend_id IS NULL))))
);


--
-- Name: roast_detail; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.roast_detail AS
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'RF1iFWjOh7'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), 4) AS roast_reset_day,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = '761fd894'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), (25)::numeric) AS charge_weight,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = '1de271df'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), 0.82) AS retention_rate
           FROM public.facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            fp.charge_weight,
            fp.retention_rate,
            (((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date))::integer - fp.roast_reset_day) + 7) % 7)) AS roast_week_start
           FROM facility_params fp
        ), origin_facility AS (
         SELECT DISTINCT rc.coffee_item AS origin,
            f.facility_id,
            f.company_id
           FROM ((public.recipe_components rc
             JOIN public.roast_recipes rr ON ((rc.recipe_id = rr.recipe_id)))
             JOIN public.facilities f ON (((f.company_id = rr.company_id) AND ((rr.facility_id IS NULL) OR (rr.facility_id = f.facility_id)))))
        ), per_origin AS (
         SELECT of2.origin,
            of2.facility_id,
            of2.company_id,
            (COALESCE(( SELECT sum(rsl.lbs_in_stock) AS sum
                   FROM public.roast_stock_log rsl
                  WHERE ((rsl.origin_id = of2.origin) AND (rsl.facility_id = of2.facility_id) AND (((rsl.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start))), (0)::numeric) + COALESCE(( SELECT sum((rsl.lbs_in_stock * rc.percentage)) AS sum
                   FROM (public.roast_stock_log rsl
                     JOIN public.recipe_components rc ON ((rsl.blend_id = rc.recipe_id)))
                  WHERE ((rc.coffee_item = of2.origin) AND (rsl.facility_id = of2.facility_id) AND (((rsl.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start))), (0)::numeric)) AS in_stock_roasted,
            COALESCE(( SELECT sum(((od.quantity * p.weight_lbs) * rc.percentage)) AS sum
                   FROM (((public.order_details od
                     JOIN public.orders o ON ((od.order_id = o.order_id)))
                     JOIN public.products p ON ((od.product_id = p.product_id)))
                     JOIN public.recipe_components rc ON ((p.recipe_id = rc.recipe_id)))
                  WHERE ((rc.coffee_item = of2.origin) AND (o.order_status = 'Open'::text) AND (o.facility_id = of2.facility_id))), (0)::numeric) AS total_ordered,
            (COALESCE(( SELECT sum(rl.roasted_weight) AS sum
                   FROM public.roast_log rl
                  WHERE ((rl.origin_id = of2.origin) AND (rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = of2.facility_id))), (0)::numeric) + COALESCE(( SELECT sum((rl.roasted_weight * rc.percentage)) AS sum
                   FROM ((public.roast_log rl
                     JOIN public.roast_recipes rr ON ((rl.recipe_id = rr.recipe_id)))
                     JOIN public.recipe_components rc ON ((rl.recipe_id = rc.recipe_id)))
                  WHERE ((rr.roast_type = 'Pre-Blend'::text) AND (rc.coffee_item = of2.origin) AND (rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = of2.facility_id))), (0)::numeric)) AS total_roasted,
            c.retention_rate,
            COALESCE(( SELECT avg(rl.charge_weight_lbs) AS avg
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM public.roast_log
                          WHERE ((roast_log.origin_id = of2.origin) AND (roast_log.facility_id = of2.facility_id) AND (roast_log.charge_weight_lbs > (0)::numeric))
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) rl), c.charge_weight, (25)::numeric) AS effective_charge_weight
           FROM (origin_facility of2
             JOIN calc c ON ((c.facility_id = of2.facility_id)))
        )
 SELECT ((origin || '-'::text) || facility_id) AS roast_detail_id,
    origin,
    facility_id,
    company_id,
    in_stock_roasted,
    total_roasted,
    total_ordered,
    GREATEST((0)::numeric, ((total_ordered - in_stock_roasted) - total_roasted)) AS final_roasted_weight,
    (GREATEST((0)::numeric, ((total_ordered - in_stock_roasted) - total_roasted)) / NULLIF(retention_rate, (0)::numeric)) AS green_to_roast,
    ((GREATEST((0)::numeric, ((total_ordered - in_stock_roasted) - total_roasted)) / NULLIF(retention_rate, (0)::numeric)) / NULLIF(effective_charge_weight, (0)::numeric)) AS roasts_remaining
   FROM per_origin;


--
-- Name: roast_log_recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_log_recipes (
    roast_log_recipe_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    roast_log_id text NOT NULL,
    recipe_id text NOT NULL,
    lbs_allocated numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: roast_detail_by_blend; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.roast_detail_by_blend AS
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'RF1iFWjOh7'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), 4) AS roast_reset_day,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'orders_reset_day'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS orders_reset_day,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = '761fd894'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), (25)::numeric) AS charge_weight,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = '1de271df'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT sp.amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = '1de271df'::text)
                 LIMIT 1), 0.82) AS retention_rate,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'backstock_buffer_pct'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT sp.amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'backstock_buffer_pct'::text)
                 LIMIT 1), (0)::numeric) AS backstock_buffer_pct
           FROM public.facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            fp.roast_reset_day,
            fp.orders_reset_day,
            fp.charge_weight,
            fp.retention_rate,
            fp.backstock_buffer_pct,
            (((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date))::integer - fp.roast_reset_day) + 7) % 7)) AS roast_week_start,
            (((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date))::integer - fp.orders_reset_day) + 7) % 7)) AS orders_week_start
           FROM facility_params fp
        ), recipe_facility AS (
         SELECT rr.recipe_id,
            rr.roast_type,
            rr.retention_factor,
            f.facility_id,
            f.company_id
           FROM (public.roast_recipes rr
             JOIN public.facilities f ON (((f.company_id = rr.company_id) AND ((rr.facility_id IS NULL) OR (rr.facility_id = f.facility_id)))))
        ), recipe_anchor AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            c.roast_week_start,
            c.orders_week_start,
            c.timezone,
            anchor.anchor_stock,
            anchor.anchor_date,
            anchor.in_current_week
           FROM ((recipe_facility rf
             JOIN calc c ON ((c.facility_id = rf.facility_id)))
             LEFT JOIN LATERAL ( SELECT rsl.lbs_in_stock AS anchor_stock,
                    ((rsl.created_at AT TIME ZONE c.timezone))::date AS anchor_date,
                    (((rsl.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start) AS in_current_week
                   FROM public.roast_stock_log rsl
                  WHERE ((rsl.stock_type = 'blend'::text) AND (rsl.blend_id = rf.recipe_id) AND (rsl.facility_id = rf.facility_id) AND (((rsl.created_at AT TIME ZONE c.timezone))::date >= (c.roast_week_start - '28 days'::interval)))
                  ORDER BY rsl.created_at DESC
                 LIMIT 1) anchor ON (true))
        ), recipe_is AS (
         SELECT ra.recipe_id,
            ra.facility_id,
                CASE
                    WHEN ra.in_current_week THEN GREATEST((0)::numeric, ra.anchor_stock)
                    ELSE GREATEST((0)::numeric, ((COALESCE(ra.anchor_stock, (0)::numeric) + COALESCE(( SELECT sum((rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, (0)::numeric)))) AS sum
                       FROM (public.roast_log rl
                         JOIN public.roast_log_recipes rlr ON ((rlr.roast_log_id = rl.roast_log_id)))
                      WHERE ((rlr.recipe_id = ra.recipe_id) AND (rl.facility_id = ra.facility_id) AND (rl."charged?" = true) AND (rl.roast_date >= COALESCE((ra.anchor_date)::timestamp without time zone, (ra.roast_week_start - '28 days'::interval))) AND (rl.roast_date < ra.roast_week_start))), (0)::numeric)) - COALESCE(( SELECT (sum(od.roasted_weight))::numeric AS sum
                       FROM ((public.order_details od
                         JOIN public.orders o ON ((od.order_id = o.order_id)))
                         JOIN public.products p ON ((od.product_id = p.product_id)))
                      WHERE ((p.recipe_id = ra.recipe_id) AND (o.facility_id = ra.facility_id) AND (o.order_status = 'Delivered'::text) AND (COALESCE(((o.status_changed_at AT TIME ZONE ra.timezone))::date, o.order_date) >= COALESCE((ra.anchor_date)::timestamp without time zone, (ra.orders_week_start - '28 days'::interval))) AND (COALESCE(((o.status_changed_at AT TIME ZONE ra.timezone))::date, o.order_date) < ra.orders_week_start))), (0)::numeric)))
                END AS in_stock_roasted
           FROM recipe_anchor ra
        ), recipe_override AS (
         SELECT rwt.recipe_id,
            rwt.facility_id,
            rwt.target_lbs,
            rwt.notes
           FROM (public.recipe_weekly_targets rwt
             JOIN calc c ON ((c.facility_id = rwt.facility_id)))
          WHERE (rwt.week_start = c.roast_week_start)
        ), recipe_level AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            c.backstock_buffer_pct,
            COALESCE(ris.in_stock_roasted, (0)::numeric) AS in_stock_roasted,
            COALESCE(ordered.total_ordered, (0)::double precision) AS total_ordered,
            COALESCE(roasted.total_roasted, (0)::numeric) AS total_roasted,
            COALESCE(NULLIF(rf.retention_factor, (0)::numeric), c.retention_rate) AS retention_rate,
            COALESCE(( SELECT avg(rl.charge_weight_lbs) AS avg
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM public.roast_log
                          WHERE ((roast_log.recipe_id = rf.recipe_id) AND (roast_log.facility_id = rf.facility_id) AND (roast_log.charge_weight_lbs > (0)::numeric))
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) rl), c.charge_weight, (25)::numeric) AS effective_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, (0)::numeric) AS avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override
           FROM ((((((recipe_facility rf
             JOIN calc c ON ((c.facility_id = rf.facility_id)))
             LEFT JOIN recipe_is ris ON (((ris.recipe_id = rf.recipe_id) AND (ris.facility_id = rf.facility_id))))
             LEFT JOIN recipe_override ovr ON (((ovr.recipe_id = rf.recipe_id) AND (ovr.facility_id = rf.facility_id))))
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight) AS total_ordered
                   FROM ((public.order_details od
                     JOIN public.orders o ON ((od.order_id = o.order_id)))
                     JOIN public.products p ON ((od.product_id = p.product_id)))
                  WHERE ((p.recipe_id = rf.recipe_id) AND (o.facility_id = rf.facility_id) AND (o.order_status <> 'Canceled'::text) AND (o.order_date >= c.orders_week_start) AND (o.order_date < (c.orders_week_start + '7 days'::interval)))) ordered ON (true))
             LEFT JOIN LATERAL ( SELECT sum((rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, (0)::numeric)))) AS total_roasted
                   FROM (public.roast_log rl
                     JOIN public.roast_log_recipes rlr ON ((rlr.roast_log_id = rl.roast_log_id)))
                  WHERE ((rlr.recipe_id = rf.recipe_id) AND (rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = rf.facility_id))) roasted ON (true))
             LEFT JOIN LATERAL ( SELECT (COALESCE(sum(weekly.lbs), (0)::numeric) / (6)::numeric) AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, (o2.order_date)::timestamp with time zone) AS wk,
                            sum((od2.quantity * COALESCE(p2.weight_lbs, (0)::numeric))) AS lbs
                           FROM ((public.order_details od2
                             JOIN public.orders o2 ON ((od2.order_id = o2.order_id)))
                             JOIN public.products p2 ON ((od2.product_id = p2.product_id)))
                          WHERE ((p2.recipe_id = rf.recipe_id) AND (o2.facility_id = rf.facility_id) AND (o2.order_status <> 'Canceled'::text) AND (o2.order_date >= (c.orders_week_start - '42 days'::interval)) AND (o2.order_date < c.orders_week_start))
                          GROUP BY (date_trunc('week'::text, (o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON (true))
          WHERE ((rf.roast_type = 'Pre-Blend'::text) OR (NOT (EXISTS ( SELECT 1
                   FROM public.recipe_components rc
                  WHERE (rc.recipe_id = rf.recipe_id)))))
        ), component_raw AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            rc.coffee_item AS origin_id,
            COALESCE(rc.percentage, (0)::numeric) AS percentage,
            c.backstock_buffer_pct,
            COALESCE(NULLIF(rf.retention_factor, (0)::numeric), c.retention_rate) AS retention_rate,
            c.charge_weight AS facility_charge_weight,
            (COALESCE(ordered.total_ordered, (0)::double precision))::numeric AS recipe_demand,
            (COALESCE(ris.in_stock_roasted, (0)::numeric) * COALESCE(rc.percentage, (0)::numeric)) AS this_week_stock,
            COALESCE(component_roasted.lbs, (0)::numeric) AS component_roasted,
            COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, (25)::numeric) AS component_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, (0)::numeric) AS recipe_avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override
           FROM ((((((((((recipe_facility rf
             JOIN public.recipe_components rc ON ((rc.recipe_id = rf.recipe_id)))
             JOIN calc c ON ((c.facility_id = rf.facility_id)))
             LEFT JOIN recipe_is ris ON (((ris.recipe_id = rf.recipe_id) AND (ris.facility_id = rf.facility_id))))
             LEFT JOIN recipe_override ovr ON (((ovr.recipe_id = rf.recipe_id) AND (ovr.facility_id = rf.facility_id))))
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight) AS total_ordered
                   FROM ((public.order_details od
                     JOIN public.orders o ON ((od.order_id = o.order_id)))
                     JOIN public.products p ON ((od.product_id = p.product_id)))
                  WHERE ((p.recipe_id = rf.recipe_id) AND (o.facility_id = rf.facility_id) AND (o.order_status <> 'Canceled'::text) AND (o.order_date >= c.orders_week_start) AND (o.order_date < (c.orders_week_start + '7 days'::interval)))) ordered ON (true))
             LEFT JOIN LATERAL ( SELECT COALESCE(sum((rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, (0)::numeric)))), (0)::numeric) AS lbs
                   FROM (public.roast_log rl
                     JOIN public.roast_log_recipes rlr ON ((rlr.roast_log_id = rl.roast_log_id)))
                  WHERE ((rlr.recipe_id = rf.recipe_id) AND (rl.origin_id = rc.coffee_item) AND (rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = rf.facility_id))) component_roasted ON (true))
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM public.roast_log
                          WHERE ((roast_log.recipe_id = rf.recipe_id) AND (roast_log.origin_id = rc.coffee_item) AND (roast_log.facility_id = rf.facility_id) AND (roast_log.charge_weight_lbs > (0)::numeric))
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) charge_w ON (true))
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM public.roast_log
                          WHERE ((roast_log.recipe_id = rf.recipe_id) AND (roast_log.facility_id = rf.facility_id) AND (roast_log.charge_weight_lbs > (0)::numeric))
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) recipe_charge_w ON (true))
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM public.roast_log
                          WHERE ((roast_log.origin_id = rc.coffee_item) AND (roast_log.facility_id = rf.facility_id) AND (roast_log.charge_weight_lbs > (0)::numeric))
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) origin_charge_w ON (true))
             LEFT JOIN LATERAL ( SELECT (COALESCE(sum(weekly.lbs), (0)::numeric) / (6)::numeric) AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, (o2.order_date)::timestamp with time zone) AS wk,
                            sum((od2.quantity * COALESCE(p2.weight_lbs, (0)::numeric))) AS lbs
                           FROM ((public.order_details od2
                             JOIN public.orders o2 ON ((od2.order_id = o2.order_id)))
                             JOIN public.products p2 ON ((od2.product_id = p2.product_id)))
                          WHERE ((p2.recipe_id = rf.recipe_id) AND (o2.facility_id = rf.facility_id) AND (o2.order_status <> 'Canceled'::text) AND (o2.order_date >= (c.orders_week_start - '42 days'::interval)) AND (o2.order_date < c.orders_week_start))
                          GROUP BY (date_trunc('week'::text, (o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON (true))
          WHERE ((rf.roast_type IS DISTINCT FROM 'Pre-Blend'::text) AND (EXISTS ( SELECT 1
                   FROM public.recipe_components rc2
                  WHERE (rc2.recipe_id = rf.recipe_id))))
        ), component_alloc AS (
         SELECT cr.recipe_id,
            cr.facility_id,
            cr.company_id,
            cr.origin_id,
            cr.percentage,
            cr.backstock_buffer_pct,
            cr.retention_rate,
            cr.facility_charge_weight,
            cr.recipe_demand,
            cr.this_week_stock,
            cr.component_roasted,
            cr.component_charge_weight,
            cr.recipe_avg_weekly_lbs,
            cr.weekly_target_override,
            ((cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct) / (100)::numeric) AS recipe_buffer_target,
            (cr.percentage * (cr.recipe_demand + ((cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct) / (100)::numeric))) AS component_demand_buf,
            (cr.percentage * cr.recipe_demand) AS component_demand_orders,
            cr.this_week_stock AS effective_stock
           FROM component_raw cr
        ), component_split AS (
         SELECT ca.recipe_id,
            ca.facility_id,
            ca.company_id,
            ca.origin_id,
            ca.percentage,
            ca.backstock_buffer_pct,
            ca.retention_rate,
            ca.facility_charge_weight,
            ca.recipe_demand,
            ca.this_week_stock,
            ca.component_roasted,
            ca.component_charge_weight,
            ca.recipe_avg_weekly_lbs,
            ca.weekly_target_override,
            ca.recipe_buffer_target,
            ca.component_demand_buf,
            ca.component_demand_orders,
            ca.effective_stock,
            ca.effective_stock AS applied_stock,
            GREATEST((0)::numeric, (ca.component_demand_buf - ca.effective_stock)) AS demand_after_stock
           FROM component_alloc ca
        ), component_final AS (
         SELECT cs.recipe_id,
            cs.facility_id,
            cs.company_id,
            cs.origin_id,
            cs.percentage,
            cs.backstock_buffer_pct,
            cs.retention_rate,
            cs.facility_charge_weight,
            cs.recipe_demand,
            cs.this_week_stock,
            cs.component_roasted,
            cs.component_charge_weight,
            cs.recipe_avg_weekly_lbs,
            cs.weekly_target_override,
            cs.recipe_buffer_target,
            cs.component_demand_buf,
            cs.component_demand_orders,
            cs.effective_stock,
            cs.applied_stock,
            cs.demand_after_stock,
            LEAST(cs.demand_after_stock, cs.component_roasted) AS applied_roasted,
            GREATEST((0)::numeric, (cs.demand_after_stock - cs.component_roasted)) AS component_remaining,
            GREATEST((0)::numeric, ((cs.component_demand_orders - cs.effective_stock) - cs.component_roasted)) AS component_remaining_orders_only
           FROM component_split cs
        ), post_blend_recipe AS (
         SELECT cf.recipe_id,
            cf.facility_id,
            cf.company_id,
            max(cf.retention_rate) AS retention_rate,
            (max(cf.recipe_demand))::double precision AS total_ordered,
            sum(cf.applied_stock) AS in_stock_roasted,
            sum(cf.applied_roasted) AS total_roasted,
            (sum(cf.component_remaining))::double precision AS roasted_left,
            (sum(ceil(((cf.component_remaining / NULLIF(cf.retention_rate, (0)::numeric)) / NULLIF(cf.component_charge_weight, (0)::numeric)))))::double precision AS roasts_remaining,
            max(cf.recipe_avg_weekly_lbs) AS avg_weekly_lbs,
            max(cf.backstock_buffer_pct) AS backstock_buffer_pct,
            max(cf.recipe_buffer_target) AS buffer_target,
            LEAST((max(cf.recipe_buffer_target))::double precision, (GREATEST((0)::numeric, (sum(cf.component_remaining) - sum(cf.component_remaining_orders_only))))::double precision) AS buffer_left_calc,
            max(cf.weekly_target_override) AS weekly_target_override
           FROM component_final cf
          GROUP BY cf.recipe_id, cf.facility_id, cf.company_id
        ), unioned AS (
         SELECT rl.recipe_id,
            rl.facility_id,
            rl.company_id,
            rl.in_stock_roasted,
            rl.total_ordered,
            rl.total_roasted,
            GREATEST((0)::double precision, (((rl.total_ordered + (((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / (100)::numeric))::double precision) - (rl.in_stock_roasted)::double precision) - (rl.total_roasted)::double precision)) AS roasted_left,
            ((GREATEST((0)::double precision, (((rl.total_ordered + (((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / (100)::numeric))::double precision) - (rl.in_stock_roasted)::double precision) - (rl.total_roasted)::double precision)) / (NULLIF(rl.retention_rate, (0)::numeric))::double precision) / (NULLIF(rl.effective_charge_weight, (0)::numeric))::double precision) AS roasts_remaining,
            rl.avg_weekly_lbs,
            rl.backstock_buffer_pct,
            ((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / (100)::numeric) AS buffer_target,
            LEAST(GREATEST((0)::double precision, (((rl.total_ordered + (((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / (100)::numeric))::double precision) - (rl.in_stock_roasted)::double precision) - (rl.total_roasted)::double precision)), (((rl.avg_weekly_lbs * rl.backstock_buffer_pct) / (100)::numeric))::double precision) AS buffer_left,
            rl.weekly_target_override
           FROM recipe_level rl
        UNION ALL
         SELECT pbr.recipe_id,
            pbr.facility_id,
            pbr.company_id,
            pbr.in_stock_roasted,
            pbr.total_ordered,
            pbr.total_roasted,
            pbr.roasted_left,
            pbr.roasts_remaining,
            pbr.avg_weekly_lbs,
            pbr.backstock_buffer_pct,
            pbr.buffer_target,
            pbr.buffer_left_calc AS buffer_left,
            pbr.weekly_target_override
           FROM post_blend_recipe pbr
        )
 SELECT ((recipe_id || '-'::text) || facility_id) AS roast_blend_id,
    recipe_id,
    facility_id,
    company_id,
    in_stock_roasted,
    total_ordered,
    total_roasted,
    roasted_left,
    roasts_remaining,
    avg_weekly_lbs,
    backstock_buffer_pct,
    buffer_target,
    (total_ordered + (buffer_target)::double precision) AS effective_target,
    buffer_left,
    weekly_target_override
   FROM unioned;


--
-- Name: roast_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_events (
    event_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    session_id text NOT NULL,
    elapsed_secs numeric NOT NULL,
    event_type text NOT NULL,
    bt_at_event numeric,
    et_at_event numeric,
    label text,
    notes text,
    facility_id text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    value_numeric numeric,
    value_unit text,
    gas_at_event numeric,
    drum_at_event numeric,
    airflow_at_event numeric,
    inlet_at_event numeric,
    stack_at_event numeric,
    CONSTRAINT roast_events_event_type_check CHECK ((event_type = ANY (ARRAY['charge'::text, 'turning_point'::text, 'yellowing'::text, 'maillard'::text, 'first_crack_start'::text, 'first_crack_end'::text, 'second_crack_start'::text, 'second_crack_end'::text, 'drop'::text, 'cool_end'::text, 'custom'::text])))
);


--
-- Name: roast_profile_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_profile_nodes (
    node_id bigint NOT NULL,
    profile_id text NOT NULL,
    elapsed_secs numeric NOT NULL,
    bt_temp numeric,
    et_temp numeric,
    bt_ror numeric,
    inlet_temp numeric,
    stack_temp numeric,
    gas_pct numeric,
    drum_speed_rpm numeric,
    airflow_pct numeric,
    ambient_temp numeric
);


--
-- Name: roast_profile_nodes_node_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.roast_profile_nodes ALTER COLUMN node_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.roast_profile_nodes_node_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: roast_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_profiles (
    profile_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    profile_name text NOT NULL,
    recipe_id text,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    company_id text NOT NULL,
    facility_id text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: roast_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_sessions (
    session_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    roast_log_id text,
    facility_id text NOT NULL,
    company_id text NOT NULL,
    roaster_unit_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    green_weight_lbs numeric,
    roasted_weight_lbs numeric,
    charge_weight_id text,
    recipe_id text,
    origin_id text,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    profile_name text,
    agtron_color numeric,
    post_moisture numeric,
    post_density numeric,
    ambient_temp numeric,
    ambient_humidity numeric,
    roast_degree text,
    rating integer,
    is_profile_template boolean DEFAULT false NOT NULL,
    target_dev_secs numeric,
    target_dev_pct numeric,
    CONSTRAINT roast_sessions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'discarded'::text])))
);


--
-- Name: roast_smartroast_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_smartroast_log (
    log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id text,
    facility_id text NOT NULL,
    company_id text NOT NULL,
    roaster_unit_id uuid,
    event_type text NOT NULL,
    source text NOT NULL,
    fired_at_ms bigint,
    peak_at_ms bigint,
    manual_press_at_ms bigint,
    peak_bt numeric,
    cliff_rate numeric,
    sensitivity_used text,
    thresholds_used jsonb,
    calibration_source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT smartroast_log_calibration_source_check CHECK (((calibration_source IS NULL) OR (calibration_source = ANY (ARRAY['hardcoded'::text, 'model'::text, 'unit'::text])))),
    CONSTRAINT smartroast_log_event_type_check CHECK ((event_type = ANY (ARRAY['charge'::text, 'drop'::text]))),
    CONSTRAINT smartroast_log_source_check CHECK ((source = ANY (ARRAY['auto'::text, 'manual'::text, 'auto_cancelled'::text])))
);


--
-- Name: roast_temp_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roast_temp_nodes (
    node_id bigint NOT NULL,
    session_id text NOT NULL,
    elapsed_secs numeric NOT NULL,
    bt_temp numeric,
    et_temp numeric,
    bt_ror numeric,
    et_ror numeric,
    facility_id text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    inlet_temp numeric,
    stack_temp numeric,
    gas_pct numeric,
    drum_speed_rpm numeric,
    airflow_pct numeric,
    ambient_temp numeric
);


--
-- Name: roast_temp_nodes_node_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.roast_temp_nodes ALTER COLUMN node_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.roast_temp_nodes_node_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: roaster_bank_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roaster_bank_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    account_holder_name text NOT NULL,
    account_type text DEFAULT 'checking'::text NOT NULL,
    routing_number_last4 text,
    account_number_last4 text NOT NULL,
    plaid_access_token_encrypted bytea,
    plaid_account_id text,
    plaid_item_id text,
    verification_method text NOT NULL,
    verification_status text DEFAULT 'pending'::text NOT NULL,
    verified_at timestamp with time zone,
    nacha_authorized_at timestamp with time zone,
    nacha_auth_ip text,
    nacha_auth_user_agent text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT roaster_bank_account_type_chk CHECK ((account_type = ANY (ARRAY['checking'::text, 'savings'::text]))),
    CONSTRAINT roaster_bank_verification_method_chk CHECK ((verification_method = ANY (ARRAY['plaid'::text, 'micro_deposit'::text, 'manual'::text]))),
    CONSTRAINT roaster_bank_verification_status_chk CHECK ((verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'failed'::text])))
);


--
-- Name: roaster_model_smartroast_calibration; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roaster_model_smartroast_calibration (
    brand text NOT NULL,
    model text NOT NULL,
    event_type text NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    peak_bt_avg numeric,
    peak_bt_stddev numeric,
    peak_bt_m2 numeric DEFAULT 0,
    cliff_rate_avg numeric,
    cliff_rate_m2 numeric DEFAULT 0,
    contributing_companies integer DEFAULT 0 NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_cal_event_check CHECK ((event_type = ANY (ARRAY['charge'::text, 'drop'::text])))
);


--
-- Name: roaster_unit_smartroast_calibration; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roaster_unit_smartroast_calibration (
    roaster_unit_id uuid NOT NULL,
    event_type text NOT NULL,
    company_id text NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    peak_bt_avg numeric,
    peak_bt_stddev numeric,
    peak_bt_m2 numeric DEFAULT 0,
    cliff_rate_avg numeric,
    cliff_rate_m2 numeric DEFAULT 0,
    last_updated timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT unit_cal_event_check CHECK ((event_type = ANY (ARRAY['charge'::text, 'drop'::text])))
);


--
-- Name: roaster_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roaster_units (
    roaster_unit_id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id text NOT NULL,
    company_id text NOT NULL,
    name text NOT NULL,
    max_charge_weight_lbs numeric,
    capacity_hrs_per_week numeric,
    is_active boolean DEFAULT true,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    max_charge_weight_id text,
    probe_offset_bt numeric DEFAULT 0 NOT NULL,
    probe_offset_et numeric DEFAULT 0 NOT NULL,
    min_charge_weight_id text,
    brand text,
    driver_id text,
    driver_config jsonb,
    model text,
    mac_address text,
    last_active_source text,
    last_active_at timestamp with time zone
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_id text NOT NULL,
    permission_id text NOT NULL,
    granted boolean DEFAULT false NOT NULL,
    deny_message text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text
);


--
-- Name: sales_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_activity (
    sales_activity_id text NOT NULL,
    sales_activity_type text,
    activity_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


--
-- Name: sales_area; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_area (
    area_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    id text NOT NULL,
    state_id text
);


--
-- Name: sales_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_category (
    sales_category text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: sales_city; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_city (
    sales_city_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    city_name text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    state_id text,
    company_id text
);


--
-- Name: sales_data_filter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_data_filter (
    sales_data_filter_id text NOT NULL,
    start_date date,
    end_date date,
    category text,
    customer text,
    product text,
    recipe text,
    size text,
    order_status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    user_email text,
    product_type text
);


--
-- Name: sales_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_goals (
    sales_goal_id text NOT NULL,
    sales_person text,
    first_action_daily_goal numeric,
    follow_up_action_daily_goal numeric,
    personal_action_weekly_goal numeric,
    signed_accounts_weekly_goal numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


--
-- Name: sales_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_notes (
    salesnote_id text NOT NULL,
    customer_id text,
    contact text,
    sales_activity_type text,
    sales_person text,
    sales_note text,
    date date,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: sales_parameters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_parameters (
    sales_parameter_id text NOT NULL,
    sales_person text,
    follow_up_reminder_weeks numeric,
    current_client_follow_up_reminder_weeks numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: sales_region; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_region (
    id text NOT NULL,
    name text NOT NULL,
    country_code text DEFAULT 'US'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sales_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_state (
    id text NOT NULL,
    country_code text NOT NULL,
    state_name text NOT NULL,
    state_abbrev text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    region_id text
);


--
-- Name: sales_state_backup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_state_backup (
    sales_state text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: sales_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_tasks (
    sales_task_id text NOT NULL,
    sales_person text,
    customer_id text,
    contact text,
    sales_activity_type text,
    task text,
    date_due date,
    status boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: sales_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_tracking (
    sales_tracking_id text NOT NULL,
    sales_person text,
    period text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    first_actions_taken text DEFAULT '0/0'::text,
    personal_actions_taken text DEFAULT '0/0'::text,
    deals_signed text DEFAULT '0/0'::text,
    follow_up_actions_taken text DEFAULT '0/0'::text,
    denials integer DEFAULT 0,
    win_count integer DEFAULT 0
);


--
-- Name: setup_countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.setup_countries (
    country_name text NOT NULL,
    country_code text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: setup_timezones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.setup_timezones (
    timezone_name text NOT NULL,
    display_label text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: shop_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_config (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    facility_id text,
    slug text NOT NULL,
    is_enabled boolean DEFAULT false NOT NULL,
    shop_name text,
    tagline text,
    logo_url text,
    accent_color text,
    welcome_message text,
    shipping_enabled boolean DEFAULT false NOT NULL,
    shipping_rate_per_lb numeric,
    shipping_rate_unit text DEFAULT 'lb'::text,
    free_shipping_threshold numeric,
    wholesale_enabled boolean DEFAULT true NOT NULL,
    vip_enabled boolean DEFAULT false NOT NULL,
    stripe_connect_account_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    shop_product_limit integer,
    emblem_url text,
    payments_enabled boolean DEFAULT false NOT NULL,
    reply_to_email text,
    retail_enabled boolean DEFAULT false NOT NULL,
    invoice_payment_instructions text
);


--
-- Name: shop_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_invitations (
    invitation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    token uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id text NOT NULL,
    company_id text NOT NULL,
    slug text NOT NULL,
    invited_email text NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    target_role text DEFAULT 'buyer'::text NOT NULL
);


--
-- Name: shop_order_ref_counter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_order_ref_counter (
    company_id text NOT NULL,
    next_value bigint DEFAULT 1 NOT NULL
);


--
-- Name: shopify_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shopify_connections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    facility_id text NOT NULL,
    shop_domain text NOT NULL,
    access_token text NOT NULL,
    webhook_secret text NOT NULL,
    auto_accept boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    connected_by text
);


--
-- Name: shopify_product_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shopify_product_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id text NOT NULL,
    company_id text NOT NULL,
    shopify_variant_id text NOT NULL,
    shopify_product_id text NOT NULL,
    shopify_product_title text NOT NULL,
    shopify_variant_title text NOT NULL,
    product_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: size; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.size (
    size_id text NOT NULL,
    size_name text,
    weight numeric,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: sorted_onboarding_slides; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sorted_onboarding_slides AS
 SELECT id,
    sort_order,
    title,
    short_text,
    detail_text,
    created_at,
    updated_at,
    image
   FROM public.onboarding_slides
  ORDER BY sort_order;


--
-- Name: staged_import_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staged_import_sessions (
    id bigint NOT NULL,
    import_id text NOT NULL,
    payload jsonb NOT NULL,
    processed boolean DEFAULT false NOT NULL
);


--
-- Name: staged_import_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.staged_import_sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.staged_import_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: staged_line_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staged_line_items (
    staged_line_item_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    staged_shipment_id text NOT NULL,
    line_type text DEFAULT 'coffee'::text NOT NULL,
    item_name_raw text,
    coffee_source_id text,
    coffee_source_confidence numeric,
    origin_id text,
    bags_ordered numeric,
    cost_per_unit numeric,
    cost_unit text DEFAULT 'lb'::text,
    bag_size numeric,
    lot_number text,
    harvest_year text,
    consumable_id text,
    consumable_confidence numeric,
    units_ordered numeric,
    cost_per_consumable numeric,
    line_total numeric,
    sort_order integer DEFAULT 0,
    company_id text NOT NULL,
    facility_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


--
-- Name: staged_shipments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staged_shipments (
    staged_shipment_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    status text DEFAULT 'processing'::text NOT NULL,
    supplier_name_raw text,
    supplier_id text,
    supplier_confidence numeric,
    order_date date,
    shipping_cost numeric,
    currency text DEFAULT 'USD'::text,
    invoice_number text,
    ai_raw_response jsonb,
    confirmed_shipment_id text,
    processing_error text,
    company_id text NOT NULL,
    facility_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


--
-- Name: standing_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.standing_order_lines (
    standing_order_line_id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id text NOT NULL,
    company_id text NOT NULL,
    product_id text NOT NULL,
    quantity numeric NOT NULL,
    coffee_prep text DEFAULT 'Whole Bean'::text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT standing_order_lines_quantity_check CHECK ((quantity > (0)::numeric))
);


--
-- Name: statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statements (
    statement_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    opening_balance_cents bigint DEFAULT 0 NOT NULL,
    gross_sales_cents bigint DEFAULT 0 NOT NULL,
    gateway_fees_cents bigint DEFAULT 0 NOT NULL,
    platform_fees_cents bigint DEFAULT 0 NOT NULL,
    refunds_cents bigint DEFAULT 0 NOT NULL,
    chargebacks_cents bigint DEFAULT 0 NOT NULL,
    payouts_cents bigint DEFAULT 0 NOT NULL,
    closing_balance_cents bigint DEFAULT 0 NOT NULL,
    transaction_count integer DEFAULT 0 NOT NULL,
    pdf_storage_path text,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text
);


--
-- Name: stock_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_types (
    stock_type_id text NOT NULL,
    label text NOT NULL,
    sort_order integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: subscription_admin_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_admin_log (
    log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    action text NOT NULL,
    delta jsonb DEFAULT '{}'::jsonb NOT NULL,
    reason text NOT NULL,
    performed_by text NOT NULL,
    performed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: supplier; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier (
    supplier_id text NOT NULL,
    supplier text,
    supplier_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text,
    is_active boolean DEFAULT true NOT NULL,
    website text,
    catalog_url text,
    contact_name text,
    contact_email text,
    contact_phone text,
    notes text
);


--
-- Name: supplier_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_category (
    supplier_category_id text NOT NULL,
    supplier_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


--
-- Name: tax_forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_forms (
    tax_form_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    form_type text DEFAULT '1099-K'::text NOT NULL,
    tax_year integer NOT NULL,
    gross_annual_cents bigint NOT NULL,
    gross_jan_cents bigint DEFAULT 0 NOT NULL,
    gross_feb_cents bigint DEFAULT 0 NOT NULL,
    gross_mar_cents bigint DEFAULT 0 NOT NULL,
    gross_apr_cents bigint DEFAULT 0 NOT NULL,
    gross_may_cents bigint DEFAULT 0 NOT NULL,
    gross_jun_cents bigint DEFAULT 0 NOT NULL,
    gross_jul_cents bigint DEFAULT 0 NOT NULL,
    gross_aug_cents bigint DEFAULT 0 NOT NULL,
    gross_sep_cents bigint DEFAULT 0 NOT NULL,
    gross_oct_cents bigint DEFAULT 0 NOT NULL,
    gross_nov_cents bigint DEFAULT 0 NOT NULL,
    gross_dec_cents bigint DEFAULT 0 NOT NULL,
    transaction_count integer NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    tax1099_submission_id text,
    filed_at timestamp with time zone,
    payee_delivered_at timestamp with time zone,
    pdf_storage_path text,
    correction_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text,
    CONSTRAINT tax_forms_form_type_chk CHECK ((form_type = ANY (ARRAY['1099-K'::text, '1099-MISC'::text]))),
    CONSTRAINT tax_forms_status_chk CHECK ((status = ANY (ARRAY['draft'::text, 'filed'::text, 'corrected'::text, 'void'::text])))
);


--
-- Name: team; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team (
    team_member_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    name text,
    email text,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    role text DEFAULT 'staff'::text,
    facility_id text,
    auth_user_id uuid,
    onboarding_completed boolean DEFAULT false NOT NULL,
    first_app_open_at timestamp with time zone,
    is_active boolean DEFAULT true,
    activity_last_seen_at timestamp with time zone,
    ui_hide_help boolean DEFAULT false NOT NULL
);


--
-- Name: totals; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.totals AS
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'orders_reset_day'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS orders_reset_day
           FROM public.facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            (((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date))::integer - fp.orders_reset_day) + 7) % 7)) AS orders_week_start
           FROM facility_params fp
        ), product_facility AS (
         SELECT p.product_id,
            f.facility_id,
            f.company_id
           FROM (public.products p
             JOIN public.facilities f ON (((p.company_id = f.company_id) AND ((p.facility_id IS NULL) OR (p.facility_id = f.facility_id)))))
        )
 SELECT ((pf.product_id || '-'::text) || pf.facility_id) AS totals_id,
    pf.product_id,
    pf.facility_id,
    pf.company_id,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS total,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (od.item_status = 'Open'::text) AND (o.facility_id = pf.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS left_to_pack,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (od.item_status = 'Open'::text) AND (o.order_date < c.orders_week_start) AND (o.facility_id = pf.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS open_backlog,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (od.item_status = 'Packed'::text) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS packed_qty,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_status = 'Delivered'::text) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id))), (0)::numeric) AS delivered_qty,
    COALESCE(( SELECT avg(sub.weekly_sum) AS avg
           FROM ( SELECT sum(od2.quantity) AS weekly_sum
                   FROM (public.order_details od2
                     JOIN public.orders o2 ON ((od2.order_id = o2.order_id)))
                  WHERE ((od2.product_id = pf.product_id) AND (o2.order_date >= (c.orders_week_start - '42 days'::interval)) AND (o2.order_date < c.orders_week_start) AND (o2.facility_id = pf.facility_id) AND (o2.order_status <> 'Canceled'::text))
                  GROUP BY (date_trunc('week'::text, (o2.order_date)::timestamp with time zone))) sub), (0)::numeric) AS recent_avg_week
   FROM (product_facility pf
     JOIN calc c ON ((c.facility_id = pf.facility_id)));


--
-- Name: user_parameters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_parameters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    parameter_id text NOT NULL,
    facility_id text,
    company_id text NOT NULL,
    value text,
    value_number numeric,
    day_of_week text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by text,
    updated_by text
);


--
-- Name: user_roaster_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roaster_settings (
    email text NOT NULL,
    roaster_unit_id uuid,
    facility_id text,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    user_roaster_settings_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    projected_source text,
    CONSTRAINT user_roaster_settings_projected_source_check CHECK (((projected_source IS NULL) OR (projected_source = ANY (ARRAY['avg'::text, 'orders'::text]))))
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    role_id text NOT NULL,
    role_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    sort_order integer
);


--
-- Name: vmi_checkin_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vmi_checkin_items (
    vmi_checkin_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    vmi_checkin_id uuid NOT NULL,
    product_id text NOT NULL,
    observed_qty numeric DEFAULT 0 NOT NULL,
    suggested_qty numeric,
    ordered_qty numeric,
    coffee_prep text DEFAULT 'Whole Bean'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vmi_checkins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vmi_checkins (
    vmi_checkin_id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    facility_id text,
    customer_id text NOT NULL,
    visited_at timestamp with time zone DEFAULT now() NOT NULL,
    visited_by text,
    notes text,
    generated_order_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: weekly_coffee_stock_by_origin; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.weekly_coffee_stock_by_origin AS
 WITH direct_roasts AS (
         SELECT (rl.roast_date)::date AS roast_date,
            rl.origin_id,
            rl.facility_id,
            rl.charge_weight_lbs AS green_lbs
           FROM (public.roast_log rl
             JOIN public.roast_recipes rr ON ((rr.recipe_id = rl.recipe_id)))
          WHERE ((rl.origin_id IS NOT NULL) AND (rl."charged?" = true) AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend'::text))
        ), blend_roasts AS (
         SELECT (rl.roast_date)::date AS roast_date,
            rc.coffee_item AS origin_id,
            rl.facility_id,
            (rl.charge_weight_lbs * rc.percentage) AS green_lbs
           FROM ((public.roast_log rl
             JOIN public.roast_recipes rr ON ((rr.recipe_id = rl.recipe_id)))
             JOIN public.recipe_components rc ON ((rc.recipe_id = rl.recipe_id)))
          WHERE ((rl.origin_id IS NULL) AND (rr.roast_type = 'Pre-Blend'::text) AND (rl."charged?" = true))
        ), all_roasts AS (
         SELECT direct_roasts.roast_date,
            direct_roasts.origin_id,
            direct_roasts.facility_id,
            direct_roasts.green_lbs
           FROM direct_roasts
        UNION ALL
         SELECT blend_roasts.roast_date,
            blend_roasts.origin_id,
            blend_roasts.facility_id,
            blend_roasts.green_lbs
           FROM blend_roasts
        ), all_purchases AS (
         SELECT sr.date_received AS received_date,
            p.origin AS origin_id,
            p.facility_id,
            p.amount AS purchased_lbs
           FROM (public.coffee_inventory_purchased p
             JOIN public.shipment_received sr ON ((sr.shipment_id = p.shipment_id)))
          WHERE ((sr.date_received IS NOT NULL) AND (COALESCE(sr.voided, false) = false))
        ), origins AS (
         SELECT DISTINCT ci.origin_id,
            ci.facility_id,
            ci.company_id,
            ci.bag_size,
            ci.origin AS origin_name
           FROM public.coffee_inventory ci
          WHERE (ci.origin_id IS NOT NULL)
        ), date_spine AS (
         SELECT o.origin_id,
            o.facility_id,
            o.company_id,
            o.bag_size,
            o.origin_name,
            (gs.week_start)::date AS week_start
           FROM (origins o
             JOIN LATERAL generate_series(date_trunc('week'::text, (now() - '1 year'::interval)), date_trunc('week'::text, now()), '7 days'::interval) gs(week_start) ON (true))
        )
 SELECT ((((facility_id || '_'::text) || origin_id) || '_'::text) || week_start) AS week_stock_id,
    week_start,
    origin_id,
    origin_name,
    facility_id,
    company_id,
    GREATEST((0)::numeric, ((COALESCE(( SELECT (ci.inventory_count_bags * (ci.bag_size)::numeric)
           FROM public.coffee_inventory ci
          WHERE ((ci.origin_id = ds.origin_id) AND (ci.facility_id = ds.facility_id))
         LIMIT 1), (0)::numeric) + COALESCE(( SELECT sum(p.purchased_lbs) AS sum
           FROM all_purchases p
          WHERE ((p.origin_id = ds.origin_id) AND (p.facility_id = ds.facility_id) AND (p.received_date > ( SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) AS "coalesce"
                   FROM public.coffee_inventory ci
                  WHERE ((ci.origin_id = ds.origin_id) AND (ci.facility_id = ds.facility_id))
                 LIMIT 1)) AND (p.received_date <= ds.week_start))), (0)::numeric)) - COALESCE(( SELECT sum(r.green_lbs) AS sum
           FROM all_roasts r
          WHERE ((r.origin_id = ds.origin_id) AND (r.facility_id = ds.facility_id) AND (r.roast_date > ( SELECT COALESCE(ci.last_inventory, '1970-01-01'::date) AS "coalesce"
                   FROM public.coffee_inventory ci
                  WHERE ((ci.origin_id = ds.origin_id) AND (ci.facility_id = ds.facility_id))
                 LIMIT 1)) AND (r.roast_date <= ds.week_start))), (0)::numeric))) AS stock_lbs
   FROM date_spine ds
  WITH NO DATA;


--
-- Name: weekly_grand_total; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.weekly_grand_total AS
 WITH facility_config AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'UTC'::text) AS timezone,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'RF1iFWjOh7'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'RF1iFWjOh7'::text)
                 LIMIT 1), 4) AS roast_target_day,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = '1de271df'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), 0.82) AS retention_rate,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'orders_reset_day'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS orders_reset_day,
            COALESCE(( SELECT cp.value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'roast_capacity_hrs'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT sp.amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'roast_capacity_hrs'::text)
                 LIMIT 1), (35)::numeric) AS facility_capacity_hrs
           FROM public.facilities f
        ), calc AS (
         SELECT fc.facility_id,
            fc.company_id,
            fc.retention_rate,
            fc.facility_capacity_hrs,
            COALESCE(NULLIF(( SELECT sum(ru.capacity_hrs_per_week) AS sum
                   FROM public.roaster_units ru
                  WHERE ((ru.facility_id = fc.facility_id) AND (ru.is_active = true) AND (ru.capacity_hrs_per_week IS NOT NULL))), (0)::numeric), fc.facility_capacity_hrs) AS total_capacity_hrs,
            (((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone))::date))::integer - fc.orders_reset_day) + 7) % 7)) AS order_week_start,
            (((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fc.timezone))::date))::integer - fc.roast_target_day) + 7) % 7)) AS roast_week_start
           FROM facility_config fc
        )
 SELECT facility_id AS open_order_total_id,
    facility_id,
    company_id,
    COALESCE(( SELECT sum(od.roasted_weight) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((o.order_date >= c.order_week_start) AND (o.facility_id = c.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::double precision) AS total_ordered_roasted,
    (COALESCE(( SELECT sum(od.roasted_weight) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((o.order_date >= c.order_week_start) AND (o.facility_id = c.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::double precision) / (NULLIF(retention_rate, (0)::numeric))::double precision) AS total_ordered_green,
    COALESCE(( SELECT sum(rl.roasted_weight) AS sum
           FROM public.roast_log rl
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = c.facility_id))), (0)::numeric) AS total_roasted,
    COALESCE(( SELECT sum(rl.charge_weight_lbs) AS sum
           FROM public.roast_log rl
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = c.facility_id))), (0)::numeric) AS total_roasted_green,
    ( SELECT max(rl.batches_since_chaff) AS max
           FROM public.roast_log rl
          WHERE (rl.facility_id = c.facility_id)) AS batches_since_chaff,
    COALESCE(( SELECT count(DISTINCT o.order_id) AS count
           FROM public.orders o
          WHERE ((o.order_date >= c.order_week_start) AND (o.facility_id = c.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::bigint) AS order_count,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((o.order_date >= c.order_week_start) AND (o.facility_id = c.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS products_sold,
    COALESCE(( SELECT count(*) AS count
           FROM public.roast_log rl
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = c.facility_id))), (0)::bigint) AS roast_count,
    round((((COALESCE(( SELECT count(*) AS count
           FROM public.roast_log rl
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = c.facility_id))), (0)::bigint))::numeric * COALESCE(( SELECT avg(gaps.gap_minutes) AS avg
           FROM ( SELECT (EXTRACT(epoch FROM (roast_log.roast_date - lag(roast_log.roast_date) OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date))) / 60.0) AS gap_minutes
                   FROM public.roast_log
                  WHERE ((roast_log."charged?" = true) AND (roast_log.roast_date >= c.roast_week_start) AND (roast_log.facility_id = c.facility_id))) gaps
          WHERE ((gaps.gap_minutes > (0)::numeric) AND (gaps.gap_minutes <= (25)::numeric))), (0)::numeric)) / 60.0), 2) AS roasting_hours,
    round((((((COALESCE(( SELECT count(*) AS count
           FROM public.roast_log rl
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c.roast_week_start) AND (rl.facility_id = c.facility_id))), (0)::bigint))::numeric * COALESCE(( SELECT avg(gaps.gap_minutes) AS avg
           FROM ( SELECT (EXTRACT(epoch FROM (roast_log.roast_date - lag(roast_log.roast_date) OVER (PARTITION BY roast_log.roaster_unit_id ORDER BY roast_log.roast_date))) / 60.0) AS gap_minutes
                   FROM public.roast_log
                  WHERE ((roast_log."charged?" = true) AND (roast_log.roast_date >= c.roast_week_start) AND (roast_log.facility_id = c.facility_id))) gaps
          WHERE ((gaps.gap_minutes > (0)::numeric) AND (gaps.gap_minutes <= (25)::numeric))), (0)::numeric)) / 60.0) / NULLIF(total_capacity_hrs, (0)::numeric)) * (100)::numeric), 1) AS capacity_pct
   FROM calc c;


--
-- Name: weekly_orders_live; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.weekly_orders_live AS
 SELECT (date_trunc('week'::text, (od.order_date)::timestamp with time zone))::date AS week_start,
    od.facility_id,
    count(DISTINCT od.order_id) AS order_count,
    sum(od.quantity) AS products_sold
   FROM (public.order_details od
     JOIN public.orders o ON ((o.order_id = od.order_id)))
  WHERE ((o.order_status <> 'Canceled'::text) AND (od.quantity > (0)::numeric))
  GROUP BY ((date_trunc('week'::text, (od.order_date)::timestamp with time zone))::date), od.facility_id;


--
-- Name: weekly_roast_current; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.weekly_roast_current AS
 WITH fac AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'UTC'::text) AS tz,
            COALESCE(( SELECT (company_parameters.value_number)::integer AS value_number
                   FROM public.company_parameters
                  WHERE ((company_parameters.parameter_id = 'RF1iFWjOh7'::text) AND (company_parameters.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (standard_parameters.amount)::integer AS amount
                   FROM public.standard_parameters
                  WHERE (standard_parameters.parameters_id = 'RF1iFWjOh7'::text)
                 LIMIT 1), 4) AS reset_day,
            COALESCE(( SELECT (company_parameters.value_number)::integer AS value_number
                   FROM public.company_parameters
                  WHERE ((company_parameters.parameter_id = 'orders_reset_day'::text) AND (company_parameters.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (standard_parameters.amount)::integer AS amount
                   FROM public.standard_parameters
                  WHERE (standard_parameters.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS order_reset_day,
            COALESCE(NULLIF(( SELECT sum(COALESCE(ru.capacity_hrs_per_week, COALESCE(( SELECT company_parameters.value_number
                           FROM public.company_parameters
                          WHERE ((company_parameters.parameter_id = 'roast_capacity_hrs'::text) AND (company_parameters.facility_id = f.facility_id))
                         LIMIT 1), (35)::numeric))) AS sum
                   FROM public.roaster_units ru
                  WHERE ((ru.facility_id = f.facility_id) AND (ru.is_active = true))), (0)::numeric), COALESCE(( SELECT company_parameters.value_number
                   FROM public.company_parameters
                  WHERE ((company_parameters.parameter_id = 'roast_capacity_hrs'::text) AND (company_parameters.facility_id = f.facility_id))
                 LIMIT 1), (35)::numeric)) AS capacity_hrs
           FROM public.facilities f
        ), fac_week AS (
         SELECT fac.facility_id,
            fac.company_id,
            fac.tz,
            fac.reset_day,
            fac.order_reset_day,
            fac.capacity_hrs,
            (((CURRENT_TIMESTAMP AT TIME ZONE fac.tz))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fac.tz))::date))::integer - fac.reset_day) + 7) % 7)) AS week_start,
            (((CURRENT_TIMESTAMP AT TIME ZONE fac.tz))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fac.tz))::date))::integer - fac.order_reset_day) + 7) % 7)) AS order_week_start
           FROM fac
        ), roast_agg AS (
         SELECT fw.facility_id,
            fw.company_id,
            fw.week_start,
            fw.order_week_start,
            fw.capacity_hrs,
            count(rl.roast_log_id) AS roast_count,
            COALESCE(sum(rl.roasted_weight), (0)::numeric) AS total_roasted,
            COALESCE(sum(rl.charge_weight_lbs), (0)::numeric) AS total_roasted_green,
            round((((count(rl.roast_log_id))::numeric * COALESCE(( SELECT avg(g.gap_minutes) AS avg
                   FROM ( SELECT (EXTRACT(epoch FROM (rl2.roast_date - lag(rl2.roast_date) OVER (PARTITION BY rl2.roaster_unit_id ORDER BY rl2.roast_date))) / 60.0) AS gap_minutes
                           FROM public.roast_log rl2
                          WHERE ((rl2."charged?" = true) AND (rl2.facility_id = fw.facility_id) AND (rl2.roast_date >= fw.week_start))) g
                  WHERE ((g.gap_minutes > (0)::numeric) AND (g.gap_minutes <= (25)::numeric))), (0)::numeric)) / 60.0), 2) AS roasting_hours
           FROM (fac_week fw
             LEFT JOIN public.roast_log rl ON (((rl.facility_id = fw.facility_id) AND (rl."charged?" = true) AND (rl.roast_date >= fw.week_start))))
          GROUP BY fw.facility_id, fw.company_id, fw.week_start, fw.order_week_start, fw.capacity_hrs
        )
 SELECT facility_id,
    company_id,
    week_start,
    total_roasted,
    total_roasted_green,
    (roast_count)::integer AS roast_count,
    roasting_hours,
    round(((roasting_hours / NULLIF(capacity_hrs, (0)::numeric)) * (100)::numeric), 1) AS capacity_pct,
    COALESCE(( SELECT sum(od.roasted_weight) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((o.facility_id = ra.facility_id) AND (o.order_date >= ra.order_week_start) AND (o.order_status <> 'Canceled'::text))), (0)::double precision) AS total_ordered_roasted,
    (COALESCE(( SELECT count(DISTINCT o.order_id) AS count
           FROM public.orders o
          WHERE ((o.facility_id = ra.facility_id) AND (o.order_date >= ra.order_week_start) AND (o.order_status <> 'Canceled'::text))), (0)::bigint))::integer AS order_count,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((o.facility_id = ra.facility_id) AND (o.order_date >= ra.order_week_start) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS products_sold
   FROM roast_agg ra;


--
-- Name: weekly_roast_snapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_roast_snapshot (
    snapshot_id uuid DEFAULT gen_random_uuid() NOT NULL,
    facility_id text NOT NULL,
    company_id text,
    week_start date NOT NULL,
    total_roasted numeric,
    total_roasted_green numeric,
    total_ordered_roasted numeric,
    total_ordered_green numeric,
    order_count integer,
    products_sold numeric,
    roast_count integer,
    roasting_hours numeric,
    capacity_pct numeric,
    batches_since_chaff integer,
    snapshotted_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: marketing_pageview id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_pageview ALTER COLUMN id SET DEFAULT nextval('public.marketing_pageview_id_seq'::regclass);


--
-- Name: coffee_inventory_purchased Coffee Inventory Purchased_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT "Coffee Inventory Purchased_pkey" PRIMARY KEY (origin_purchase_id);


--
-- Name: companies Companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT "Companies_pkey" PRIMARY KEY (company_id);


--
-- Name: consumable_inventory_purchased Consumable Inventory Purchased_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT "Consumable Inventory Purchased_pkey" PRIMARY KEY (consumable_purchase_id);


--
-- Name: consumable_inventory Consumable Inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT "Consumable Inventory_pkey" PRIMARY KEY (consumable_inventory_id);


--
-- Name: contacts Contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT "Contacts_pkey" PRIMARY KEY (contact_id);


--
-- Name: customers Customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT "Customers_pkey" PRIMARY KEY (customer_id);


--
-- Name: order_details Order Details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT "Order Details_pkey" PRIMARY KEY (order_detail_id);


--
-- Name: orders Orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT "Orders_pkey" PRIMARY KEY (order_id);


--
-- Name: products_price_log Products Price Log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT "Products Price Log_pkey" PRIMARY KEY (price_log_id);


--
-- Name: products Products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT "Products_pkey" PRIMARY KEY (product_id);


--
-- Name: roast_log Roast Log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT "Roast Log_pkey" PRIMARY KEY (roast_log_id);


--
-- Name: roast_recipes Roast Recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT "Roast Recipes_pkey" PRIMARY KEY (recipe_id);


--
-- Name: sales_notes Sales Notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT "Sales Notes_pkey" PRIMARY KEY (salesnote_id);


--
-- Name: sales_state_backup Sales State_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_state_backup
    ADD CONSTRAINT "Sales State_pkey" PRIMARY KEY (sales_state);


--
-- Name: sales_tasks Sales Tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_tasks
    ADD CONSTRAINT "Sales Tasks_pkey" PRIMARY KEY (sales_task_id);


--
-- Name: size Size_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size
    ADD CONSTRAINT "Size_pkey" PRIMARY KEY (size_id);


--
-- Name: app_menu app_menu_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_menu
    ADD CONSTRAINT app_menu_pkey PRIMARY KEY (menu_item_id);


--
-- Name: bag_sizes bag_sizes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bag_sizes
    ADD CONSTRAINT bag_sizes_pkey PRIMARY KEY (bag_size_id);


--
-- Name: blending_worksheet blending_worksheet_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_pkey PRIMARY KEY (blending_id);


--
-- Name: channel channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_pkey PRIMARY KEY (channel_id);


--
-- Name: charge_weight_options charge_weight_options_facility_weight_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_facility_weight_key UNIQUE (facility_id, charge_weight);


--
-- Name: charge_weight_options charge_weight_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_pkey PRIMARY KEY (id);


--
-- Name: chargebacks chargebacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chargebacks
    ADD CONSTRAINT chargebacks_pkey PRIMARY KEY (chargeback_id);


--
-- Name: chargebacks chargebacks_provider_provider_case_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chargebacks
    ADD CONSTRAINT chargebacks_provider_provider_case_id_key UNIQUE (provider, provider_case_id);


--
-- Name: coffee_inventory coffee_inventory_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: coffee_inventory_history coffee_inventory_history_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: coffee_inventory_history coffee_inventory_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_pkey PRIMARY KEY (history_id);


--
-- Name: coffee_inventory coffee_inventory_par_nonnegative; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_par_nonnegative CHECK ((par >= (0)::numeric)) NOT VALID;


--
-- Name: coffee_inventory coffee_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_pkey PRIMARY KEY (origin_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: coffee_inventory coffee_inventory_restock_level_nonnegative; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_restock_level_nonnegative CHECK ((restock_level >= (0)::numeric)) NOT VALID;


--
-- Name: coffee_source coffee_source_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_source
    ADD CONSTRAINT coffee_source_pkey PRIMARY KEY (coffee_source_id);


--
-- Name: coffee_usage_by_month coffee_usage_by_month_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_pkey PRIMARY KEY (coffee_usage_id);


--
-- Name: companies companies_stripe_customer_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_stripe_customer_id_key UNIQUE (stripe_customer_id);


--
-- Name: company_kyc_beneficial_owners company_kyc_beneficial_owners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_beneficial_owners
    ADD CONSTRAINT company_kyc_beneficial_owners_pkey PRIMARY KEY (id);


--
-- Name: company_kyc_documents company_kyc_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_pkey PRIMARY KEY (id);


--
-- Name: company_kyc company_kyc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc
    ADD CONSTRAINT company_kyc_pkey PRIMARY KEY (company_id);


--
-- Name: company_parameters company_parameters_company_facility_parameter_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_company_facility_parameter_key UNIQUE (company_id, facility_id, parameter_id);


--
-- Name: company_parameters company_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_pkey PRIMARY KEY (id);


--
-- Name: company_signup_form company_signup_form_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_signup_form
    ADD CONSTRAINT company_signup_form_pkey PRIMARY KEY (id);


--
-- Name: consumable_inventory consumable_inventory_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: consumable_inventory_history consumable_inventory_history_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: consumable_inventory_history consumable_inventory_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_pkey PRIMARY KEY (history_id);


--
-- Name: consumable_inventory consumable_inventory_par_nonnegative; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_par_nonnegative CHECK ((par >= (0)::numeric)) NOT VALID;


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: consumable_inventory consumable_inventory_restock_level_nonnegative; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_restock_level_nonnegative CHECK ((restock_level >= (0)::numeric)) NOT VALID;


--
-- Name: consumable_type consumable_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_type
    ADD CONSTRAINT consumable_type_pkey PRIMARY KEY (consumable_type_id);


--
-- Name: contact_role contact_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_role
    ADD CONSTRAINT contact_role_pkey PRIMARY KEY (contact_role_id);


--
-- Name: customer_category customer_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_category
    ADD CONSTRAINT customer_category_pkey PRIMARY KEY (id);


--
-- Name: customer_notes_detail customer_notes_detail_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: customer_notes_detail customer_notes_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_pkey PRIMARY KEY (notes_detail_id);


--
-- Name: customer_sales_filter customer_sales_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_pkey PRIMARY KEY (sales_filter_id);


--
-- Name: customer_users customer_users_customer_id_auth_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_users
    ADD CONSTRAINT customer_users_customer_id_auth_user_id_key UNIQUE (customer_id, auth_user_id);


--
-- Name: customer_users customer_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_users
    ADD CONSTRAINT customer_users_pkey PRIMARY KEY (customer_user_id);


--
-- Name: customers customers_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.customers
    ADD CONSTRAINT customers_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: developer_impersonation_log developer_impersonation_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.developer_impersonation_log
    ADD CONSTRAINT developer_impersonation_log_pkey PRIMARY KEY (log_id);


--
-- Name: developer_users developer_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.developer_users
    ADD CONSTRAINT developer_users_pkey PRIMARY KEY (auth_user_id);


--
-- Name: email_log email_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_log
    ADD CONSTRAINT email_log_pkey PRIMARY KEY (email_log_id);


--
-- Name: facilities facilities_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.facilities
    ADD CONSTRAINT facilities_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: facilities facilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_pkey PRIMARY KEY (facility_id);


--
-- Name: get_started get_started_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.get_started
    ADD CONSTRAINT get_started_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (invitation_id);


--
-- Name: invitations invitations_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_token_key UNIQUE (token);


--
-- Name: invoice_documents invoice_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_documents
    ADD CONSTRAINT invoice_documents_pkey PRIMARY KEY (invoice_document_id);


--
-- Name: management_type management_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.management_type
    ADD CONSTRAINT management_type_pkey PRIMARY KEY (management_type);


--
-- Name: marketing_pageview marketing_pageview_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_pageview
    ADD CONSTRAINT marketing_pageview_pkey PRIMARY KEY (id);


--
-- Name: onboarding_slides onboarding_slides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.onboarding_slides
    ADD CONSTRAINT onboarding_slides_pkey PRIMARY KEY (id);


--
-- Name: open_order_totals open_order_totals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.open_order_totals
    ADD CONSTRAINT open_order_totals_pkey PRIMARY KEY (open_order_total_id);


--
-- Name: order_details order_details_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.order_details
    ADD CONSTRAINT order_details_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: order_details order_details_quantity_positive; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.order_details
    ADD CONSTRAINT order_details_quantity_positive CHECK ((quantity > (0)::numeric)) NOT VALID;


--
-- Name: order_statuses order_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_statuses
    ADD CONSTRAINT order_statuses_pkey PRIMARY KEY (status_id);


--
-- Name: orders orders_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.orders
    ADD CONSTRAINT orders_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: payment_transactions payment_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_pkey PRIMARY KEY (payment_transaction_id);


--
-- Name: payment_webhook_events payment_webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_webhook_events
    ADD CONSTRAINT payment_webhook_events_pkey PRIMARY KEY (webhook_event_id);


--
-- Name: payment_webhook_events payment_webhook_events_provider_provider_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_webhook_events
    ADD CONSTRAINT payment_webhook_events_provider_provider_event_id_key UNIQUE (provider, provider_event_id);


--
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (payout_id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (permission_id);


--
-- Name: plan_permissions plan_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_permissions
    ADD CONSTRAINT plan_permissions_pkey PRIMARY KEY (plan_id, permission_id);


--
-- Name: prep_type prep_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prep_type
    ADD CONSTRAINT prep_type_pkey PRIMARY KEY (prep_type_id);


--
-- Name: product_consumables product_consumables_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.product_consumables
    ADD CONSTRAINT product_consumables_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: product_consumables product_consumables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_pkey PRIMARY KEY (product_consumable_id);


--
-- Name: product_filter product_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_pkey PRIMARY KEY (products_filter_id);


--
-- Name: product_groups product_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_groups
    ADD CONSTRAINT product_groups_pkey PRIMARY KEY (group_id);


--
-- Name: product_type product_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_type
    ADD CONSTRAINT product_type_pkey PRIMARY KEY (product_type_id);


--
-- Name: products products_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.products
    ADD CONSTRAINT products_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: products products_group_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.products
    ADD CONSTRAINT products_group_id_not_null CHECK ((group_id IS NOT NULL)) NOT VALID;


--
-- Name: products_price_log products_price_log_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.products_price_log
    ADD CONSTRAINT products_price_log_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: products products_price_nonnegative; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.products
    ADD CONSTRAINT products_price_nonnegative CHECK ((price >= (0)::numeric)) NOT VALID;


--
-- Name: products products_weight_lbs_positive; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.products
    ADD CONSTRAINT products_weight_lbs_positive CHECK ((weight_lbs > (0)::numeric)) NOT VALID;


--
-- Name: recent_coffee_order recent_coffee_order_facility_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_facility_id_key UNIQUE (facility_id);


--
-- Name: recent_coffee_order recent_coffee_order_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_pkey PRIMARY KEY (recent_coffee_order_id);


--
-- Name: recipe_components recipe_components_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.recipe_components
    ADD CONSTRAINT recipe_components_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: recipe_components recipe_components_percentage_range; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.recipe_components
    ADD CONSTRAINT recipe_components_percentage_range CHECK (((percentage >= (0)::numeric) AND (percentage <= (1)::numeric))) NOT VALID;


--
-- Name: recipe_components recipe_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_pkey PRIMARY KEY (component_id);


--
-- Name: recipe_weekly_targets recipe_weekly_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_weekly_targets
    ADD CONSTRAINT recipe_weekly_targets_pkey PRIMARY KEY (id);


--
-- Name: recipe_weekly_targets recipe_weekly_targets_recipe_id_facility_id_week_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_weekly_targets
    ADD CONSTRAINT recipe_weekly_targets_recipe_id_facility_id_week_start_key UNIQUE (recipe_id, facility_id, week_start);


--
-- Name: restock_category restock_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restock_category
    ADD CONSTRAINT restock_category_pkey PRIMARY KEY (restock_category_id);


--
-- Name: roast_events roast_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_events
    ADD CONSTRAINT roast_events_pkey PRIMARY KEY (event_id);


--
-- Name: roast_log roast_log_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.roast_log
    ADD CONSTRAINT roast_log_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: roast_log_recipes roast_log_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log_recipes
    ADD CONSTRAINT roast_log_recipes_pkey PRIMARY KEY (roast_log_recipe_id);


--
-- Name: roast_profile_nodes roast_profile_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_profile_nodes
    ADD CONSTRAINT roast_profile_nodes_pkey PRIMARY KEY (node_id);


--
-- Name: roast_profiles roast_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_profiles
    ADD CONSTRAINT roast_profiles_pkey PRIMARY KEY (profile_id);


--
-- Name: roast_recipes roast_recipes_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.roast_recipes
    ADD CONSTRAINT roast_recipes_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: roast_sessions roast_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: roast_smartroast_log roast_smartroast_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_smartroast_log
    ADD CONSTRAINT roast_smartroast_log_pkey PRIMARY KEY (log_id);


--
-- Name: roast_stock_log roast_stock_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_stock_log
    ADD CONSTRAINT roast_stock_log_pkey PRIMARY KEY (stock_log_id);


--
-- Name: roast_temp_nodes roast_temp_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_temp_nodes
    ADD CONSTRAINT roast_temp_nodes_pkey PRIMARY KEY (node_id);


--
-- Name: roaster_bank_accounts roaster_bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_bank_accounts
    ADD CONSTRAINT roaster_bank_accounts_pkey PRIMARY KEY (id);


--
-- Name: roaster_model_smartroast_calibration roaster_model_smartroast_calibration_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_model_smartroast_calibration
    ADD CONSTRAINT roaster_model_smartroast_calibration_pkey PRIMARY KEY (brand, model, event_type);


--
-- Name: roaster_unit_smartroast_calibration roaster_unit_smartroast_calibration_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_unit_smartroast_calibration
    ADD CONSTRAINT roaster_unit_smartroast_calibration_pkey PRIMARY KEY (roaster_unit_id, event_type);


--
-- Name: roaster_units roaster_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_units
    ADD CONSTRAINT roaster_units_pkey PRIMARY KEY (roaster_unit_id);


--
-- Name: data_imports roastmaster_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_imports
    ADD CONSTRAINT roastmaster_imports_pkey PRIMARY KEY (import_id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: sales_activity sales_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_activity
    ADD CONSTRAINT sales_activity_pkey PRIMARY KEY (sales_activity_id);


--
-- Name: sales_area sales_area_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.sales_area
    ADD CONSTRAINT sales_area_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: sales_category sales_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_category
    ADD CONSTRAINT sales_category_pkey PRIMARY KEY (sales_category);


--
-- Name: sales_city sales_city_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_city
    ADD CONSTRAINT sales_city_pkey PRIMARY KEY (sales_city_id);


--
-- Name: sales_data_filter sales_data_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_pkey PRIMARY KEY (sales_data_filter_id);


--
-- Name: sales_goals sales_goals_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.sales_goals
    ADD CONSTRAINT sales_goals_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: sales_goals sales_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_pkey PRIMARY KEY (sales_goal_id);


--
-- Name: sales_notes sales_notes_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.sales_notes
    ADD CONSTRAINT sales_notes_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: sales_parameters sales_parameters_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.sales_parameters
    ADD CONSTRAINT sales_parameters_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: sales_parameters sales_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_parameters
    ADD CONSTRAINT sales_parameters_pkey PRIMARY KEY (sales_parameter_id);


--
-- Name: sales_area sales_region_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_region_pkey PRIMARY KEY (id);


--
-- Name: sales_region sales_region_pkey1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_region
    ADD CONSTRAINT sales_region_pkey1 PRIMARY KEY (id);


--
-- Name: sales_state sales_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_state
    ADD CONSTRAINT sales_state_pkey PRIMARY KEY (id);


--
-- Name: sales_tasks sales_tasks_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.sales_tasks
    ADD CONSTRAINT sales_tasks_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: sales_tracking sales_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_tracking
    ADD CONSTRAINT sales_tracking_pkey PRIMARY KEY (sales_tracking_id);


--
-- Name: setup_countries setup_countries_country_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_country_code_key UNIQUE (country_code);


--
-- Name: setup_countries setup_countries_country_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_country_name_key UNIQUE (country_name);


--
-- Name: setup_countries setup_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_pkey PRIMARY KEY (country_code);


--
-- Name: setup_timezones setup_timezones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setup_timezones
    ADD CONSTRAINT setup_timezones_pkey PRIMARY KEY (timezone_name);


--
-- Name: shipment_received shipment_received_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.shipment_received
    ADD CONSTRAINT shipment_received_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: shipment_received shipment_received_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_pkey PRIMARY KEY (shipment_id);


--
-- Name: shop_config shop_config_company_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_config
    ADD CONSTRAINT shop_config_company_id_key UNIQUE (company_id);


--
-- Name: shop_config shop_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_config
    ADD CONSTRAINT shop_config_pkey PRIMARY KEY (id);


--
-- Name: shop_config shop_config_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_config
    ADD CONSTRAINT shop_config_slug_key UNIQUE (slug);


--
-- Name: shop_invitations shop_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invitations
    ADD CONSTRAINT shop_invitations_pkey PRIMARY KEY (invitation_id);


--
-- Name: shop_invitations shop_invitations_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invitations
    ADD CONSTRAINT shop_invitations_token_key UNIQUE (token);


--
-- Name: shop_order_ref_counter shop_order_ref_counter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_order_ref_counter
    ADD CONSTRAINT shop_order_ref_counter_pkey PRIMARY KEY (company_id);


--
-- Name: shopify_connections shopify_connections_facility_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_connections
    ADD CONSTRAINT shopify_connections_facility_id_key UNIQUE (facility_id);


--
-- Name: shopify_connections shopify_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_connections
    ADD CONSTRAINT shopify_connections_pkey PRIMARY KEY (id);


--
-- Name: shopify_product_mappings shopify_product_mappings_facility_id_shopify_variant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_product_mappings
    ADD CONSTRAINT shopify_product_mappings_facility_id_shopify_variant_id_key UNIQUE (facility_id, shopify_variant_id);


--
-- Name: shopify_product_mappings shopify_product_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_product_mappings
    ADD CONSTRAINT shopify_product_mappings_pkey PRIMARY KEY (id);


--
-- Name: staged_import_sessions staged_import_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_import_sessions
    ADD CONSTRAINT staged_import_sessions_pkey PRIMARY KEY (id);


--
-- Name: staged_line_items staged_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_line_items
    ADD CONSTRAINT staged_line_items_pkey PRIMARY KEY (staged_line_item_id);


--
-- Name: staged_shipments staged_shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_shipments
    ADD CONSTRAINT staged_shipments_pkey PRIMARY KEY (staged_shipment_id);


--
-- Name: standard_parameters standard_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standard_parameters
    ADD CONSTRAINT standard_parameters_pkey PRIMARY KEY (parameters_id);


--
-- Name: standing_order_lines standing_order_lines_customer_id_product_id_coffee_prep_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standing_order_lines
    ADD CONSTRAINT standing_order_lines_customer_id_product_id_coffee_prep_key UNIQUE (customer_id, product_id, coffee_prep);


--
-- Name: standing_order_lines standing_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standing_order_lines
    ADD CONSTRAINT standing_order_lines_pkey PRIMARY KEY (standing_order_line_id);


--
-- Name: statements statements_company_id_period_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_company_id_period_start_key UNIQUE (company_id, period_start);


--
-- Name: statements statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_pkey PRIMARY KEY (statement_id);


--
-- Name: stock_types stock_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_types
    ADD CONSTRAINT stock_types_pkey PRIMARY KEY (stock_type_id);


--
-- Name: subscription_admin_log subscription_admin_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_admin_log
    ADD CONSTRAINT subscription_admin_log_pkey PRIMARY KEY (log_id);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (plan_id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (subscription_id);


--
-- Name: subscriptions subscriptions_stripe_subscription_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_stripe_subscription_id_key UNIQUE (stripe_subscription_id);


--
-- Name: supplier_category supplier_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_category
    ADD CONSTRAINT supplier_category_pkey PRIMARY KEY (supplier_category_id);


--
-- Name: supplier supplier_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.supplier
    ADD CONSTRAINT supplier_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: supplier supplier_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (supplier_id);


--
-- Name: tax_forms tax_forms_company_id_form_type_tax_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_forms
    ADD CONSTRAINT tax_forms_company_id_form_type_tax_year_key UNIQUE (company_id, form_type, tax_year);


--
-- Name: tax_forms tax_forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_forms
    ADD CONSTRAINT tax_forms_pkey PRIMARY KEY (tax_form_id);


--
-- Name: team team_company_id_not_null; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.team
    ADD CONSTRAINT team_company_id_not_null CHECK ((company_id IS NOT NULL)) NOT VALID;


--
-- Name: team team_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (team_member_id);


--
-- Name: setup_timezones unique_tz_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setup_timezones
    ADD CONSTRAINT unique_tz_name UNIQUE (timezone_name);


--
-- Name: user_parameters user_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_parameters
    ADD CONSTRAINT user_parameters_pkey PRIMARY KEY (id);


--
-- Name: user_parameters user_parameters_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_parameters
    ADD CONSTRAINT user_parameters_unique UNIQUE NULLS NOT DISTINCT (user_id, parameter_id, facility_id);


--
-- Name: user_roaster_settings user_roaster_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roaster_settings
    ADD CONSTRAINT user_roaster_settings_pkey PRIMARY KEY (email);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (role_id);


--
-- Name: user_roles user_roles_role_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_name_key UNIQUE (role_name);


--
-- Name: vmi_checkin_items vmi_checkin_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkin_items
    ADD CONSTRAINT vmi_checkin_items_pkey PRIMARY KEY (vmi_checkin_item_id);


--
-- Name: vmi_checkin_items vmi_checkin_items_vmi_checkin_id_product_id_coffee_prep_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkin_items
    ADD CONSTRAINT vmi_checkin_items_vmi_checkin_id_product_id_coffee_prep_key UNIQUE (vmi_checkin_id, product_id, coffee_prep);


--
-- Name: vmi_checkins vmi_checkins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_pkey PRIMARY KEY (vmi_checkin_id);


--
-- Name: weekly_roast_snapshot weekly_roast_snapshot_facility_id_week_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_roast_snapshot
    ADD CONSTRAINT weekly_roast_snapshot_facility_id_week_start_key UNIQUE (facility_id, week_start);


--
-- Name: weekly_roast_snapshot weekly_roast_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_roast_snapshot
    ADD CONSTRAINT weekly_roast_snapshot_pkey PRIMARY KEY (snapshot_id);


--
-- Name: customer_category_name_company_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX customer_category_name_company_idx ON public.customer_category USING btree (customer_category, COALESCE(company_id, '__global__'::text));


--
-- Name: customers_reminder_eligible_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX customers_reminder_eligible_idx ON public.customers USING btree (company_id, last_order_date, last_reminder_sent_at) WHERE ((management_type = 'Customer-Initiated with Reminders'::text) AND (order_reminders_unsubscribed IS NULL));


--
-- Name: email_log_company_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_log_company_event_idx ON public.email_log USING btree (company_id, event_type, sent_at DESC);


--
-- Name: email_log_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_log_customer_idx ON public.email_log USING btree (customer_id, sent_at DESC) WHERE (customer_id IS NOT NULL);


--
-- Name: email_log_resend_message_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_log_resend_message_id_idx ON public.email_log USING btree (resend_message_id) WHERE (resend_message_id IS NOT NULL);


--
-- Name: idx_chargebacks_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chargebacks_company ON public.chargebacks USING btree (company_id);


--
-- Name: idx_chargebacks_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chargebacks_status ON public.chargebacks USING btree (status) WHERE (status = ANY (ARRAY['open'::text, 'evidence_submitted'::text]));


--
-- Name: idx_coffee_history_origin_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coffee_history_origin_facility ON public.coffee_inventory_history USING btree (origin_id, facility_id);


--
-- Name: idx_coffee_inv_purchased_shipment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coffee_inv_purchased_shipment ON public.coffee_inventory_purchased USING btree (shipment_id);


--
-- Name: idx_coffee_source_certifications_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coffee_source_certifications_gin ON public.coffee_source USING gin (certifications);


--
-- Name: idx_coffee_source_flavor_notes_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coffee_source_flavor_notes_gin ON public.coffee_source USING gin (flavor_notes);


--
-- Name: idx_coffee_source_varietals_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coffee_source_varietals_gin ON public.coffee_source USING gin (varietals);


--
-- Name: idx_companies_stripe_connect; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_companies_stripe_connect ON public.companies USING btree (stripe_connect_account_id) WHERE (stripe_connect_account_id IS NOT NULL);


--
-- Name: idx_company_kyc_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_kyc_status ON public.company_kyc USING btree (status) WHERE (status = ANY (ARRAY['submitted'::text, 'under_review'::text]));


--
-- Name: idx_company_parameters_param_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_parameters_param_facility ON public.company_parameters USING btree (parameter_id, facility_id);


--
-- Name: idx_consumable_history_item_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_consumable_history_item_facility ON public.consumable_inventory_history USING btree (consumable_id, facility_id);


--
-- Name: idx_consumable_inv_purchased_shipment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_consumable_inv_purchased_shipment ON public.consumable_inventory_purchased USING btree (shipment_id);


--
-- Name: idx_customer_users_auth_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_users_auth_user ON public.customer_users USING btree (auth_user_id);


--
-- Name: idx_customer_users_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_users_customer ON public.customer_users USING btree (customer_id);


--
-- Name: idx_customer_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_users_email ON public.customer_users USING btree (lower(email));


--
-- Name: idx_customers_shop_access; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_shop_access ON public.customers USING gin (shop_access);


--
-- Name: idx_data_imports_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_imports_facility ON public.data_imports USING btree (facility_id);


--
-- Name: idx_data_imports_facility_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_data_imports_facility_source ON public.data_imports USING btree (facility_id, source, created_at DESC);


--
-- Name: idx_dev_imp_log_company_started; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_imp_log_company_started ON public.developer_impersonation_log USING btree (company_id, started_at DESC);


--
-- Name: idx_dev_imp_log_developer_started; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_imp_log_developer_started ON public.developer_impersonation_log USING btree (developer_id, started_at DESC);


--
-- Name: idx_invoice_documents_staged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_documents_staged ON public.invoice_documents USING btree (staged_shipment_id);


--
-- Name: idx_kyc_bo_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kyc_bo_company ON public.company_kyc_beneficial_owners USING btree (company_id);


--
-- Name: idx_kyc_docs_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kyc_docs_company ON public.company_kyc_documents USING btree (company_id);


--
-- Name: idx_monthly_consumable_stock_consumable_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_monthly_consumable_stock_consumable_facility ON public.monthly_consumable_stock_by_item USING btree (consumable_id, facility_id);


--
-- Name: idx_monthly_consumable_stock_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_monthly_consumable_stock_id ON public.monthly_consumable_stock_by_item USING btree (month_stock_id);


--
-- Name: idx_ogw_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ogw_facility ON public.order_graphs_week USING btree (facility_id);


--
-- Name: idx_ogw_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ogw_pk ON public.order_graphs_week USING btree (week_report_id);


--
-- Name: idx_order_details_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_details_facility ON public.order_details USING btree (facility_id);


--
-- Name: idx_order_details_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_details_order ON public.order_details USING btree (order_id);


--
-- Name: idx_order_details_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_details_product ON public.order_details USING btree (product_id);


--
-- Name: idx_orders_customer_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_customer_date ON public.orders USING btree (customer_id, order_date DESC);


--
-- Name: idx_orders_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_date_status ON public.orders USING btree (order_date, order_status);


--
-- Name: idx_orders_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_facility ON public.orders USING btree (facility_id);


--
-- Name: idx_orders_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_payment_status ON public.orders USING btree (payment_status) WHERE (payment_status IS NOT NULL);


--
-- Name: idx_orders_payment_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_payment_transaction_id ON public.orders USING btree (payment_transaction_id) WHERE (payment_transaction_id IS NOT NULL);


--
-- Name: idx_orders_receipt_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_receipt_token ON public.orders USING btree (receipt_token) WHERE (receipt_token IS NOT NULL);


--
-- Name: idx_orders_shop_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_orders_shop_order_id ON public.orders USING btree (facility_id, shop_order_id) WHERE (shop_order_id IS NOT NULL);


--
-- Name: idx_orders_shop_order_id_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_shop_order_id_lookup ON public.orders USING btree (shop_order_id) WHERE (shop_order_id IS NOT NULL);


--
-- Name: idx_orders_shop_order_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_orders_shop_order_ref ON public.orders USING btree (shop_order_ref) WHERE (shop_order_ref IS NOT NULL);


--
-- Name: idx_orders_shopify_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_orders_shopify_order_id ON public.orders USING btree (facility_id, shopify_order_id) WHERE (shopify_order_id IS NOT NULL);


--
-- Name: idx_orders_shopify_order_id_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_shopify_order_id_lookup ON public.orders USING btree (shopify_order_id) WHERE (shopify_order_id IS NOT NULL);


--
-- Name: idx_payment_txn_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_company ON public.payment_transactions USING btree (company_id);


--
-- Name: idx_payment_txn_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_company_created ON public.payment_transactions USING btree (company_id, created_at DESC);


--
-- Name: idx_payment_txn_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payment_txn_idempotency ON public.payment_transactions USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: idx_payment_txn_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_order ON public.payment_transactions USING btree (order_id);


--
-- Name: idx_payment_txn_payout_eligible; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_payout_eligible ON public.payment_transactions USING btree (company_id, settled_at) WHERE ((settled = true) AND (paid_out = false) AND (status = 'approved'::text));


--
-- Name: idx_payment_txn_payout_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_payout_id ON public.payment_transactions USING btree (payout_id) WHERE (payout_id IS NOT NULL);


--
-- Name: idx_payment_txn_provider_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_txn_provider_ref ON public.payment_transactions USING btree (provider_transaction_id) WHERE (provider_transaction_id IS NOT NULL);


--
-- Name: idx_payouts_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payouts_company ON public.payouts USING btree (company_id);


--
-- Name: idx_payouts_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payouts_period ON public.payouts USING btree (company_id, period_end DESC);


--
-- Name: idx_payouts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payouts_status ON public.payouts USING btree (status);


--
-- Name: idx_permissions_category_sort; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_permissions_category_sort ON public.permissions USING btree (category, sort_order, permission_id);


--
-- Name: idx_product_groups_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_groups_company ON public.product_groups USING btree (company_id);


--
-- Name: idx_product_groups_exclusive_customers; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_groups_exclusive_customers ON public.product_groups USING gin (exclusive_to_customer_ids) WHERE (exclusive_to_customer_ids IS NOT NULL);


--
-- Name: idx_product_groups_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_groups_facility ON public.product_groups USING btree (facility_id);


--
-- Name: idx_product_groups_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_groups_name ON public.product_groups USING btree (group_name);


--
-- Name: idx_products_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_channel ON public.products USING btree (channel);


--
-- Name: idx_products_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_group_id ON public.products USING btree (group_id);


--
-- Name: idx_products_price_log_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_price_log_date ON public.products_price_log USING btree (product_id, date_updated DESC);


--
-- Name: idx_products_recipe_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_recipe_facility ON public.products USING btree (recipe_id, facility_id);


--
-- Name: idx_recipe_components_recipe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recipe_components_recipe ON public.recipe_components USING btree (recipe_id);


--
-- Name: idx_restock_category_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_restock_category_facility ON public.restock_category USING btree (facility_id);


--
-- Name: idx_roast_events_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_events_session ON public.roast_events USING btree (session_id, elapsed_secs);


--
-- Name: idx_roast_log_charge_weight; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_charge_weight ON public.roast_log USING btree (charge_weight);


--
-- Name: idx_roast_log_facility_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_facility_date ON public.roast_log USING btree (facility_id, roast_date DESC);


--
-- Name: idx_roast_log_origin_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_origin_facility ON public.roast_log USING btree (origin_id, facility_id);


--
-- Name: idx_roast_log_recipe_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_recipe_date ON public.roast_log USING btree (recipe_id, roast_date DESC);


--
-- Name: idx_roast_log_recipes_log; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_recipes_log ON public.roast_log_recipes USING btree (roast_log_id);


--
-- Name: idx_roast_log_recipes_log_recipe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_recipes_log_recipe ON public.roast_log_recipes USING btree (roast_log_id, recipe_id);


--
-- Name: idx_roast_log_recipes_recipe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_recipes_recipe ON public.roast_log_recipes USING btree (recipe_id);


--
-- Name: idx_roast_log_roaster_unit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_roaster_unit ON public.roast_log USING btree (roaster_unit_id);


--
-- Name: idx_roast_log_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_log_session ON public.roast_log USING btree (session_id) WHERE (session_id IS NOT NULL);


--
-- Name: idx_roast_profile_nodes_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_profile_nodes_profile ON public.roast_profile_nodes USING btree (profile_id, elapsed_secs);


--
-- Name: idx_roast_profiles_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_profiles_facility ON public.roast_profiles USING btree (facility_id, is_active);


--
-- Name: idx_roast_recipes_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_recipes_facility ON public.roast_recipes USING btree (facility_id);


--
-- Name: idx_roast_sessions_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_sessions_facility ON public.roast_sessions USING btree (facility_id);


--
-- Name: idx_roast_sessions_log; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_sessions_log ON public.roast_sessions USING btree (roast_log_id) WHERE (roast_log_id IS NOT NULL);


--
-- Name: idx_roast_sessions_profile_templates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_sessions_profile_templates ON public.roast_sessions USING btree (facility_id) WHERE (is_profile_template = true);


--
-- Name: idx_roast_sessions_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_sessions_started_at ON public.roast_sessions USING btree (facility_id, started_at DESC);


--
-- Name: idx_roast_sessions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_sessions_status ON public.roast_sessions USING btree (facility_id, status);


--
-- Name: idx_roast_stock_log_blend; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_stock_log_blend ON public.roast_stock_log USING btree (blend_id, facility_id, created_at DESC) WHERE (stock_type = 'blend'::text);


--
-- Name: idx_roast_stock_log_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_stock_log_origin ON public.roast_stock_log USING btree (origin_id, facility_id, created_at DESC) WHERE (stock_type = 'origin'::text);


--
-- Name: idx_roast_temp_nodes_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_temp_nodes_facility ON public.roast_temp_nodes USING btree (facility_id);


--
-- Name: idx_roast_temp_nodes_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roast_temp_nodes_session ON public.roast_temp_nodes USING btree (session_id, elapsed_secs);


--
-- Name: idx_roaster_bank_active_one; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_roaster_bank_active_one ON public.roaster_bank_accounts USING btree (company_id) WHERE (is_active = true);


--
-- Name: idx_roaster_units_mac_unique_per_company; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_roaster_units_mac_unique_per_company ON public.roaster_units USING btree (company_id, mac_address) WHERE (mac_address IS NOT NULL);


--
-- Name: idx_shop_config_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_config_company ON public.shop_config USING btree (company_id);


--
-- Name: idx_shop_config_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_config_facility ON public.shop_config USING btree (facility_id);


--
-- Name: idx_shop_config_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_config_slug ON public.shop_config USING btree (slug);


--
-- Name: idx_shop_invitations_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_invitations_company ON public.shop_invitations USING btree (company_id);


--
-- Name: idx_shop_invitations_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_invitations_customer ON public.shop_invitations USING btree (customer_id);


--
-- Name: idx_shop_invitations_email_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_invitations_email_open ON public.shop_invitations USING btree (invited_email) WHERE (accepted_at IS NULL);


--
-- Name: idx_shop_invitations_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shop_invitations_token ON public.shop_invitations USING btree (token);


--
-- Name: idx_shopify_connections_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shopify_connections_company ON public.shopify_connections USING btree (company_id);


--
-- Name: idx_shopify_connections_domain; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shopify_connections_domain ON public.shopify_connections USING btree (shop_domain);


--
-- Name: idx_shopify_mappings_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shopify_mappings_facility ON public.shopify_product_mappings USING btree (facility_id);


--
-- Name: idx_shopify_mappings_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shopify_mappings_product ON public.shopify_product_mappings USING btree (product_id);


--
-- Name: idx_smartroast_log_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_smartroast_log_company ON public.roast_smartroast_log USING btree (company_id, created_at DESC);


--
-- Name: idx_smartroast_log_unit_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_smartroast_log_unit_event ON public.roast_smartroast_log USING btree (roaster_unit_id, event_type, created_at DESC);


--
-- Name: idx_staged_import_sessions_import; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staged_import_sessions_import ON public.staged_import_sessions USING btree (import_id, processed);


--
-- Name: idx_staged_line_items_shipment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staged_line_items_shipment ON public.staged_line_items USING btree (staged_shipment_id);


--
-- Name: idx_staged_shipments_company_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staged_shipments_company_facility ON public.staged_shipments USING btree (company_id, facility_id);


--
-- Name: idx_staged_shipments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staged_shipments_status ON public.staged_shipments USING btree (status);


--
-- Name: idx_statements_company_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statements_company_period ON public.statements USING btree (company_id, period_end DESC);


--
-- Name: idx_sub_admin_log_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sub_admin_log_company ON public.subscription_admin_log USING btree (company_id, performed_at DESC);


--
-- Name: idx_sub_admin_log_when; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sub_admin_log_when ON public.subscription_admin_log USING btree (performed_at DESC);


--
-- Name: idx_subscriptions_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscriptions_company_id ON public.subscriptions USING btree (company_id);


--
-- Name: idx_subscriptions_stripe_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscriptions_stripe_customer_id ON public.subscriptions USING btree (stripe_customer_id);


--
-- Name: idx_tax_forms_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_forms_year ON public.tax_forms USING btree (tax_year, company_id);


--
-- Name: idx_unit_cal_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_unit_cal_company ON public.roaster_unit_smartroast_calibration USING btree (company_id);


--
-- Name: idx_user_parameters_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_parameters_company ON public.user_parameters USING btree (company_id);


--
-- Name: idx_user_parameters_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_parameters_user ON public.user_parameters USING btree (user_id, parameter_id);


--
-- Name: idx_webhook_events_txn_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_txn_ref ON public.payment_webhook_events USING btree (provider_transaction_id) WHERE (provider_transaction_id IS NOT NULL);


--
-- Name: idx_webhook_events_unprocessed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_unprocessed ON public.payment_webhook_events USING btree (received_at) WHERE (processed = false);


--
-- Name: idx_weekly_coffee_stock_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_weekly_coffee_stock_id ON public.weekly_coffee_stock_by_origin USING btree (week_stock_id);


--
-- Name: idx_weekly_coffee_stock_origin_facility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_weekly_coffee_stock_origin_facility ON public.weekly_coffee_stock_by_origin USING btree (origin_id, facility_id);


--
-- Name: marketing_pageview_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX marketing_pageview_path_idx ON public.marketing_pageview USING btree (path, viewed_at DESC);


--
-- Name: marketing_pageview_viewed_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX marketing_pageview_viewed_at_idx ON public.marketing_pageview USING btree (viewed_at DESC);


--
-- Name: orders_vmi_checkin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX orders_vmi_checkin_idx ON public.orders USING btree (created_from_vmi_checkin_id) WHERE (created_from_vmi_checkin_id IS NOT NULL);


--
-- Name: recipe_weekly_targets_facility_week_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recipe_weekly_targets_facility_week_idx ON public.recipe_weekly_targets USING btree (facility_id, week_start);


--
-- Name: shipment_received_facility_po_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shipment_received_facility_po_uniq ON public.shipment_received USING btree (facility_id, po_number) WHERE (po_number IS NOT NULL);


--
-- Name: standing_order_lines_company_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX standing_order_lines_company_idx ON public.standing_order_lines USING btree (company_id);


--
-- Name: standing_order_lines_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX standing_order_lines_customer_idx ON public.standing_order_lines USING btree (customer_id, "position");


--
-- Name: uq_coffee_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_coffee_source ON public.coffee_source USING btree (company_id, origin_id, coffee_name);


--
-- Name: user_roaster_settings_id_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_roaster_settings_id_key ON public.user_roaster_settings USING btree (user_roaster_settings_id);


--
-- Name: vmi_checkin_items_checkin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vmi_checkin_items_checkin_idx ON public.vmi_checkin_items USING btree (vmi_checkin_id);


--
-- Name: vmi_checkins_company_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vmi_checkins_company_idx ON public.vmi_checkins USING btree (company_id, visited_at DESC);


--
-- Name: vmi_checkins_customer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vmi_checkins_customer_idx ON public.vmi_checkins USING btree (customer_id, visited_at DESC);


--
-- Name: bag_sizes trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.bag_sizes FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: blending_worksheet trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: channel trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.channel FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: charge_weight_options trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.charge_weight_options FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: chargebacks trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.chargebacks FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory_history trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory_purchased trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_source trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_source FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_usage_by_month trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_usage_by_month FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: companies trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.companies FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: company_kyc trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.company_kyc FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: company_kyc_beneficial_owners trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.company_kyc_beneficial_owners FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: company_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.company_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: company_signup_form trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.company_signup_form FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory_history trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory_purchased trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_type trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_type FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: contact_role trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.contact_role FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: contacts trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_notes_detail trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_notes_detail FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_sales_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_sales_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customers trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: facilities trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.facilities FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: invitations trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: invoice_documents trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.invoice_documents FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: management_type trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.management_type FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: open_order_totals trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.open_order_totals FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: order_details trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: order_statuses trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.order_statuses FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: orders trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: payment_transactions trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.payment_transactions FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: payouts trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.payouts FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: product_consumables trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_consumables FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: product_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: product_type trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_type FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: products trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: products_price_log trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: recent_coffee_order trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.recent_coffee_order FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: recipe_components trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_log trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_recipes trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_stock_log trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_stock_log FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roaster_bank_accounts trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roaster_bank_accounts FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roaster_units trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roaster_units FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_activity trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_activity FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_area trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_area FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_city trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_city FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_data_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_data_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_goals trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_goals FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_notes trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_region trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_region FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_state trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_state FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_state_backup trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_state_backup FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_tasks trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_tasks FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_tracking trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_tracking FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: setup_countries trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.setup_countries FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: setup_timezones trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.setup_timezones FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: shipment_received trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: shop_config trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.shop_config FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: size trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.size FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: staged_line_items trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.staged_line_items FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: staged_shipments trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.staged_shipments FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: standard_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.standard_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: stock_types trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.stock_types FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: supplier trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: supplier_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.supplier_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: team trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.team FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: user_roaster_settings trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.user_roaster_settings FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: user_roles trg_audit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.user_roles FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: bag_sizes trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.bag_sizes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: blending_worksheet trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: channel trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.channel FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: charge_weight_options trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.charge_weight_options FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: chargebacks trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.chargebacks FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory_history trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory_purchased trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_source trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_source FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_usage_by_month trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_usage_by_month FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: companies trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: company_kyc trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.company_kyc FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: company_kyc_beneficial_owners trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.company_kyc_beneficial_owners FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: company_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.company_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: company_signup_form trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.company_signup_form FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory_history trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory_purchased trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_type trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_type FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: contact_role trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.contact_role FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: contacts trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_notes_detail trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_notes_detail FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_sales_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_sales_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customers trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: facilities trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.facilities FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: invitations trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: invoice_documents trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.invoice_documents FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: management_type trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.management_type FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: open_order_totals trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.open_order_totals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: order_details trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: order_statuses trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.order_statuses FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: orders trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: payment_transactions trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.payment_transactions FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: payouts trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.payouts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: product_consumables trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_consumables FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: product_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: product_type trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_type FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: products trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: products_price_log trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: recent_coffee_order trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.recent_coffee_order FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: recipe_components trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_log trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_recipes trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_stock_log trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_stock_log FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roaster_bank_accounts trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roaster_bank_accounts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roaster_units trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roaster_units FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_activity trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_activity FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_area trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_area FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_city trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_city FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_data_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_data_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_goals trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_goals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_notes trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_region trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_region FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_state trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_state FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_state_backup trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_state_backup FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_tasks trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_tasks FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_tracking trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_tracking FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: setup_countries trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.setup_countries FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: setup_timezones trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.setup_timezones FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: shipment_received trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: shop_config trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.shop_config FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: size trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.size FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: staged_line_items trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.staged_line_items FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: staged_shipments trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.staged_shipments FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: standard_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.standard_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: stock_types trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.stock_types FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: supplier trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: supplier_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.supplier_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: team trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.team FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: user_roaster_settings trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.user_roaster_settings FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: user_roles trg_audit_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: products trg_build_product_name; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_build_product_name BEFORE INSERT OR UPDATE OF group_id, size, channel ON public.products FOR EACH ROW EXECUTE FUNCTION public.build_product_name();


--
-- Name: roast_log trg_cascade_delete_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cascade_delete_session AFTER DELETE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.trg_delete_session_on_log_delete();


--
-- Name: customers trg_clear_email_bounce_on_email_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_email_bounce_on_email_change BEFORE UPDATE OF email ON public.customers FOR EACH ROW EXECUTE FUNCTION public.clear_email_bounce_on_email_change();


--
-- Name: coffee_inventory trg_coffee_nudge_recalc; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_coffee_nudge_recalc BEFORE UPDATE OF updated_at ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.trg_recalc_coffee_on_nudge();


--
-- Name: coffee_inventory_purchased trg_coffee_purchase_add; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_coffee_purchase_add AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.update_coffee_stock_purchased();


--
-- Name: coffee_inventory trg_coffee_restock_category_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_coffee_restock_category_change BEFORE UPDATE OF restock_category_id ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.trg_recalc_coffee_on_category_change();


--
-- Name: company_kyc trg_company_kyc_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_company_kyc_updated_at BEFORE UPDATE ON public.company_kyc FOR EACH ROW EXECUTE FUNCTION public.trg_set_company_kyc_updated_at();


--
-- Name: coffee_inventory_purchased trg_compute_coffee_purchase_amount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_compute_coffee_purchase_amount BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, coffee_source_id ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.compute_coffee_purchase_amount();


--
-- Name: consumable_inventory_purchased trg_consumable_purchase_add; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_consumable_purchase_add AFTER INSERT OR DELETE OR UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.update_consumable_stock_purchased();


--
-- Name: consumable_inventory trg_consumable_restock_category_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_consumable_restock_category_change AFTER UPDATE OF restock_category_id ON public.consumable_inventory FOR EACH ROW WHEN ((old.restock_category_id IS DISTINCT FROM new.restock_category_id)) EXECUTE FUNCTION public.trg_recalc_consumable_on_category_change();


--
-- Name: coffee_inventory_history trg_copy_coffee_history_to_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_copy_coffee_history_to_parent AFTER INSERT ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.push_coffee_history_to_parent();


--
-- Name: consumable_inventory_history trg_copy_consumable_history_to_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_copy_consumable_history_to_parent AFTER INSERT ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.push_consumable_history_to_parent();


--
-- Name: customer_users trg_customer_users_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_users_updated BEFORE INSERT OR UPDATE ON public.customer_users FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: email_log trg_flag_customer_on_email_bounce; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_flag_customer_on_email_bounce AFTER UPDATE OF status ON public.email_log FOR EACH ROW EXECUTE FUNCTION public.flag_customer_on_email_bounce();


--
-- Name: coffee_inventory trg_guard_coffee_baseline; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_coffee_baseline BEFORE UPDATE OF last_inventory, inventory_count_bags ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.guard_coffee_inventory_baseline();


--
-- Name: consumable_inventory trg_guard_consumable_baseline; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_consumable_baseline BEFORE UPDATE OF last_inventory_date, inventory_count ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.guard_consumable_inventory_baseline();


--
-- Name: order_details trg_handle_order_details; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_handle_order_details BEFORE INSERT OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_order_detail_logic();


--
-- Name: coffee_inventory trg_manual_inventory_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_manual_inventory_update BEFORE INSERT OR UPDATE OF origin_id, facility_id, last_inventory, inventory_count_bags, bag_size ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_manual_inventory_update();


--
-- Name: customers trg_merge_customer; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_merge_customer AFTER UPDATE OF merge_into_id ON public.customers FOR EACH ROW WHEN (((new.merge_into_id IS NOT NULL) AND (old.merge_into_id IS DISTINCT FROM new.merge_into_id))) EXECUTE FUNCTION public.trg_do_customer_merge();


--
-- Name: products trg_merge_product; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_merge_product AFTER UPDATE OF merge_into_id ON public.products FOR EACH ROW WHEN (((new.merge_into_id IS NOT NULL) AND (old.merge_into_id IS DISTINCT FROM new.merge_into_id))) EXECUTE FUNCTION public.trg_do_product_merge();


--
-- Name: sales_notes trg_note_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_note_change AFTER INSERT OR DELETE OR UPDATE ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.trg_fn_note_change();


--
-- Name: orders trg_order_status_changed_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_order_status_changed_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_order_status_changed_at();


--
-- Name: orders trg_order_status_consumable_sync; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_order_status_consumable_sync AFTER UPDATE OF order_status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.recalculate_consumables_on_order_status();


--
-- Name: payment_transactions trg_payment_txn_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payment_txn_updated_at BEFORE UPDATE ON public.payment_transactions FOR EACH ROW EXECUTE FUNCTION public.trg_set_payment_txn_updated_at();


--
-- Name: sales_tracking trg_period_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_period_change BEFORE UPDATE OF period ON public.sales_tracking FOR EACH ROW EXECUTE FUNCTION public.trg_fn_period_change();


--
-- Name: company_signup_form trg_process_company_signup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_process_company_signup BEFORE INSERT ON public.company_signup_form FOR EACH ROW EXECUTE FUNCTION public.process_company_signup();


--
-- Name: product_groups trg_product_groups_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_product_groups_updated_at BEFORE UPDATE ON public.product_groups FOR EACH ROW EXECUTE FUNCTION public.trg_set_product_groups_updated_at();


--
-- Name: coffee_inventory trg_propagate_coffee_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_coffee_cost AFTER UPDATE OF latest_cost ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.propagate_coffee_cost_change();


--
-- Name: coffee_inventory_purchased trg_propagate_coffee_purchase_cost_to_orders; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_coffee_purchase_cost_to_orders AFTER INSERT OR UPDATE OF cost_lb ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.propagate_coffee_purchase_to_orders();


--
-- Name: coffee_source trg_propagate_coffee_source_bag_size; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_coffee_source_bag_size AFTER UPDATE OF bag_size ON public.coffee_source FOR EACH ROW EXECUTE FUNCTION public.propagate_coffee_source_bag_size();


--
-- Name: product_consumables trg_propagate_consumable_bom; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_consumable_bom AFTER INSERT OR DELETE OR UPDATE ON public.product_consumables FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_bom_to_product();


--
-- Name: consumable_inventory trg_propagate_consumable_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_consumable_cost AFTER UPDATE OF last_cost_unit ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_cost_to_products();


--
-- Name: consumable_inventory_purchased trg_propagate_consumable_purchase_cost_to_orders; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_consumable_purchase_cost_to_orders AFTER INSERT OR UPDATE OF cost_unit ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.propagate_consumable_purchase_to_orders();


--
-- Name: products_price_log trg_propagate_price_log_to_orders; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_price_log_to_orders AFTER INSERT OR UPDATE OF price, date_updated ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.propagate_price_log_to_orders();


--
-- Name: shipment_received trg_propagate_shipping_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_propagate_shipping_cost AFTER INSERT OR UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.trg_shipment_cost_update();


--
-- Name: team trg_provision_user_filter_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_provision_user_filter_rows AFTER INSERT ON public.team FOR EACH ROW EXECUTE FUNCTION public.provision_user_filter_rows();


--
-- Name: team trg_provision_user_roaster_settings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_provision_user_roaster_settings AFTER INSERT ON public.team FOR EACH ROW EXECUTE FUNCTION public.provision_user_roaster_settings();


--
-- Name: coffee_inventory_purchased trg_push_last_coffee_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_push_last_coffee_cost AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.trg_coffee_purchase_cost_update();


--
-- Name: consumable_inventory_purchased trg_push_last_consumable_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_push_last_consumable_cost AFTER INSERT OR UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.update_last_consumable_cost();


--
-- Name: recent_coffee_order trg_recent_coffee_order_calcs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_recent_coffee_order_calcs BEFORE UPDATE OF total_pallets, current_shipment_id ON public.recent_coffee_order FOR EACH ROW EXECUTE FUNCTION public.compute_recent_coffee_order_calcs();


--
-- Name: recipe_weekly_targets trg_recipe_weekly_targets_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_recipe_weekly_targets_touch BEFORE UPDATE ON public.recipe_weekly_targets FOR EACH ROW EXECUTE FUNCTION public.touch_recipe_weekly_targets_updated_at();


--
-- Name: consumable_inventory trg_refresh_consumable_cost_from_fallback; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_refresh_consumable_cost_from_fallback AFTER UPDATE OF fallback_unit_cost ON public.consumable_inventory FOR EACH ROW WHEN ((old.fallback_unit_cost IS DISTINCT FROM new.fallback_unit_cost)) EXECUTE FUNCTION public.refresh_consumable_cost_from_fallback();


--
-- Name: coffee_inventory trg_refresh_cost_from_fallback; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_refresh_cost_from_fallback AFTER UPDATE OF fallback_cost ON public.coffee_inventory FOR EACH ROW WHEN ((old.fallback_cost IS DISTINCT FROM new.fallback_cost)) EXECUTE FUNCTION public.refresh_latest_cost_from_fallback();


--
-- Name: coffee_inventory trg_refresh_par_on_bag_size_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_refresh_par_on_bag_size_change AFTER UPDATE OF bag_size ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.refresh_par_on_bag_size_change();


--
-- Name: restock_category trg_restock_category_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_restock_category_updated_at BEFORE UPDATE ON public.restock_category FOR EACH ROW EXECUTE FUNCTION public.trg_set_restock_category_updated_at();


--
-- Name: roast_profiles trg_roast_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_roast_profiles_updated_at BEFORE UPDATE ON public.roast_profiles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_sessions trg_roast_sessions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_roast_sessions_updated_at BEFORE UPDATE ON public.roast_sessions FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: shop_config trg_shop_config_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shop_config_updated_at BEFORE UPDATE ON public.shop_config FOR EACH ROW EXECUTE FUNCTION public.trg_set_shop_config_updated_at();


--
-- Name: shop_invitations trg_shop_invitations_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shop_invitations_updated BEFORE INSERT OR UPDATE ON public.shop_invitations FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_smartroast_log trg_smartroast_calibration_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_smartroast_calibration_update AFTER INSERT ON public.roast_smartroast_log FOR EACH ROW EXECUTE FUNCTION public.update_smartroast_calibrations();


--
-- Name: roast_log trg_stamp_roasted_weight; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stamp_roasted_weight BEFORE INSERT OR UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.trg_stamp_roasted_weight();


--
-- Name: shipment_received trg_sync_bag_size_on_shipment_received; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_bag_size_on_shipment_received AFTER UPDATE OF date_received ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.sync_bag_size_on_shipment_received();


--
-- Name: order_details trg_sync_consumable_usage_ins_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_consumable_usage_ins_del AFTER INSERT OR DELETE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_consumable_stock();


--
-- Name: order_details trg_sync_consumable_usage_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_consumable_usage_upd AFTER UPDATE ON public.order_details FOR EACH ROW WHEN (((old.quantity IS DISTINCT FROM new.quantity) OR (old.product_id IS DISTINCT FROM new.product_id))) EXECUTE FUNCTION public.update_consumable_stock();


--
-- Name: coffee_inventory_purchased trg_sync_current_shipment_from_coffee_purchase; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_current_shipment_from_coffee_purchase AFTER INSERT ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.sync_current_shipment_from_coffee_purchase();


--
-- Name: company_parameters trg_sync_day_of_week_company; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_day_of_week_company BEFORE INSERT OR UPDATE OF day_of_week ON public.company_parameters FOR EACH ROW EXECUTE FUNCTION public.trg_sync_day_of_week_company();


--
-- Name: standard_parameters trg_sync_day_of_week_standard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_day_of_week_standard BEFORE INSERT OR UPDATE OF day_of_week ON public.standard_parameters FOR EACH ROW EXECUTE FUNCTION public.trg_sync_day_of_week_standard();


--
-- Name: orders trg_sync_item_status_on_order_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_item_status_on_order_status AFTER UPDATE OF order_status ON public.orders FOR EACH ROW WHEN ((old.order_status IS DISTINCT FROM new.order_status)) EXECUTE FUNCTION public.sync_item_status_on_order_status_change();


--
-- Name: contacts trg_sync_primary_from_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_primary_from_contact AFTER UPDATE OF is_primary ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.sync_primary_from_contact();


--
-- Name: customers trg_sync_primary_from_customer; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_primary_from_customer AFTER UPDATE OF primary_contact_id ON public.customers FOR EACH ROW EXECUTE FUNCTION public.sync_primary_from_customer();


--
-- Name: products_price_log trg_sync_product_price_from_log; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_product_price_from_log AFTER INSERT OR DELETE OR UPDATE OF price, date_updated ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.sync_product_price_from_log();


--
-- Name: recipe_components trg_sync_recipe_costs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_recipe_costs BEFORE INSERT OR UPDATE ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.sync_recipe_component_costs();


--
-- Name: roaster_units trg_sync_roaster_charge_weight; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_roaster_charge_weight BEFORE INSERT OR UPDATE OF max_charge_weight_id ON public.roaster_units FOR EACH ROW EXECUTE FUNCTION public.fn_sync_roaster_charge_weight();


--
-- Name: vmi_checkin_items trg_touch_vmi_checkin_on_item_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_touch_vmi_checkin_on_item_change AFTER INSERT OR DELETE OR UPDATE ON public.vmi_checkin_items FOR EACH ROW EXECUTE FUNCTION public.touch_vmi_checkin_on_item_change();


--
-- Name: roast_log trg_update_batches_since_chaff; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_batches_since_chaff AFTER INSERT OR DELETE OR UPDATE OF "charged?", "chaff_cleaned?", roast_date, facility_id ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.fn_update_batches_since_chaff();


--
-- Name: blending_worksheet trg_update_blend_summary; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_blend_summary BEFORE INSERT OR UPDATE OF roast_recipe_id, amount_to_blend ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.calculate_blend_summary();


--
-- Name: consumable_inventory trg_update_consumable_ordering; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_consumable_ordering BEFORE INSERT OR UPDATE OF consumable_inventory_id, facility_id, last_inventory_date, inventory_count, par, restock_level, restock_category_id, updated_at ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.update_consumable_metrics();


--
-- Name: coffee_inventory trg_update_green_metrics_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_green_metrics_delete AFTER DELETE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();


--
-- Name: coffee_inventory_purchased trg_update_green_metrics_from_purchased; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_green_metrics_from_purchased AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.trg_green_metrics_from_purchased();


--
-- Name: coffee_inventory trg_update_green_metrics_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_green_metrics_insert AFTER INSERT ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();


--
-- Name: coffee_inventory trg_update_green_metrics_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_green_metrics_update AFTER UPDATE OF facility_id, supplier_id, bags_ordered, to_order_bags ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();


--
-- Name: order_details trg_update_order_totals_ins_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_order_totals_ins_del AFTER INSERT OR DELETE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_order_aggregates();


--
-- Name: order_details trg_update_order_totals_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_order_totals_upd AFTER UPDATE ON public.order_details FOR EACH ROW WHEN (((old.total_price IS DISTINCT FROM new.total_price) OR (old.roasted_weight IS DISTINCT FROM new.roasted_weight))) EXECUTE FUNCTION public.update_order_aggregates();


--
-- Name: products trg_update_product_cogs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_product_cogs BEFORE INSERT OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_product_total_cogs();


--
-- Name: roast_recipes trg_update_roasted_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_roasted_cost BEFORE INSERT OR UPDATE OF cost_lb_green ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_roasted_cost();


--
-- Name: sales_notes trg_update_sales_metrics; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_sales_metrics AFTER INSERT OR DELETE OR UPDATE ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.update_customer_sales_metrics();


--
-- Name: customers trg_update_status_on_deal_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_status_on_deal_change BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.update_sales_status_on_deal_change();


--
-- Name: user_parameters trg_user_parameters_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_user_parameters_updated BEFORE UPDATE ON public.user_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: shipment_received trg_void_shipment_cascade; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_void_shipment_cascade AFTER UPDATE OF voided ON public.shipment_received FOR EACH ROW WHEN ((old.voided IS DISTINCT FROM new.voided)) EXECUTE FUNCTION public.void_shipment_cascade();


--
-- Name: coffee_inventory trigger_calculate_ordered_lbs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_calculate_ordered_lbs BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, bag_size ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.update_actual_ordered_lbs();


--
-- Name: customers trigger_manual_interval_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_manual_interval_change BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.update_effective_interval_on_manual_change();


--
-- Name: orders trigger_refresh_customer_stats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_refresh_customer_stats AFTER INSERT OR DELETE OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_customer_metrics_on_order();


--
-- Name: roast_log trigger_roast_log_update_inventory; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_roast_log_update_inventory AFTER INSERT OR DELETE OR UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.trg_roast_log_inventory_update();


--
-- Name: orders trigger_update_order_metrics; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_order_metrics BEFORE INSERT OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_order_metrics();


--
-- Name: shipment_received trigger_update_shipping_unit_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_shipping_unit_cost AFTER INSERT OR UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.calculate_shipping_per_unit();


--
-- Name: coffee_inventory_purchased update_shipment_on_coffee; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_shipment_on_coffee AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.calculate_shipment_totals();


--
-- Name: consumable_inventory_purchased update_shipment_on_consumable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_shipment_on_consumable AFTER INSERT OR DELETE OR UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.calculate_shipment_totals();


--
-- Name: blending_worksheet blending_worksheet_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: blending_worksheet blending_worksheet_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: blending_worksheet blending_worksheet_roast_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_roast_recipe_id_fkey FOREIGN KEY (roast_recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL;


--
-- Name: channel channel_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: charge_weight_options charge_weight_options_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: charge_weight_options charge_weight_options_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: charge_weight_options charge_weight_options_roaster_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_roaster_unit_id_fkey FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id) ON DELETE SET NULL;


--
-- Name: chargebacks chargebacks_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chargebacks
    ADD CONSTRAINT chargebacks_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE RESTRICT;


--
-- Name: chargebacks chargebacks_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chargebacks
    ADD CONSTRAINT chargebacks_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- Name: chargebacks chargebacks_payment_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chargebacks
    ADD CONSTRAINT chargebacks_payment_transaction_id_fkey FOREIGN KEY (payment_transaction_id) REFERENCES public.payment_transactions(payment_transaction_id) ON DELETE RESTRICT;


--
-- Name: coffee_inventory coffee_inventory_bag_size_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_bag_size_fkey FOREIGN KEY (bag_size) REFERENCES public.bag_sizes(bag_size_id) ON DELETE SET NULL;


--
-- Name: coffee_inventory coffee_inventory_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_inventory coffee_inventory_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory_history coffee_inventory_history_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_origin_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_origin_fkey FOREIGN KEY (origin) REFERENCES public.coffee_inventory(origin_id) ON DELETE RESTRICT;


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_shipment_id_fkey FOREIGN KEY (shipment_id) REFERENCES public.shipment_received(shipment_id) ON DELETE SET NULL NOT VALID;


--
-- Name: coffee_inventory coffee_inventory_restock_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_restock_category_id_fkey FOREIGN KEY (restock_category_id) REFERENCES public.restock_category(restock_category_id);


--
-- Name: coffee_inventory coffee_inventory_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.supplier(supplier_id) ON DELETE SET NULL NOT VALID;


--
-- Name: coffee_source coffee_source_bag_size_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_source
    ADD CONSTRAINT coffee_source_bag_size_fkey FOREIGN KEY (bag_size) REFERENCES public.bag_sizes(bag_size_id) ON DELETE SET NULL;


--
-- Name: coffee_source coffee_source_origin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_source
    ADD CONSTRAINT coffee_source_origin_id_fkey FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id) ON DELETE RESTRICT;


--
-- Name: coffee_usage_by_month coffee_usage_by_month_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_usage_by_month coffee_usage_by_month_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: company_kyc_beneficial_owners company_kyc_beneficial_owners_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_beneficial_owners
    ADD CONSTRAINT company_kyc_beneficial_owners_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.company_kyc(company_id) ON DELETE CASCADE;


--
-- Name: company_kyc company_kyc_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc
    ADD CONSTRAINT company_kyc_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: company_kyc_documents company_kyc_documents_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_kyc_documents
    ADD CONSTRAINT company_kyc_documents_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.company_kyc(company_id) ON DELETE CASCADE;


--
-- Name: company_parameters company_parameters_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: company_parameters company_parameters_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: company_parameters company_parameters_parameter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_parameter_id_fkey FOREIGN KEY (parameter_id) REFERENCES public.standard_parameters(parameters_id);


--
-- Name: consumable_inventory consumable_inventory_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: consumable_inventory consumable_inventory_consumable_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_consumable_type_fkey FOREIGN KEY (consumable_type) REFERENCES public.consumable_type(consumable_type_id) ON DELETE SET NULL;


--
-- Name: consumable_inventory consumable_inventory_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: consumable_inventory_history consumable_inventory_history_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_item_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_item_fkey FOREIGN KEY (consumable_inventory_item) REFERENCES public.consumable_inventory(consumable_inventory_id) ON DELETE RESTRICT;


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_shipment_id_fkey FOREIGN KEY (shipment_id) REFERENCES public.shipment_received(shipment_id) ON DELETE SET NULL;


--
-- Name: consumable_inventory consumable_inventory_restock_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_restock_category_id_fkey FOREIGN KEY (restock_category_id) REFERENCES public.restock_category(restock_category_id);


--
-- Name: consumable_type consumable_type_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumable_type
    ADD CONSTRAINT consumable_type_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: contact_role contact_role_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_role
    ADD CONSTRAINT contact_role_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: contacts contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: contacts contacts_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) NOT VALID;


--
-- Name: contacts contacts_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customer_category customer_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_category
    ADD CONSTRAINT customer_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: customer_notes_detail customer_notes_detail_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customer_notes_detail customer_notes_detail_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: customer_notes_detail customer_notes_detail_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customer_sales_filter customer_sales_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customer_sales_filter customer_sales_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customer_sales_filter customer_sales_filter_sales_category_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_sales_category_fkey FOREIGN KEY (sales_category) REFERENCES public.sales_category(sales_category) NOT VALID;


--
-- Name: customer_users customer_users_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_users
    ADD CONSTRAINT customer_users_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: customer_users customer_users_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_users
    ADD CONSTRAINT customer_users_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: customers customers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customers customers_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.setup_countries(country_code);


--
-- Name: customers customers_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customers customers_primary_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_primary_contact_id_fkey FOREIGN KEY (primary_contact_id) REFERENCES public.contacts(contact_id) NOT VALID;


--
-- Name: customers customers_sales_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_sales_area_fkey FOREIGN KEY (sales_area) REFERENCES public.sales_area(id);


--
-- Name: customers customers_sales_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_sales_status_fkey FOREIGN KEY (sales_status) REFERENCES public.sales_activity(sales_activity_id) NOT VALID;


--
-- Name: customers customers_state_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_state_fkey FOREIGN KEY (state) REFERENCES public.sales_state(id) NOT VALID;


--
-- Name: developer_impersonation_log developer_impersonation_log_developer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.developer_impersonation_log
    ADD CONSTRAINT developer_impersonation_log_developer_id_fkey FOREIGN KEY (developer_id) REFERENCES auth.users(id);


--
-- Name: developer_users developer_users_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.developer_users
    ADD CONSTRAINT developer_users_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: email_log email_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_log
    ADD CONSTRAINT email_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE SET NULL;


--
-- Name: email_log email_log_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_log
    ADD CONSTRAINT email_log_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: facilities facilities_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: facilities facilities_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_country_fkey FOREIGN KEY (country_code) REFERENCES public.setup_countries(country_code);


--
-- Name: coffee_inventory_purchased fk_coffee_inventory_purchased_source; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT fk_coffee_inventory_purchased_source FOREIGN KEY (coffee_source_id) REFERENCES public.coffee_source(coffee_source_id) ON DELETE SET NULL;


--
-- Name: customers fk_last_order; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_last_order FOREIGN KEY (last_order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- Name: invitations invitations_company_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_company_fk FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: invitations invitations_facility_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_facility_fk FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: invitations invitations_invited_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_invited_by_fk FOREIGN KEY (invited_by) REFERENCES public.team(team_member_id);


--
-- Name: invitations invitations_role_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_role_fk FOREIGN KEY (role_id) REFERENCES public.user_roles(role_id);


--
-- Name: invoice_documents invoice_documents_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_documents
    ADD CONSTRAINT invoice_documents_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: invoice_documents invoice_documents_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_documents
    ADD CONSTRAINT invoice_documents_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: invoice_documents invoice_documents_staged_shipment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_documents
    ADD CONSTRAINT invoice_documents_staged_shipment_fkey FOREIGN KEY (staged_shipment_id) REFERENCES public.staged_shipments(staged_shipment_id) ON DELETE SET NULL;


--
-- Name: management_type management_type_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.management_type
    ADD CONSTRAINT management_type_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: open_order_totals open_order_totals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.open_order_totals
    ADD CONSTRAINT open_order_totals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: order_details order_details_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: order_details order_details_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: order_details order_details_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE NOT VALID;


--
-- Name: order_details order_details_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE SET NULL;


--
-- Name: order_details order_details_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL NOT VALID;


--
-- Name: orders orders_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: orders orders_created_from_vmi_checkin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_created_from_vmi_checkin_id_fkey FOREIGN KEY (created_from_vmi_checkin_id) REFERENCES public.vmi_checkins(vmi_checkin_id) ON DELETE SET NULL;


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE SET NULL;


--
-- Name: orders orders_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: payment_transactions payment_transactions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE RESTRICT;


--
-- Name: payment_transactions payment_transactions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- Name: payment_transactions payment_transactions_payout_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_payout_id_fkey FOREIGN KEY (payout_id) REFERENCES public.payouts(payout_id) ON DELETE SET NULL;


--
-- Name: payouts payouts_bank_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES public.roaster_bank_accounts(id) ON DELETE SET NULL;


--
-- Name: payouts payouts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE RESTRICT;


--
-- Name: plan_permissions plan_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_permissions
    ADD CONSTRAINT plan_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: plan_permissions plan_permissions_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_permissions
    ADD CONSTRAINT plan_permissions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(plan_id) ON DELETE CASCADE;


--
-- Name: prep_type prep_type_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prep_type
    ADD CONSTRAINT prep_type_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: product_consumables product_consumables_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: product_consumables product_consumables_consumable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_consumable_id_fkey FOREIGN KEY (consumable_id) REFERENCES public.consumable_inventory(consumable_inventory_id) ON DELETE CASCADE;


--
-- Name: product_consumables product_consumables_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: product_consumables product_consumables_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- Name: product_filter product_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: product_filter product_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: product_groups product_groups_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_groups
    ADD CONSTRAINT product_groups_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: product_groups product_groups_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_groups
    ADD CONSTRAINT product_groups_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE CASCADE;


--
-- Name: product_type product_type_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_type
    ADD CONSTRAINT product_type_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: products products_channel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_channel_fkey FOREIGN KEY (channel) REFERENCES public.channel(channel_id) ON DELETE SET NULL;


--
-- Name: products products_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: products products_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: products products_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.product_groups(group_id) ON DELETE SET NULL;


--
-- Name: products_price_log products_price_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT products_price_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: products_price_log products_price_log_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT products_price_log_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: products_price_log products_price_log_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT products_price_log_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- Name: products products_product_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_product_type_fkey FOREIGN KEY (product_type) REFERENCES public.product_type(product_type_id) ON DELETE SET NULL;


--
-- Name: products products_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL;


--
-- Name: products products_size_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_size_fkey FOREIGN KEY (size) REFERENCES public.size(size_id) ON DELETE SET NULL;


--
-- Name: recent_coffee_order recent_coffee_order_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: recent_coffee_order recent_coffee_order_current_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_current_shipment_id_fkey FOREIGN KEY (current_shipment_id) REFERENCES public.shipment_received(shipment_id);


--
-- Name: recent_coffee_order recent_coffee_order_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: recipe_components recipe_components_coffee_item_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_coffee_item_fkey FOREIGN KEY (coffee_item) REFERENCES public.coffee_inventory(origin_id) ON DELETE SET NULL;


--
-- Name: recipe_components recipe_components_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: recipe_components recipe_components_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: recipe_components recipe_components_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE CASCADE;


--
-- Name: recipe_weekly_targets recipe_weekly_targets_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_weekly_targets
    ADD CONSTRAINT recipe_weekly_targets_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE CASCADE;


--
-- Name: recipe_weekly_targets recipe_weekly_targets_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipe_weekly_targets
    ADD CONSTRAINT recipe_weekly_targets_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE CASCADE;


--
-- Name: restock_category restock_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restock_category
    ADD CONSTRAINT restock_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: restock_category restock_category_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restock_category
    ADD CONSTRAINT restock_category_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE CASCADE;


--
-- Name: roast_events roast_events_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_events
    ADD CONSTRAINT roast_events_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.roast_sessions(session_id) ON DELETE CASCADE;


--
-- Name: roast_log roast_log_coffee_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_coffee_source_id_fkey FOREIGN KEY (coffee_source_id) REFERENCES public.coffee_source(coffee_source_id) ON DELETE SET NULL;


--
-- Name: roast_log roast_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_log roast_log_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_log roast_log_origin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_origin_id_fkey FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id) ON DELETE RESTRICT;


--
-- Name: roast_log roast_log_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL NOT VALID;


--
-- Name: roast_log_recipes roast_log_recipes_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log_recipes
    ADD CONSTRAINT roast_log_recipes_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id);


--
-- Name: roast_log_recipes roast_log_recipes_roast_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log_recipes
    ADD CONSTRAINT roast_log_recipes_roast_log_id_fkey FOREIGN KEY (roast_log_id) REFERENCES public.roast_log(roast_log_id) ON DELETE CASCADE;


--
-- Name: roast_log roast_log_reference_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_reference_profile_id_fkey FOREIGN KEY (reference_profile_id) REFERENCES public.roast_sessions(session_id) ON DELETE SET NULL;


--
-- Name: roast_log roast_log_roaster_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_roaster_unit_id_fkey FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id);


--
-- Name: roast_log roast_log_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.roast_sessions(session_id) ON DELETE SET NULL;


--
-- Name: roast_profile_nodes roast_profile_nodes_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_profile_nodes
    ADD CONSTRAINT roast_profile_nodes_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.roast_profiles(profile_id) ON DELETE CASCADE;


--
-- Name: roast_profiles roast_profiles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_profiles
    ADD CONSTRAINT roast_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: roast_profiles roast_profiles_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_profiles
    ADD CONSTRAINT roast_profiles_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL;


--
-- Name: roast_recipes roast_recipes_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT roast_recipes_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_recipes roast_recipes_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT roast_recipes_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_sessions roast_sessions_charge_weight_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_charge_weight_id_fkey FOREIGN KEY (charge_weight_id) REFERENCES public.charge_weight_options(id) ON DELETE SET NULL;


--
-- Name: roast_sessions roast_sessions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: roast_sessions roast_sessions_origin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_origin_id_fkey FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id) ON DELETE SET NULL;


--
-- Name: roast_sessions roast_sessions_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_recipe_id_fkey FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id) ON DELETE SET NULL;


--
-- Name: roast_sessions roast_sessions_roast_log_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_roast_log_id_fkey FOREIGN KEY (roast_log_id) REFERENCES public.roast_log(roast_log_id) ON DELETE SET NULL;


--
-- Name: roast_sessions roast_sessions_roaster_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_sessions
    ADD CONSTRAINT roast_sessions_roaster_unit_id_fkey FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id) ON DELETE SET NULL;


--
-- Name: roast_stock_log roast_stock_log_blend_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_stock_log
    ADD CONSTRAINT roast_stock_log_blend_fk FOREIGN KEY (blend_id) REFERENCES public.roast_recipes(recipe_id);


--
-- Name: roast_stock_log roast_stock_log_origin_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_stock_log
    ADD CONSTRAINT roast_stock_log_origin_fk FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id);


--
-- Name: roast_stock_log roast_stock_log_stock_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_stock_log
    ADD CONSTRAINT roast_stock_log_stock_type_fk FOREIGN KEY (stock_type) REFERENCES public.stock_types(stock_type_id);


--
-- Name: roast_temp_nodes roast_temp_nodes_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_temp_nodes
    ADD CONSTRAINT roast_temp_nodes_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.roast_sessions(session_id) ON DELETE CASCADE;


--
-- Name: roaster_bank_accounts roaster_bank_accounts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_bank_accounts
    ADD CONSTRAINT roaster_bank_accounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: roaster_units roaster_units_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_units
    ADD CONSTRAINT roaster_units_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roaster_units roaster_units_max_charge_weight_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_units
    ADD CONSTRAINT roaster_units_max_charge_weight_id_fkey FOREIGN KEY (max_charge_weight_id) REFERENCES public.charge_weight_options(id);


--
-- Name: roaster_units roaster_units_min_charge_weight_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_units
    ADD CONSTRAINT roaster_units_min_charge_weight_id_fkey FOREIGN KEY (min_charge_weight_id) REFERENCES public.charge_weight_options(id);


--
-- Name: data_imports roastmaster_imports_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_imports
    ADD CONSTRAINT roastmaster_imports_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: data_imports roastmaster_imports_imported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_imports
    ADD CONSTRAINT roastmaster_imports_imported_by_fkey FOREIGN KEY (imported_by) REFERENCES auth.users(id);


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.user_roles(role_id) ON DELETE CASCADE;


--
-- Name: sales_area sales_area_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_area_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.sales_state(id);


--
-- Name: sales_category sales_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_category
    ADD CONSTRAINT sales_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_city sales_city_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_city
    ADD CONSTRAINT sales_city_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.sales_state(id);


--
-- Name: sales_data_filter sales_data_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_data_filter sales_data_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_goals sales_goals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_goals sales_goals_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_notes sales_notes_activity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT sales_notes_activity_fkey FOREIGN KEY (sales_activity_type) REFERENCES public.sales_activity(sales_activity_id) NOT VALID;


--
-- Name: sales_notes sales_notes_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT sales_notes_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_notes sales_notes_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT sales_notes_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) NOT VALID;


--
-- Name: sales_parameters sales_parameters_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_parameters
    ADD CONSTRAINT sales_parameters_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_area sales_region_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_region_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_state_backup sales_state_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_state_backup
    ADD CONSTRAINT sales_state_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_state sales_state_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_state
    ADD CONSTRAINT sales_state_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.sales_region(id);


--
-- Name: sales_tasks sales_tasks_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_tasks
    ADD CONSTRAINT sales_tasks_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_tasks sales_tasks_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_tasks
    ADD CONSTRAINT sales_tasks_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE SET NULL;


--
-- Name: sales_tracking sales_tracking_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_tracking
    ADD CONSTRAINT sales_tracking_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: shipment_received shipment_received_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: shipment_received shipment_received_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: shipment_received shipment_received_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.supplier(supplier_id) ON DELETE SET NULL;


--
-- Name: shop_config shop_config_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_config
    ADD CONSTRAINT shop_config_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: shop_config shop_config_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_config
    ADD CONSTRAINT shop_config_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE SET NULL;


--
-- Name: shop_invitations shop_invitations_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invitations
    ADD CONSTRAINT shop_invitations_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: shop_order_ref_counter shop_order_ref_counter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_order_ref_counter
    ADD CONSTRAINT shop_order_ref_counter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: shopify_connections shopify_connections_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_connections
    ADD CONSTRAINT shopify_connections_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: shopify_connections shopify_connections_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_connections
    ADD CONSTRAINT shopify_connections_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE CASCADE;


--
-- Name: shopify_product_mappings shopify_product_mappings_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_product_mappings
    ADD CONSTRAINT shopify_product_mappings_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE CASCADE;


--
-- Name: shopify_product_mappings shopify_product_mappings_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shopify_product_mappings
    ADD CONSTRAINT shopify_product_mappings_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE SET NULL;


--
-- Name: size size_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size
    ADD CONSTRAINT size_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_smartroast_log smartroast_log_session_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_smartroast_log
    ADD CONSTRAINT smartroast_log_session_fk FOREIGN KEY (session_id) REFERENCES public.roast_sessions(session_id) ON DELETE CASCADE;


--
-- Name: roast_smartroast_log smartroast_log_unit_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roast_smartroast_log
    ADD CONSTRAINT smartroast_log_unit_fk FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id) ON DELETE SET NULL;


--
-- Name: staged_import_sessions staged_import_sessions_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_import_sessions
    ADD CONSTRAINT staged_import_sessions_import_id_fkey FOREIGN KEY (import_id) REFERENCES public.data_imports(import_id) ON DELETE CASCADE;


--
-- Name: staged_line_items staged_line_items_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_line_items
    ADD CONSTRAINT staged_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: staged_line_items staged_line_items_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_line_items
    ADD CONSTRAINT staged_line_items_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: staged_line_items staged_line_items_staged_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_line_items
    ADD CONSTRAINT staged_line_items_staged_shipment_id_fkey FOREIGN KEY (staged_shipment_id) REFERENCES public.staged_shipments(staged_shipment_id) ON DELETE CASCADE;


--
-- Name: staged_shipments staged_shipments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_shipments
    ADD CONSTRAINT staged_shipments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: staged_shipments staged_shipments_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_shipments
    ADD CONSTRAINT staged_shipments_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: standing_order_lines standing_order_lines_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standing_order_lines
    ADD CONSTRAINT standing_order_lines_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: standing_order_lines standing_order_lines_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standing_order_lines
    ADD CONSTRAINT standing_order_lines_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: standing_order_lines standing_order_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.standing_order_lines
    ADD CONSTRAINT standing_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE RESTRICT;


--
-- Name: statements statements_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: subscription_admin_log subscription_admin_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_admin_log
    ADD CONSTRAINT subscription_admin_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.subscription_plans(plan_id);


--
-- Name: supplier_category supplier_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_category
    ADD CONSTRAINT supplier_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: supplier supplier_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: supplier supplier_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: tax_forms tax_forms_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_forms
    ADD CONSTRAINT tax_forms_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: team team_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: team team_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: team team_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: team team_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_role_fkey FOREIGN KEY (role) REFERENCES public.user_roles(role_id);


--
-- Name: roaster_unit_smartroast_calibration unit_cal_unit_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roaster_unit_smartroast_calibration
    ADD CONSTRAINT unit_cal_unit_fk FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id) ON DELETE CASCADE;


--
-- Name: user_parameters user_parameters_company_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_parameters
    ADD CONSTRAINT user_parameters_company_fk FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: user_parameters user_parameters_facility_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_parameters
    ADD CONSTRAINT user_parameters_facility_fk FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: user_parameters user_parameters_param_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_parameters
    ADD CONSTRAINT user_parameters_param_fk FOREIGN KEY (parameter_id) REFERENCES public.standard_parameters(parameters_id) ON DELETE CASCADE;


--
-- Name: user_roaster_settings user_roaster_settings_roaster_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roaster_settings
    ADD CONSTRAINT user_roaster_settings_roaster_unit_id_fkey FOREIGN KEY (roaster_unit_id) REFERENCES public.roaster_units(roaster_unit_id);


--
-- Name: vmi_checkin_items vmi_checkin_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkin_items
    ADD CONSTRAINT vmi_checkin_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- Name: vmi_checkin_items vmi_checkin_items_vmi_checkin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkin_items
    ADD CONSTRAINT vmi_checkin_items_vmi_checkin_id_fkey FOREIGN KEY (vmi_checkin_id) REFERENCES public.vmi_checkins(vmi_checkin_id) ON DELETE CASCADE;


--
-- Name: vmi_checkins vmi_checkins_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: vmi_checkins vmi_checkins_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: vmi_checkins vmi_checkins_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id) ON DELETE SET NULL;


--
-- Name: vmi_checkins vmi_checkins_generated_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_generated_order_id_fkey FOREIGN KEY (generated_order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- Name: vmi_checkins vmi_checkins_visited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vmi_checkins
    ADD CONSTRAINT vmi_checkins_visited_by_fkey FOREIGN KEY (visited_by) REFERENCES public.team(team_member_id) ON DELETE SET NULL;


--
-- Name: sales_state Global Read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Global Read" ON public.sales_state FOR SELECT USING (true);


--
-- Name: setup_countries Public Read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read" ON public.setup_countries FOR SELECT USING (true);


--
-- Name: sales_region Public Read Access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read Access" ON public.sales_region FOR SELECT USING (true);


--
-- Name: sales_state Public Read Access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read Access" ON public.sales_state FOR SELECT USING (true);


--
-- Name: setup_countries Public Read Access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read Access" ON public.setup_countries FOR SELECT USING (true);


--
-- Name: setup_timezones Public Read Access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read Access" ON public.setup_timezones FOR SELECT USING (true);


--
-- Name: user_roles Public Read Access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public Read Access" ON public.user_roles FOR SELECT USING (true);


--
-- Name: app_menu; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_menu ENABLE ROW LEVEL SECURITY;

--
-- Name: bag_sizes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bag_sizes ENABLE ROW LEVEL SECURITY;

--
-- Name: blending_worksheet; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.blending_worksheet ENABLE ROW LEVEL SECURITY;

--
-- Name: app_menu catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.app_menu FOR SELECT TO authenticated USING (true);


--
-- Name: company_signup_form catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.company_signup_form FOR SELECT TO authenticated USING (true);


--
-- Name: get_started catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.get_started FOR SELECT TO authenticated USING (true);


--
-- Name: onboarding_slides catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.onboarding_slides FOR SELECT TO authenticated USING (true);


--
-- Name: permissions catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.permissions FOR SELECT TO authenticated USING (true);


--
-- Name: plan_permissions catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.plan_permissions FOR SELECT TO authenticated USING (true);


--
-- Name: role_permissions catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.role_permissions FOR SELECT TO authenticated USING (true);


--
-- Name: sales_region catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.sales_region FOR SELECT TO authenticated USING (true);


--
-- Name: sales_state catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.sales_state FOR SELECT TO authenticated USING (true);


--
-- Name: setup_countries catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.setup_countries FOR SELECT TO authenticated USING (true);


--
-- Name: setup_timezones catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.setup_timezones FOR SELECT TO authenticated USING (true);


--
-- Name: standard_parameters catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.standard_parameters FOR SELECT TO authenticated USING (true);


--
-- Name: stock_types catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.stock_types FOR SELECT TO authenticated USING (true);


--
-- Name: subscription_plans catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.subscription_plans FOR SELECT TO authenticated USING (true);


--
-- Name: user_roles catalog_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_read ON public.user_roles FOR SELECT TO authenticated USING (true);


--
-- Name: channel; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channel ENABLE ROW LEVEL SECURITY;

--
-- Name: charge_weight_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.charge_weight_options ENABLE ROW LEVEL SECURITY;

--
-- Name: chargebacks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chargebacks ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory_history ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory_purchased; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coffee_inventory_purchased ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_source; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coffee_source ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_usage_by_month; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coffee_usage_by_month ENABLE ROW LEVEL SECURITY;

--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: company_kyc; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_kyc ENABLE ROW LEVEL SECURITY;

--
-- Name: company_kyc_beneficial_owners; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_kyc_beneficial_owners ENABLE ROW LEVEL SECURITY;

--
-- Name: company_kyc_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_kyc_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: company_parameters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: company_signup_form; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_signup_form ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory_history ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory_purchased; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consumable_inventory_purchased ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_type; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consumable_type ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_role; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contact_role ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_category; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_category ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_notes_detail; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_notes_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_sales_filter; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_sales_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_users ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: data_imports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.data_imports ENABLE ROW LEVEL SECURITY;

--
-- Name: developer_users dev_self_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dev_self_read ON public.developer_users FOR SELECT TO authenticated USING ((auth_user_id = auth.uid()));


--
-- Name: developer_impersonation_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.developer_impersonation_log ENABLE ROW LEVEL SECURITY;

--
-- Name: developer_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.developer_users ENABLE ROW LEVEL SECURITY;

--
-- Name: email_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_log ENABLE ROW LEVEL SECURITY;

--
-- Name: facilities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.facilities ENABLE ROW LEVEL SECURITY;

--
-- Name: get_started; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.get_started ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: management_type; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.management_type ENABLE ROW LEVEL SECURITY;

--
-- Name: marketing_pageview; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.marketing_pageview ENABLE ROW LEVEL SECURITY;

--
-- Name: onboarding_slides; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.onboarding_slides ENABLE ROW LEVEL SECURITY;

--
-- Name: open_order_totals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.open_order_totals ENABLE ROW LEVEL SECURITY;

--
-- Name: order_details; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_details ENABLE ROW LEVEL SECURITY;

--
-- Name: order_statuses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_statuses ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_webhook_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

--
-- Name: payouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;

--
-- Name: permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: plan_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plan_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: prep_type; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prep_type ENABLE ROW LEVEL SECURITY;

--
-- Name: product_consumables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_consumables ENABLE ROW LEVEL SECURITY;

--
-- Name: product_filter; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: product_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_groups ENABLE ROW LEVEL SECURITY;

--
-- Name: product_type; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_type ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products_price_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products_price_log ENABLE ROW LEVEL SECURITY;

--
-- Name: shop_config public_read_enabled; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_enabled ON public.shop_config FOR SELECT USING ((is_enabled = true));


--
-- Name: customer_category public_read_global; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_read_global ON public.customer_category FOR SELECT USING ((company_id IS NULL));


--
-- Name: recent_coffee_order; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recent_coffee_order ENABLE ROW LEVEL SECURITY;

--
-- Name: recipe_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recipe_components ENABLE ROW LEVEL SECURITY;

--
-- Name: recipe_weekly_targets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recipe_weekly_targets ENABLE ROW LEVEL SECURITY;

--
-- Name: restock_category; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restock_category ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_events ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_events roast_events tenant access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "roast_events tenant access" ON public.roast_events TO authenticated USING ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids)));


--
-- Name: roast_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_log ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_log roast_log tenant access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "roast_log tenant access" ON public.roast_log TO authenticated USING ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids)));


--
-- Name: roast_log_recipes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_log_recipes ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_profile_nodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_profile_nodes ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_recipes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_recipes ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_sessions roast_sessions tenant access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "roast_sessions tenant access" ON public.roast_sessions TO authenticated USING ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids)));


--
-- Name: roast_smartroast_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_smartroast_log ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_stock_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_stock_log ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_temp_nodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roast_temp_nodes ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_temp_nodes roast_temp_nodes tenant access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "roast_temp_nodes tenant access" ON public.roast_temp_nodes TO authenticated USING ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.user_facility_ids() AS user_facility_ids)));


--
-- Name: roaster_bank_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roaster_bank_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_users roaster_manage_customer_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY roaster_manage_customer_users ON public.customer_users TO authenticated USING ((customer_id IN ( SELECT c.customer_id
   FROM public.customers c
  WHERE (c.company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))))) WITH CHECK ((customer_id IN ( SELECT c.customer_id
   FROM public.customers c
  WHERE (c.company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)))));


--
-- Name: roaster_model_smartroast_calibration; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roaster_model_smartroast_calibration ENABLE ROW LEVEL SECURITY;

--
-- Name: roaster_unit_smartroast_calibration; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roaster_unit_smartroast_calibration ENABLE ROW LEVEL SECURITY;

--
-- Name: roaster_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roaster_units ENABLE ROW LEVEL SECURITY;

--
-- Name: role_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_activity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_area; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_area ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_category; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_category ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_city; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_city ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_data_filter; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_data_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_goals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_goals ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_parameters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_region; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_region ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_state; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_state ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_state_backup; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_state_backup ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_tasks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_tracking; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_tracking ENABLE ROW LEVEL SECURITY;

--
-- Name: setup_countries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.setup_countries ENABLE ROW LEVEL SECURITY;

--
-- Name: setup_timezones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.setup_timezones ENABLE ROW LEVEL SECURITY;

--
-- Name: shipment_received; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipment_received ENABLE ROW LEVEL SECURITY;

--
-- Name: customers shop_buyer_self_customer; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_buyer_self_customer ON public.customers FOR SELECT TO authenticated USING ((customer_id IN ( SELECT public.auth_customer_ids() AS auth_customer_ids)));


--
-- Name: customer_users shop_buyer_self_customer_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_buyer_self_customer_users ON public.customer_users FOR SELECT TO authenticated USING ((auth_user_id = auth.uid()));


--
-- Name: order_details shop_buyer_self_order_details; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_buyer_self_order_details ON public.order_details FOR SELECT TO authenticated USING ((customer_id IN ( SELECT public.auth_customer_ids() AS auth_customer_ids)));


--
-- Name: orders shop_buyer_self_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shop_buyer_self_orders ON public.orders FOR SELECT TO authenticated USING ((customer_id IN ( SELECT public.auth_customer_ids() AS auth_customer_ids)));


--
-- Name: shop_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shop_config ENABLE ROW LEVEL SECURITY;

--
-- Name: shop_invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shop_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: shop_order_ref_counter; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shop_order_ref_counter ENABLE ROW LEVEL SECURITY;

--
-- Name: shopify_connections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shopify_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: shopify_product_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shopify_product_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: size; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.size ENABLE ROW LEVEL SECURITY;

--
-- Name: staged_import_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staged_import_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: staged_line_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staged_line_items ENABLE ROW LEVEL SECURITY;

--
-- Name: staged_shipments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staged_shipments ENABLE ROW LEVEL SECURITY;

--
-- Name: standard_parameters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.standard_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: standing_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.standing_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: statements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.statements ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_types ENABLE ROW LEVEL SECURITY;

--
-- Name: subscription_admin_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscription_admin_log ENABLE ROW LEVEL SECURITY;

--
-- Name: subscription_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_category; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supplier_category ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_forms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_forms ENABLE ROW LEVEL SECURITY;

--
-- Name: team; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.team ENABLE ROW LEVEL SECURITY;

--
-- Name: team team_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY team_admin_write ON public.team TO authenticated USING (public.auth_is_company_admin(company_id)) WITH CHECK (public.auth_is_company_admin(company_id));


--
-- Name: team team_read_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY team_read_same_company ON public.team FOR SELECT TO authenticated USING (((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)) OR (auth_user_id = auth.uid())));


--
-- Name: team team_self_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY team_self_update ON public.team FOR UPDATE TO authenticated USING ((auth_user_id = auth.uid())) WITH CHECK ((auth_user_id = auth.uid()));


--
-- Name: bag_sizes tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.bag_sizes TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: blending_worksheet tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.blending_worksheet TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: channel tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.channel TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: charge_weight_options tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.charge_weight_options TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: chargebacks tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.chargebacks TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: coffee_inventory tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.coffee_inventory TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: coffee_inventory_history tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.coffee_inventory_history TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: coffee_inventory_purchased tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.coffee_inventory_purchased TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: coffee_source tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.coffee_source TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: coffee_usage_by_month tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.coffee_usage_by_month TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: companies tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.companies TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: company_kyc tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.company_kyc TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: company_kyc_beneficial_owners tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.company_kyc_beneficial_owners TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: company_kyc_documents tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.company_kyc_documents TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: company_parameters tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.company_parameters TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: consumable_inventory tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.consumable_inventory TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: consumable_inventory_history tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.consumable_inventory_history TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: consumable_inventory_purchased tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.consumable_inventory_purchased TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: consumable_type tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.consumable_type TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: contact_role tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.contact_role TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: contacts tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.contacts TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: customer_category tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.customer_category USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: customer_notes_detail tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.customer_notes_detail TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: customer_sales_filter tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.customer_sales_filter TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: customers tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.customers TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: data_imports tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.data_imports TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: email_log tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.email_log TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: facilities tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.facilities TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: invitations tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.invitations TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: invoice_documents tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.invoice_documents TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: management_type tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.management_type TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: open_order_totals tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.open_order_totals TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: order_details tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.order_details TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: order_statuses tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.order_statuses TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: orders tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.orders TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: payment_transactions tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.payment_transactions TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: payouts tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.payouts TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: prep_type tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.prep_type TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: product_consumables tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.product_consumables TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: product_filter tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.product_filter TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: product_groups tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.product_groups TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: product_type tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.product_type TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: products tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.products TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: products_price_log tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.products_price_log TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: recent_coffee_order tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.recent_coffee_order TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: recipe_components tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.recipe_components TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: restock_category tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.restock_category TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_log tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_log TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_profiles tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_profiles TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_recipes tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_recipes TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_sessions tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_sessions TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_smartroast_log tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_smartroast_log TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roast_stock_log tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roast_stock_log TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roaster_bank_accounts tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roaster_bank_accounts TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roaster_unit_smartroast_calibration tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roaster_unit_smartroast_calibration TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: roaster_units tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.roaster_units TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_area tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_area TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_category tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_category TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_city tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_city TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_data_filter tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_data_filter TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_goals tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_goals TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_notes tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_notes TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_parameters tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_parameters TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_state_backup tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_state_backup TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_tasks tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_tasks TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: sales_tracking tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.sales_tracking TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shipment_received tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shipment_received TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shop_config tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shop_config TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shop_invitations tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shop_invitations TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shop_order_ref_counter tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shop_order_ref_counter TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shopify_connections tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shopify_connections TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: shopify_product_mappings tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.shopify_product_mappings TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: size tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.size TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: staged_line_items tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.staged_line_items TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: staged_shipments tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.staged_shipments TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: standing_order_lines tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.standing_order_lines TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: statements tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.statements TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: subscriptions tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.subscriptions TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: supplier tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.supplier TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: supplier_category tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.supplier_category TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: tax_forms tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.tax_forms TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: vmi_checkins tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.vmi_checkins USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: weekly_roast_snapshot tenant_company_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_company_access ON public.weekly_roast_snapshot TO authenticated USING ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))) WITH CHECK ((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)));


--
-- Name: recipe_weekly_targets tenant_facility_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_facility_access ON public.recipe_weekly_targets TO authenticated USING ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids)));


--
-- Name: roast_events tenant_facility_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_facility_access ON public.roast_events TO authenticated USING ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids)));


--
-- Name: roast_temp_nodes tenant_facility_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_facility_access ON public.roast_temp_nodes TO authenticated USING ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids))) WITH CHECK ((facility_id IN ( SELECT public.auth_facility_ids() AS auth_facility_ids)));


--
-- Name: vmi_checkin_items tenant_via_checkin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_via_checkin ON public.vmi_checkin_items USING ((vmi_checkin_id IN ( SELECT vmi_checkins.vmi_checkin_id
   FROM public.vmi_checkins
  WHERE (vmi_checkins.company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))))) WITH CHECK ((vmi_checkin_id IN ( SELECT vmi_checkins.vmi_checkin_id
   FROM public.vmi_checkins
  WHERE (vmi_checkins.company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)))));


--
-- Name: user_parameters user_owns_row; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_owns_row ON public.user_parameters TO authenticated USING (((user_id = auth.uid()) AND (company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)))) WITH CHECK (((user_id = auth.uid()) AND (company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids))));


--
-- Name: user_roaster_settings user_owns_row; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_owns_row ON public.user_roaster_settings TO authenticated USING (((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)) AND (lower(email) = lower((( SELECT users.email
   FROM auth.users
  WHERE (users.id = auth.uid())))::text)))) WITH CHECK (((company_id IN ( SELECT public.auth_company_ids() AS auth_company_ids)) AND (lower(email) = lower((( SELECT users.email
   FROM auth.users
  WHERE (users.id = auth.uid())))::text))));


--
-- Name: user_parameters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roaster_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_roaster_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: vmi_checkin_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vmi_checkin_items ENABLE ROW LEVEL SECURITY;

--
-- Name: vmi_checkins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vmi_checkins ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_roast_snapshot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_roast_snapshot ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--


