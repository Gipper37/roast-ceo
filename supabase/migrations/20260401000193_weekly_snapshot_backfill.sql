-- Backfill weekly_roast_snapshot for all completed roast weeks since earliest data.

DO $$
DECLARE
    v_fac              RECORD;
    v_tz               text;
    v_reset_day        integer;
    v_week_start       date;
    v_next_week        date;
    v_earliest         date;
    v_current_week     date;
    v_order_reset_day  integer;
    v_prev_order_start date;
    v_retention        numeric;
    v_capacity_hrs     numeric;
BEGIN
    FOR v_fac IN SELECT facility_id, company_id FROM public.facilities LOOP

        v_tz := COALESCE(
            (SELECT NULLIF(time_zone, '') FROM public.facilities WHERE facility_id = v_fac.facility_id),
            'UTC');

        v_reset_day := COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = v_fac.facility_id LIMIT 1),
            4);

        v_order_reset_day := COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'orders_reset_day' AND facility_id = v_fac.facility_id LIMIT 1),
            (SELECT amount::integer FROM public.standard_parameters
              WHERE parameters_id = 'orders_reset_day' LIMIT 1), 6);

        v_retention := COALESCE(
            (SELECT value_number FROM public.company_parameters
              WHERE parameter_id = '1de271df' AND facility_id = v_fac.facility_id LIMIT 1),
            0.82);

        v_capacity_hrs := COALESCE(
            NULLIF((SELECT SUM(COALESCE(ru.capacity_hrs_per_week,
                        COALESCE(
                            (SELECT value_number FROM public.company_parameters
                              WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = v_fac.facility_id LIMIT 1),
                            35)))
                     FROM public.roaster_units ru
                    WHERE ru.facility_id = v_fac.facility_id AND ru.is_active = true), 0),
            COALESCE(
                (SELECT value_number FROM public.company_parameters
                  WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = v_fac.facility_id LIMIT 1),
                35));

        -- Earliest roast date for this facility
        SELECT MIN(roast_date)::date INTO v_earliest
          FROM public.roast_log
         WHERE facility_id = v_fac.facility_id AND "charged?" = true;

        IF v_earliest IS NULL THEN CONTINUE; END IF;

        -- Find the roast week start on or before the earliest roast
        v_week_start := v_earliest
            - ((EXTRACT(dow FROM v_earliest)::integer - v_reset_day + 7) % 7);

        -- Current roast week start (don't snapshot the current incomplete week)
        v_current_week := (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date
            - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date)::integer
                - v_reset_day + 7) % 7);

        -- Loop through each past completed week
        WHILE v_week_start < v_current_week LOOP

            v_next_week := v_week_start + 7;

            -- Order week start aligned to the same period
            v_prev_order_start := v_week_start
                - ((EXTRACT(dow FROM v_week_start)::integer - v_order_reset_day + 7) % 7);

            INSERT INTO public.weekly_roast_snapshot (
                facility_id, company_id, week_start,
                total_roasted, total_roasted_green,
                total_ordered_roasted, total_ordered_green,
                order_count, products_sold,
                roast_count, roasting_hours, capacity_pct,
                batches_since_chaff
            )
            SELECT
                v_fac.facility_id,
                v_fac.company_id,
                v_week_start,
                COALESCE((SELECT sum(roasted_weight) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_week_start AND roast_date < v_next_week), 0),
                COALESCE((SELECT sum(charge_weight_lbs) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_week_start AND roast_date < v_next_week), 0),
                COALESCE((SELECT sum(od.roasted_weight)
                            FROM public.order_details od
                            JOIN public.orders o ON od.order_id = o.order_id
                           WHERE o.facility_id = v_fac.facility_id
                             AND o.order_date >= v_prev_order_start
                             AND o.order_date < v_prev_order_start + 7
                             AND o.order_status <> 'Canceled'), 0),
                COALESCE((SELECT sum(od.roasted_weight)
                            FROM public.order_details od
                            JOIN public.orders o ON od.order_id = o.order_id
                           WHERE o.facility_id = v_fac.facility_id
                             AND o.order_date >= v_prev_order_start
                             AND o.order_date < v_prev_order_start + 7
                             AND o.order_status <> 'Canceled'), 0)
                    / NULLIF(v_retention, 0),
                COALESCE((SELECT count(DISTINCT order_id) FROM public.orders
                           WHERE facility_id = v_fac.facility_id
                             AND order_date >= v_prev_order_start
                             AND order_date < v_prev_order_start + 7
                             AND order_status <> 'Canceled'), 0),
                COALESCE((SELECT sum(od.quantity)
                            FROM public.order_details od
                            JOIN public.orders o ON od.order_id = o.order_id
                           WHERE o.facility_id = v_fac.facility_id
                             AND o.order_date >= v_prev_order_start
                             AND o.order_date < v_prev_order_start + 7
                             AND o.order_status <> 'Canceled'), 0),
                COALESCE((SELECT count(*) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_week_start AND roast_date < v_next_week), 0),
                ROUND(
                    COALESCE((SELECT count(*) FROM public.roast_log
                               WHERE "charged?" = true AND facility_id = v_fac.facility_id
                                 AND roast_date >= v_week_start AND roast_date < v_next_week), 0)
                    * COALESCE((
                        SELECT AVG(gap_minutes) FROM (
                            SELECT EXTRACT(EPOCH FROM (
                                roast_date - LAG(roast_date) OVER (PARTITION BY roaster_unit_id ORDER BY roast_date)
                            )) / 60.0 AS gap_minutes
                              FROM public.roast_log
                             WHERE "charged?" = true AND facility_id = v_fac.facility_id
                               AND roast_date >= v_week_start AND roast_date < v_next_week
                        ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                    ), 0) / 60.0
                , 2),
                ROUND(
                    COALESCE((SELECT count(*) FROM public.roast_log
                               WHERE "charged?" = true AND facility_id = v_fac.facility_id
                                 AND roast_date >= v_week_start AND roast_date < v_next_week), 0)
                    * COALESCE((
                        SELECT AVG(gap_minutes) FROM (
                            SELECT EXTRACT(EPOCH FROM (
                                roast_date - LAG(roast_date) OVER (PARTITION BY roaster_unit_id ORDER BY roast_date)
                            )) / 60.0 AS gap_minutes
                              FROM public.roast_log
                             WHERE "charged?" = true AND facility_id = v_fac.facility_id
                               AND roast_date >= v_week_start AND roast_date < v_next_week
                        ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                    ), 0) / 60.0
                    / NULLIF(v_capacity_hrs, 0) * 100
                , 1),
                (SELECT MAX(batches_since_chaff) FROM public.roast_log
                  WHERE facility_id = v_fac.facility_id
                    AND roast_date >= v_week_start AND roast_date < v_next_week)
            ON CONFLICT (facility_id, week_start) DO NOTHING;

            v_week_start := v_next_week;
        END LOOP;
    END LOOP;
END;
$$;
