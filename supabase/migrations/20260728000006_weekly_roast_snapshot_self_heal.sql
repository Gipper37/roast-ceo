-- Weekly roast snapshot: make it self-healing instead of write-once.
--
-- 🔴 THE BUG, as MCR hit it: the "LBS Ordered Roasted" weekly chart is a flat line
-- at zero with a single spike, while the MONTHLY chart on the same card shows a
-- healthy ~3,000 lbs/week all year. Both claim to plot the same quantity.
--
-- The monthly series reads a live view (order_graphs_weekly_avg_by_month) and is
-- right. The weekly series reads this snapshot TABLE, and the table is wrong,
-- because snapshot_completed_roast_weeks captured each week ONCE — on the morning
-- that week flipped — and never looked at it again:
--
--     IF v_today <> v_week_start THEN CONTINUE; END IF;   -- only on flip day
--     IF EXISTS (… week_start = v_prev_week_start) THEN CONTINUE; END IF;  -- never revisit
--
-- MCR's weeks were all snapshotted as ZERO, correctly, because at the time each one
-- flipped there were no orders in STRATA. Then the QuickBooks import landed 13
-- months of history with backdated order_dates — and not one of those weeks was ever
-- recomputed. The data is all there; the cache was sealed before it arrived.
--
-- This is not specific to an import. Any backdated order, any edit to a past order,
-- any correction to a roast log is invisible to the weekly chart forever under a
-- write-once cache. Verified on prod for MCR: every week Apr–Jul holds 2,200–3,600
-- real ordered lbs; the snapshot held 0 for all but one.
--
-- FIX: one week's computation becomes an idempotent UPSERT, and the nightly job
-- (a) fills every completed week a facility has data for, and (b) re-computes a
-- trailing window so late-arriving data lands. The maths is copied verbatim from
-- the old function — this changes WHEN and HOW OFTEN a week is computed, never HOW.

begin;

-- ── One week, idempotent ───────────────────────────────────────────────────
-- p_week_start is the ROAST week start. Orders are bucketed on their own reset day
-- (default Saturday) which is derived from it, exactly as the old function did —
-- the two calendars genuinely differ and must not be collapsed.
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

  v_capacity_hrs := COALESCE(
      (SELECT value_number FROM public.company_parameters
        WHERE parameter_id = 'roast_capacity_hrs' AND facility_id = p_facility_id LIMIT 1),
      (SELECT amount FROM public.standard_parameters
        WHERE parameters_id = 'roast_capacity_hrs' LIMIT 1),
      35);

  SELECT count(*) INTO v_roast_count FROM public.roast_log
   WHERE "charged?" = true AND facility_id = p_facility_id
     AND roast_date >= p_week_start AND roast_date < v_week_end;

  -- Mean gap between consecutive charges, capped at 25 min so an overnight break
  -- does not read as roasting time. Computed once and reused by both hours and
  -- capacity — the old function ran this identical subquery twice.
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

comment on function public.snapshot_roast_week(text, text, date) is
  'Compute and UPSERT one completed roast week for one facility. Idempotent — safe to re-run to pick up backdated or imported orders.';

-- ── The nightly job ────────────────────────────────────────────────────────
create or replace function public.snapshot_completed_roast_weeks()
returns void
language plpgsql
as $$
DECLARE
  v_fac         RECORD;
  v_tz          text;
  v_reset_day   integer;
  v_today       date;
  v_week_start  date;
  v_first       date;
  v_w           date;
  v_guard       integer;
BEGIN
  FOR v_fac IN SELECT facility_id, company_id FROM public.facilities LOOP

    v_tz := COALESCE((SELECT NULLIF(time_zone,'') FROM public.facilities
                       WHERE facility_id = v_fac.facility_id), 'UTC');
    v_today := (CURRENT_TIMESTAMP AT TIME ZONE v_tz)::date;

    v_reset_day := COALESCE(
        (SELECT value_number::integer FROM public.company_parameters
          WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = v_fac.facility_id LIMIT 1),
        (SELECT amount::integer FROM public.standard_parameters
          WHERE parameters_id = 'RF1iFWjOh7' LIMIT 1),
        4);

    -- Start of the CURRENT (incomplete) roast week. Everything before it is done.
    v_week_start := v_today - ((EXTRACT(dow FROM v_today)::integer - v_reset_day + 7) % 7);

    -- Earliest week this facility has anything to say about. Orders and roasts are
    -- both consulted because an importing roaster has order history long before it
    -- has roast history.
    SELECT LEAST(
             (SELECT MIN(order_date) FROM public.orders     WHERE facility_id = v_fac.facility_id),
             (SELECT MIN(roast_date::date) FROM public.roast_log WHERE facility_id = v_fac.facility_id)
           ) INTO v_first;
    IF v_first IS NULL THEN CONTINUE; END IF;

    -- Never rebuild more than ~3 years in one pass; the trailing refresh below keeps
    -- the recent end honest and this bound keeps a huge tenant from stalling the job.
    v_first := GREATEST(v_first, v_today - 1100);
    v_w := v_first - ((EXTRACT(dow FROM v_first)::integer - v_reset_day + 7) % 7);

    v_guard := 0;
    WHILE v_w < v_week_start AND v_guard < 200 LOOP
      -- Recompute a week when it is missing OR when it falls in the trailing window.
      -- The trailing window is what makes this self-healing: an order edited, added,
      -- or imported with a backdated date lands in a week that was already
      -- snapshotted, and a write-once cache would never notice.
      IF v_w >= v_week_start - 56
         OR NOT EXISTS (SELECT 1 FROM public.weekly_roast_snapshot
                         WHERE facility_id = v_fac.facility_id AND week_start = v_w)
      THEN
        PERFORM public.snapshot_roast_week(v_fac.facility_id, v_fac.company_id, v_w);
      END IF;
      v_w := v_w + 7;
      v_guard := v_guard + 1;
    END LOOP;

  END LOOP;
END;
$$;

comment on function public.snapshot_completed_roast_weeks() is
  'Nightly: fill every completed roast week a facility has data for, and recompute the trailing 8 weeks so backdated/imported orders are picked up. Idempotent.';

-- ── One-time repair of the sealed rows ─────────────────────────────────────
-- The nightly job's trailing window is 8 weeks, which is right for ongoing drift but
-- cannot reach a week that was sealed at zero months ago. MCR's Apr–Jul rows are
-- exactly that: present, and wrong. Recompute EVERY week once, unconditionally, so
-- existing snapshots stop contradicting the live data they were derived from.
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
  RAISE NOTICE 'weekly_roast_snapshot: recomputed % facility-weeks', v_n;
END $$;

commit;

notify pgrst, 'reload schema';
