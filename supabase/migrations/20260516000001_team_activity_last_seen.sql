-- Cross-device unread state for the operator activity feed
-- (the sidebar bell). Previously stored in browser localStorage,
-- which meant web and desktop app each had their own unread count.
-- A single DB column on `team` is the source of truth so all of an
-- operator's devices agree.
--
-- Per the workflow rule "All user-specific data lives in the DB" —
-- localStorage is only for ephemeral UI (open/closed dropdowns).
-- Read-state of a notification stream is per-user persistent data,
-- so it belongs here.

ALTER TABLE public.team
  ADD COLUMN IF NOT EXISTS activity_last_seen_at timestamptz;

-- No backfill — NULL means "never seen anything," which makes ALL
-- existing events unread on first load. Operator clears it by
-- opening the bell once.
