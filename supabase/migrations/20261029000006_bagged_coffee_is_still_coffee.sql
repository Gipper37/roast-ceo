-- Bagged coffee is still coffee. Revert the per-variant clamp; keep the
-- delivery debit.
--
-- Owner, 2026-10-29, on the roast page after release-2026-10-29-2:
-- *"that completely screwed everything up."* He is right, and this is mine.
--
-- == WHAT I GOT WRONG =====================================================
--
-- 20261029000004 capped each product's bag credit at that product's own open
-- demand. The intent was his own correction: *"those are already bagged so
-- they can't go toward future items other than that variant they are bagged
-- for."* True for DEMAND -- a Safeway 8oz bag cannot fill a 12oz wholesale
-- order.
--
-- 🔴 BUT IT IS FALSE FOR THE BACKSTOCK BUFFER, AND THE BUFFER IS MOST OF THE
-- PLAN. A bag with no matching order is still finished coffee on a shelf;
-- that is precisely what backstock IS. Capping at demand did not stop those
-- bags offsetting the wrong orders, it deleted them from stock entirely.
-- Measured on prod, MCR:
--
--     total_ordered     801.1      roasted_left     2226.1
--     buffer_target    2729.3      of which buffer  2151.2
--     in_stock         1176.5      of which orders     74.9
--
--     bagged coffee actually on the shelf, after the debit:  1689.8 lbs
--
-- So the plan demanded 2,151 lbs of fresh cushion while 1,690 lbs of cushion
-- sat in bags, credited as zero. 56 of 60 batches were pure backstock.
--
-- == AND THE ALGEBRA SAYS THE CLAMP WAS NEVER THE RIGHT LEVER =============
--
-- Let D be demand, B bagged, K bulk, T the buffer target. Leftover bags must
-- count toward T, because they are literally backstock. Then the per-variant
-- form is
--
--   SUM max(0, d_v - b_v)  +  T  -  K  -  SUM max(0, b_v - d_v)
--     = (D - SUM min) + T - K - (B - SUM min)
--     = D + T - K - B
--
-- which is the ORIGINAL formula. **With a buffer on, variant matching cancels
-- out of the total exactly.** It can only ever change the answer by throwing
-- the leftover bags away, and throwing them away is the bug. 31c is a real
-- observation, but it cannot be implemented as a reduction in stock; it has to
-- change which DEMAND a bag is allowed to answer, which is a different and
-- larger change than this one. Reopened on the list, unimplemented.
--
-- == WHAT THIS KEEPS ======================================================
--
-- 🔴 The delivery debit STAYS. Nothing debits pack_stock_count, and MCR's 80
-- variants were counted once on 10-25 while 804 units shipped out from under
-- those counts by 10-29. That half was never in question. Checked for
-- double-counting at the boundary: the debit uses `>= count DATE`, and of the
-- 804 units, **0** were delivered on the count day at all (the counts were
-- taken 17:19-18:12 on 10-25), so the date boundary costs nothing here.
--
-- `recipe_bagged_applied` loses its clamp for the same reason, so it again
-- means "the bags that are still there" and the roast page's bin column stays
-- `in_stock_roasted - recipe_bagged_applied`.
--
-- == MEASURED, BY RUNNING THIS TEXT READ-ONLY AGAINST PROD ================
--
--                              in_stock     left to roast
--     this morning              4276.2            237.2     (bags never debited)
--     20261029000004 shipped    1176.5           2226.1     (bags deleted)
--     this migration            2836.2           1258.2     (bags debited, kept)
--
-- 🔴 BOTH BODIES FROM ONE TEXT, as 20261029000004 established: the function's
-- live body with the clamp removed from both pack legs, and the view from that
-- same string with the two facility filters dropped. Asserted: 2 pack legs.

begin;

