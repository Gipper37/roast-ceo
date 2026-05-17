-- Migration 00076: Fix period change trigger — AFTER → BEFORE
--
-- The AFTER trigger in 00074 does a separate UPDATE to set goals/actuals,
-- but AppSheet (via PostgREST RETURNING *) only sees the row from its own
-- UPDATE — the AFTER trigger's changes aren't in that response.
--
-- Fix: BEFORE trigger that sets NEW.column values directly, same pattern as
-- trg_update_status_on_deal_change on customers (migration 00066).
--
-- refresh_sales_tracking_row() is kept for trg_note_change (fires from
-- sales_notes — separate table, AFTER + separate UPDATE is fine there)
-- and manual backfills.

-- ── A. Drop old AFTER trigger ──────────────────────────────────────
DROP TRIGGER IF EXISTS trg_period_change ON public.sales_tracking;

-- ── B. New BEFORE trigger function ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_fn_period_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_start     date;
    v_end       date;
    v_goal_fa   numeric;
    v_goal_pa   numeric;
    v_goal_sa   numeric;
    v_goal_fu   numeric;
BEGIN
    v_start := CASE NEW.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN date_trunc('week', CURRENT_DATE)::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '7 days')::date
        WHEN 'This Month' THEN date_trunc('month', CURRENT_DATE)::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 month')::date
        WHEN 'This Year'  THEN date_trunc('year', CURRENT_DATE)::date
    END;

    v_end := CASE NEW.period
        WHEN 'Today'      THEN CURRENT_DATE
        WHEN 'This Week'  THEN (date_trunc('week', CURRENT_DATE) + interval '6 days')::date
        WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Month' THEN (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
        WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 day')::date
        WHEN 'This Year'  THEN (date_trunc('year', CURRENT_DATE) + interval '1 year' - interval '1 day')::date
    END;

    -- Goals: LIMIT 1 + ORDER BY matches AppSheet any()
    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = NEW.sales_person AND company_id = NEW.company_id
    ORDER BY sales_goal_id LIMIT 1;

    -- Set NEW directly — included in the RETURNING response to AppSheet
    NEW.first_actions_actual := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'First Action'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.first_actions_goal := ROUND(v_goal_fa * CASE NEW.period
        WHEN 'Today'      THEN 1
        WHEN 'This Week'  THEN 5
        WHEN 'Last Week'  THEN 5
        WHEN 'This Month' THEN 5.0 * 52 / 12
        WHEN 'Last Month' THEN 5.0 * 52 / 12
        WHEN 'This Year'  THEN 5.0 * 52
        END);

    NEW.personal_actions_actual := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Personal Action'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.personal_actions_goal := ROUND(v_goal_pa * CASE NEW.period
        WHEN 'Today'      THEN 1.0 / 5
        WHEN 'This Week'  THEN 1
        WHEN 'Last Week'  THEN 1
        WHEN 'This Month' THEN 52.0 / 12
        WHEN 'Last Month' THEN 52.0 / 12
        WHEN 'This Year'  THEN 52
        END);

    NEW.deals_signed_actual := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.deals_signed_goal := ROUND(v_goal_sa * CASE NEW.period
        WHEN 'Today'      THEN 1.0 / 5
        WHEN 'This Week'  THEN 1
        WHEN 'Last Week'  THEN 1
        WHEN 'This Month' THEN 52.0 / 12
        WHEN 'Last Month' THEN 52.0 / 12
        WHEN 'This Year'  THEN 52
        END);

    NEW.denials := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Denial'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.follow_up_actual := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Follow Up Action'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.follow_up_goal := ROUND(v_goal_fu * CASE NEW.period
        WHEN 'Today'      THEN 1
        WHEN 'This Week'  THEN 5
        WHEN 'Last Week'  THEN 5
        WHEN 'This Month' THEN 5.0 * 52 / 12
        WHEN 'Last Month' THEN 5.0 * 52 / 12
        WHEN 'This Year'  THEN 5.0 * 52
        END);

    NEW.win_count := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account');

    RETURN NEW;
END;
$$;

-- ── C. Create BEFORE trigger ───────────────────────────────────────
CREATE TRIGGER trg_period_change
    BEFORE UPDATE OF period ON public.sales_tracking
    FOR EACH ROW EXECUTE FUNCTION public.trg_fn_period_change();
