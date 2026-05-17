-- =============================================================================
-- Add "Manually Tracked" as a 7th global management type
-- =============================================================================
-- Surfaced during Phase 2 planning: roasters have relationship-driven
-- accounts (VIP, high-touch, longstanding) where automated email
-- reminders feel impersonal. They want the system to TRACK the
-- cadence and surface "due to reach out" customers in a queue, but
-- never to auto-send anything — the operator decides each touchpoint
-- (phone, text, in-person, hand-written email).
--
-- The "Send reminder" button in the customer detail still works for
-- this type; it just requires an explicit click. Cron will exclude
-- this management_type from auto-fire (handled in the cron query
-- predicate, not here).
-- =============================================================================

INSERT INTO public.management_type (management_type, company_id, created_at, updated_at)
VALUES ('Manually Tracked', NULL, now(), now())
ON CONFLICT (management_type) DO NOTHING;
