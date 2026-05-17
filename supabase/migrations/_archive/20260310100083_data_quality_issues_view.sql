-- Migration 00083: data_quality_issues view
-- Consolidates all data_warning = TRUE records from product_margins, order_profitability,
-- and customer_profitability into a single list for AppSheet.
-- entity_type + entity_id is the effective composite key.

CREATE VIEW public.data_quality_issues WITH (security_invoker = 'true') AS
SELECT
    'product'                   AS entity_type,
    p.product_id::text          AS entity_id,
    p.product_name              AS entity_name,
    p.company_id,
    NULL::text                  AS facility_id,
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
    'order'                     AS entity_type,
    o.order_id::text            AS entity_id,
    o.order_id::text            AS entity_name,
    o.company_id,
    o.facility_id::text         AS facility_id,
    o.margin_pct,
    CASE
        WHEN o.cogs = 0          THEN 'Missing COGS'
        WHEN o.margin_pct < 0    THEN 'Selling below cost'
        WHEN o.margin_pct > 90   THEN 'Suspiciously high margin'
    END                         AS issue
FROM public.order_profitability o
WHERE o.data_warning = TRUE

UNION ALL

SELECT
    'customer'                  AS entity_type,
    c.customer_id::text         AS entity_id,
    c.customer_name             AS entity_name,
    c.company_id,
    NULL::text                  AS facility_id,
    c.margin_pct,
    CASE
        WHEN c.cogs = 0          THEN 'Missing COGS'
        WHEN c.margin_pct < 0    THEN 'Selling below cost'
        WHEN c.margin_pct > 90   THEN 'Suspiciously high margin'
    END                         AS issue
FROM public.customer_profitability c
WHERE c.data_warning = TRUE;
