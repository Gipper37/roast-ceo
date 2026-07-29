-- Invoices never become overdue (plan Phase 1.6).
--
-- recompute_overdue_invoices(p_company_id) has existed since P4 with NO CALLER, and
-- vercel.json has three crons, none for A/R. So invoice_state can hold 'overdue' but
-- nothing ever writes it: an invoice sits at 'open' forever, however late it gets.
-- Dunning has no signal to fire on, and the collections view has nothing to collect.
--
-- (The invoice register works around this today by DERIVING overdue from
-- invoice_state IN ('open','partial','overdue') AND due_date < today. That stays —
-- it is correct regardless of whether this job has run, and it is what makes a
-- partially-paid-and-late invoice visible. See the note on 'partial' below.)
--
-- Three things are fixed here, not just the missing schedule:
--
-- 1. IT ONLY EVER FLIPPED ONE WAY. open → overdue, never back. Correct a due date
--    (a customer negotiates terms, or someone fat-fingered the date), and the
--    invoice stays marked overdue forever with nothing in the app able to clear it.
--
-- 2. IT USED UTC. `due_date < current_date` on a server running UTC marks a Hawaii
--    roaster's invoice overdue at 14:00 local ON THE DAY IT IS DUE. MCR is
--    Pacific/Honolulu — ten hours of every due date spent wrongly telling a customer
--    they are late. Now compared against the company's own local date.
--
-- 3. IT TOOK A COMPANY ID, so nothing could schedule it. A no-arg wrapper iterates
--    the companies actually using STRATA invoicing.
--
-- Deliberately NOT touching 'partial': recompute_invoice_ar_state resolves a
-- part-paid invoice to 'partial', which the state column cannot express
-- simultaneously with 'overdue'. Flipping those to 'overdue' here would fight that
-- function every time a payment landed. Lateness for part-paid invoices is derived
-- at read time, where both facts can coexist.

begin;

create or replace function public.recompute_overdue_invoices(p_company_id text)
returns integer
language plpgsql
as $$
DECLARE v_tz text; v_today date; v_n integer; v_back integer;
BEGIN
  -- The company's own date. A due date is a calendar promise, so it must be judged
  -- in the calendar the roaster lives in, not the server's.
  SELECT COALESCE(NULLIF(MIN(f.time_zone), ''), 'UTC') INTO v_tz
    FROM public.facilities f WHERE f.company_id = p_company_id;
  v_today := (CURRENT_TIMESTAMP AT TIME ZONE COALESCE(v_tz, 'UTC'))::date;

  UPDATE public.orders o SET invoice_state = 'overdue'
   WHERE o.company_id = p_company_id
     AND o.invoice_state = 'open'
     AND o.due_date IS NOT NULL
     AND o.due_date < v_today;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- The way back. Without this an edited or cleared due date leaves the invoice
  -- permanently, unfixably late.
  UPDATE public.orders o SET invoice_state = 'open'
   WHERE o.company_id = p_company_id
     AND o.invoice_state = 'overdue'
     AND (o.due_date IS NULL OR o.due_date >= v_today);
  GET DIAGNOSTICS v_back = ROW_COUNT;

  RETURN v_n + v_back;
END;
$$;

comment on function public.recompute_overdue_invoices(text) is
  'Flip open→overdue for invoices past their due date in the COMPANY''S timezone, and overdue→open when a due date is corrected. Idempotent.';

-- ── The schedulable wrapper ────────────────────────────────────────────────
create or replace function public.recompute_overdue_invoices_all()
returns integer
language plpgsql
as $$
DECLARE v_c RECORD; v_total integer := 0;
BEGIN
  -- Only companies whose book of record is STRATA. A QuickBooks-mode company's
  -- invoice lifecycle is not ours to move.
  FOR v_c IN
    SELECT company_id FROM public.billing_settings WHERE invoice_of_record = 'strata'
  LOOP
    v_total := v_total + COALESCE(public.recompute_overdue_invoices(v_c.company_id), 0);
  END LOOP;
  RETURN v_total;
END;
$$;

comment on function public.recompute_overdue_invoices_all() is
  'Nightly: recompute overdue state for every company on STRATA invoicing. The caller recompute_overdue_invoices never had.';

commit;

-- ── Schedule ───────────────────────────────────────────────────────────────
-- Outside the transaction: cron.schedule commits its own work.
-- 12:30 UTC = 02:30 Honolulu, 07:30 Chicago, 13:30 London — past midnight in the
-- westernmost tenant timezone, so every company's "today" has actually started
-- before its invoices are judged.
do $$
BEGIN
  -- pg_cron is installed on prod but NOT on staging (free tier). Referencing cron.*
  -- unconditionally fails the whole migration there with
  -- `schema "cron" does not exist`, which would leave staging without the FUNCTIONS
  -- either — so the schema check guards the schedule, and the functions above land
  -- everywhere regardless. The statements below are never parsed when the branch is
  -- not taken, which is what makes this safe on a database with no cron schema.
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE NOTICE 'pg_cron not installed — functions created, schedule skipped. Schedule manually where cron exists.';
    RETURN;
  END IF;

  -- Idempotent: drop any existing job of this name before scheduling, rather than
  -- relying on cron.schedule to upsert by name (version-dependent).
  PERFORM cron.unschedule('recompute_overdue_invoices')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'recompute_overdue_invoices');

  PERFORM cron.schedule(
    'recompute_overdue_invoices',
    '30 12 * * *',
    'SELECT public.recompute_overdue_invoices_all()'
  );
END $$;

notify pgrst, 'reload schema';
