-- Backfill date_from / date_to on historic data_imports rows.
--
-- Migration 20260505000002 added the date_from/date_to columns when we
-- started capturing the user's date filter at import time. Imports
-- that ran BEFORE that migration have NULL in both columns, so the
-- /configuration/Integrations history view shows no date-window badge
-- for them. Backfilling lets the badge render an inferred window
-- (the actual span of imported sessions) for those historic rows.
--
-- Method: for each data_imports row that
--   • has NULL date_from
--   • AND has a non-empty session_ids array
-- compute MIN/MAX of started_at across the linked roast_sessions and
-- write those back as date_from/date_to. This is the actual date range
-- of imported data, not the original user filter (which is lost), but
-- is the closest reconstruction available and meaningful for display.
--
-- Imports with no sessions imported (failed / aborted runs, sessions=0)
-- are left as NULL — there's nothing to derive a range from.

BEGIN;

UPDATE data_imports d
SET date_from = sub.min_date,
    date_to   = sub.max_date
FROM (
  SELECT
    di.import_id,
    MIN(rs.started_at)::date AS min_date,
    MAX(rs.started_at)::date AS max_date
  FROM data_imports di
  JOIN roast_sessions rs ON rs.session_id = ANY(di.session_ids)
  WHERE di.date_from IS NULL
    AND di.date_to IS NULL
    AND di.session_ids IS NOT NULL
    AND array_length(di.session_ids, 1) > 0
  GROUP BY di.import_id
) sub
WHERE d.import_id = sub.import_id;

COMMIT;
