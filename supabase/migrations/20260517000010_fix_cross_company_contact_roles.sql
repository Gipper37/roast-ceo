-- ============================================================
-- Fix: 62 contacts pointing at contact_role rows from the wrong company
-- ============================================================
-- Audit found contacts.role IDs that resolve to a contact_role row
-- belonging to a different company_id than the contact itself. Most
-- likely from a copy-paste during the UK provisioning where US role
-- IDs got applied to UK contacts and vice versa.
--
-- Pattern affected:
--   Social Hour US contacts  → UK role IDs   (51 rows)
--   Social Hour UK contacts  → US role IDs   (11 rows)
--
-- Fix strategy: for each broken contact, find the role in THEIR
-- company that has the same `contact_role` label and rewrite c.role
-- to that ID. Rows whose label doesn't exist in their company are
-- left untouched and reported via a NOTICE.
-- ============================================================

DO $$
DECLARE
  r RECORD;
  fix_id text;
  fixed_count int := 0;
  unmatched_count int := 0;
BEGIN
  FOR r IN
    SELECT c.contact_id, c.company_id AS contact_company,
           cr.company_id AS role_company,
           cr.contact_role AS role_label,
           c.role AS bad_role_id
    FROM public.contacts c
    JOIN public.contact_role cr ON cr.contact_role_id = c.role
    WHERE c.role IS NOT NULL AND c.company_id != cr.company_id
  LOOP
    -- Find equivalent role in the contact's actual company
    SELECT contact_role_id INTO fix_id
    FROM public.contact_role
    WHERE company_id = r.contact_company
      AND lower(contact_role) = lower(r.role_label)
    LIMIT 1;

    IF fix_id IS NOT NULL THEN
      UPDATE public.contacts SET role = fix_id WHERE contact_id = r.contact_id;
      fixed_count := fixed_count + 1;
    ELSE
      RAISE NOTICE 'No equivalent "%" role in company % for contact % — leaving as-is', r.role_label, r.contact_company, r.contact_id;
      unmatched_count := unmatched_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Fixed: %  Unmatched: %', fixed_count, unmatched_count;
END
$$ LANGUAGE plpgsql;
