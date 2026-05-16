-- Migration 00070: Add primary contact fields to customers_sales view
--
-- Adds a JOIN to contacts on primary_contact_id so AppSheet (and the
-- proprietary frontend) can read the primary contact name/role directly
-- from the view without any AppSheet formula logic.
--
-- New columns:
--   primary_contact_name    — contacts.contact (person's name)
--   primary_contact_display — "Name (Role)" or just "Name" if no role set
--
-- NULL when no primary_contact_id is set on the customer.

DROP VIEW IF EXISTS public.customers_sales;

CREATE VIEW public.customers_sales AS
SELECT
    c.*,
    ct.contact                                                         AS primary_contact_name,
    CASE
        WHEN ct.contact IS NOT NULL
        THEN ct.contact || COALESCE(' (' || cr.contact_role || ')', '')
        ELSE NULL
    END                                                                AS primary_contact_display,
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
LEFT JOIN public.contacts ct
       ON ct.contact_id = c.primary_contact_id
LEFT JOIN public.contact_role cr
       ON cr.contact_role_id = ct.role
LEFT JOIN public.sales_activity sa
       ON sa.sales_activity_id = c.sales_status;
