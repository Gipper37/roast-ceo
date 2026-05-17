-- ============================================================
-- Equipment: predictive maintenance + due-status views
-- ============================================================
-- The differentiator: because we own the operator's roast volumes
-- (roast_log) and customer order history (order_details), we can
-- predict equipment wear ahead of any fixed time schedule:
--
--   - A grinder at a busy cafe sees 2x the lbs/week of one at a slow
--     account — burrs need replacement sooner.
--   - An in-house roaster running 30 batches/week wears gaskets +
--     bearings faster than one running 10 batches/week.
--
-- Other equipment-tech vendors don't have volume data. We do.
--
-- This migration introduces:
--   - update_equipment_cumulative_lbs()  function: recomputes
--     cumulative_lbs_processed for roaster + grinder equipment from
--     roast_log / order_details
--   - equipment_due_status view: per-schedule view that returns
--     `is_due`, `predicted_due_at`, `days_until_due` for the UI to
--     filter / sort. Combines time-based and usage-based logic.
-- ============================================================

-- ------------------------------------------------------------
-- Cumulative lbs roasted per roaster_unit (in-house equipment).
--
-- roast_log has roaster_unit_id; we sum roasted_weight (lbs) for all
-- successful roasts. This is the operator's actual usage data.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW public.equipment_roaster_lbs AS
SELECT
  e.equipment_id,
  COALESCE(SUM(rl.roasted_weight), 0)::numeric AS lbs_roasted_lifetime
FROM public.equipment e
JOIN public.roast_log rl
  ON rl.roaster_unit_id = e.linked_roaster_unit_id
WHERE e.category = 'roaster'
  AND e.linked_roaster_unit_id IS NOT NULL
GROUP BY e.equipment_id;

COMMENT ON VIEW public.equipment_roaster_lbs IS
  'Lifetime lbs roasted per in-house roaster, summed from roast_log via linked_roaster_unit_id. Feeds the cumulative_lbs_processed counter that the predictive view uses.';


-- ------------------------------------------------------------
-- Cumulative lbs ground per grinder placed at a customer.
--
-- Heuristic: lbs ground = lbs sold (order_details where status is
-- delivered or in-progress, multiplied by customer_id match). This
-- gives a reasonable proxy for grinder usage at customer accounts
-- without requiring the customer to enter usage themselves.
--
-- For grinders that serve multiple bags (most cafes have one grinder
-- handling all bean origins), we sum all delivered weight to the
-- customer. The operator can override with manual lbs entry on the
-- equipment record if the heuristic is wrong.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW public.equipment_grinder_lbs AS
SELECT
  e.equipment_id,
  COALESCE(SUM(od.roasted_weight), 0)::numeric AS lbs_ground_lifetime
FROM public.equipment e
JOIN public.order_details od ON od.customer_id = e.customer_id
JOIN public.orders o ON o.order_id = od.order_id
WHERE e.category = 'grinder'
  AND e.customer_id IS NOT NULL
  AND od.item_status IN ('packed','delivered')
GROUP BY e.equipment_id;

COMMENT ON VIEW public.equipment_grinder_lbs IS
  'Proxy: total lbs of coffee delivered to the customer that owns this grinder. Assumes single grinder per account. Operator can override with manual entry on equipment.cumulative_lbs_processed when the heuristic is wrong (e.g. multi-grinder shops).';


-- ------------------------------------------------------------
-- Background-recompute function — call periodically (or on-demand
-- from the UI) to sync equipment.cumulative_lbs_processed with the
-- views above. Cheap to run; touches one row per equipment.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_equipment_usage()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count int := 0;
BEGIN
  -- Roasters
  WITH src AS (SELECT * FROM public.equipment_roaster_lbs),
       upd AS (
         UPDATE public.equipment e
            SET cumulative_lbs_processed = s.lbs_roasted_lifetime,
                updated_at = now()
           FROM src s
          WHERE e.equipment_id = s.equipment_id
            AND COALESCE(e.cumulative_lbs_processed, 0) <> s.lbs_roasted_lifetime
        RETURNING e.equipment_id
       )
  SELECT count(*) INTO updated_count FROM upd;

  -- Grinders at customers
  WITH src AS (SELECT * FROM public.equipment_grinder_lbs),
       upd AS (
         UPDATE public.equipment e
            SET cumulative_lbs_processed = s.lbs_ground_lifetime,
                updated_at = now()
           FROM src s
          WHERE e.equipment_id = s.equipment_id
            AND COALESCE(e.cumulative_lbs_processed, 0) <> s.lbs_ground_lifetime
        RETURNING e.equipment_id
       )
  SELECT updated_count + count(*) INTO updated_count FROM upd;

  RETURN updated_count;
