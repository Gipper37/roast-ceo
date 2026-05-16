-- Migration 00084: Replace data_quality_issues view
-- Drops orders + customers (downstream symptoms) in favor of the actual root causes:
-- (1) products with bad/missing COGS or suspicious margins
-- (2) coffee origins with no cost entered (latest_cost = 0 or NULL)
-- (3) consumables with no cost entered (last_cost_unit = 0 or NULL)

CREATE OR REPLACE VIEW public.data_quality_issues WITH (security_invoker = 'true') AS
SELECT
    'product'                   AS entity_type,
    p.product_id::text          AS entity_id,
    p.product_name              AS entity_name,
    p.company_id,
    p.facility_id::text         AS facility_id,
    p.margin_pct,
    CASE
        WHEN p.total_unit_cogs = 0   THEN 'Missing COGS'
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
WHERE COALESCE(c.last_cost_unit, 0) = 0;
