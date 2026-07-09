-- login_events — server-side login-attempt telemetry for the dev portal.
--
-- Populated by the login server action (service-role client); read by
-- /app/dev/login-events. This is what the 2026-07-09 auth-outage incident
-- lacked: a way to see "N transient sign-in failures with code X at time T"
-- vs. "someone is typing the wrong password". Supabase's own
-- auth.audit_log_entries is empty (auth events go to its Logs UI, not a
-- queryable table).
--
-- Sensitive (records attempted emails + outcomes) → service-role only. RLS on,
-- NO policies: anon/authenticated can neither read nor write; the service role
-- bypasses RLS for the action's insert + the dev page's read. Mirrors the
-- client_telemetry_events access model.

CREATE TABLE IF NOT EXISTS public.login_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at    timestamptz NOT NULL DEFAULT now(),
  email         text,
  outcome       text NOT NULL,   -- success | invalid_credentials | transient | no_access
  status        integer,         -- GoTrue HTTP status on failure (null on success)
  error_code    text,            -- GoTrue error code (e.g. over_request_rate_limit)
  platform      text,            -- web | native (from the strata_platform marker)
  user_agent    text,
  auth_user_id  uuid             -- set on success
);

CREATE INDEX IF NOT EXISTS login_events_created_at_idx ON public.login_events (created_at DESC);
CREATE INDEX IF NOT EXISTS login_events_outcome_idx    ON public.login_events (outcome, created_at DESC);

ALTER TABLE public.login_events ENABLE ROW LEVEL SECURITY;
-- Intentionally no policies: service-role only (insert from the login action,
-- read from the /app/dev portal).
