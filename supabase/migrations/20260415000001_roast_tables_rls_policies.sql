-- RLS policies for the roast tables.
--
-- Background: roast_log, roast_sessions, roast_events, and roast_temp_nodes
-- all have RLS *enabled* but ZERO policies, which means browser-side
-- (authenticated user JWT, not service_role) requests return ZERO rows for
-- everything. Server-side Next.js + AppSheet keep working because they use
-- service_role and bypass RLS — but client-side React components like the
-- post-roast cards and the historical profile modal can't read or write
-- anything they just saved. That manifests as "Cannot coerce the result to
-- a single JSON object", missing green/roasted weights, missing dev time,
-- broken reference profile loading, etc.
--
-- These policies grant authenticated users full access to rows belonging to
-- any facility they're a member of (via the `team` table). Service_role is
-- unaffected (continues to bypass RLS).

-- Helper: returns the set of facility_ids the current authenticated user is
-- a member of. SECURITY DEFINER so it can read `team` even if `team`'s own
-- RLS would deny it. Marked STABLE because within a single transaction the
-- result doesn't change.
CREATE OR REPLACE FUNCTION public.user_facility_ids()
RETURNS SETOF text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT facility_id FROM public.team WHERE auth_user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.user_facility_ids() TO authenticated;

-- ── roast_log ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "roast_log tenant access" ON public.roast_log;
CREATE POLICY "roast_log tenant access" ON public.roast_log
  FOR ALL
  TO authenticated
  USING (facility_id IN (SELECT public.user_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.user_facility_ids()));

-- ── roast_sessions ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "roast_sessions tenant access" ON public.roast_sessions;
CREATE POLICY "roast_sessions tenant access" ON public.roast_sessions
  FOR ALL
  TO authenticated
  USING (facility_id IN (SELECT public.user_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.user_facility_ids()));

-- ── roast_events ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "roast_events tenant access" ON public.roast_events;
CREATE POLICY "roast_events tenant access" ON public.roast_events
  FOR ALL
  TO authenticated
  USING (facility_id IN (SELECT public.user_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.user_facility_ids()));

-- ── roast_temp_nodes ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "roast_temp_nodes tenant access" ON public.roast_temp_nodes;
CREATE POLICY "roast_temp_nodes tenant access" ON public.roast_temp_nodes
  FOR ALL
  TO authenticated
  USING (facility_id IN (SELECT public.user_facility_ids()))
  WITH CHECK (facility_id IN (SELECT public.user_facility_ids()));

-- Sanity comment: service_role connections (server-side Next.js, AppSheet)
-- bypass RLS entirely, so all existing server-side code keeps working.
