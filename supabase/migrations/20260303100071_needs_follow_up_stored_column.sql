-- Migration 00071: Move needs_follow_up from view to stored column
--
-- Replaces the customers_sales view approach with a stored boolean on
-- customers, refreshed nightly by pg_cron. Simpler than a view and
-- keeps AppSheet pointed at the base customers table.
--
-- Cron schedule: daily at midnight UTC (same pattern as hourly job).
-- needs_follow_up is date-based so daily refresh is sufficient.
--
-- Also drops customers_sales view (migrations 00067 + 00070) and the
-- primary_contact_name / primary_contact_display columns it was adding
-- (those are better handled by AppSheet Ref or the proprietary frontend join).

-- ── A. Drop customers_sales view ────────────────────────────────
DROP VIEW IF EXISTS public.customers_sales;

-- ── B. Add stored column ─────────────────────────────────────────
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS needs_follow_up boolean DEFAULT FALSE;

-- ── C. Refresh function ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_needs_follow_up()
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.customers c
    SET needs_follow_up = (
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
    )
    FROM public.sales_activity sa
    WHERE sa.sales_activity_id = c.sales_status;

    -- Customers with no sales_status (NULL) are never overdue
    UPDATE public.customers
    SET needs_follow_up = FALSE
    WHERE sales_status IS NULL
      AND needs_follow_up = TRUE;
END;
$$;

-- ── D. Backfill existing rows ────────────────────────────────────
SELECT public.refresh_needs_follow_up();

-- ── E. Schedule nightly pg_cron refresh ─────────────────────────
-- Runs at midnight UTC daily — date-based flag only needs daily refresh.
SELECT cron.schedule(
    'daily-needs-follow-up',
    '0 0 * * *',
    'SELECT public.refresh_needs_follow_up();'
);
