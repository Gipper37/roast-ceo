-- ============================================================
-- Equipment Phase 7: reminders + maintenance programs
-- ============================================================
-- Three things this adds:
--
-- A) Reminders on equipment_schedule
--    Per-schedule toggles for whether to fire reminder emails when
--    a task comes due, how many days lead time, and whether to
--    notify the customer + the roaster. Plus a small log table so
--    we don't double-fire on cron retries.
--
-- B) Maintenance programs
--    A "program" is a bundle of templates an equipment can subscribe
--    to in one click — e.g. "Espresso Bar — Standard PM" pulls in
--    monthly shower screens, quarterly descale, semi-annual gaskets,
--    annual full PM, annual water filter. Globals seeded in the
--    next migration; tenants can also build their own.
--
-- C) Helper functions
--    - apply_program_to_equipment(equipment_id, program_id) seeds
--      equipment_schedule from a program's template list
--    - equipment_reminders_due() returns the set of (schedule,
--      equipment, customer, contacts) tuples the cron should email
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- A) Reminder columns on equipment_schedule
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.equipment_schedule
  ADD COLUMN IF NOT EXISTS send_reminder       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_lead_days  int     NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS customer_notify     boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS roaster_notify      boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.equipment_schedule.send_reminder IS
  'When true, the daily equipment-reminders cron fires emails as next_due_at approaches.';
COMMENT ON COLUMN public.equipment_schedule.reminder_lead_days IS
  'Days BEFORE next_due_at to start sending reminders. 7 = "warn one week ahead".';


-- Reminder log — one row per email actually sent. Lets the cron be
-- idempotent (don't re-send the same reminder twice in the same
-- lead-day window) and gives operators a record.
CREATE TABLE IF NOT EXISTS public.equipment_reminder_log (
  id           bigserial PRIMARY KEY,
  company_id   text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  schedule_id  text NOT NULL REFERENCES public.equipment_schedule(schedule_id) ON DELETE CASCADE,
  recipient_email text NOT NULL,
  recipient_role  text NOT NULL CHECK (recipient_role IN ('customer','roaster')),
  due_at_snapshot timestamptz,
  sent_at      timestamptz NOT NULL DEFAULT now(),
  resend_message_id text
);
CREATE INDEX equipment_reminder_log_schedule_idx ON public.equipment_reminder_log (schedule_id, sent_at DESC);

ALTER TABLE public.equipment_reminder_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_reminder_log
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- B) Maintenance programs
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.maintenance_program (
  program_id   text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name         text NOT NULL,
  description  text,
  -- Targeting: a program is for one equipment category (espresso /
  -- grinder / roaster / etc.) so the equipment-detail "subscribe"
  -- dropdown can filter to relevant programs only.
  category     text NOT NULL,
  company_id   text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text,
  updated_by   text
);
CREATE INDEX maintenance_program_category_idx ON public.maintenance_program (category);
CREATE INDEX maintenance_program_company_idx  ON public.maintenance_program (company_id);

ALTER TABLE public.maintenance_program ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.maintenance_program
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.maintenance_program
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- Templates that belong to a program (many-to-many).
CREATE TABLE IF NOT EXISTS public.maintenance_program_template (
  program_id    text NOT NULL REFERENCES public.maintenance_program(program_id) ON DELETE CASCADE,
  template_id   text NOT NULL REFERENCES public.maintenance_template(template_id) ON DELETE CASCADE,
  -- Optional override of the template's default interval — lets a
  -- "Premium PM" program tighten cadence without forking the
  -- underlying templates.
  frequency_type     text,
  frequency_interval numeric,
  PRIMARY KEY (program_id, template_id)
);

ALTER TABLE public.maintenance_program_template ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.maintenance_program_template
  FOR SELECT TO authenticated USING (
    program_id IN (SELECT program_id FROM public.maintenance_program WHERE company_id IS NULL)
  );
CREATE POLICY tenant_company_access ON public.maintenance_program_template
  FOR ALL TO authenticated USING (
    program_id IN (
      SELECT program_id FROM public.maintenance_program
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );


-- Subscription: which programs each equipment is on
CREATE TABLE IF NOT EXISTS public.equipment_program_subscription (
  subscription_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id      text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  equipment_id    text NOT NULL REFERENCES public.equipment(equipment_id) ON DELETE CASCADE,
  program_id      text NOT NULL REFERENCES public.maintenance_program(program_id) ON DELETE CASCADE,
  subscribed_at   timestamptz NOT NULL DEFAULT now(),
  subscribed_by   text,
  UNIQUE (equipment_id, program_id)
);
CREATE INDEX equipment_program_subscription_eq_idx ON public.equipment_program_subscription (equipment_id);

ALTER TABLE public.equipment_program_subscription ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_program_subscription
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- C) Helper functions
-- ────────────────────────────────────────────────────────────────

