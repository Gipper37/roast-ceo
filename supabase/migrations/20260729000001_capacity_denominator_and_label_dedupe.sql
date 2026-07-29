-- Two fixes.
--
-- ══ 1. Capacity % is computed against a DIFFERENT denominator for the current week
--       than for every week before it. ═══════════════════════════════════════════
--
-- weekly_roast_current (the live current week) derives capacity hours PER ACTIVE
-- ROASTER — each unit contributes capacity_hrs_per_week, or the 35-hour fallback if
-- it has none — and SUMS them. snapshot_roast_week uses a single facility-level 35.
--
--     facility                             active roasters   live    snapshot
--     cc844abb-db0b-48db-9aeb-abd8df9117de       3            105       35
--     demo-kailua-roastery                       2             70       35
--     5cc581b9 (MCR)                             1             35       35
--
-- So on a 3-roaster facility the newest point on the Roaster Capacity % chart is
-- divided by 105 while the whole history behind it is divided by 35 — a 3x step
-- change with no cause in the data. Reported as "23 roast hours showing 21.9%":
-- 23/105 = 21.9%, where 23/35 = 65.7%. The number is not merely wrong, it is
-- incomparable to the line it sits on.
--
-- The LIVE view is right: three machines really can run 105 hours a week, and
-- capacity that ignores the fleet is not capacity. So the snapshot adopts the live
-- view's expression verbatim. MCR is unaffected (one roaster → 35 either way);
-- multi-roaster facilities' historical percentages drop to the correct value.
--
-- The 25-minute gap cap is deliberately KEPT — nobody is intentionally roasting
-- longer than that, so a longer gap is a break, not a batch.

begin;

create or replace function public.snapshot_roast_week(
  p_facility_id text,
  p_company_id  text,
  p_week_start  date
) returns void
language plpgsql
as $$
DECLARE
  v_week_end         date := p_week_start + 7;
  v_order_start      date;
  v_capacity_hrs     numeric;
  v_retention        numeric;
  v_roast_count      bigint;
  v_avg_gap_hours    numeric;
  v_param_hrs        numeric;
BEGIN
  v_order_start := p_week_start
      - ((EXTRACT(dow FROM p_week_start)::integer
          - COALESCE(
              (SELECT value_number::integer FROM public.company_parameters
                WHERE parameter_id = 'orders_reset_day' AND facility_id = p_facility_id LIMIT 1),
              (SELECT amount::integer FROM public.standard_parameters
                WHERE parameters_id = 'orders_reset_day' LIMIT 1),
              6)
          + 7) % 7);

  v_retention := COALESCE(
      (SELECT value_number FROM public.company_parameters
        WHERE parameter_id = '1de271df' AND facility_id = p_facility_id LIMIT 1),
      0.82);

  -- Per-facility configured hours, used as the PER-UNIT fallback below and as the
  -- whole-facility answer when there are no active roasters on record.
  v_param_hrs := COALESCE(
      (SELECT value_number FROM public.company_parameters
        WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = p_facility_id LIMIT 1),
      (SELECT amount FROM public.standard_parameters
        WHERE parameters_id = 'roast_capacity_hrs' LIMIT 1),
      35);

  -- MATCHES weekly_roast_current exactly: sum each active roaster's own weekly
  -- capacity, falling back per unit, and only drop to the facility figure when the
  -- fleet total is absent or zero. Divergence here is what made the current week's
  -- percentage incomparable to the history behind it.
  v_capacity_hrs := COALESCE(
      NULLIF((SELECT sum(COALESCE(ru.capacity_hrs_per_week, v_param_hrs))
                FROM public.roaster_units ru
               WHERE ru.facility_id = p_facility_id AND ru.is_active = true), 0),
      v_param_hrs);

  SELECT count(*) INTO v_roast_count FROM public.roast_log
   WHERE "charged?" = true AND facility_id = p_facility_id
     AND roast_date >= p_week_start AND roast_date < v_week_end;

  -- Mean gap between consecutive charges, capped at 25 min so a break does not read
  -- as roasting time. Computed once and reused by both hours and capacity.
  SELECT COALESCE(AVG(gap_minutes), 0) / 60.0 INTO v_avg_gap_hours
    FROM (
      SELECT EXTRACT(EPOCH FROM (roast_date - LAG(roast_date) OVER (ORDER BY roast_date))) / 60.0 AS gap_minutes
        FROM public.roast_log
       WHERE "charged?" = true AND facility_id = p_facility_id
         AND roast_date >= p_week_start AND roast_date < v_week_end
    ) g
   WHERE gap_minutes > 0 AND gap_minutes <= 25;

  INSERT INTO public.weekly_roast_snapshot (
      facility_id, company_id, week_start,
      total_roasted, total_roasted_green,
      total_ordered_roasted, total_ordered_green,
      order_count, products_sold,
      roast_count, roasting_hours, capacity_pct,
      batches_since_chaff
  )
  SELECT
      p_facility_id, p_company_id, p_week_start,
      COALESCE((SELECT sum(roasted_weight) FROM public.roast_log
                 WHERE "charged?" = true AND facility_id = p_facility_id
                   AND roast_date >= p_week_start AND roast_date < v_week_end), 0),
      COALESCE((SELECT sum(charge_weight_lbs) FROM public.roast_log
                 WHERE "charged?" = true AND facility_id = p_facility_id
                   AND roast_date >= p_week_start AND roast_date < v_week_end), 0),
      COALESCE((SELECT sum(od.roasted_weight)
                  FROM public.order_details od
                  JOIN public.orders o ON od.order_id = o.order_id
                 WHERE o.facility_id = p_facility_id
                   AND o.order_date >= v_order_start AND o.order_date < v_order_start + 7
                   AND o.order_status <> 'Canceled'), 0),
      COALESCE((SELECT sum(od.roasted_weight)
                  FROM public.order_details od
                  JOIN public.orders o ON od.order_id = o.order_id
                 WHERE o.facility_id = p_facility_id
                   AND o.order_date >= v_order_start AND o.order_date < v_order_start + 7
                   AND o.order_status <> 'Canceled'), 0) / NULLIF(v_retention, 0),
      COALESCE((SELECT count(DISTINCT order_id) FROM public.orders
                 WHERE facility_id = p_facility_id
                   AND order_date >= v_order_start AND order_date < v_order_start + 7
                   AND order_status <> 'Canceled'), 0),
      COALESCE((SELECT sum(od.quantity)
                  FROM public.order_details od
                  JOIN public.orders o ON od.order_id = o.order_id
                 WHERE o.facility_id = p_facility_id
                   AND o.order_date >= v_order_start AND o.order_date < v_order_start + 7
                   AND o.order_status <> 'Canceled'), 0),
      v_roast_count,
      ROUND(v_roast_count * v_avg_gap_hours, 2),
      ROUND(v_roast_count * v_avg_gap_hours / NULLIF(v_capacity_hrs, 0) * 100, 1),
      (SELECT MAX(batches_since_chaff) FROM public.roast_log WHERE facility_id = p_facility_id)
  ON CONFLICT (facility_id, week_start) DO UPDATE SET
      total_roasted         = EXCLUDED.total_roasted,
      total_roasted_green   = EXCLUDED.total_roasted_green,
      total_ordered_roasted = EXCLUDED.total_ordered_roasted,
      total_ordered_green   = EXCLUDED.total_ordered_green,
      order_count           = EXCLUDED.order_count,
      products_sold         = EXCLUDED.products_sold,
      roast_count           = EXCLUDED.roast_count,
      roasting_hours        = EXCLUDED.roasting_hours,
      capacity_pct          = EXCLUDED.capacity_pct,
      batches_since_chaff   = EXCLUDED.batches_since_chaff;
