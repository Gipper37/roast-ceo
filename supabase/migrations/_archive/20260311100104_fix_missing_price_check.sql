-- Migration 00104: Fix "Missing product price" to only flag products with no price log history
--
-- Old check: COALESCE(price, 0) = 0 — incorrectly flags intentionally-free samples
-- (Dawn Patrol Sample, Hendrix Sample, Rubix Sample, Vinyl Sample, Nova Sample,
--  Super Nova Sample all have explicit $0 entries in products_price_log).
--
-- New check: NOT EXISTS (products_price_log entry) — flags only products where
-- no price has EVER been entered. Includes archived products since they may have
-- historical orders with $0 revenue that still need the backfill applied.

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
    'Fallback cost only – add item to a shipment'  AS issue
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
WHERE NOT EXISTS (
    SELECT 1 FROM public.products_price_log ppl
    WHERE ppl.product_id = p.product_id
);
