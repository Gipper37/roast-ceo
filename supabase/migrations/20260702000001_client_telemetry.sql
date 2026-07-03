-- ─────────────────────────────────────────────────────────────────────────────
-- Client telemetry events
--
-- Append-only event stream from the STRATA frontend / Tauri native app:
-- js errors, unhandled rejections, console errors, error-boundary catches,
-- hydration errors, stalled App Router transitions, long tasks, heartbeats.
-- Ingested by /api/telemetry (route handler, createUserClient → this table's
-- RLS INSERT policy). Read ONLY by the dev portal (/app/dev/telemetry) via the
-- sanctioned admin client — no SELECT/UPDATE/DELETE policies on purpose.
--
-- Payloads are redacted client-side AND server-side (no PII, no form values,
-- messages/stacks truncated to 2KB); the 4KB pg_column_size CHECK is a
-- guard-rail, not the primary control.
--
-- TODO (follow-up): 30-day retention purge via a scheduled route under the
-- existing /api/cron/* pattern (DELETE WHERE created_at < now() - interval '30 days').
-- ─────────────────────────────────────────────────────────────────────────────

-- ── table ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.client_telemetry_events (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id        text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  auth_user_id      uuid,
  client_session_id uuid NOT NULL,
  app_version       text,
  platform          text,
  event_type        text NOT NULL CHECK (event_type IN (
                      'js_error',
                      'unhandled_rejection',
                      'console_error',
                      'error_boundary',
                      'hydration_error',
                      'stalled_transition',
                      'long_task',
                      'heartbeat'
                    )),
  route             text,
  payload           jsonb NOT NULL DEFAULT '{}'::jsonb
                      CHECK (pg_column_size(payload) <= 4096),
  created_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.client_telemetry_events IS
  'Client-side telemetry (errors, stalled transitions, heartbeats) from the STRATA app. INSERT-only via RLS; dev portal reads via admin client. 30-day retention purge = follow-up cron.';

COMMENT ON COLUMN public.client_telemetry_events.client_session_id IS
  'Random uuid generated per app launch on the client; groups events from one session.';

COMMENT ON COLUMN public.client_telemetry_events.platform IS
  'tauri-macos | tauri-windows | web';

COMMENT ON COLUMN public.client_telemetry_events.route IS
  'Pathname only — query strings stripped client- and server-side.';

COMMENT ON COLUMN public.client_telemetry_events.payload IS
  'Redacted event context (BLE state, readings rate, deploymentId, truncated message/stack, heartbeat-log lines). Capped at 4KB stored size.';

-- ── indexes ──────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS client_telemetry_events_company_created_idx
  ON public.client_telemetry_events (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS client_telemetry_events_type_created_idx
  ON public.client_telemetry_events (event_type, created_at DESC);

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- INSERT-only for authenticated team members of the target company (any active
-- team row, via the canonical auth_company_ids() helper). Deliberately NO
-- SELECT/UPDATE/DELETE policies: clients can never read telemetry back;
-- the dev portal reads with the service-role admin client, which bypasses RLS.

ALTER TABLE public.client_telemetry_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS telemetry_insert_own_company ON public.client_telemetry_events;

CREATE POLICY telemetry_insert_own_company ON public.client_telemetry_events
  FOR INSERT TO authenticated
  WITH CHECK (company_id IN (SELECT auth_company_ids()));

NOTIFY pgrst, 'reload schema';
