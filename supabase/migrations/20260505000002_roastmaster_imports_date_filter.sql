-- ============================================================================
-- Persist the user-selected date filter on each Roastmaster import.
--
-- The import tool lets the user filter sessions by date range (from/to)
-- so they only pull in recent work. Today those filter values are
-- ephemeral — the import row records what landed but not what range was
-- requested. That makes the history view ambiguous: was the import a
-- 5-session pull because the user chose a tight window, or because the
-- file genuinely only had 5? And re-running the same range later means
-- re-typing the dates from memory.
--
-- This migration stores the filter on the import record itself. NULL on
-- either side means "no bound" (the user left it blank). When only
-- date_from is set, the history view renders the import's created_at
-- as the implied to-date (which matches the user's mental model — "I
-- imported everything since X").
-- ============================================================================

BEGIN;

ALTER TABLE roastmaster_imports
  ADD COLUMN IF NOT EXISTS date_from date,
  ADD COLUMN IF NOT EXISTS date_to   date;

COMMENT ON COLUMN roastmaster_imports.date_from IS
  'User-selected lower bound of the session-date filter applied at '
  'import time. NULL = no lower bound. Stored so the import history '
  'can show what range the user pulled.';

COMMENT ON COLUMN roastmaster_imports.date_to IS
  'User-selected upper bound of the session-date filter applied at '
  'import time. NULL = no upper bound; the history view substitutes '
  'created_at::date as the implied end when only date_from is set.';

COMMIT;
