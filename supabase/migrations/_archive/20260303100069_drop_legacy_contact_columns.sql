-- Migration 00069: Drop legacy contact-customer link columns
--
-- contacts.company     → replaced by contacts.customer_id (migration 00068)
-- customers.contact    → replaced by customers.primary_contact_id (migration 00068)
--
-- Both new columns are backfilled, FK-constrained, and trigger-maintained.
-- The old columns served AppSheet only; AppSheet is being migrated to the new names.
--
-- Views that use SELECT * on these tables must be dropped and recreated
-- so PostgreSQL expands * against the updated column list.

-- ── A. Drop dependent views ──────────────────────────────────────
DROP VIEW IF EXISTS public.contacts_view;
DROP VIEW IF EXISTS public.customers_sales;

-- ── B. Drop legacy columns ───────────────────────────────────────
ALTER TABLE public.contacts
    DROP COLUMN IF EXISTS company;

ALTER TABLE public.customers
    DROP COLUMN IF EXISTS contact;

-- ── C. Recreate contacts_view ────────────────────────────────────
CREATE VIEW public.contacts_view AS
SELECT
    ct.*,
    cust.flag AS customer_flag
FROM public.contacts ct
LEFT JOIN public.customers cust
       ON cust.customer_id = ct.customer_id;

-- ── D. Recreate customers_sales ──────────────────────────────────
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