create or replace view public.roast_detail_by_blend with (security_invoker = true) as
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
        ), origin_pool AS (
         SELECT DISTINCT ON (rsl.facility_id, rsl.origin_id) rsl.facility_id,
            rsl.origin_id,
            GREATEST(0::numeric, rsl.lbs_in_stock) AS pool_lbs
           FROM roast_stock_log rsl
             JOIN calc c ON c.facility_id = rsl.facility_id
          WHERE rsl.stock_type = 'origin'::text AND rsl.origin_id IS NOT NULL AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
          ORDER BY rsl.facility_id, rsl.origin_id, rsl.created_at DESC
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
             LEFT JOIN LATERAL ( SELECT sum(x.lbs_in_stock * ds.share) AS anchor_stock,
                    max(x.counted_on) AS anchor_date,
                    bool_or(x.counted_on >= c.roast_week_start) AS in_current_week
                   FROM recipe_demand_source ds
                     JOIN LATERAL ( SELECT rsl.lbs_in_stock,
                            (rsl.created_at AT TIME ZONE c.timezone)::date AS counted_on
                           FROM roast_stock_log rsl
                          WHERE rsl.stock_type = 'blend'::text AND rsl.blend_id = ds.source_recipe_id AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= (c.roast_week_start - '28 days'::interval)
                          ORDER BY rsl.created_at DESC
                         LIMIT 1) x ON true
                  WHERE ds.recipe_id = rf.recipe_id AND ds.share > 0::numeric) anchor ON true
        ), recipe_is AS (
         SELECT ra.recipe_id,
            ra.facility_id,
                CASE
                    WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock) + COALESCE(( SELECT sum(
                                   GREATEST(0::numeric, b.counted_bags - COALESCE(( SELECT sum(odp.quantity)::numeric
                                        FROM order_details odp
                                          JOIN orders op ON op.order_id = odp.order_id
                                       WHERE odp.product_id = b.product_id AND op.facility_id = ra.facility_id AND op.order_status = 'Delivered'::text AND COALESCE((op.status_changed_at AT TIME ZONE ra.timezone)::date, op.order_date) >= (b.counted_at AT TIME ZONE ra.timezone)::date), 0::numeric))
                                     * (COALESCE(p.weight_lbs, 0::numeric) / COALESCE(NULLIF(( SELECT sz.units_per_case FROM size sz WHERE sz.size_id = p.size), 0), 1))
                                 * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                    ELSE GREATEST(0::numeric, COALESCE(ra.anchor_stock, 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS sum
                       FROM roast_log rl
                         JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                      WHERE rlr.recipe_id = ra.recipe_id AND rl.facility_id = ra.facility_id AND rl."charged?" = true AND rl.roast_date >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND rl.roast_date < ra.roast_week_start), 0::numeric) - COALESCE(( SELECT sum(od.roasted_weight * (SELECT dsd.share FROM recipe_demand_source dsd WHERE dsd.recipe_id = ra.recipe_id AND dsd.source_recipe_id = p.recipe_id))::numeric AS sum
                       FROM order_details od
                         JOIN orders o ON od.order_id = o.order_id
                         JOIN products p ON od.product_id = p.product_id
                      WHERE p.recipe_id IN (SELECT dsd2.source_recipe_id FROM recipe_demand_source dsd2 WHERE dsd2.recipe_id = ra.recipe_id AND dsd2.share > 0::numeric) AND o.facility_id = ra.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) < ra.roast_week_start), 0::numeric)) + COALESCE(( SELECT sum(
                                   GREATEST(0::numeric, b.counted_bags - COALESCE(( SELECT sum(odp.quantity)::numeric
                                        FROM order_details odp
                                          JOIN orders op ON op.order_id = odp.order_id
                                       WHERE odp.product_id = b.product_id AND op.facility_id = ra.facility_id AND op.order_status = 'Delivered'::text AND COALESCE((op.status_changed_at AT TIME ZONE ra.timezone)::date, op.order_date) >= (b.counted_at AT TIME ZONE ra.timezone)::date), 0::numeric))
                                     * (COALESCE(p.weight_lbs, 0::numeric) / COALESCE(NULLIF(( SELECT sz.units_per_case FROM size sz WHERE sz.size_id = p.size), 0), 1))
                                 * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                END AS in_stock_roasted
           FROM recipe_anchor ra
        ), recipe_override AS (
         SELECT dsw.recipe_id,
            dsw.facility_id,
            sum(rwt.target_lbs * dsw.share) AS target_lbs,
            min(rwt.notes) AS notes
           FROM recipe_weekly_targets rwt
             JOIN calc c ON c.facility_id = rwt.facility_id
             JOIN recipe_demand_source dsw ON dsw.source_recipe_id = rwt.recipe_id AND dsw.facility_id = rwt.facility_id AND dsw.share > 0::numeric
          WHERE rwt.week_start = c.roast_week_start
          GROUP BY dsw.recipe_id, dsw.facility_id
        ), recipe_level AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            c.backstock_buffer_pct,
            COALESCE(ris.in_stock_roasted, 0::numeric) AS in_stock_roasted,
            COALESCE(ovr.target_lbs::double precision, ordered.total_ordered, 0::double precision) AS total_ordered,
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
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * ds.share) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                     JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = rf.recipe_id
                  WHERE o.facility_id = rf.facility_id AND o.order_status = 'Open'::text) ordered ON true
             LEFT JOIN LATERAL ( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS total_roasted
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start, ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND ((s.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1)) AND rl.facility_id = rf.facility_id) roasted ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric) * ds2.share) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                             JOIN recipe_demand_source ds2 ON ds2.source_recipe_id = p2.recipe_id AND ds2.recipe_id = rf.recipe_id
                          WHERE o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND COALESCE(o2.production_date, o2.order_date) >= (c.orders_week_start - '42 days'::interval) AND COALESCE(o2.production_date, o2.order_date) < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON true
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
            COALESCE(ovr.target_lbs, ordered.total_ordered::numeric, 0::numeric) AS recipe_demand,
            COALESCE(ris.in_stock_roasted, 0::numeric) * COALESCE(rc.percentage, 0::numeric) AS this_week_stock,
            COALESCE(component_roasted.lbs, 0::numeric) AS component_roasted,
            COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override,
            ran.anchor_date AS blend_anchor_date,
            COALESCE(op.pool_lbs, 0::numeric) AS origin_pool_lbs,
            comp_count.cc_date,
                CASE
                    WHEN comp_count.cc_date IS NULL THEN NULL::numeric
                    WHEN comp_count.cc_in_current_week THEN GREATEST(0::numeric, comp_count.cc_stock)
                    ELSE GREATEST(0::numeric, COALESCE(comp_count.cc_stock, 0::numeric) + COALESCE(cc_roasted.lbs, 0::numeric) - COALESCE(cc_delivered.lbs, 0::numeric) * COALESCE(rc.percentage, 0::numeric))
                END AS counted_component_stock
           FROM recipe_facility rf
             JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
             JOIN calc c ON c.facility_id = rf.facility_id
             LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
             LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * ds.share) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                     JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = rf.recipe_id
                  WHERE o.facility_id = rf.facility_id AND o.order_status = 'Open'::text) ordered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start, ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND ((s.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1), ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'origin'::text AND s.origin_id = rc.coffee_item AND s.facility_id = rf.facility_id AND (s.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1)) AND rl.facility_id = rf.facility_id) component_roasted ON true
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
             LEFT JOIN recipe_anchor ran ON ran.recipe_id = rf.recipe_id AND ran.facility_id = rf.facility_id
             LEFT JOIN origin_pool op ON op.facility_id = rf.facility_id AND op.origin_id = rc.coffee_item
             LEFT JOIN LATERAL ( SELECT rsl.lbs_in_stock AS cc_stock,
                    (rsl.created_at AT TIME ZONE c.timezone)::date AS cc_date,
                    (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start AS cc_in_current_week
                   FROM roast_stock_log rsl
                  WHERE rsl.stock_type = 'component'::text AND rsl.blend_id = rf.recipe_id AND rsl.origin_id = rc.coffee_item AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= (c.roast_week_start - '28 days'::interval)
                  ORDER BY rsl.created_at DESC
                 LIMIT 1) comp_count ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE comp_count.cc_date IS NOT NULL AND rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.facility_id = rf.facility_id AND rl.roast_date >= comp_count.cc_date::timestamp without time zone AND rl.roast_date < c.roast_week_start) cc_roasted ON true
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * (SELECT dsc.share FROM recipe_demand_source dsc WHERE dsc.recipe_id = rf.recipe_id AND dsc.source_recipe_id = p.recipe_id))::numeric AS lbs
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE comp_count.cc_date IS NOT NULL AND p.recipe_id IN (SELECT dsc2.source_recipe_id FROM recipe_demand_source dsc2 WHERE dsc2.recipe_id = rf.recipe_id AND dsc2.share > 0::numeric) AND o.facility_id = rf.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) >= comp_count.cc_date AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) < c.roast_week_start) cc_delivered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric) * ds2.share) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                             JOIN recipe_demand_source ds2 ON ds2.source_recipe_id = p2.recipe_id AND ds2.recipe_id = rf.recipe_id
                          WHERE o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND COALESCE(o2.production_date, o2.order_date) >= (c.orders_week_start - '42 days'::interval) AND COALESCE(o2.production_date, o2.order_date) < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON true
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
            cr.origin_pool_lbs,
            cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric AS recipe_buffer_target,
            cr.percentage * (cr.recipe_demand + cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric) AS component_demand_buf,
            cr.percentage * cr.recipe_demand AS component_demand_orders,
                CASE
                    WHEN cr.cc_date IS NOT NULL AND (cr.blend_anchor_date IS NULL OR cr.cc_date >= cr.blend_anchor_date) THEN cr.counted_component_stock
                    ELSE cr.this_week_stock
                END AS effective_stock
           FROM component_raw cr
        ), component_pool AS (
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
            ca.origin_pool_lbs,
            ca.recipe_buffer_target,
            ca.component_demand_buf,
            ca.component_demand_orders,
            ca.effective_stock,
            GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock) AS pool_residual,
            sum(GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock)) OVER (PARTITION BY ca.company_id, ca.facility_id, ca.origin_id) AS pool_residual_total
           FROM component_alloc ca
        ), component_grant AS (
         SELECT cp.recipe_id,
            cp.facility_id,
            cp.company_id,
            cp.origin_id,
            cp.percentage,
            cp.backstock_buffer_pct,
            cp.retention_rate,
            cp.facility_charge_weight,
            cp.recipe_demand,
            cp.this_week_stock,
            cp.component_roasted,
            cp.component_charge_weight,
            cp.recipe_avg_weekly_lbs,
            cp.weekly_target_override,
            cp.origin_pool_lbs,
            cp.recipe_buffer_target,
            cp.component_demand_buf,
            cp.component_demand_orders,
            cp.effective_stock,
            cp.pool_residual,
            LEAST(cp.pool_residual, COALESCE(cp.origin_pool_lbs * cp.pool_residual / NULLIF(cp.pool_residual_total, 0::numeric), 0::numeric)) AS origin_applied
           FROM component_pool cp
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
            ca.origin_applied,
            ca.effective_stock + ca.origin_applied AS applied_stock,
            GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock - ca.origin_applied) AS demand_after_stock
           FROM component_grant ca
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
            cs.origin_applied,
            cs.applied_stock,
            cs.demand_after_stock,
            LEAST(cs.demand_after_stock, cs.component_roasted) AS applied_roasted,
            GREATEST(0::numeric, cs.demand_after_stock - cs.component_roasted) AS component_remaining,
            GREATEST(0::numeric, cs.component_demand_orders - cs.effective_stock - cs.origin_applied - cs.component_roasted) AS component_remaining_orders_only
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

