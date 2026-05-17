-- ============================================================
-- signup_rate_limit — per-IP signup throttle
-- ============================================================
-- Backs the /api/signup rate limiter. One row per attempt. The route
-- counts rows for an IP in the last N minutes and rejects when the
-- threshold is exceeded.
--
-- RLS: service_role only (no policies, table is server-managed).
-- Pruned hourly by a pg_cron job so the table stays small.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.signup_rate_limit (
  id           bigserial PRIMARY KEY,
  ip           text NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS signup_rate_limit_ip_attempted_at_idx
  ON public.signup_rate_limit (ip, attempted_at DESC);

ALTER TABLE public.signup_rate_limit ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.signup_rate_limit IS
  'Per-IP signup throttle. Service-role only (no RLS policies by design). Pruned hourly to keep table size bounded.';

-- Prune entries older than 1 day every hour, IF pg_cron is enabled.
-- Skipped on environments where the extension isn't available (e.g.
-- Supabase free tier where it must be enabled via the dashboard).
-- Without the prune the table grows by ~1 row per signup attempt
-- and can be cleared by hand if it ever matters.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'signup_rate_limit_prune',
      '0 * * * *',
      $cron$DELETE FROM public.signup_rate_limit WHERE attempted_at < now() - interval '1 day'$cron$
    );
  ELSE
    RAISE NOTICE 'pg_cron not installed — skipping signup_rate_limit prune schedule';
  END IF;
END
$$;
