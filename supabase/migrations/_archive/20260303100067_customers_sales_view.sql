-- Migration 00067: customers_sales view with needs_follow_up
--
-- needs_follow_up is a boolean computed from:
--   1. The customer's current sales status activity_category being
--      'Personal Action' or 'Follow Up Action'
--   2. last_contact being older than the assigned salesperson's
--      follow_up_reminder_weeks threshold (from sales_parameters)
--
-- Implemented as a VIEW (not a stored column) because it depends on
-- CURRENT_DATE which changes daily. A stored column would require a
-- daily pg_cron refresh to stay accurate — no cron job exists yet.
-- The view is always fresh with zero maintenance overhead.
--
-- AppSheet: point the Customers read slice at customers_sales.
-- All writes (INSERT/UPDATE on customers, sales_notes) still target
-- the base tables directly.

DROP VIEW IF EXISTS public.customers_sales;

CREATE VIEW public.customers_sales AS
SELECT
    c.*,
    (
        sa.activity_category IN ('Personal Action', 'Follow Up Action')
        AND c.last_contact IS NOT NULL
        AND c.sales_person IS NOT NULL
        AND c.last_contact < CURRENT_DATE - (
            (SELECT sp.follow_up_reminder_weeks
             FROM public.sales_parameters sp
             WHERE sp.sales_person = c.sales_person
               AND sp.company_id  = c.company_id
             LIMIT 1) * 7
        )::integer
    ) AS needs_follow_up
FROM public.customers c
LEFT JOIN public.sales_activity sa
       ON sa.sales_activity_id = c.sales_status;
