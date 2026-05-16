-- Migration 00100: Add "Missing product price" to data_quality_issues
--
-- Products with price = 0 or NULL generate $0 revenue on every order.
-- This UNION adds them as actionable warnings alongside the existing
-- cost/margin checks.

CREATE OR REPLACE VIEW public.data_quality_issues WITH (security_invoker = 'true') AS
SELECT
    'product'                   AS entity_type,
    p.product_id::text          AS entity_id,
    p.product_name              AS entity_name,
    p.company_id,
    p.facility_id::text         AS facility_id,
    p.margin_pct,
    CASE
        WHEN p.total_unit_cogs = 0   THEN 'No product cost'
        WHEN p.margin_pct < 0        THEN 'Selling below cost'
        WHEN p.margin_pct > 90       THEN 'Suspiciously high margin'
    END                         AS issue
FROM public.product_margins p
WHERE p.data_warning = TRUE

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
