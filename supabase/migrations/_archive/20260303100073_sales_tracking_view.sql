-- Migration 00073: sales_tracking_view
--
-- Replaces 6 AppSheet VCs on the Sales Tracking table with DB-computed columns.
-- AppSheet points at this view instead of the base sales_tracking table.
--
-- Computes per (sales_person, period) row:
--   first_actions_actual / first_actions_goal
--   personal_actions_actual / personal_actions_goal
--   deals_signed_actual / deals_signed_goal
--   denials (no goal)
--   follow_up_actual / follow_up_goal
--   win_count (all-time, no period filter)
--
-- Date ranges are computed from CURRENT_DATE so always fresh — no cron needed.
-- Goals use LIMIT 1 matching AppSheet any() — salesperson 15e4644e has 2 goal
-- rows (facility-level); ORDER BY sales_goal_id makes the pick deterministic.
--
-- Goal scaling:
--   first_action_daily_goal:      Today×1 | Week×5 | Month×5×52/12 | Year×5×52
--   personal_action_weekly_goal:  Today÷5 | Week×1 | Month×52/12   | Year×52
--   signed_accounts_weekly_goal:  same as personal
--   follow_up_action_daily_goal:  same as first_action

CREATE VIEW public.sales_tracking_view AS
WITH date_ranges AS (
    SELECT
        st.sales_tracking_id,
        CASE st.period
            WHEN 'Today'      THEN CURRENT_DATE
            WHEN 'This Week'  THEN date_trunc('week', CURRENT_DATE)::date
            WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '7 days')::date
            WHEN 'This Month' THEN date_trunc('month', CURRENT_DATE)::date
            WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 month')::date
            WHEN 'This Year'  THEN date_trunc('year', CURRENT_DATE)::date
        END AS period_start,
        CASE st.period
            WHEN 'Today'      THEN CURRENT_DATE
            WHEN 'This Week'  THEN (date_trunc('week', CURRENT_DATE) + interval '6 days')::date
            WHEN 'Last Week'  THEN (date_trunc('week', CURRENT_DATE) - interval '1 day')::date
            WHEN 'This Month' THEN (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
            WHEN 'Last Month' THEN (date_trunc('month', CURRENT_DATE) - interval '1 day')::date
            WHEN 'This Year'  THEN (date_trunc('year', CURRENT_DATE) + interval '1 year' - interval '1 day')::date
        END AS period_end
    FROM public.sales_tracking st
)
SELECT
    st.*,
    dr.period_start,
    dr.period_end,

    -- ── First Actions ─────────────────────────────────────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'First Action'
       AND sn.date BETWEEN dr.period_start AND dr.period_end
    ) AS first_actions_actual,

    ROUND(
        (SELECT sg.first_action_daily_goal FROM public.sales_goals sg
         WHERE sg.sales_person = st.sales_person AND sg.company_id = st.company_id
         ORDER BY sg.sales_goal_id LIMIT 1) *
        CASE st.period
            WHEN 'Today'                THEN 1
            WHEN 'This Week'            THEN 5
            WHEN 'Last Week'            THEN 5
            WHEN 'This Month'           THEN 5.0 * 52 / 12
            WHEN 'Last Month'           THEN 5.0 * 52 / 12
            WHEN 'This Year'            THEN 5.0 * 52
        END
    ) AS first_actions_goal,

    -- ── Personal Actions ──────────────────────────────────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'Personal Action'
       AND sn.date BETWEEN dr.period_start AND dr.period_end
    ) AS personal_actions_actual,

    ROUND(
        (SELECT sg.personal_action_weekly_goal FROM public.sales_goals sg
         WHERE sg.sales_person = st.sales_person AND sg.company_id = st.company_id
         ORDER BY sg.sales_goal_id LIMIT 1) *
        CASE st.period
            WHEN 'Today'                THEN 1.0 / 5
            WHEN 'This Week'            THEN 1
            WHEN 'Last Week'            THEN 1
            WHEN 'This Month'           THEN 52.0 / 12
            WHEN 'Last Month'           THEN 52.0 / 12
            WHEN 'This Year'            THEN 52
        END
    ) AS personal_actions_goal,

    -- ── Deals Signed ──────────────────────────────────────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'Signed Account'
       AND sn.date BETWEEN dr.period_start AND dr.period_end
    ) AS deals_signed_actual,

    ROUND(
        (SELECT sg.signed_accounts_weekly_goal FROM public.sales_goals sg
         WHERE sg.sales_person = st.sales_person AND sg.company_id = st.company_id
         ORDER BY sg.sales_goal_id LIMIT 1) *
        CASE st.period
            WHEN 'Today'                THEN 1.0 / 5
            WHEN 'This Week'            THEN 1
            WHEN 'Last Week'            THEN 1
            WHEN 'This Month'           THEN 52.0 / 12
            WHEN 'Last Month'           THEN 52.0 / 12
            WHEN 'This Year'            THEN 52
        END
    ) AS deals_signed_goal,

    -- ── Denials (no goal) ─────────────────────────────────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'Denial'
       AND sn.date BETWEEN dr.period_start AND dr.period_end
    ) AS denials,

    -- ── Follow Up Actions ─────────────────────────────────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'Follow Up Action'
       AND sn.date BETWEEN dr.period_start AND dr.period_end
    ) AS follow_up_actual,

    ROUND(
        (SELECT sg.follow_up_action_daily_goal FROM public.sales_goals sg
         WHERE sg.sales_person = st.sales_person AND sg.company_id = st.company_id
         ORDER BY sg.sales_goal_id LIMIT 1) *
        CASE st.period
            WHEN 'Today'                THEN 1
            WHEN 'This Week'            THEN 5
            WHEN 'Last Week'            THEN 5
            WHEN 'This Month'           THEN 5.0 * 52 / 12
            WHEN 'Last Month'           THEN 5.0 * 52 / 12
            WHEN 'This Year'            THEN 5.0 * 52
        END
    ) AS follow_up_goal,

    -- ── Win Count (all-time signed, no period filter) ─────────────
    (SELECT COUNT(*) FROM public.sales_notes sn
     JOIN public.sales_activity sa ON sa.sales_activity_id = sn.sales_activity_type
     WHERE sn.sales_person = st.sales_person
       AND sn.company_id   = st.company_id
       AND sa.activity_category = 'Signed Account'
    ) AS win_count

FROM public.sales_tracking st
JOIN date_ranges dr ON dr.sales_tracking_id = st.sales_tracking_id;
