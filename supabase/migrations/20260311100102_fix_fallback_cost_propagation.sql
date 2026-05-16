-- Migration 00102: Fix fallback_cost → latest_cost propagation
--
-- Bug 1: recalculate_inventory_cost() ignores fallback_cost entirely.
--   When no shipment has cost_lb > 0, it defaults latest_cost = 0 instead of
--   checking the user-entered fallback_cost column (added in migration 00090).
--
-- Bug 2: No trigger fires when coffee_inventory.fallback_cost is updated.
--   Updating fallback_cost has no live effect on latest_cost.
--
-- Bug 3: Once fallback_cost fills latest_cost, "Missing coffee cost" clears
--   silently — nobody knows a real shipment cost is still needed.
--   Fix: split into two severity levels in data_quality_issues.
--
-- Note on fallback_cost semantics: it is entered by the user as a final
-- roasted $/lb (same unit as latest_cost), NOT as a green cost. So it is
-- used directly, bypassing the (green + shipping) / retention formula.
-- When the fallback path is taken, last_cost_lb is set to NULL to signal
-- "no real shipment cost" — used by the data quality view to detect this state.

-- ── Part A: Update recalculate_inventory_cost() ───────────────────────────────

CREATE OR REPLACE FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_retention             numeric;
    v_latest_green_cost     numeric;
    v_latest_shipping_cost  numeric;
    v_final_landed_cost     numeric;
    v_fallback_cost         numeric;
BEGIN
    -- 1. Resolve retention factor (3-tier: company override → system default → 0.82)
    SELECT value_number
      INTO v_retention
    FROM company_parameters
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
      SELECT sp.amount
        INTO v_retention
      FROM standard_parameters sp
      WHERE sp.parameters_id = '1de271df'
      LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
      v_retention := 0.82;
    END IF;

    -- 2. Find most recent shipment green cost
    SELECT cp.cost_lb
      INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND cp.cost_lb > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    -- 3. Find most recent shipment shipping cost
    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost    := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    -- 4. If no shipment green cost found, try fallback_cost before defaulting to 0
    IF v_latest_green_cost = 0 THEN
        SELECT ci.fallback_cost INTO v_fallback_cost
        FROM public.coffee_inventory ci
        WHERE ci.origin_id   = p_origin_id
          AND ci.facility_id = p_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            -- fallback_cost is already roasted $/lb — use directly.
            -- Set last_cost_lb = NULL to signal "fallback only, no real shipment"
            -- (data_quality_issues uses this to show "Fallback cost only" advisory).
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

-- ── Part B: Trigger — fallback_cost change → re-run recalculate ───────────────

CREATE OR REPLACE FUNCTION public.refresh_latest_cost_from_fallback()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.recalculate_inventory_cost(NEW.origin_id, NEW.facility_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_cost_from_fallback ON public.coffee_inventory;

CREATE TRIGGER trg_refresh_cost_from_fallback
    AFTER UPDATE OF fallback_cost
    ON public.coffee_inventory
    FOR EACH ROW
    WHEN (OLD.fallback_cost IS DISTINCT FROM NEW.fallback_cost)
    EXECUTE FUNCTION public.refresh_latest_cost_from_fallback();

-- ── Part C: Update data_quality_issues — two coffee cost severity levels ──────
--
-- "Missing coffee cost"  — critical: no cost at all (latest_cost = 0)
-- "Fallback cost only"   — advisory: has fallback estimate, needs real shipment
--   Detected by: latest_cost > 0 AND last_cost_lb IS NULL (fallback path sets last_cost_lb = NULL)

CREATE OR REPLACE VIEW public.data_quality_issues WITH (security_invoker = 'true') AS
SELECT
    'product'                   AS entity_type,
    p.product_id::text          AS entity_id,
    p.product_name              AS entity_name,
    p.company_id,
    p.facility_id::text         AS facility_id,
    p.margin_pct,
    CASE
        WHEN p.margin_pct < 0   THEN 'Selling below cost'
        WHEN p.margin_pct > 90  THEN 'Suspiciously high margin'
    END                         AS issue
FROM public.product_margins p
WHERE p.data_warning = TRUE
  AND p.total_unit_cogs > 0

UNION ALL

SELECT
    'coffee'                    AS entity_type,
    ci.origin_id                AS entity_id,
    ci.origin                   AS entity_name,
    ci.company_id,
    ci.facility_id              AS facility_id,
    NULL::numeric               AS margin_pct,
    'Missing coffee cost'       AS issue
FROM public.coffee_inventory ci
WHERE COALESCE(ci.latest_cost, 0) = 0

UNION ALL

SELECT
    'coffee'                    AS entity_type,
    ci.origin_id                AS entity_id,
    ci.origin                   AS entity_name,
    ci.company_id,
    ci.facility_id              AS facility_id,
    NULL::numeric               AS margin_pct,
    'Fallback cost only — enter shipment cost'  AS issue
FROM public.coffee_inventory ci
WHERE ci.latest_cost > 0
  AND COALESCE(ci.last_cost_lb, 0) = 0

UNION ALL

SELECT
    'consumable'                AS entity_type,
    c.consumable_inventory_id   AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id               AS facility_id,
    NULL::numeric               AS margin_pct,
    'Missing consumable cost'   AS issue
FROM public.consumable_inventory c
WHERE COALESCE(c.last_cost_unit, 0) = 0

UNION ALL

SELECT
    'product'                   AS entity_type,
    p.product_id                AS entity_id,
    p.product_name              AS entity_name,
    p.company_id,
    p.facility_id               AS facility_id,
    NULL::numeric               AS margin_pct,
    'Missing product price'     AS issue
FROM public.products p
WHERE COALESCE(p.price, 0) = 0;