create or replace function public.roast_detail_by_blend(p_facility_id text)
 returns setof roast_detail_by_blend
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
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
          WHERE f.facility_id = p_facility_id
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
        ), origin_pool AS (
         SELECT DISTINCT ON (rsl.facility_id, rsl.origin_id) rsl.facility_id,
            rsl.origin_id,
            GREATEST(0::numeric, rsl.lbs_in_stock) AS pool_lbs
           FROM roast_stock_log rsl
             JOIN calc c ON c.facility_id = rsl.facility_id
          WHERE rsl.stock_type = 'origin'::text AND rsl.origin_id IS NOT NULL AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
          ORDER BY rsl.facility_id, rsl.origin_id, rsl.created_at DESC
        ), recipe_facility AS (
         SELECT rr.recipe_id,
            rr.roast_type,
            rr.retention_factor,
            f.facility_id,
            f.company_id
           FROM roast_recipes rr
             JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
          WHERE f.facility_id = p_facility_id
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
             LEFT JOIN LATERAL ( SELECT sum(x.lbs_in_stock * ds.share) AS anchor_stock,
                    max(x.counted_on) AS anchor_date,
                    bool_or(x.counted_on >= c.roast_week_start) AS in_current_week
                   FROM recipe_demand_source ds
                     JOIN LATERAL ( SELECT rsl.lbs_in_stock,
                            (rsl.created_at AT TIME ZONE c.timezone)::date AS counted_on
                           FROM roast_stock_log rsl
                          WHERE rsl.stock_type = 'blend'::text AND rsl.blend_id = ds.source_recipe_id AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= (c.roast_week_start - '28 days'::interval)
                          ORDER BY rsl.created_at DESC
                         LIMIT 1) x ON true
                  WHERE ds.recipe_id = rf.recipe_id AND ds.share > 0::numeric) anchor ON true
        ), recipe_is AS (
         SELECT ra.recipe_id,
            ra.facility_id,
                CASE
                    WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock) + COALESCE(( SELECT sum(
                                   GREATEST(0::numeric, b.counted_bags - COALESCE(( SELECT sum(odp.quantity)::numeric
                                        FROM order_details odp
                                          JOIN orders op ON op.order_id = odp.order_id
                                       WHERE odp.product_id = b.product_id AND op.facility_id = ra.facility_id AND op.order_status = 'Delivered'::text AND COALESCE((op.status_changed_at AT TIME ZONE ra.timezone)::date, op.order_date) >= (b.counted_at AT TIME ZONE ra.timezone)::date), 0::numeric))
                                     * (COALESCE(p.weight_lbs, 0::numeric) / COALESCE(NULLIF(( SELECT sz.units_per_case FROM size sz WHERE sz.size_id = p.size), 0), 1))
                                 * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                    ELSE GREATEST(0::numeric, COALESCE(ra.anchor_stock, 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS sum
                       FROM roast_log rl
                         JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                      WHERE rlr.recipe_id = ra.recipe_id AND rl.facility_id = ra.facility_id AND rl."charged?" = true AND rl.roast_date >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND rl.roast_date < ra.roast_week_start), 0::numeric) - COALESCE(( SELECT sum(od.roasted_weight * (SELECT dsd.share FROM recipe_demand_source dsd WHERE dsd.recipe_id = ra.recipe_id AND dsd.source_recipe_id = p.recipe_id))::numeric AS sum
                       FROM order_details od
                         JOIN orders o ON od.order_id = o.order_id
                         JOIN products p ON od.product_id = p.product_id
                      WHERE p.recipe_id IN (SELECT dsd2.source_recipe_id FROM recipe_demand_source dsd2 WHERE dsd2.recipe_id = ra.recipe_id AND dsd2.share > 0::numeric) AND o.facility_id = ra.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) < ra.roast_week_start), 0::numeric)) + COALESCE(( SELECT sum(
                                   GREATEST(0::numeric, b.counted_bags - COALESCE(( SELECT sum(odp.quantity)::numeric
                                        FROM order_details odp
                                          JOIN orders op ON op.order_id = odp.order_id
                                       WHERE odp.product_id = b.product_id AND op.facility_id = ra.facility_id AND op.order_status = 'Delivered'::text AND COALESCE((op.status_changed_at AT TIME ZONE ra.timezone)::date, op.order_date) >= (b.counted_at AT TIME ZONE ra.timezone)::date), 0::numeric))
                                     * (COALESCE(p.weight_lbs, 0::numeric) / COALESCE(NULLIF(( SELECT sz.units_per_case FROM size sz WHERE sz.size_id = p.size), 0), 1))
                                 * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                END AS in_stock_roasted
           FROM recipe_anchor ra
        ), recipe_override AS (
         SELECT dsw.recipe_id,
            dsw.facility_id,
            sum(rwt.target_lbs * dsw.share) AS target_lbs,
            min(rwt.notes) AS notes
           FROM recipe_weekly_targets rwt
             JOIN calc c ON c.facility_id = rwt.facility_id
             JOIN recipe_demand_source dsw ON dsw.source_recipe_id = rwt.recipe_id AND dsw.facility_id = rwt.facility_id AND dsw.share > 0::numeric
          WHERE rwt.week_start = c.roast_week_start
          GROUP BY dsw.recipe_id, dsw.facility_id
        ), recipe_level AS (
         SELECT rf.recipe_id,
            rf.facility_id,
            rf.company_id,
            c.backstock_buffer_pct,
            COALESCE(ris.in_stock_roasted, 0::numeric) AS in_stock_roasted,
            COALESCE(ovr.target_lbs::double precision, ordered.total_ordered, 0::double precision) AS total_ordered,
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
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * ds.share) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                     JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = rf.recipe_id
                  WHERE o.facility_id = rf.facility_id AND o.order_status = 'Open'::text) ordered ON true
             LEFT JOIN LATERAL ( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS total_roasted
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start, ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND ((s.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1)) AND rl.facility_id = rf.facility_id) roasted ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric) * ds2.share) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                             JOIN recipe_demand_source ds2 ON ds2.source_recipe_id = p2.recipe_id AND ds2.recipe_id = rf.recipe_id
                          WHERE o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND COALESCE(o2.production_date, o2.order_date) >= (c.orders_week_start - '42 days'::interval) AND COALESCE(o2.production_date, o2.order_date) < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON true
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
            COALESCE(ovr.target_lbs, ordered.total_ordered::numeric, 0::numeric) AS recipe_demand,
            COALESCE(ris.in_stock_roasted, 0::numeric) * COALESCE(rc.percentage, 0::numeric) AS this_week_stock,
            COALESCE(component_roasted.lbs, 0::numeric) AS component_roasted,
            COALESCE(charge_w.avg_w, recipe_charge_w.avg_w, origin_charge_w.avg_w, c.charge_weight, 25::numeric) AS component_charge_weight,
            COALESCE(avg_lbs.avg_weekly_lbs, 0::numeric) AS recipe_avg_weekly_lbs,
            ovr.target_lbs AS weekly_target_override,
            ran.anchor_date AS blend_anchor_date,
            COALESCE(op.pool_lbs, 0::numeric) AS origin_pool_lbs,
            comp_count.cc_date,
                CASE
                    WHEN comp_count.cc_date IS NULL THEN NULL::numeric
                    WHEN comp_count.cc_in_current_week THEN GREATEST(0::numeric, comp_count.cc_stock)
                    ELSE GREATEST(0::numeric, COALESCE(comp_count.cc_stock, 0::numeric) + COALESCE(cc_roasted.lbs, 0::numeric) - COALESCE(cc_delivered.lbs, 0::numeric) * COALESCE(rc.percentage, 0::numeric))
                END AS counted_component_stock
           FROM recipe_facility rf
             JOIN recipe_components rc ON rc.recipe_id = rf.recipe_id
             JOIN calc c ON c.facility_id = rf.facility_id
             LEFT JOIN recipe_is ris ON ris.recipe_id = rf.recipe_id AND ris.facility_id = rf.facility_id
             LEFT JOIN recipe_override ovr ON ovr.recipe_id = rf.recipe_id AND ovr.facility_id = rf.facility_id
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * ds.share) AS total_ordered
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                     JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = rf.recipe_id
                  WHERE o.facility_id = rf.facility_id AND o.order_status = 'Open'::text) ordered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start, ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND ((s.created_at AT TIME ZONE c.timezone))::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1), ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'origin'::text AND s.origin_id = rc.coffee_item AND s.facility_id = rf.facility_id AND (s.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1)) AND rl.facility_id = rf.facility_id) component_roasted ON true
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
             LEFT JOIN recipe_anchor ran ON ran.recipe_id = rf.recipe_id AND ran.facility_id = rf.facility_id
             LEFT JOIN origin_pool op ON op.facility_id = rf.facility_id AND op.origin_id = rc.coffee_item
             LEFT JOIN LATERAL ( SELECT rsl.lbs_in_stock AS cc_stock,
                    (rsl.created_at AT TIME ZONE c.timezone)::date AS cc_date,
                    (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start AS cc_in_current_week
                   FROM roast_stock_log rsl
                  WHERE rsl.stock_type = 'component'::text AND rsl.blend_id = rf.recipe_id AND rsl.origin_id = rc.coffee_item AND rsl.facility_id = rf.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= (c.roast_week_start - '28 days'::interval)
                  ORDER BY rsl.created_at DESC
                 LIMIT 1) comp_count ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE comp_count.cc_date IS NOT NULL AND rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.facility_id = rf.facility_id AND rl.roast_date >= comp_count.cc_date::timestamp without time zone AND rl.roast_date < c.roast_week_start) cc_roasted ON true
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight * (SELECT dsc.share FROM recipe_demand_source dsc WHERE dsc.recipe_id = rf.recipe_id AND dsc.source_recipe_id = p.recipe_id))::numeric AS lbs
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE comp_count.cc_date IS NOT NULL AND p.recipe_id IN (SELECT dsc2.source_recipe_id FROM recipe_demand_source dsc2 WHERE dsc2.recipe_id = rf.recipe_id AND dsc2.share > 0::numeric) AND o.facility_id = rf.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) >= comp_count.cc_date AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) < c.roast_week_start) cc_delivered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(weekly.lbs), 0::numeric) / 6::numeric AS avg_weekly_lbs
                   FROM ( SELECT date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone) AS wk,
                            sum(od2.quantity * COALESCE(p2.weight_lbs, 0::numeric) * ds2.share) AS lbs
                           FROM order_details od2
                             JOIN orders o2 ON od2.order_id = o2.order_id
                             JOIN products p2 ON od2.product_id = p2.product_id
                             JOIN recipe_demand_source ds2 ON ds2.source_recipe_id = p2.recipe_id AND ds2.recipe_id = rf.recipe_id
                          WHERE o2.facility_id = rf.facility_id AND o2.order_status <> 'Canceled'::text AND COALESCE(o2.production_date, o2.order_date) >= (c.orders_week_start - '42 days'::interval) AND COALESCE(o2.production_date, o2.order_date) < c.orders_week_start
                          GROUP BY (date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone))) weekly) avg_lbs ON true
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
            cr.origin_pool_lbs,
            cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric AS recipe_buffer_target,
            cr.percentage * (cr.recipe_demand + cr.recipe_avg_weekly_lbs * cr.backstock_buffer_pct / 100::numeric) AS component_demand_buf,
            cr.percentage * cr.recipe_demand AS component_demand_orders,
                CASE
                    WHEN cr.cc_date IS NOT NULL AND (cr.blend_anchor_date IS NULL OR cr.cc_date >= cr.blend_anchor_date) THEN cr.counted_component_stock
                    ELSE cr.this_week_stock
                END AS effective_stock
           FROM component_raw cr
        ), component_pool AS (
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
            ca.origin_pool_lbs,
            ca.recipe_buffer_target,
            ca.component_demand_buf,
            ca.component_demand_orders,
            ca.effective_stock,
            GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock) AS pool_residual,
            sum(GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock)) OVER (PARTITION BY ca.company_id, ca.facility_id, ca.origin_id) AS pool_residual_total
           FROM component_alloc ca
        ), component_grant AS (
         SELECT cp.recipe_id,
            cp.facility_id,
            cp.company_id,
            cp.origin_id,
            cp.percentage,
            cp.backstock_buffer_pct,
            cp.retention_rate,
            cp.facility_charge_weight,
            cp.recipe_demand,
            cp.this_week_stock,
            cp.component_roasted,
            cp.component_charge_weight,
            cp.recipe_avg_weekly_lbs,
            cp.weekly_target_override,
            cp.origin_pool_lbs,
            cp.recipe_buffer_target,
            cp.component_demand_buf,
            cp.component_demand_orders,
            cp.effective_stock,
            cp.pool_residual,
            LEAST(cp.pool_residual, COALESCE(cp.origin_pool_lbs * cp.pool_residual / NULLIF(cp.pool_residual_total, 0::numeric), 0::numeric)) AS origin_applied
           FROM component_pool cp
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
            ca.origin_applied,
            ca.effective_stock + ca.origin_applied AS applied_stock,
            GREATEST(0::numeric, ca.component_demand_buf - ca.effective_stock - ca.origin_applied) AS demand_after_stock
           FROM component_grant ca
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
            cs.origin_applied,
            cs.applied_stock,
            cs.demand_after_stock,
            LEAST(cs.demand_after_stock, cs.component_roasted) AS applied_roasted,
            GREATEST(0::numeric, cs.demand_after_stock - cs.component_roasted) AS component_remaining,
            GREATEST(0::numeric, cs.component_demand_orders - cs.effective_stock - cs.origin_applied - cs.component_roasted) AS component_remaining_orders_only
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
   FROM unioned
$function$;

create or replace function public.recipe_bagged_applied(p_facility_id text)
 returns table(recipe_id text, applied_lbs numeric)
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  with w as (
    select ws.roast_week_start,
           coalesce(nullif(f.time_zone, ''::text), 'Pacific/Honolulu'::text) as timezone
      from facilities f
      cross join lateral public.facility_week_starts(f.facility_id) ws
     where f.facility_id = p_facility_id
  ),
  latest as (
    select distinct on (psc.product_id) psc.product_id, psc.counted_bags, psc.counted_at
      from pack_stock_count psc
      cross join w
     where psc.facility_id = p_facility_id
       and (psc.counted_at at time zone w.timezone)::date >= (w.roast_week_start - interval '28 days')
     order by psc.product_id, psc.counted_at desc
  )
  select ds.recipe_id,
         -- The bags that are STILL THERE: counted, less what has shipped
         -- since the count. NOT capped at this variant's own demand -- a bag
         -- with no matching order is still finished coffee on a shelf, which
         -- is exactly what the backstock buffer is made of. See
         -- 20261029000006 for the arithmetic that settles it.
         sum(greatest(0::numeric, l.counted_bags - coalesce((
                 select sum(odp.quantity)::numeric
                   from order_details odp
                   join orders op on op.order_id = odp.order_id
                  where odp.product_id = l.product_id
                    and op.facility_id = p_facility_id
                    and op.order_status = 'Delivered'::text
                    and coalesce((op.status_changed_at at time zone w.timezone)::date, op.order_date)
                        >= (l.counted_at at time zone w.timezone)::date), 0::numeric))
                 * (coalesce(p.weight_lbs, 0::numeric)
                    / coalesce(nullif((select sz.units_per_case from size sz where sz.size_id = p.size), 0), 1))
             * ds.share) as applied_lbs
    from latest l
    cross join w
    join products p on p.product_id = l.product_id
    join recipe_demand_source ds on ds.source_recipe_id = p.recipe_id
   where ds.share > 0::numeric
   group by ds.recipe_id;
$function$;

comment on function public.recipe_bagged_applied(text) is
  'Per recipe, the lbs of counted bags still on the shelf: counted_bags less units delivered since the count. in_stock_roasted minus this is bin stock. Mirrors the roast plan pack leg -- change both together.';

do $$
declare n integer;
begin
  insert into public.roast_plan_dirty (facility_id, reason)
  select f.facility_id, 'bagged coffee counts toward the backstock buffer again'
    from public.facilities f;
  get diagnostics n = row_count;
  raise notice 'roast_plan marked dirty for % facilities', n;
end $$;

commit;
