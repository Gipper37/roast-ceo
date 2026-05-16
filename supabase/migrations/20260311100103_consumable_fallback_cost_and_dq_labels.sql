-- Migration 00103: Extend fallback cost to consumables + fix DQ labels
--
-- 1. update_last_consumable_cost() — add fallback_unit_cost as last resort
--    (mirrors the fix applied to recalculate_inventory_cost() in 00102)
-- 2. New trigger on consumable_inventory.fallback_unit_cost changes
-- 3. Update data_quality_issues view:
--    - Rename "Fallback cost only — enter shipment cost" → "Fallback cost only – add item to a shipment"
--    - Add same "Fallback cost only" advisory row for consumables

-- ── Part A: Update update_last_consumable_cost() ─────────────────────────────

CREATE OR REPLACE FUNCTION public.update_last_consumable_cost()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_item_id       TEXT;
    v_facility_id   TEXT;
    v_latest_cost   NUMERIC;
    v_fallback_cost NUMERIC;
BEGIN
    v_item_id     := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- Find most recent valid purchase cost for this consumable + facility
    SELECT cp.cost_unit::numeric
    INTO   v_latest_cost
    FROM   consumable_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE  cp.consumable_inventory_item = v_item_id
      AND  cp.facility_id = v_facility_id
      AND  cp.cost_unit IS NOT NULL
      AND  cp.cost_unit::text <> ''
      AND  cp.cost_unit::numeric > 0
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC
    LIMIT 1;

    IF v_latest_cost IS NOT NULL THEN
        -- Real purchase cost found — use it
        UPDATE consumable_inventory
        SET    last_cost_unit = v_latest_cost,
               updated_at     = NOW()
        WHERE  consumable_inventory_id = v_item_id
          AND  facility_id = v_facility_id;
    ELSE
        -- No purchase cost — try fallback_unit_cost
        SELECT fallback_unit_cost INTO v_fallback_cost
        FROM   consumable_inventory
        WHERE  consumable_inventory_id = v_item_id
          AND  facility_id = v_facility_id;

        IF COALESCE(v_fallback_cost, 0) > 0 THEN
            UPDATE consumable_inventory
            SET    last_cost_unit = v_fallback_cost,
                   updated_at     = NOW()
            WHERE  consumable_inventory_id = v_item_id
              AND  facility_id = v_facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$function$;

-- ── Part B: Trigger — fallback_unit_cost change → refresh last_cost_unit ─────

CREATE OR REPLACE FUNCTION public.refresh_consumable_cost_from_fallback()
RETURNS trigger
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

DROP TRIGGER IF EXISTS trg_refresh_consumable_cost_from_fallback ON public.consumable_inventory;

CREATE TRIGGER trg_refresh_consumable_cost_from_fallback
    AFTER UPDATE OF fallback_unit_cost
    ON public.consumable_inventory
    FOR EACH ROW
    WHEN (OLD.fallback_unit_cost IS DISTINCT FROM NEW.fallback_unit_cost)
    EXECUTE FUNCTION public.refresh_consumable_cost_from_fallback();

-- ── Part C: data_quality_issues — rename label + add consumable advisory ──────

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

-- Critical: coffee with no cost at all
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

-- Advisory: coffee using fallback only (last_cost_lb NULL = no real shipment cost)
SELECT
    'coffee'                    AS entity_type,
    ci.origin_id                AS entity_id,
    ci.origin                   AS entity_name,
    ci.company_id,
    ci.facility_id              AS facility_id,
    NULL::numeric               AS margin_pct,
    'Fallback cost only – add item to a shipment'  AS issue
FROM public.coffee_inventory ci
WHERE ci.latest_cost > 0
  AND COALESCE(ci.last_cost_lb, 0) = 0

UNION ALL

-- Critical: consumable with no cost at all
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

-- Advisory: consumable using fallback only (has fallback set, no real purchase records)
SELECT
    'consumable'                AS entity_type,
    c.consumable_inventory_id   AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id               AS facility_id,
    NULL::numeric               AS margin_pct,
    'Fallback cost only – add item to a shipment'  AS issue
FROM public.consumable_inventory c
WHERE COALESCE(c.fallback_unit_cost, 0) > 0
  AND COALESCE(c.last_cost_unit, 0) > 0
  AND NOT EXISTS (
      SELECT 1
      FROM   public.consumable_inventory_purchased cip
      WHERE  cip.consumable_inventory_item = c.consumable_inventory_id
        AND  cip.facility_id = c.facility_id
        AND  cip.cost_unit IS NOT NULL
        AND  cip.cost_unit::text <> ''
        AND  cip.cost_unit::numeric > 0
  )

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
