-- Simplify packed_qty and delivered_qty to use order_date >= orders_week_start,
-- consistent with the total column. No dependency on status_changed_at.
CREATE OR REPLACE VIEW public.totals AS
 WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT (cp.value_number)::integer AS value_number
                   FROM public.company_parameters cp
                  WHERE ((cp.parameter_id = 'orders_reset_day'::text) AND (cp.facility_id = f.facility_id))
                 LIMIT 1), ( SELECT (sp.amount)::integer AS amount
                   FROM public.standard_parameters sp
                  WHERE (sp.parameters_id = 'orders_reset_day'::text)
                 LIMIT 1), 6) AS orders_reset_day
           FROM public.facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            (((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE fp.timezone))::date))::integer - fp.orders_reset_day) + 7) % 7)) AS orders_week_start
           FROM facility_params fp
        ), product_facility AS (
         SELECT p.product_id,
            f.facility_id,
            f.company_id
           FROM (public.products p
             JOIN public.facilities f ON (((p.company_id = f.company_id) AND ((p.facility_id IS NULL) OR (p.facility_id = f.facility_id)))))
        )
 SELECT ((pf.product_id || '-'::text) || pf.facility_id) AS totals_id,
    pf.product_id,
    pf.facility_id,
    pf.company_id,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id) AND (o.order_status <> 'Canceled'::text))), (0)::numeric) AS total,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_status = 'Open'::text) AND (o.facility_id = pf.facility_id))), (0)::numeric) AS left_to_pack,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_date < c.orders_week_start) AND (o.order_status = 'Open'::text) AND (o.facility_id = pf.facility_id))), (0)::numeric) AS open_backlog,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_status = 'Packed'::text) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id))), (0)::numeric) AS packed_qty,
    COALESCE(( SELECT sum(od.quantity) AS sum
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
          WHERE ((od.product_id = pf.product_id) AND (o.order_status = 'Delivered'::text) AND (o.order_date >= c.orders_week_start) AND (o.facility_id = pf.facility_id))), (0)::numeric) AS delivered_qty,
    COALESCE(( SELECT avg(sub.weekly_sum) AS avg
           FROM ( SELECT sum(od2.quantity) AS weekly_sum
                   FROM (public.order_details od2
                     JOIN public.orders o2 ON ((od2.order_id = o2.order_id)))
                  WHERE ((od2.product_id = pf.product_id) AND (o2.order_date >= (c.orders_week_start - '42 days'::interval)) AND (o2.order_date < c.orders_week_start) AND (o2.facility_id = pf.facility_id) AND (o2.order_status <> 'Canceled'::text))
                  GROUP BY (date_trunc('week'::text, (o2.order_date)::timestamp with time zone))) sub), (0)::numeric) AS recent_avg_week
   FROM (product_facility pf
     JOIN calc c ON ((c.facility_id = pf.facility_id)));
