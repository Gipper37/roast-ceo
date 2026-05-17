-- ── 1. roaster_units ─────────────────────────────────────────────────────────

CREATE TABLE public.roaster_units (
    roaster_unit_id       uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    facility_id           text        NOT NULL REFERENCES public.facilities(facility_id),
    company_id            text        NOT NULL,
    name                  text        NOT NULL,
    max_charge_weight_lbs numeric,        -- machine batch capacity
    capacity_hrs_per_week numeric,        -- override facility default (NULL = use facility param)
    is_active             boolean     DEFAULT true,
    notes                 text,
    created_at            timestamptz DEFAULT now(),
    updated_at            timestamptz DEFAULT now(),
    created_by            text,
    updated_by            text
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roaster_units
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roaster_units
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- ── 2. roaster_unit_id on roast_log ──────────────────────────────────────────
-- Nullable — existing rows stay intact; filled in via AppSheet action.

ALTER TABLE public.roast_log
    ADD COLUMN IF NOT EXISTS roaster_unit_id uuid
        REFERENCES public.roaster_units(roaster_unit_id);

CREATE INDEX idx_roast_log_roaster_unit ON public.roast_log(roaster_unit_id);

-- ── 3. weekly_roast_snapshot ──────────────────────────────────────────────────

CREATE TABLE public.weekly_roast_snapshot (
    snapshot_id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    facility_id           text        NOT NULL,
    company_id            text,
    week_start            date        NOT NULL,   -- roast_week_start that was completed
    total_roasted         numeric,
    total_roasted_green   numeric,
    total_ordered_roasted numeric,
    total_ordered_green   numeric,
    order_count           integer,
    products_sold         numeric,
    roast_count           integer,
    roasting_hours        numeric,
    capacity_pct          numeric,
    batches_since_chaff   integer,
    snapshotted_at        timestamptz DEFAULT now(),
    created_at            timestamptz DEFAULT now(),
    UNIQUE (facility_id, week_start)
);

-- ── 4. Snapshot function ──────────────────────────────────────────────────────
-- Checks each facility to see if a new roast week just started.
-- If so, and no snapshot exists yet for the completed week, inserts one.

CREATE OR REPLACE FUNCTION public.snapshot_completed_roast_weeks()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_fac              RECORD;
    v_tz               text;
    v_reset_day        integer;
    v_today            date;
    v_week_start       date;
    v_prev_week_start  date;
    v_prev_order_start date;
    v_capacity_hrs     numeric;
    v_retention        numeric;
BEGIN
    FOR v_fac IN SELECT facility_id, company_id FROM public.facilities LOOP

        v_tz := COALESCE(
            (SELECT NULLIF(time_zone, '') FROM public.facilities WHERE facility_id = v_fac.facility_id),
            'UTC');

        v_today := (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date;

        -- Roast week reset day (default Thursday = 4)
        v_reset_day := COALESCE(
            (SELECT value_number::integer FROM public.company_parameters
              WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = v_fac.facility_id
              LIMIT 1),
            (SELECT amount::integer FROM public.standard_parameters
              WHERE parameters_id = 'RF1iFWjOh7' LIMIT 1),
            4);

        -- Current roast week start
        v_week_start := v_today
            - ((EXTRACT(dow FROM v_today)::integer - v_reset_day + 7) % 7);

        -- Only proceed if today IS the first day of a new week (week just flipped)
        IF v_today <> v_week_start THEN CONTINUE; END IF;

        v_prev_week_start := v_week_start - 7;

        -- Skip if already snapshotted
        IF EXISTS (
            SELECT 1 FROM public.weekly_roast_snapshot
             WHERE facility_id = v_fac.facility_id AND week_start = v_prev_week_start
        ) THEN CONTINUE; END IF;

        -- Order week reset day (default Saturday = 6)
        v_prev_order_start := v_prev_week_start
            - ((EXTRACT(dow FROM v_prev_week_start)::integer
                - COALESCE(
                    (SELECT value_number::integer FROM public.company_parameters
                      WHERE parameter_id = 'orders_reset_day' AND facility_id = v_fac.facility_id LIMIT 1),
                    (SELECT amount::integer FROM public.standard_parameters
                      WHERE parameters_id = 'orders_reset_day' LIMIT 1),
                    6)
                + 7) % 7);

        v_retention := COALESCE(
            (SELECT value_number FROM public.company_parameters
              WHERE parameter_id = '1de271df' AND facility_id = v_fac.facility_id LIMIT 1),
            0.82);

        v_capacity_hrs := COALESCE(
            (SELECT value_number FROM public.company_parameters
              WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = v_fac.facility_id LIMIT 1),
            (SELECT amount FROM public.standard_parameters
              WHERE parameters_id = 'roast_capacity_hrs' LIMIT 1),
            35);

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
            v_prev_week_start,
            -- roasted lbs
            COALESCE((SELECT sum(roasted_weight) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- green lbs
            COALESCE((SELECT sum(charge_weight_lbs) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- ordered roasted
            COALESCE((SELECT sum(od.roasted_weight)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0),
            -- ordered green
            COALESCE((SELECT sum(od.roasted_weight)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0)
                / NULLIF(v_retention, 0),
            -- order count
            COALESCE((SELECT count(DISTINCT order_id) FROM public.orders
                       WHERE facility_id = v_fac.facility_id
                         AND order_date >= v_prev_order_start AND order_date < v_prev_order_start + 7
                         AND order_status <> 'Canceled'), 0),
            -- products sold
            COALESCE((SELECT sum(od.quantity)
                        FROM public.order_details od
                        JOIN public.orders o ON od.order_id = o.order_id
                       WHERE o.facility_id = v_fac.facility_id
                         AND o.order_date >= v_prev_order_start AND o.order_date < v_prev_order_start + 7
                         AND o.order_status <> 'Canceled'), 0),
            -- roast count
            COALESCE((SELECT count(*) FROM public.roast_log
                       WHERE "charged?" = true AND facility_id = v_fac.facility_id
                         AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0),
            -- roasting hours
            ROUND(
                COALESCE((SELECT count(*) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0)
                * COALESCE((
                    SELECT AVG(gap_minutes) FROM (
                        SELECT EXTRACT(EPOCH FROM (
                            roast_date - LAG(roast_date) OVER (ORDER BY roast_date)
                        )) / 60.0 AS gap_minutes
                          FROM public.roast_log
                         WHERE "charged?" = true AND facility_id = v_fac.facility_id
                           AND roast_date >= v_prev_week_start AND roast_date < v_week_start
                    ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                ), 0) / 60.0
            , 2),
            -- capacity pct
            ROUND(
                COALESCE((SELECT count(*) FROM public.roast_log
                           WHERE "charged?" = true AND facility_id = v_fac.facility_id
                             AND roast_date >= v_prev_week_start AND roast_date < v_week_start), 0)
                * COALESCE((
                    SELECT AVG(gap_minutes) FROM (
                        SELECT EXTRACT(EPOCH FROM (
                            roast_date - LAG(roast_date) OVER (ORDER BY roast_date)
                        )) / 60.0 AS gap_minutes
                          FROM public.roast_log
                         WHERE "charged?" = true AND facility_id = v_fac.facility_id
                           AND roast_date >= v_prev_week_start AND roast_date < v_week_start
                    ) g WHERE gap_minutes > 0 AND gap_minutes <= 25
                ), 0) / 60.0
                / NULLIF(v_capacity_hrs, 0) * 100
            , 1),
            -- batches_since_chaff at week end
            (SELECT MAX(batches_since_chaff) FROM public.roast_log
              WHERE facility_id = v_fac.facility_id);

    END LOOP;
END;
$$;

-- ── 5. pg_cron: run daily, snapshots fire only on week-reset days ─────────────

SELECT cron.schedule(
    'snapshot_weekly_roast_data',
    '0 10 * * *',   -- 10:00 UTC daily (midnight Hawaii = 10:00 UTC)
    'SELECT public.snapshot_completed_roast_weeks()'
);
