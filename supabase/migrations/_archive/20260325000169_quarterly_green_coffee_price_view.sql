-- Drop combined view if it exists
DROP VIEW IF EXISTS public.quarterly_green_coffee_price;

-- Per-origin view
CREATE OR REPLACE VIEW public.quarterly_green_coffee_price AS

SELECT
    (date_trunc('quarter', sr.date_received)::date)::text
        || '_' || cip.company_id
        || '_' || cip.facility_id
        || '_' || cip.origin                              AS row_id,
    date_trunc('quarter', sr.date_received)::date         AS quarter_start,
    to_char(date_trunc('quarter', sr.date_received), 'YYYY "Q"Q') AS quarter_label,
    cip.company_id,
    cip.facility_id,
    cip.origin                                            AS origin_id,
    ci_name.origin                                        AS origin_name,
    COUNT(cip.origin_purchase_id)                         AS purchase_count,
    ROUND(SUM(cip.amount), 2)                             AS total_lbs_purchased,
    ROUND(
        SUM(cip.cost_lb * cip.amount) / NULLIF(SUM(cip.amount), 0), 2
    )                                                     AS avg_cost_lb,
    ROUND(
        SUM((cip.cost_lb + COALESCE(sr.shipping_cost_unit, 0)) * cip.amount)
            / NULLIF(SUM(cip.amount), 0), 2
    )                                                     AS avg_landed_cost_lb
FROM public.coffee_inventory_purchased cip
JOIN public.shipment_received sr
    ON cip.shipment_id = sr.shipment_id
LEFT JOIN LATERAL (
    SELECT origin
    FROM public.coffee_inventory
    WHERE origin_id = cip.origin
      AND facility_id = cip.facility_id
    LIMIT 1
) ci_name ON true
WHERE sr.date_received IS NOT NULL
  AND COALESCE(sr.voided, false) = false
  AND cip.cost_lb IS NOT NULL
GROUP BY
    date_trunc('quarter', sr.date_received),
    cip.company_id,
    cip.facility_id,
    cip.origin,
    ci_name.origin
ORDER BY quarter_start, origin_name;


-- Aggregate view (all origins combined, volume-weighted)
CREATE OR REPLACE VIEW public.quarterly_green_coffee_price_aggregate AS

WITH per_origin AS (
    SELECT
        date_trunc('quarter', sr.date_received)::date     AS quarter_start,
        to_char(date_trunc('quarter', sr.date_received), 'YYYY "Q"Q') AS quarter_label,
        cip.company_id,
        cip.facility_id,
        ROUND(SUM(cip.amount), 2)                         AS total_lbs_purchased,
        SUM(cip.cost_lb * cip.amount)                     AS cost_x_lbs,
        SUM((cip.cost_lb + COALESCE(sr.shipping_cost_unit, 0)) * cip.amount) AS landed_cost_x_lbs,
        COUNT(cip.origin_purchase_id)                     AS purchase_count
    FROM public.coffee_inventory_purchased cip
    JOIN public.shipment_received sr
        ON cip.shipment_id = sr.shipment_id
    WHERE sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cip.cost_lb IS NOT NULL
    GROUP BY
        date_trunc('quarter', sr.date_received),
        cip.company_id,
        cip.facility_id,
        cip.origin
)

SELECT
    quarter_start::text || '_' || company_id || '_' || facility_id AS row_id,
    quarter_start,
    quarter_label,
    company_id,
    facility_id,
    SUM(purchase_count)                                   AS purchase_count,
    ROUND(SUM(total_lbs_purchased), 2)                    AS total_lbs_purchased,
    ROUND(SUM(cost_x_lbs) / NULLIF(SUM(total_lbs_purchased), 0), 2)        AS avg_cost_lb,
    ROUND(SUM(landed_cost_x_lbs) / NULLIF(SUM(total_lbs_purchased), 0), 2) AS avg_landed_cost_lb
FROM per_origin
GROUP BY quarter_start, quarter_label, company_id, facility_id
ORDER BY quarter_start;
