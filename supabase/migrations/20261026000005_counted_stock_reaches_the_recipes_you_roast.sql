-- The stock you count on a post-blend reaches the recipes you roast.
--
-- Step 5, and the one the owner asked for from the floor: *"what about when i
-- count in plan inputs. will it split the recipe 50 50 for allocation of what
-- needs to be roasted?"*
--
-- Step 4 moved DEMAND down to the children and left stock where it was, so a
-- counted bin or bag of finished Maui Blend sat on the parent, which has no
-- demand to offset, and reduced nothing. A bag of Maui Blend physically IS half
-- dark and half light, so it has to reduce each child by half.
--
-- Three stock paths, all now resolved through `recipe_demand_source` at share:
--
--   the blend anchor   was "the latest count for THIS recipe". It is now "the
--                      latest count for each SOURCE, summed at that source's
--                      share". A child therefore adds its own unblended bin at
--                      share 1 and its parent's finished bin at 0.5.
--   bagged counts      multiplied by the share as well as joined, so a 1 lb bag
--                      of the parent's product is half a pound to each child.
--   the roasted-since  floor now honours a count on the recipe OR on any of its
--   floor              sources, so a count of the finished blend supersedes the
--                      children's earlier roasts instead of double counting
--                      against them.
--
-- 🔴 THE ANCHOR CHANGED SHAPE, from a LIMIT 1 row to an aggregate, and that is
-- the delicate part of this whole batch. For an ordinary recipe
-- `recipe_demand_source` is a single identity row at share 1, so the inner
-- lateral picks the same latest row, `sum(x * 1)` is that row's value,
-- `max(counted_on)` is its date and `bool_or` is its in-week flag: byte for
-- byte the old answer. With NO count at all, the aggregate returns one row of
-- NULLs, exactly as the old LEFT JOIN did.
--
-- 🔴 A CONTAINER'S OWN ROW IS EXCLUDED by `ds.share > 0`. Its stock has flowed
-- to its children; leaving it would count the same coffee twice.
--
-- 🔴 NOT SPLIT, deliberately: a `stock_type='component'` count is already tagged
-- to a specific (recipe, origin) pair, and a `stock_type='origin'` bin is green
-- that has not been blended into anything yet. Neither belongs to a parent.
--
-- Ten edits, patched by script from the step-4 text with the count asserted at
-- each site, never retyped. Both bodies.

begin;

