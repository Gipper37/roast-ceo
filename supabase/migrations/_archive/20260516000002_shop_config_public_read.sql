-- shop_config: allow anon SELECT on enabled shops.
--
-- Without this, the middleware's slug→login lookup at
-- `lib/supabase/middleware.ts` returns no rows for anon visitors,
-- and customers clicking a reminder email link land on the staff
-- /login page instead of /<slug>/login. The storefront page itself
-- also can't render its branding pre-auth.
--
-- Existing tenant_company_access (ALL) policy stays — it still gates
-- writes + reads of disabled shops + private columns. The new
-- public_read policy only adds SELECT access, only on enabled shops.
-- Postgres OR's policies of the same cmd, so the union is:
--   anon  → can SELECT enabled shops
--   member → can SELECT any (incl. disabled) + INSERT/UPDATE/DELETE
--
-- Safety: every column in shop_config is intended to be
-- customer-visible on the storefront (slug, name, logo, accent,
-- tagline, reply_to_email, retail flags, etc.). No private secrets
-- live here.

DROP POLICY IF EXISTS public_read_enabled ON public.shop_config;
CREATE POLICY public_read_enabled ON public.shop_config
  FOR SELECT
  USING (is_enabled = true);
