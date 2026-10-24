-- The pack queue was counting coffee that had already left the building.
--
-- Owner, 2026-10-23, on the orders dashboard: the pack queue was listing
-- orders that had already been DELIVERED.
--
-- -- WHY, AND THE NUMBERS OFF PROD ------------------------------------------
--
-- `packed_qty` asks two things: is the LINE `item_status = 'Packed'`, and is
-- the ORDER not Canceled. It never asks whether the order shipped. And the
-- line does not change when it ships: migration 20260910000028 deliberately
-- maps a delivery transition to `Packed` on the line, because 'Delivered' is
-- not a packing state. So the ORDER carries the fact of delivery and the line
-- does not, and a filter reading only the line cannot see it.
--
-- Measured on prod, across every `item_status = 'Packed'` line:
--
--     order_status   lines   units
--     Delivered       3958   18596
--     Packed            83     436
--
-- Ninety-eight percent of them. In the order week of 2026-10-19 the
-- dashboard's "Packed / orders ready to ship" card read 1,260 units when 260
-- were actually waiting to ship: four fifths of that card, and of the pack
-- queue under it, was coffee already on a customer's shelf.
--
-- -- THE FIX IS IN THE VIEWS, NOT IN THE LINE -------------------------------
--
-- Both views gain `AND o.order_status <> 'Delivered'` on packed_qty ALONE.
-- `total`, `left_to_pack`, `open_backlog` and `delivered_qty` are untouched:
-- delivered_qty is supposed to count delivered orders, and the open measures
-- read `item_status = 'Open'`, which a delivered order's lines are not.
--
-- NOT a backfill of order_details, deliberately. Rewriting 3,958 lines to
-- 'Delivered' would restate four weeks of history to repair one card, and the
-- 20260910000028 decision -- that a line records packing and not shipping --
-- is still the right one. The order is the authority on delivery; the view
-- now asks it.
--
-- Four surfaces read packed_qty and every one means "packed, not yet gone":
-- the orders dashboard pack queue, the main dashboard pack totals, the Weekly
-- Totals Packed column, and the Product Filter's `packed` list that feeds
-- bulk marking. Nothing else in the database reads it.
--
-- NOTE Both views are `security_invoker=true` and MUST stay so: CREATE OR
-- REPLACE drops reloptions that are not restated, and pg_get_viewdef does not
-- report them, which is how a view quietly starts reading as its owner. The
-- bodies below are the LIVE definitions with the one condition inserted by
-- script, not retyped.

begin;

create or replace view public.totals with (security_invoker = true) as
WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT cp.value_number::integer AS value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'orders_reset_day'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), ( SELECT sp.amount::integer AS amount
                   FROM standard_parameters sp
                  WHERE sp.parameters_id = 'orders_reset_day'::text
                 LIMIT 1), 6) AS orders_reset_day
           FROM facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start
           FROM facility_params fp
        ), product_facility AS (
         SELECT p.product_id,
            f.facility_id,
            f.company_id
           FROM products p
             JOIN facilities f ON p.company_id = f.company_id AND (p.facility_id IS NULL OR p.facility_id = f.facility_id)
        )
 SELECT (pf.product_id || '-'::text) || pf.facility_id AS totals_id,
    pf.product_id,
    pf.facility_id,
    pf.company_id,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND COALESCE(o.production_date, o.order_date) < (c.orders_week_start + '7 days'::interval) AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text), 0::numeric) AS total,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND od.item_status = 'Open'::text AND (o.production_date IS NULL OR o.production_date < (c.orders_week_start + '7 days'::interval)) AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text), 0::numeric) AS left_to_pack,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND od.item_status = 'Open'::text AND COALESCE(o.production_date, o.order_date) < c.orders_week_start AND (o.production_date IS NULL OR o.production_date < (c.orders_week_start + '7 days'::interval)) AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text), 0::numeric) AS open_backlog,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND od.item_status = 'Packed'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text AND o.order_status <> 'Delivered'::text), 0::numeric) AS packed_qty,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND o.order_status = 'Delivered'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND o.facility_id = pf.facility_id), 0::numeric) AS delivered_qty,
    COALESCE(( SELECT avg(sub.weekly_sum) AS avg
           FROM ( SELECT sum(od2.quantity) AS weekly_sum
                   FROM order_details od2
                     JOIN orders o2 ON od2.order_id = o2.order_id
                  WHERE od2.product_id = pf.product_id AND COALESCE(o2.production_date, o2.order_date) >= (c.orders_week_start - '42 days'::interval) AND COALESCE(o2.production_date, o2.order_date) < c.orders_week_start AND o2.facility_id = pf.facility_id AND o2.order_status <> 'Canceled'::text
                  GROUP BY (date_trunc('week'::text, COALESCE(o2.production_date, o2.order_date)::timestamp with time zone))) sub), 0::numeric) AS recent_avg_week
   FROM product_facility pf
     JOIN calc c ON c.facility_id = pf.facility_id;

create or replace view public.pack_totals_by_prep with (security_invoker = true) as
WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT cp.value_number::integer AS value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'orders_reset_day'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), ( SELECT sp.amount::integer AS amount
                   FROM standard_parameters sp
                  WHERE sp.parameters_id = 'orders_reset_day'::text
                 LIMIT 1), 6) AS orders_reset_day
           FROM facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start
           FROM facility_params fp
        )
 SELECT o.facility_id,
    o.company_id,
    od.product_id,
    od.coffee_prep,
    sum(od.quantity) FILTER (WHERE od.item_status = 'Open'::text AND (o.production_date IS NULL OR o.production_date < (c.orders_week_start + '7 days'::interval))) AS left_to_pack,
    sum(od.quantity) FILTER (WHERE od.item_status = 'Packed'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND o.order_status <> 'Delivered'::text) AS packed_qty
   FROM order_details od
     JOIN orders o ON o.order_id = od.order_id
     JOIN calc c ON c.facility_id = o.facility_id
  WHERE o.order_status <> 'Canceled'::text
  GROUP BY o.facility_id, o.company_id, od.product_id, od.coffee_prep;

-- Prove the condition landed in both, and that security_invoker survived.
do $$
declare
  n_totals int;
  n_prep   int;
  n_si     int;
begin
  select count(*) into n_totals from pg_views
   where schemaname = 'public' and viewname = 'totals'
     and definition like '%order_status <> ''Delivered''%';
  select count(*) into n_prep from pg_views
   where schemaname = 'public' and viewname = 'pack_totals_by_prep'
     and definition like '%order_status <> ''Delivered''%';
  select count(*) into n_si from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname in ('totals','pack_totals_by_prep')
     and c.reloptions @> array['security_invoker=true'];

  if n_totals <> 1 then raise exception 'totals did not take the Delivered exclusion'; end if;
  if n_prep   <> 1 then raise exception 'pack_totals_by_prep did not take the Delivered exclusion'; end if;
  if n_si     <> 2 then raise exception 'security_invoker missing: only % of 2 views carry it', n_si; end if;
end $$;

commit;
