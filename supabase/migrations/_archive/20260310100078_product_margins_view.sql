-- Migration 00078: product_margins view
--
-- Surfaces per-product profitability: gross profit and margin % computed from
-- the already-trigger-maintained products.total_unit_cogs and products.price.
-- Excludes archived products.
--
-- AppSheet use: read-only list sorted by margin_pct ascending (worst first)
-- to identify under-priced or over-expensive products.

CREATE VIEW public.product_margins WITH (security_invoker = 'true') AS
SELECT
    p.product_id,
    p.product_name,
    p.company_id,
    p.facility_id,
    p.price,
    p.total_unit_cogs,
    ROUND((p.price - p.total_unit_cogs)::numeric, 2)                        AS gross_profit_per_unit,
    ROUND(((p.price - p.total_unit_cogs) / NULLIF(p.price, 0)) * 100, 1)   AS margin_pct,
    p.weight_lbs,
    p.size
FROM public.products p
WHERE NOT p."archived?";
