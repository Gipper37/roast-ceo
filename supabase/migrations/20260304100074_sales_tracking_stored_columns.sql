-- Migration 00074: Replace sales_tracking_view with stored columns on sales_tracking
--
-- The view approach required two AppSheet data sources for one logical table,
-- broke live-update behaviour, and made dashboard-within-dashboard impossible.
-- Stored columns with triggers are real-time and keep everything in one table.
--
-- Triggers:
--   trg_period_change    — fires when period is updated, recomputes all metrics
--   trg_note_change      — fires on sales_notes INSERT/UPDATE/DELETE, recomputes actuals

-- ── A. Drop view ─────────────────────────────────────────────────
DROP VIEW IF EXISTS public.sales_tracking_view;

-- ── B. Add stored columns ────────────────────────────────────────
ALTER TABLE public.sales_tracking
    ADD COLUMN IF NOT EXISTS first_actions_actual    integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS first_actions_goal      numeric DEFAULT 0,
    ADD COLUMN IF NOT EXISTS personal_actions_actual integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS personal_actions_goal   numeric DEFAULT 0,
    ADD COLUMN IF NOT EXISTS deals_signed_actual     integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS deals_signed_goal       numeric DEFAULT 0,
    ADD COLUMN IF NOT EXISTS denials                 integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS follow_up_actual        integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS follow_up_goal          numeric DEFAULT 0,
    ADD COLUMN IF NOT EXISTS win_count               integer DEFAULT 0;

-- ── C. Core refresh function ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_sales_tracking_row(p_id text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    r           public.sales_tracking%ROWTYPE;
    v_start     date;
    v_end       date;
    v_goal_fa   numeric;
    v_goal_pa   numeric;
    v_goal_sa   numeric;
    v_goal_fu   numeric;
BEGIN
    SELECT * INTO r FROM public.sales_tracking WHERE sales_tracking_id = p_id;

    v_start := CASE r.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN date_trunc('week', CURRENT_DATE)::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '7 days')::date
        WHEN 'This Month' THEN date_trunc('month', CURRENT_DATE)::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 month')::date
        WHEN 'This Year'  THEN date_trunc('year', CURRENT_DATE)::date
    END;

    v_end := CASE r.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN (date_trunc('week', CURRENT_DATE) + interval '6 days')::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Month' THEN (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Year'  THEN (date_trunc('year', CURRENT_DATE) + interval '1 year' - interval '1 day')::date
    END;

    -- Goals: LIMIT 1 + ORDER BY matches AppSheet any() — deterministic when multiple rows exist
    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = r.sales_person AND company_id = r.company_id
    ORDER BY sales_goal_id LIMIT 1;

    UPDATE public.sales_tracking SET
        first_actions_actual    = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'First Action'
              AND sn.date BETWEEN v_start AND v_end),

        first_actions_goal      = ROUND(v_goal_fa * CASE r.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
            END),

        personal_actions_actual = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'Personal Action'
              AND sn.date BETWEEN v_start AND v_end),

        personal_actions_goal   = ROUND(v_goal_pa * CASE r.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
            END),

        deals_signed_actual     = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'Signed Account'
              AND sn.date BETWEEN v_start AND v_end),

        deals_signed_goal       = ROUND(v_goal_sa * CASE r.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
            END),

        denials                 = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'Denial'
              AND sn.date BETWEEN v_start AND v_end),

        follow_up_actual        = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'Follow Up Action'
              AND sn.date BETWEEN v_start AND v_end),

        follow_up_goal          = ROUND(v_goal_fu * CASE r.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
            END),

        win_count               = (
            SELECT COUNT(*) FROM public.sales_notes sn
            JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
            WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
              AND sa.activity_category = 'Signed Account')

    WHERE sales_tracking_id = p_id;
END;
$$;

-- ── D. Trigger: period change ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_fn_period_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM public.refresh_sales_tracking_row(NEW.sales_tracking_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_period_change ON public.sales_tracking;
CREATE TRIGGER trg_period_change
    AFTER UPDATE OF period ON public.sales_tracking
    FOR EACH ROW EXECUTE FUNCTION public.trg_fn_period_change();

-- ── E. Trigger: sales_notes changes ─────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_fn_note_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_sales_person text;
    v_company_id   text;
    v_id           text;
BEGIN
    v_sales_person := COALESCE(NEW.sales_person, OLD.sales_person);
    v_company_id   := COALESCE(NEW.company_id,   OLD.company_id);

    SELECT sales_tracking_id INTO v_id
    FROM public.sales_tracking
    WHERE sales_person = v_sales_person AND company_id = v_company_id
    LIMIT 1;

    IF v_id IS NOT NULL THEN
        PERFORM public.refresh_sales_tracking_row(v_id);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_note_change ON public.sales_notes;
CREATE TRIGGER trg_note_change
    AFTER INSERT OR UPDATE OR DELETE ON public.sales_notes
    FOR EACH ROW EXECUTE FUNCTION public.trg_fn_note_change();

-- ── F. Backfill all existing rows ────────────────────────────────
SELECT public.refresh_sales_tracking_row(sales_tracking_id)
FROM public.sales_tracking;
