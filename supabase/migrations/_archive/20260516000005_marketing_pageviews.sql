-- Marketing site pageview tracker.
--
-- Scoped to public marketing pages only (anything under (marketing)/*
-- in our route tree: /, /about, /contact, /demo, /features/*,
-- /pricing, /signup, /suppliers). NOT the app — we already infer
-- roaster usage from order / customer / roast counts and don't want
-- to track operators inside their own tool.
--
-- Writes come from a small client-side beacon (lib/marketing/track.ts)
-- that POSTs to /api/marketing/pageview on every Next.js route change
-- while on a marketing page. INSERT-only; data is read by the dev
-- portal only.
--
-- Volume estimate: ~hundreds to low-thousands of rows/day at most
-- for a small SaaS marketing site. Auto-trim rows older than 180d
-- via the daily pg_cron job below so the table stays small forever.

CREATE TABLE IF NOT EXISTS public.marketing_pageview (
  id               bigserial PRIMARY KEY,
  path             text NOT NULL,
  referrer         text,
  country          text,
  -- Coarse user-agent class so dev portal can show device split
  -- without storing PII. 'mobile' / 'tablet' / 'desktop' / 'bot' / 'other'.
  ua_class         text,
  -- Lightweight session hash — first 12 chars of sha256(ip + day + ua).
  -- Lets us count "unique visitors" without storing IP. Resets daily so
  -- a visitor counts once per day per surface.
  session_hash     text,
  viewed_at        timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS marketing_pageview_viewed_at_idx
  ON public.marketing_pageview (viewed_at DESC);
CREATE INDEX IF NOT EXISTS marketing_pageview_path_idx
  ON public.marketing_pageview (path, viewed_at DESC);

-- RLS: nobody reads via PostgREST. The /api/marketing/pageview route
-- uses the service-role client to INSERT. Dev portal pages query via
-- the service-role client too (server component). Lock down anon +
-- authenticated SELECT entirely.
ALTER TABLE public.marketing_pageview ENABLE ROW LEVEL SECURITY;

-- No SELECT policy → no role can read via Supabase API. Service role
-- bypasses RLS, which is fine because the dev portal already uses
-- service-role for its admin queries.

-- 180-day retention sweep — run nightly.
CREATE OR REPLACE FUNCTION public.trim_marketing_pageview()
RETURNS void
LANGUAGE sql
AS $$
  DELETE FROM public.marketing_pageview
  WHERE viewed_at < NOW() - INTERVAL '180 days';
$$;

SELECT cron.schedule(
  'trim_marketing_pageview_daily',
  '15 3 * * *',  -- 03:15 UTC daily (offset from the cadence recompute at 03:00)
  $$SELECT public.trim_marketing_pageview();$$
);

-- Verification (post-push):
--   \d marketing_pageview
--   SELECT cron.job WHERE jobname='trim_marketing_pageview_daily';
