-- Migration 00068: Formalize contact-customer relationship
--
-- Adds proper customer_id + is_primary + primary_contact_id columns alongside
-- the legacy contacts.company and customers.contact columns (which are deferred
-- to the AppSheet FK pass for renaming/dropping to avoid breaking AppSheet).
--
-- Also: bidirectional sync triggers so primary can be set from either side,
-- auto-splits 10 multi-person contact records on commas,
-- and creates contacts_view with customer_flag.

-- ── A. Add new columns ──────────────────────────────────────────
ALTER TABLE public.contacts
    ADD COLUMN IF NOT EXISTS customer_id text,
    ADD COLUMN IF NOT EXISTS is_primary  boolean DEFAULT FALSE;

ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS primary_contact_id text;

-- ── B. Backfill ─────────────────────────────────────────────────

-- contacts.customer_id from contacts.company (139 records already set)
UPDATE public.contacts
SET customer_id = company
WHERE company IS NOT NULL AND company != ''
  AND customer_id IS NULL;

-- contacts without customer link → reverse lookup via customers.contact
UPDATE public.contacts ct
SET customer_id = cust.customer_id
FROM public.customers cust
WHERE cust.contact = ct.contact_id
  AND ct.customer_id IS NULL;

-- customers.primary_contact_id from customers.contact
UPDATE public.customers
SET primary_contact_id = contact
WHERE contact IS NOT NULL
  AND primary_contact_id IS NULL;

-- contacts.is_primary from customers.primary_contact_id
UPDATE public.contacts ct
SET is_primary = TRUE
FROM public.customers cust
WHERE cust.primary_contact_id = ct.contact_id;

-- ── C. FK constraints (NOT VALID — safe for production) ─────────
ALTER TABLE public.contacts
    ADD CONSTRAINT contacts_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id)
    NOT VALID;

ALTER TABLE public.customers
    ADD CONSTRAINT customers_primary_contact_id_fkey
    FOREIGN KEY (primary_contact_id) REFERENCES public.contacts(contact_id)
    NOT VALID;

-- ── D. Bidirectional sync triggers ─────────────────────────────

-- contacts → customers (set primary from contact record / toggle)
CREATE OR REPLACE FUNCTION public.sync_primary_from_contact()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- Guard against recursive trigger firing
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    IF NEW.is_primary = TRUE
       AND (OLD.is_primary IS DISTINCT FROM TRUE)
       AND NEW.customer_id IS NOT NULL
    THEN
        -- Update customer's primary_contact_id
        UPDATE public.customers
        SET primary_contact_id = NEW.contact_id
        WHERE customer_id = NEW.customer_id;

        -- Clear is_primary on all other contacts for same customer
        UPDATE public.contacts
        SET is_primary = FALSE
        WHERE customer_id = NEW.customer_id
          AND contact_id  != NEW.contact_id
          AND is_primary   = TRUE;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_primary_from_contact ON public.contacts;
CREATE TRIGGER trg_sync_primary_from_contact
    AFTER UPDATE OF is_primary ON public.contacts
    FOR EACH ROW EXECUTE FUNCTION public.sync_primary_from_contact();

-- customers → contacts (set primary from customer dropdown)
CREATE OR REPLACE FUNCTION public.sync_primary_from_customer()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    IF NEW.primary_contact_id IS DISTINCT FROM OLD.primary_contact_id THEN
        -- Set new primary contact
        IF NEW.primary_contact_id IS NOT NULL THEN
            UPDATE public.contacts
            SET is_primary = TRUE
            WHERE contact_id = NEW.primary_contact_id;
        END IF;

        -- Clear old primary contact
        IF OLD.primary_contact_id IS NOT NULL THEN
            UPDATE public.contacts
            SET is_primary = FALSE
            WHERE contact_id = OLD.primary_contact_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_primary_from_customer ON public.customers;
CREATE TRIGGER trg_sync_primary_from_customer
    AFTER UPDATE OF primary_contact_id ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.sync_primary_from_customer();

-- ── E. Auto-split multi-person contact records ──────────────────
-- 10 contacts have multiple people in one contacts.contact text field.
-- Split on comma: insert new rows for parts 2..N, trim originals to part 1.
-- Note: us6uhh ("Jeff (GM) Shawn (owner), ...") still has two people in
-- parts 1 and 2 after splitting — one remaining manual fix needed.

INSERT INTO public.contacts (
    contact_id, contact, company, customer_id, role,
    email, phone, notes, company_id, facility_id
)
SELECT
    left(replace(gen_random_uuid()::text, '-', ''), 8),
    trim(split_part(ct.contact, ',', n)),
    ct.company,
    ct.customer_id,
    NULL, NULL, NULL, NULL,
    ct.company_id,
    ct.facility_id
FROM public.contacts ct
CROSS JOIN generate_series(2, array_length(string_to_array(ct.contact, ','), 1)) AS n
WHERE ct.contact LIKE '%,%';

-- Trim originals to first person only
UPDATE public.contacts
SET contact = trim(split_part(contact, ',', 1))
WHERE contact LIKE '%,%';

-- ── F. contacts_view ────────────────────────────────────────────
-- is_primary is now a real stored column — no need to compute it in the view.
-- customer_flag replaces the AppSheet flag VC:
--   any(select(Customers[Flag],[_thisrow].[Contact ID]=[Contact]))

DROP VIEW IF EXISTS public.contacts_view;

CREATE VIEW public.contacts_view AS
SELECT
    ct.*,
    cust.flag AS customer_flag
FROM public.contacts ct
LEFT JOIN public.customers cust
       ON cust.customer_id = ct.customer_id;
