-- Migration 00077: Consolidate sales_tracking columns
--
-- Replaces 10 separate actual/goal columns with 6 display columns.
-- 4 text columns already formatted as "actual/goal" (e.g. "3/15") —
-- AppSheet reads them directly, no VCs needed.
-- 2 integer columns for plain counts (denials, win_count — no goal).
--
-- BEFORE trigger on period change sets NEW directly → AppSheet sees
-- updated values in the RETURNING response immediately.
-- AFTER trigger on sales_notes calls refresh function → picks up on next sync.

-- ── A. Drop old columns ───────────────────────────────────────────
ALTER TABLE public.sales_tracking
    DROP COLUMN IF EXISTS first_actions_actual,
    DROP COLUMN IF EXISTS first_actions_goal,
    DROP COLUMN IF EXISTS personal_actions_actual,
    DROP COLUMN IF EXISTS personal_actions_goal,
    DROP COLUMN IF EXISTS deals_signed_actual,
    DROP COLUMN IF EXISTS deals_signed_goal,
    DROP COLUMN IF EXISTS follow_up_actual,
    DROP COLUMN IF EXISTS follow_up_goal,
    DROP COLUMN IF EXISTS denials,
    DROP COLUMN IF EXISTS win_count;

-- ── B. Add new columns ────────────────────────────────────────────
ALTER TABLE public.sales_tracking
    ADD COLUMN IF NOT EXISTS first_actions_taken     text DEFAULT '0/0',
    ADD COLUMN IF NOT EXISTS personal_actions_taken  text DEFAULT '0/0',
    ADD COLUMN IF NOT EXISTS deals_signed            text DEFAULT '0/0',
    ADD COLUMN IF NOT EXISTS follow_up_actions_taken text DEFAULT '0/0',
    ADD COLUMN IF NOT EXISTS denials                 integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS win_count               integer DEFAULT 0;

-- ── C. Update refresh function ────────────────────────────────────
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
    v_act_fa    integer;
    v_act_pa    integer;
    v_act_sa    integer;
    v_act_fu    integer;
    v_denials   integer;
    v_wins      integer;
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

    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = r.sales_person AND company_id = r.company_id
    ORDER BY sales_goal_id LIMIT 1;

    SELECT COUNT(*) INTO v_act_fa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'First Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_pa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Personal Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_sa
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Signed Account'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_act_fu
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Follow Up Action'
      AND sn.date BETWEEN v_start AND v_end;

    SELECT COUNT(*) INTO v_denials
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Denial'
      AND sn.date BETWEEN v_start AND v_end;

    -- win_count: all-time signed accounts (no period filter)
    SELECT COUNT(*) INTO v_wins
    FROM public.sales_notes sn
    JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
    WHERE sn.sales_person = r.sales_person AND sn.company_id = r.company_id
      AND sa.activity_category = 'Signed Account';

    UPDATE public.sales_tracking SET
        first_actions_taken     = v_act_fa::text || '/' ||
                                  ROUND(v_goal_fa * CASE r.period
                                      WHEN 'Today'      THEN 1
                                      WHEN 'This Week'  THEN 5
                                      WHEN 'Last Week'  THEN 5
                                      WHEN 'This Month' THEN 5.0 * 52 / 12
                                      WHEN 'Last Month' THEN 5.0 * 52 / 12
                                      WHEN 'This Year'  THEN 5.0 * 52
                                  END)::text,
        personal_actions_taken  = v_act_pa::text || '/' ||
                                  ROUND(v_goal_pa * CASE r.period
                                      WHEN 'Today'      THEN 1.0 / 5
                                      WHEN 'This Week'  THEN 1
                                      WHEN 'Last Week'  THEN 1
                                      WHEN 'This Month' THEN 52.0 / 12
                                      WHEN 'Last Month' THEN 52.0 / 12
                                      WHEN 'This Year'  THEN 52
                                  END)::text,
        deals_signed            = v_act_sa::text || '/' ||
                                  ROUND(v_goal_sa * CASE r.period
                                      WHEN 'Today'      THEN 1.0 / 5
                                      WHEN 'This Week'  THEN 1
                                      WHEN 'Last Week'  THEN 1
                                      WHEN 'This Month' THEN 52.0 / 12
                                      WHEN 'Last Month' THEN 52.0 / 12
                                      WHEN 'This Year'  THEN 52
                                  END)::text,
        follow_up_actions_taken = v_act_fu::text || '/' ||
                                  ROUND(v_goal_fu * CASE r.period
                                      WHEN 'Today'      THEN 1
                                      WHEN 'This Week'  THEN 5
                                      WHEN 'Last Week'  THEN 5
                                      WHEN 'This Month' THEN 5.0 * 52 / 12
                                      WHEN 'Last Month' THEN 5.0 * 52 / 12
                                      WHEN 'This Year'  THEN 5.0 * 52
                                  END)::text,
        denials                 = v_denials,
        win_count               = v_wins
    WHERE sales_tracking_id = p_id;
END;
$$;

-- ── D. Update BEFORE trigger function (period change) ─────────────
CREATE OR REPLACE FUNCTION public.trg_fn_period_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_start   date;
    v_end     date;
    v_goal_fa numeric;
    v_goal_pa numeric;
    v_goal_sa numeric;
    v_goal_fu numeric;
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

    SELECT first_action_daily_goal, personal_action_weekly_goal,
           signed_accounts_weekly_goal, follow_up_action_daily_goal
    INTO v_goal_fa, v_goal_pa, v_goal_sa, v_goal_fu
    FROM public.sales_goals
    WHERE sales_person = NEW.sales_person AND company_id = NEW.company_id
    ORDER BY sales_goal_id LIMIT 1;

    NEW.first_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'First Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_fa * CASE NEW.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
        END)::text;

    NEW.personal_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Personal Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_pa * CASE NEW.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
        END)::text;

    NEW.deals_signed := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_sa * CASE NEW.period
            WHEN 'Today'      THEN 1.0 / 5
            WHEN 'This Week'  THEN 1
            WHEN 'Last Week'  THEN 1
            WHEN 'This Month' THEN 52.0 / 12
            WHEN 'Last Month' THEN 52.0 / 12
            WHEN 'This Year'  THEN 52
        END)::text;

    NEW.follow_up_actions_taken := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Follow Up Action'
          AND sn.date BETWEEN v_start AND v_end)::text
        || '/' ||
        ROUND(v_goal_fu * CASE NEW.period
            WHEN 'Today'      THEN 1
            WHEN 'This Week'  THEN 5
            WHEN 'Last Week'  THEN 5
            WHEN 'This Month' THEN 5.0 * 52 / 12
            WHEN 'Last Month' THEN 5.0 * 52 / 12
            WHEN 'This Year'  THEN 5.0 * 52
        END)::text;

    NEW.denials := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Denial'
          AND sn.date BETWEEN v_start AND v_end);

    NEW.win_count := (
        SELECT COUNT(*) FROM public.sales_notes sn
        JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
        WHERE sn.sales_person = NEW.sales_person AND sn.company_id = NEW.company_id
          AND sa.activity_category = 'Signed Account');

    RETURN NEW;
END;
$$;

-- ── E. Backfill all rows ──────────────────────────────────────────
SELECT public.refresh_sales_tracking_row(sales_tracking_id)
FROM public.sales_tracking;