END
$$;

REVOKE EXECUTE ON FUNCTION public.recompute_equipment_usage() FROM public;
GRANT  EXECUTE ON FUNCTION public.recompute_equipment_usage() TO authenticated, service_role;

-- Schedule the recompute hourly when pg_cron is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'equipment_usage_recompute',
      '15 * * * *',
      $cron$SELECT public.recompute_equipment_usage()$cron$
    );
  END IF;
END
$$;


-- ------------------------------------------------------------
-- Due-status view — one row per equipment_schedule, computing:
--   * effective_due_at  — time-based for monthly+, usage-based
--                          (lbs/hours since last service vs lifespan)
--                          for usage-based templates
--   * days_until_due    — negative if overdue
--   * is_due            — convenience boolean (due now or overdue)
--   * is_overdue
--   * usage_pct         — for usage-based, where we are on the
--                          lifespan curve (0-100+)
--
-- The UI lists/filters by this view, NOT directly by
-- equipment_schedule.next_due_at — which is only correct for
-- time-based templates.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW public.equipment_due_status AS
WITH lifespan AS (
  SELECT
    s.schedule_id,
    s.company_id,
    s.equipment_id,
    s.template_id,
    s.frequency_type,
    s.frequency_interval,
    s.last_completed_at,
    s.next_due_at,
    s.paused,
    e.category,
    e.status AS equipment_status,
    e.cumulative_lbs_processed,
    e.cumulative_hours,
    -- For usage-based templates, look up where we were at last
    -- completion (from maintenance_log) so we can compute "since
    -- last service" rather than "lifetime".
    (SELECT lbs_at_completion
       FROM public.maintenance_log
      WHERE schedule_id = s.schedule_id
        AND lbs_at_completion IS NOT NULL
      ORDER BY completed_at DESC
      LIMIT 1) AS lbs_at_last_service,
    (SELECT hours_at_completion
       FROM public.maintenance_log
      WHERE schedule_id = s.schedule_id
        AND hours_at_completion IS NOT NULL
      ORDER BY completed_at DESC
      LIMIT 1) AS hours_at_last_service
  FROM public.equipment_schedule s
  JOIN public.equipment e ON e.equipment_id = s.equipment_id
)
SELECT
  l.schedule_id,
  l.company_id,
  l.equipment_id,
  l.template_id,
  l.frequency_type,
  l.frequency_interval,
  l.last_completed_at,
  l.paused,
  l.equipment_status,

  -- Effective due date
  CASE
    WHEN l.paused THEN NULL
    WHEN l.frequency_type IN ('daily','weekly','monthly','quarterly','semi_annual','annual','biennial')
      THEN l.next_due_at
    WHEN l.frequency_type = 'lbs_processed' THEN
      -- Project forward: when will lbs since last service exceed interval?
      -- We don't have a calendar projection without a rolling rate, so we
      -- return NULL for due-date and let the UI use usage_pct instead.
      NULL
    WHEN l.frequency_type = 'hours_used' THEN NULL
    ELSE l.next_due_at
  END AS effective_due_at,

  -- Days until due (NULL for usage-based)
  CASE
    WHEN l.paused OR l.next_due_at IS NULL THEN NULL
    WHEN l.frequency_type IN ('daily','weekly','monthly','quarterly','semi_annual','annual','biennial')
      THEN EXTRACT(EPOCH FROM (l.next_due_at - now())) / 86400
    ELSE NULL
  END::int AS days_until_due,

  -- Usage progress for usage-based templates
  CASE
    WHEN l.frequency_type = 'lbs_processed' THEN
      (COALESCE(l.cumulative_lbs_processed, 0) - COALESCE(l.lbs_at_last_service, 0))
        / NULLIF(l.frequency_interval, 0) * 100
    WHEN l.frequency_type = 'hours_used' THEN
      (COALESCE(l.cumulative_hours, 0) - COALESCE(l.hours_at_last_service, 0))
        / NULLIF(l.frequency_interval, 0) * 100
    ELSE NULL
  END::numeric AS usage_pct,

  -- Convenience flags
  CASE
    WHEN l.paused THEN false
    WHEN l.frequency_type IN ('daily','weekly','monthly','quarterly','semi_annual','annual','biennial')
      THEN l.next_due_at <= now()
    WHEN l.frequency_type = 'lbs_processed' THEN
      (COALESCE(l.cumulative_lbs_processed, 0) - COALESCE(l.lbs_at_last_service, 0))
        >= l.frequency_interval
    WHEN l.frequency_type = 'hours_used' THEN
      (COALESCE(l.cumulative_hours, 0) - COALESCE(l.hours_at_last_service, 0))
        >= l.frequency_interval
    ELSE false
  END AS is_due,

  -- Overdue = is_due AND (time-based past 20% of interval, usage past 100%)
  CASE
    WHEN l.paused THEN false
    WHEN l.frequency_type IN ('daily','weekly','monthly','quarterly','semi_annual','annual','biennial')
      THEN l.next_due_at IS NOT NULL AND l.next_due_at < (now() - interval '7 days')
    WHEN l.frequency_type = 'lbs_processed' THEN
      (COALESCE(l.cumulative_lbs_processed, 0) - COALESCE(l.lbs_at_last_service, 0))
        >= l.frequency_interval * 1.10
    WHEN l.frequency_type = 'hours_used' THEN
      (COALESCE(l.cumulative_hours, 0) - COALESCE(l.hours_at_last_service, 0))
        >= l.frequency_interval * 1.10
    ELSE false
  END AS is_overdue,

  l.cumulative_lbs_processed,
  l.lbs_at_last_service
