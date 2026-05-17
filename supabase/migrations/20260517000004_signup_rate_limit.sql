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

-- Prune entries older than 1 day every hour
SELECT cron.schedule(
  'signup_rate_limit_prune',
  '0 * * * *',
  $$DELETE FROM public.signup_rate_limit WHERE attempted_at < now() - interval '1 day'$$
);
