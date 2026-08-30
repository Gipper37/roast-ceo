-- The production date feeds the roast plan.
--
-- orders.production_date ("the day WE plan to roast it") has been captured
-- since 20260826000001 and read by nothing. Deliberately deferred at the time:
-- a date that silently starts driving production is worse than no date. The
-- owner has now asked for it (open-list item).
--
-- Semantics: an order with a production date counts as roast demand in the
-- week that CONTAINS that date, instead of the week of its order_date. Orders
-- without one behave exactly as before. One change, two places — the two
-- identical current-week demand windows in roast_detail_by_blend — and
-- nothing else: the trailing 6-week average stays on order_date (history is
-- history), and the plan/LFP invariant holds because plan, preview, pills and
-- the queue insert all read THIS view.

create or replace view public.roast_detail_by_blend as
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT cp.value_number::integer AS value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'RF1iFWjOh7'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), 4) AS roast_reset_day,
            COALESCE(( SELECT cp.value_number::integer AS value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'orders_reset_day'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), ( SELECT sp.amount::integer AS amount
                   FROM standard_parameters sp
                  WHERE sp.parameters_id = 'orders_reset_day'::text
                 LIMIT 1), 6) AS orders_reset_day,
            COALESCE(( SELECT cp.value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = '761fd894'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), 25::numeric) AS charge_weight,
            COALESCE(( SELECT cp.value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = '1de271df'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), ( SELECT sp.amount
                   FROM standard_parameters sp
                  WHERE sp.parameters_id = '1de271df'::text
                 LIMIT 1), 0.82) AS retention_rate,
            COALESCE(( SELECT cp.value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'backstock_buffer_pct'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), ( SELECT sp.amount
                   FROM standard_parameters sp
                  WHERE sp.parameters_id = 'backstock_buffer_pct'::text
                 LIMIT 1), 0::numeric) AS backstock_buffer_pct
           FROM facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            fp.roast_reset_day,
            fp.orders_reset_day,
            fp.charge_weight,
            fp.retention_rate,
            fp.backstock_buffer_pct,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day + 7) % 7 AS roast_week_start,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start
           FROM facility_params fp
        ), recipe_facility AS (
         SELECT rr.recipe_id,
            rr.roast_type,
            rr.retention_factor,
            f.facility_id,
            f.company_id
           FROM roast_recipes rr
             JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
        ), recipe_anchor AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            c.roast_week_start,
            c.orders_week_start,
            c.timezone,
            anchor.anchor_stock,
            anchor.anchor_date,
            anchor.in_current_week
           FROM recipe_facility rf
             JOIN calc c ON c.facility_id = rf.facility_id
             LEFT JOIN LATERAL ( SELECT rsl.lbs_in_stock AS anchor_stock,
                    (rsl.created_at AT TIME ZONE c.timezone)::date AS anchor_date,
                    (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start AS in_current_week
                   FROM roast_stock_log rsl
                  WHERE rsl.stock_type = 'blend'::text AND rsl.blend_id = rf.recipe_id AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= (c.roast_week_start - '28 days'::interval)
                  ORDER BY rsl.created_at DESC
                 LIMIT 1) anchor ON true
        ), recipe_is AS (
         SELECT ra.recipe_id,
            ra.facility_id,
                CASE
                    WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock)
                    ELSE GREATEST(0::numeric, COALESCE(ra.anchor_stock, 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS sum
                       FROM roast_log rl
                         JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                      WHERE rlr.recipe_id = ra.recipe_id AND rl.facility_id = ra.facility_id AND rl."charged?" = true AND rl.roast_date >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND rl.roast_date < ra.roast_week_start), 0::numeric) - COALESCE(( SELECT sum(od.roasted_weight)::numeric AS sum
                       FROM order_details od
                         JOIN orders o ON od.order_id = o.order_id
                         JOIN products p ON od.product_id = p.product_id
                      WHERE p.recipe_id = ra.recipe_id AND o.facility_id = ra.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) >= COALESCE(ra.anchor_date::timestamp without time zone, ra.orders_week_start - '28 days'::interval) AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) < ra.orders_week_start), 0::numeric))
                END AS in_stock_roasted
           FROM recipe_anchor ra
        ), recipe_override AS (
         SELECT rwt.recipe_id,
            rwt.facility_id,
            rwt.target_lbs,
            rwt.notes
           FROM recipe_weekly_targets rwt
             JOIN calc c ON c.facility_id = rwt.facility_id
          WHERE rwt.week_start = c.roast_week_start
        ), recipe_level AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            c.backstock_buffer_pct,
            COALESCE(ris.in_stock_roasted, 0::numeric) AS in_stock_roasted,
            COALESCE(ordered.total_ordered, 0::double precision) AS total_ordered,
            COALESCE(roasted.total_roasted, 0::numeric) AS total_roasted,
            COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
            COALESCE(( SELECT avg(rl.charge_weight_lbs) AS avg
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM roast_log
                          WHERE roast_log.recipe_id = rf.recipe_id AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) rl), c.charge_weight, 25::numeric) AS effective_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override
           FROM recipe_facility rf
             JOIN calc c ON c.facility_id = rf.facility_id
             LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
             LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
             LEFT JOIN LATERAL ( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS total_roasted
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = rf.facility_id) roasted ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, o2.order_date::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                          WHERE p2.recipe_id = rf.recipe_id AND o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND o2.order_date >= (c.orders_week_start - '42 days'::interval) AND o2.order_date < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, o2.order_date::timestamp with time zone))) weekly) avg_lbs ON true
          WHERE rf.roast_type = 'Pre-Blend'::text OR NOT (EXISTS ( SELECT 1
                   FROM recipe_components rc
                  WHERE rc.recipe_id = rf.recipe_id))
        ), component_raw AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            rc.coffee_item AS origin_id,
            COALESCE(rc.percentage, 0::numeric) AS percentage,
            c.backstock_buffer_pct,
            COALESCE(NULLIF(rf.retention_factor, 0::numeric), c.retention_rate) AS retention_rate,
            c.charge_weight AS facility_charge_weight,
            COALESCE(ordered.total_ordered, 0::double precision)::numeric AS recipe_demand,
            COALESCE(ris.in_stock_roasted, 0::numeric) * COALESCE(rc.percentage, 0::numeric) AS this_week_stock,
            COALESCE(component_roasted.lbs, 0::numeric) AS component_roasted,
            COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override
           FROM recipe_facility rf
             JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
             JOIN calc c ON c.facility_id = rf.facility_id
             LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
             LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = rf.facility_id) component_roasted ON true
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM roast_log
                          WHERE roast_log.recipe_id = rf.recipe_id AND roast_log.origin_id = rc.coffee_item AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) charge_w ON true
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM roast_log
                          WHERE roast_log.recipe_id = rf.recipe_id AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) recipe_charge_w ON true
             LEFT JOIN LATERAL ( SELECT avg(sub.charge_weight_lbs) AS avg_w
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM roast_log
                          WHERE roast_log.origin_id = rc.coffee_item AND roast_log.facility_id = rf.facility_id AND roast_log.charge_weight_lbs > 0::numeric
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) sub) origin_charge_w ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, o2.order_date::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric)) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                          WHERE p2.recipe_id = rf.recipe_id AND o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND o2.order_date >= (c.orders_week_start - '42 days'::interval) AND o2.order_date < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, o2.order_date::timestamp with time zone))) weekly) avg_lbs ON true
          WHERE rf.roast_type IS DISTINCT FROM 'Pre-Blend'::text AND (EXISTS ( SELECT 1
                   FROM recipe_components rc2
                  WHERE rc2.recipe_id = rf.recipe_id))
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
            cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric AS recipe_buffer_target,
            cr.percentage * (cr.recipe_demand + cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric) AS component_demand_buf,
            cr.percentage * cr.recipe_demand AS component_demand_orders,
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
            GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock) AS demand_after_stock
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
            GREATEST(0::numeric, cs.demand_after_stock - cs.component_roasted) AS component_remaining,
            GREATEST(0::numeric, cs.component_demand_orders - cs.effective_stock - cs.component_roasted) AS component_remaining_orders_only
           FROM component_split cs
        ), post_blend_recipe AS (
         SELECT cf.recipe_id,
            cf.facility_id,
            cf.company_id,
            max(cf.retention_rate) AS retention_rate,
            max(cf.recipe_demand)::double precision AS total_ordered,
            sum(cf.applied_stock) AS in_stock_roasted,
            sum(cf.applied_roasted) AS total_roasted,
            sum(cf.component_remaining)::double precision AS roasted_left,
            sum(ceil(cf.component_remaining / NULLIF(cf.retention_rate, 0::numeric) / NULLIF(cf.component_charge_weight, 0::numeric)))::double precision AS roasts_remaining,
            max(cf.recipe_avg_weekly_lbs) AS avg_weekly_lbs,
            max(cf.backstock_buffer_pct) AS backstock_buffer_pct,
            max(cf.recipe_buffer_target) AS buffer_target,
            LEAST(max(cf.recipe_buffer_target)::double precision, GREATEST(0::numeric, sum(cf.component_remaining) - sum(cf.component_remaining_orders_only))::double precision) AS buffer_left_calc,
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
            GREATEST(0::double precision, rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision - rl.in_stock_roasted::double precision - rl.total_roasted::double precision) AS roasted_left,
            GREATEST(0::double precision, rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision - rl.in_stock_roasted::double precision - rl.total_roasted::double precision) / NULLIF(rl.retention_rate, 0::numeric)::double precision / NULLIF(rl.effective_charge_weight, 0::numeric)::double precision AS roasts_remaining,
            rl.avg_weekly_lbs,
            rl.backstock_buffer_pct,
            rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric AS buffer_target,
            LEAST(GREATEST(0::double precision, rl.total_ordered + (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision - rl.in_stock_roasted::double precision - rl.total_roasted::double precision), (rl.avg_weekly_lbs * rl.backstock_buffer_pct / 100::numeric)::double precision) AS buffer_left,
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
 SELECT (recipe_id || '-'::text) || facility_id AS roast_blend_id,
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
    total_ordered + buffer_target::double precision AS effective_target,
    buffer_left,
    weekly_target_override
   FROM unioned;