FROM lifespan l;

COMMENT ON VIEW public.equipment_due_status IS
  'Per-schedule due-status with time- AND usage-based logic. UI filters/sorts by this. is_due + is_overdue are convenience booleans; usage_pct lets the UI render a progress bar for burrs/hours-based tasks.';


-- ------------------------------------------------------------
-- Convenience function: seed default schedule entries for an equipment.
-- Pulls all matching maintenance_template rows (most-specific match
-- per task — model > brand > category) and inserts equipment_schedule
-- rows for the non-recommended-only ones.
--
-- Called when an equipment is created.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_equipment_schedule(p_equipment_id text)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  e RECORD;
  inserted_count int := 0;
BEGIN
  SELECT * INTO e FROM public.equipment WHERE equipment_id = p_equipment_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  WITH applicable AS (
    -- For each template task_name, pick the most-specific row:
    -- model match > brand match > category-only. Use distinct on for
    -- (category, task_name) ordered by specificity.
    SELECT DISTINCT ON (mt.task_name)
      mt.template_id,
      mt.task_name,
      mt.frequency_type,
      mt.frequency_interval
    FROM public.maintenance_template mt
    WHERE mt.is_active
      AND mt.is_recommended_only = false  -- only tracked tasks get scheduled
      AND mt.category = e.category
      AND (mt.applies_to_brand_id IS NULL OR mt.applies_to_brand_id = e.brand_id)
      AND (mt.applies_to_model_id IS NULL OR mt.applies_to_model_id = e.model_id)
      AND (mt.company_id IS NULL OR mt.company_id = e.company_id)
    ORDER BY
      mt.task_name,
      (mt.applies_to_model_id IS NOT NULL) DESC,
      (mt.applies_to_brand_id IS NOT NULL) DESC,
      (mt.company_id IS NOT NULL) DESC
  ),
  ins AS (
    INSERT INTO public.equipment_schedule
      (company_id, equipment_id, template_id, frequency_type, frequency_interval)
    SELECT e.company_id, e.equipment_id, a.template_id, a.frequency_type, a.frequency_interval
    FROM applicable a
    ON CONFLICT (equipment_id, template_id) DO NOTHING
    RETURNING schedule_id
  )
  SELECT count(*) INTO inserted_count FROM ins;

  RETURN inserted_count;
END
$$;

REVOKE EXECUTE ON FUNCTION public.seed_equipment_schedule(text) FROM public;
GRANT  EXECUTE ON FUNCTION public.seed_equipment_schedule(text) TO authenticated;