create or replace view public.roast_detail_by_blend with (security_invoker = true) as
WITH facility_params AS NOT MATERIALIZED (
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
        ), calc AS NOT MATERIALIZED (
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
        ), origin_pool AS NOT MATERIALIZED (
         SELECT DISTINCT ON (rsl.facility_id, rsl.origin_id) rsl.facility_id,
            rsl.origin_id,
            GREATEST(0::numeric, rsl.lbs_in_stock) AS pool_lbs
           FROM roast_stock_log rsl
             JOIN calc c ON c.facility_id = rsl.facility_id
          WHERE rsl.stock_type = 'origin'::text AND rsl.origin_id IS NOT NULL AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
          ORDER BY rsl.facility_id, rsl.origin_id, rsl.created_at DESC
        ), recipe_facility AS NOT MATERIALIZED (
         SELECT rr.recipe_id,
            rr.roast_type,
            rr.retention_factor,
            f.facility_id,
            f.company_id
           FROM roast_recipes rr
             JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
        ), recipe_anchor AS NOT MATERIALIZED (
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
        ), recipe_is AS NOT MATERIALIZED (
         SELECT ra.recipe_id,
            ra.facility_id,
                CASE
                    WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock) + COALESCE(( SELECT sum(b.counted_bags * COALESCE(p.weight_lbs, 0::numeric) * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                    ELSE GREATEST(0::numeric, COALESCE(ra.anchor_stock, 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS sum
                       FROM roast_log rl
                         JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                      WHERE rlr.recipe_id = ra.recipe_id AND rl.facility_id = ra.facility_id AND rl."charged?" = true AND rl.roast_date >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND rl.roast_date < ra.roast_week_start), 0::numeric) - COALESCE(( SELECT sum(od.roasted_weight)::numeric AS sum
                       FROM order_details od
                         JOIN orders o ON od.order_id = o.order_id
                         JOIN products p ON od.product_id = p.product_id
                      WHERE p.recipe_id = ra.recipe_id AND o.facility_id = ra.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) >= COALESCE(ra.anchor_date::timestamp without time zone, ra.orders_week_start - '28 days'::interval) AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) < ra.orders_week_start), 0::numeric)) + COALESCE(( SELECT sum(b.counted_bags * COALESCE(p.weight_lbs, 0::numeric) * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                END AS in_stock_roasted
           FROM recipe_anchor ra
        ), recipe_override AS NOT MATERIALIZED (
         SELECT rwt.recipe_id,
            rwt.facility_id,
            rwt.target_lbs,
            rwt.notes
           FROM recipe_weekly_targets rwt
             JOIN calc c ON c.facility_id = rwt.facility_id
          WHERE rwt.week_start = c.roast_week_start
        ), recipe_level AS NOT MATERIALIZED (
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
                  WHERE o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
             LEFT JOIN LATERAL ( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS total_roasted
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start::timestamp without time zone, ( SELECT (s.created_at AT TIME ZONE c.timezone) AS timezone
                           FROM roast_stock_log s
                          WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND (s.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
                          ORDER BY s.created_at DESC
                         LIMIT 1)) AND rl.facility_id = rf.facility_id) roasted ON true
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
        ), component_raw AS NOT MATERIALIZED (
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
                  WHERE o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))), 0::numeric) AS lbs
                   FROM roast_log rl
                     JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                  WHERE rlr.recipe_id = rf.recipe_id AND rl.origin_id = rc.coffee_item AND rl."charged?" = true AND rl.roast_date >= GREATEST(c.roast_week_start::timestamp without time zone, ( SELECT (s.created_at AT TIME ZONE c.timezone) AS timezone
                           FROM roast_stock_log s
                          WHERE s.stock_type = 'blend'::text AND s.blend_id IN (SELECT ds2.source_recipe_id FROM recipe_demand_source ds2 WHERE ds2.recipe_id = rf.recipe_id AND ds2.share > 0::numeric) AND s.facility_id = rf.facility_id AND (s.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start
                          ORDER BY s.created_at DESC
                         LIMIT 1), ( SELECT (s.created_at AT TIME ZONE c.timezone) FROM roast_stock_log s WHERE s.stock_type = 'origin'::text AND s.origin_id = rc.coffee_item AND s.facility_id = rf.facility_id AND (s.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start ORDER BY s.created_at DESC LIMIT 1)) AND rl.facility_id = rf.facility_id) component_roasted ON true
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
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight)::numeric AS lbs
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE comp_count.cc_date IS NOT NULL AND p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) >= comp_count.cc_date AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) < c.orders_week_start) cc_delivered ON true
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
        ), component_alloc AS NOT MATERIALIZED (
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
        ), component_pool AS NOT MATERIALIZED (
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
        ), component_grant AS NOT MATERIALIZED (
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
        ), component_split AS NOT MATERIALIZED (
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
        ), component_final AS NOT MATERIALIZED (
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
        ), post_blend_recipe AS NOT MATERIALIZED (
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
        ), unioned AS NOT MATERIALIZED (
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

CREATE OR REPLACE FUNCTION public.roast_detail_by_blend(p_facility_id text)
 RETURNS SETOF roast_detail_by_blend
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                    WHEN ra.in_current_week THEN GREATEST(0::numeric, ra.anchor_stock) + COALESCE(( SELECT sum(b.counted_bags * COALESCE(p.weight_lbs, 0::numeric) * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
                    ELSE GREATEST(0::numeric, COALESCE(ra.anchor_stock, 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * (rlr.lbs_allocated / NULLIF(rl.charge_weight_lbs, 0::numeric))) AS sum
                       FROM roast_log rl
                         JOIN roast_log_recipes rlr ON rlr.roast_log_id = rl.roast_log_id
                      WHERE rlr.recipe_id = ra.recipe_id AND rl.facility_id = ra.facility_id AND rl."charged?" = true AND rl.roast_date >= COALESCE(ra.anchor_date::timestamp without time zone, ra.roast_week_start - '28 days'::interval) AND rl.roast_date < ra.roast_week_start), 0::numeric) - COALESCE(( SELECT sum(od.roasted_weight)::numeric AS sum
                       FROM order_details od
                         JOIN orders o ON od.order_id = o.order_id
                         JOIN products p ON od.product_id = p.product_id
                      WHERE p.recipe_id = ra.recipe_id AND o.facility_id = ra.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) >= COALESCE(ra.anchor_date::timestamp without time zone, ra.orders_week_start - '28 days'::interval) AND COALESCE((o.status_changed_at AT TIME ZONE ra.timezone)::date, o.order_date) < ra.orders_week_start), 0::numeric)) + COALESCE(( SELECT sum(b.counted_bags * COALESCE(p.weight_lbs, 0::numeric) * ds.share) AS sum
                       FROM ( SELECT DISTINCT ON (psc.product_id) psc.product_id, psc.counted_bags
                                FROM pack_stock_count psc
                               WHERE psc.facility_id = ra.facility_id AND (psc.counted_at AT TIME ZONE ra.timezone)::date >= (ra.roast_week_start - '28 days'::interval)
                               ORDER BY psc.product_id, psc.counted_at DESC) b
                         JOIN products p ON p.product_id = b.product_id
                         JOIN recipe_demand_source ds ON ds.source_recipe_id = p.recipe_id AND ds.recipe_id = ra.recipe_id
                      WHERE ds.share > 0::numeric), 0::numeric)
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
                  WHERE o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
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
                  WHERE o.facility_id = rf.facility_id AND o.order_status <> 'Canceled'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval)) ordered ON true
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
             LEFT JOIN LATERAL ( SELECT sum(od.roasted_weight)::numeric AS lbs
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                  WHERE comp_count.cc_date IS NOT NULL AND p.recipe_id = rf.recipe_id AND o.facility_id = rf.facility_id AND o.order_status = 'Delivered'::text AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) >= comp_count.cc_date AND COALESCE((o.status_changed_at AT TIME ZONE c.timezone)::date, o.order_date) < c.orders_week_start) cc_delivered ON true
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