END;
$$;

-- Recompute so history stops disagreeing with the current week.
do $$
DECLARE
  v_fac RECORD; v_tz text; v_reset_day integer; v_today date;
  v_week_start date; v_first date; v_w date; v_guard integer; v_n integer := 0;
BEGIN
  FOR v_fac IN SELECT facility_id, company_id FROM public.facilities LOOP
    v_tz := COALESCE((SELECT NULLIF(time_zone,'') FROM public.facilities
                       WHERE facility_id = v_fac.facility_id), 'UTC');
    v_today := (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date;
    v_reset_day := COALESCE(
        (SELECT value_number::integer FROM public.company_parameters
          WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = v_fac.facility_id LIMIT 1),
        (SELECT amount::integer FROM public.standard_parameters
          WHERE parameters_id = 'RF1iFWjOh7' LIMIT 1), 4);
    v_week_start := v_today - ((EXTRACT(dow FROM v_today)::integer - v_reset_day + 7) % 7);

    SELECT LEAST(
             (SELECT MIN(order_date) FROM public.orders WHERE facility_id = v_fac.facility_id),
             (SELECT MIN(roast_date::date) FROM public.roast_log WHERE facility_id = v_fac.facility_id)
           ) INTO v_first;
    CONTINUE WHEN v_first IS NULL;

    v_first := GREATEST(v_first, v_today - 1100);
    v_w := v_first - ((EXTRACT(dow FROM v_first)::integer - v_reset_day + 7) % 7);
    v_guard := 0;
    WHILE v_w < v_week_start AND v_guard < 200 LOOP
      PERFORM public.snapshot_roast_week(v_fac.facility_id, v_fac.company_id, v_w);
      v_w := v_w + 7; v_guard := v_guard + 1; v_n := v_n + 1;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'capacity recompute: % facility-weeks', v_n;
END $$;

-- ══ 2. "(deprecated) (deprecated)" — a doubled suffix sitting in prod. ═══════════
--
-- 20260728000004 line 112 did `set label = label || ' (deprecated)'` with no
-- idempotency guard, and it ran twice on prod: once from a dry run of mine that
-- committed (an inner COMMIT defeats an outer ROLLBACK), then again through CI. The
-- doubled text is user-visible in the dev permission grid.
--
-- Editing the original migration would only protect future environments, so the
-- repair is forward-only. The `not like` guard makes it re-runnable.
update public.permissions
   set label = replace(label, ' (deprecated) (deprecated)', ' (deprecated)')
 where permission_id in ('payments.charge', 'payments.onboard', 'payments.refund')
   and label like '%(deprecated) (deprecated)%';

commit;

notify pgrst, 'reload schema';
