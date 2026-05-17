-- Migration 00101: Remove redundant "No product cost" from data_quality_issues
--
-- "No product cost" (total_unit_cogs = 0) is always caused by a missing coffee or
-- consumable cost, which are already flagged by the "Missing coffee cost" and
-- "Missing consumable cost" rows. Showing it at the product level too is noise.
--
-- Keeping the two genuinely product-level warnings: "Selling below cost" and
-- "Suspiciously high margin". "Missing product price" (00100) covers the price gap.

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
  AND p.total_unit_cogs > 0   -- exclude zero-cost products (covered by ingredient rows)

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
