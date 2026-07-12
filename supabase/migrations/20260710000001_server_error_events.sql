-- server_error_events — SERVER-side error telemetry for the dev portal.
--
-- The 2026-07-10 shipment-save incident cost a day because the failure was
-- INVISIBLE: a Server Action threw before touching the DB (`const rpc =
-- supabase.rpc` dropped the `this` binding → this.rest undefined), and Next.js
-- prod only surfaces the generic "An error occurred in the Server Components
-- render... a digest property is included" message. The real message/stack are
-- stripped client-side, and NOTHING recorded it: client_telemetry_events only
-- captures browser JS errors, never a server throw.
--
-- This table is the missing net. It is populated by Next's `onRequestError`
-- hook (instrumentation.ts, service-role client) which fires for EVERY server
-- throw — RSC render, Server Action, and Route Handler — with the same
-- `digest` the client shows and the Vercel runtime log carries, so a "server
-- render" error the operator sees can be resolved to its real message here.
-- Read by /app/dev/errors.
--
-- Infra/no-tenant-context (instrumentation runs outside request auth scope) →
-- service-role only. RLS on, NO policies: anon/authenticated can neither read
-- nor write; the service role bypasses RLS for the hook's insert + the dev
-- page's read. Mirrors the login_events access model (20260709000002).

CREATE TABLE IF NOT EXISTS public.server_error_events (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at        timestamptz NOT NULL DEFAULT now(),
  message           text,            -- the REAL error message (stripped from the client in prod)
  error_name        text,            -- error.name (TypeError, PermissionError, …)
  stack             text,            -- server stack trace
  digest            text,            -- correlation key: === client-shown digest === Vercel log digest
  route_type        text,            -- render | action | route  (action = Server Action throw)
  router_kind       text,            -- App Router | Pages Router
  route_path        text,            -- matched route (e.g. /app/(app)/inventory)
  render_source     text,            -- react-server-components | server-rendering | …
  revalidate_reason text,            -- on-demand | stale | undefined
  request_path      text,            -- actual request URL path
  request_method    text,            -- GET | POST | …
  user_agent        text,
  environment       text,            -- VERCEL_ENV / NODE_ENV
  app_version       text             -- build sha when available
);

CREATE INDEX IF NOT EXISTS server_error_events_created_at_idx ON public.server_error_events (created_at DESC);
CREATE INDEX IF NOT EXISTS server_error_events_route_type_idx ON public.server_error_events (route_type, created_at DESC);

ALTER TABLE public.server_error_events ENABLE ROW LEVEL SECURITY;
-- Intentionally no policies: service-role only (insert from the onRequestError
-- hook in instrumentation.ts, read from the /app/dev portal).

NOTIFY pgrst, 'reload schema';