grant select on public.roast_detail_by_blend to authenticated, service_role;
grant execute on function public.roast_detail_by_blend(text) to authenticated, service_role;

-- Prove it, rather than assume it.

do $$
declare n_view int; n_fn int; n_si int;
begin
  -- 🔴 MATCH ON IDENTIFIERS, NOT ON SPACING. pg_get_viewdef renormalises the
  -- stored view: `0::numeric` comes back as `(0)::numeric` and products gain
  -- parentheses, so a literal pattern matches the function's verbatim source
  -- and silently never matches the view. That exact mistake reported "view 0,
  -- function 1" on the first run of this block.
  select count(*) into n_view from pg_views
   where schemaname='public' and viewname='roast_detail_by_blend'
     and definition like '%ds.share%'
     and definition like '%counted_on%'
     and definition like '%bool_or%';
  select count(*) into n_fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='roast_detail_by_blend'
     and pg_get_functiondef(p.oid) like '%ds.share%'
     and pg_get_functiondef(p.oid) like '%counted_on%'
     and pg_get_functiondef(p.oid) like '%bool_or%';
  if n_view <> 1 or n_fn <> 1 then
    raise exception 'the stock split reached % of the two bodies (view %, function %)',
      n_view + n_fn, n_view, n_fn;
  end if;

  select count(*) into n_si from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
   where ns.nspname='public' and c.relname='roast_detail_by_blend'
     and c.reloptions @> array['security_invoker=true'];
  if n_si <> 1 then raise exception 'security_invoker was dropped on re-emit'; end if;

  perform 1 from (select 1 from public.roast_detail_by_blend limit 1) x;
end $$;

commit;
