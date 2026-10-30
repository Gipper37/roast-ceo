-- The pack queue reads the date the customer gave, on a horizon that does not
-- shrink.
--
-- Owner, 2026-10-28, looking at the roast plan: *"european dark is showing for
-- saint josephs order in the roast plan (maybe not in the lfq though which
-- would be weird) but the production date is not until the 2nd. i thought we
-- fixed that stuff"*
--
-- He was right, and about the half he put in brackets. The roast plan was NOT
-- the thing that was wrong.
--
-- ── TWO FAULTS, AND FIXING EITHER ALONE MAKES IT WORSE ────────────────────
--
-- 1. THE QUEUE READ THE DATE NOBODY FILLS IN. The test was on
--    `o.production_date` alone. Across every tenant's Open lines:
--
--        production_date set .............  4 lines
--        only requested_delivery_date ... 42 lines   (307 units)
--        no date at all ................. 79 lines
--
--    So the clause consulted the column that is set four times, and ignored
--    the one set forty-two times. Every one of those 42 took the
--    `production_date IS NULL` branch and was treated as having no due date,
--    whatever the customer had actually asked for.
--
-- 2. THE HORIZON SHRANK ALL WEEK. The ceiling was `orders_week_start + 7
--    days` -- a FIXED date, not a rolling one. MCR's orders week opens
--    Saturday, so the ceiling sat at 2026-10-31 every day of the week: a
--    7-day view of the work on Saturday, 2 days by Thursday, and on Friday
--    one. Worse, the ROAST week runs Thursday to Wednesday (2026-10-29 to
--    11-04), so from Thursday on, the pack queue could not show the back half
--    of the week the roast plan was already roasting for. Saint Joseph's
--    European Dark, due 11-02, was in the plan and absent from the queue.
--
-- Fixing 1 without 2 would have REMOVED 172 units of MCR's work from the
-- queue: orders due 11-04 and 11-05 that today sneak in through the
-- `production_date IS NULL` branch would have acquired a due date past a
-- ceiling still stuck at 10-31. Fixing 2 without 1 leaves 307 units still
-- claiming to have no due date. They go together or not at all.
--
-- ── WHAT IT DOES NOW ─────────────────────────────────────────────────────
--
-- A due date is `COALESCE(production_date, requested_delivery_date)` -- what
-- the roastery scheduled, else what the customer asked for. It may still be
-- NULL, and NULL still means SHOW IT: undated Open work has to stay visible,
-- which is the same principle 20261026000008 settled for the roast plan.
--
-- The ceiling rolls from the facility's own today: due within the next seven
-- days, inclusive. `today_local` is computed in the facility's timezone in the
-- same calc CTE that already derives orders_week_start, so a Honolulu roastery
-- and a London one each get their own today.
--
-- There is still NO FLOOR, deliberately. An Open line due last month is work
-- you owe somebody.
--
-- ── MEASURED ON PROD: THIS TEXT, RUN READ-ONLY, BEFORE COMMITTING IT ─────
--
--                              to pack        flagged overdue
--     Maui Coffee Roasters     327 -> 747        120 -> 0
--     Portland Roastery        462 -> 462        390 -> 390
--     Demo Roastery             16 ->  16         16 -> 16
--     Anglesey Roastery         19 ->  19          0 -> 0
--
-- 420 units ADDED at MCR and NOTHING removed, at any tenant.
--
-- 🔴 The 420 IS ONE ORDER. Saint Joseph's, due 2026-11-02, and it is the
-- largest single thing MCR owes anybody. MCR's whole Open book by effective
-- due date:
--
--     10-28   2 orders     9 units      11-04   3 orders   137 units
--     10-29   6 orders   133 units      11-05   1 order     35 units
--     10-30   2 orders    13 units      11-09   1 order      1 unit
--     11-02   1 order    420 units
--
-- Everything from 11-02 on -- 593 of the 747 units, four fifths of the book --
-- sat past a ceiling frozen at 10-31. The roast plan was asking for it and the
-- pack queue did not know it existed.
--
-- The overdue count falling to 0 is the same correction from the other side.
-- Those 120 units are ONE order, placed 2026-10-08, requested for 11-04. It
-- was called backlog because of when it was PLACED. It is not late, it stays
-- in the queue, it just stops being flagged. Nothing at MCR is genuinely
-- overdue, and 0 is checked, not assumed: Portland still reports 390 and Demo
-- 16 from the same expression.
--
-- 🔴 THREE OCCURRENCES IN TWO VIEWS, NOT ONE. `totals` carries the ceiling
-- twice (left_to_pack and open_backlog) and `pack_totals_by_prep` once, and
-- open_backlog's own FLOOR needs the same due date or it contradicts the
-- ceiling above it. The counts are asserted by the generator; grep before and
-- after.
--
-- 🔴 BOTH VIEWS MUST RESTATE security_invoker. pg_get_viewdef drops it, so a
-- body round-tripped through it and replayed without the clause silently
-- turns the view into a tenant-blind one.

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
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date AS today_local
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
          WHERE od.product_id = pf.product_id AND od.item_status = 'Open'::text AND (COALESCE(o.production_date, o.requested_delivery_date) IS NULL OR COALESCE(o.production_date, o.requested_delivery_date) <= (c.today_local + 7)) AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text), 0::numeric) AS left_to_pack,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM order_details od
             JOIN orders o ON od.order_id = o.order_id
          WHERE od.product_id = pf.product_id AND od.item_status = 'Open'::text AND COALESCE(o.production_date, o.requested_delivery_date, o.order_date) < c.orders_week_start AND (COALESCE(o.production_date, o.requested_delivery_date) IS NULL OR COALESCE(o.production_date, o.requested_delivery_date) <= (c.today_local + 7)) AND o.facility_id = pf.facility_id AND o.order_status <> 'Canceled'::text), 0::numeric) AS open_backlog,
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
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.orders_reset_day + 7) % 7 AS orders_week_start,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date AS today_local
           FROM facility_params fp
        )
 SELECT o.facility_id,
    o.company_id,
    od.product_id,
    od.coffee_prep,
    sum(od.quantity) FILTER (WHERE od.item_status = 'Open'::text AND (COALESCE(o.production_date, o.requested_delivery_date) IS NULL OR COALESCE(o.production_date, o.requested_delivery_date) <= (c.today_local + 7))) AS left_to_pack,
    sum(od.quantity) FILTER (WHERE od.item_status = 'Packed'::text AND COALESCE(o.production_date, o.order_date) >= c.orders_week_start AND o.order_status <> 'Delivered'::text) AS packed_qty
   FROM order_details od
     JOIN orders o ON o.order_id = od.order_id
     JOIN calc c ON c.facility_id = o.facility_id
  WHERE o.order_status <> 'Canceled'::text
  GROUP BY o.facility_id, o.company_id, od.product_id, od.coffee_prep;

commit;