-- Apply a program to an equipment: insert equipment_schedule rows for
-- every template in the program. Existing schedule rows (whether from
-- a previous program subscription or from seed_equipment_schedule) are
-- left alone via ON CONFLICT — the user keeps their history.
CREATE OR REPLACE FUNCTION public.apply_program_to_equipment(
  p_equipment_id text,
  p_program_id   text
)
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

  -- Record the subscription (idempotent)
  INSERT INTO public.equipment_program_subscription
    (company_id, equipment_id, program_id, subscribed_at)
  VALUES (e.company_id, p_equipment_id, p_program_id, now())
  ON CONFLICT (equipment_id, program_id) DO NOTHING;

  -- Seed schedule rows for every template in the program
  WITH ins AS (
    INSERT INTO public.equipment_schedule
      (company_id, equipment_id, template_id, frequency_type, frequency_interval)
    SELECT
      e.company_id,
      p_equipment_id,
      mpt.template_id,
      COALESCE(mpt.frequency_type,     mt.frequency_type),
      COALESCE(mpt.frequency_interval, mt.frequency_interval)
    FROM public.maintenance_program_template mpt
    JOIN public.maintenance_template mt ON mt.template_id = mpt.template_id
    WHERE mpt.program_id = p_program_id
    ON CONFLICT (equipment_id, template_id) DO NOTHING
    RETURNING schedule_id
  )
  SELECT count(*) INTO inserted_count FROM ins;

  RETURN inserted_count;
END
$$;

REVOKE EXECUTE ON FUNCTION public.apply_program_to_equipment(text, text) FROM public;
GRANT  EXECUTE ON FUNCTION public.apply_program_to_equipment(text, text) TO authenticated;


-- Reminder selector: returns rows the cron should process THIS RUN.
-- Filter criteria:
--   * send_reminder = true
--   * not paused
--   * next_due_at within [now(), now() + lead_days]  (time-based)
--     OR usage already at or past threshold        (usage-based)
--   * no reminder logged for this schedule in the last 24h
--     (idempotency — cron retries are safe)
--
-- Returns one row per (schedule, recipient_email, recipient_role)
-- so the cron just iterates and sends.
CREATE OR REPLACE VIEW public.equipment_reminders_due AS
WITH eligible AS (
  SELECT
    s.schedule_id,
    s.company_id,
    s.equipment_id,
    s.reminder_lead_days,
    s.customer_notify,
    s.roaster_notify,
    s.next_due_at,
    eds.is_due,
    eds.is_overdue,
    eds.days_until_due,
    e.customer_id,
    e.facility_id,
    cu.name_company    AS customer_name,
    cu.email           AS customer_primary_email,
    mt.task_name,
    co.company_name    AS roaster_name
  FROM public.equipment_schedule s
  JOIN public.equipment_due_status eds
    ON eds.schedule_id = s.schedule_id
  JOIN public.equipment e
    ON e.equipment_id = s.equipment_id
  JOIN public.maintenance_template mt
    ON mt.template_id = s.template_id
  LEFT JOIN public.customers cu
    ON cu.customer_id = e.customer_id
  LEFT JOIN public.companies co
    ON co.company_id = s.company_id
  WHERE s.send_reminder = true
    AND s.paused = false
    AND e.status = 'active'
    AND (
      -- time-based: due now OR within lead_days
      (s.frequency_type IN ('daily','weekly','monthly','quarterly','semi_annual','annual','biennial')
        AND s.next_due_at IS NOT NULL
        AND s.next_due_at <= now() + (s.reminder_lead_days || ' days')::interval)
      OR
      -- usage-based: already past threshold (no lead time concept for these)
      (eds.is_due AND s.frequency_type IN ('lbs_processed','hours_used'))
    )
    -- Idempotency: don't re-send if we sent ANY reminder for this
    -- schedule in the last 24h
    AND NOT EXISTS (
      SELECT 1 FROM public.equipment_reminder_log rl
      WHERE rl.schedule_id = s.schedule_id
        AND rl.sent_at > now() - interval '24 hours'
    )
)
SELECT
  el.schedule_id,
  el.company_id,
  el.equipment_id,
  el.customer_id,
  el.customer_name,
  el.roaster_name,
  el.task_name,
  el.next_due_at,
  el.is_overdue,
  el.days_until_due,
  -- Fan out: one row per recipient
  recipient_email,
  recipient_role
FROM eligible el,
LATERAL (
  -- customer recipients: primary email + every active contact email
  SELECT email AS recipient_email, 'customer'::text AS recipient_role
  FROM (
    SELECT el.customer_primary_email AS email WHERE el.customer_notify AND el.customer_primary_email IS NOT NULL
    UNION
    SELECT c.email FROM public.contacts c
      WHERE el.customer_notify AND el.customer_id IS NOT NULL
        AND c.customer_id = el.customer_id AND c.is_active = true AND c.email IS NOT NULL
  ) cu_e
  WHERE email IS NOT NULL AND email <> ''

  UNION ALL

  -- roaster recipient: the company's primary contact (from companies row)
  -- For now we use the first company_admin team member's email.
  SELECT t.email AS recipient_email, 'roaster'::text AS recipient_role
  FROM public.team t
  WHERE el.roaster_notify
    AND t.company_id = el.company_id
    AND t.role = 'company_admin'
    AND t.is_active = true
    AND t.email IS NOT NULL
) recipients;

COMMENT ON VIEW public.equipment_reminders_due IS
  'One row per (schedule, recipient) ready for the daily equipment-reminders cron to email. Idempotent: excludes any schedule that already sent in the last 24h.';
