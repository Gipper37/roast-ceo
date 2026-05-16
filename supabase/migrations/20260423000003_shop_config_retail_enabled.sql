-- Sprint 6.0 (B2C foundation): add retail_enabled flag to shop_config so
-- roasters can opt-in to a public, no-auth storefront for the `retail`
-- channel. Default OFF so existing wholesale-only roasters are unaffected.
--
-- Pairs with `wholesale_enabled` (default true) and `vip_enabled` (default
-- false). The shop page reads this flag to decide whether to allow an
-- unauthenticated viewer through to the storefront — guests see only
-- products on the `retail` channel; wholesale and VIP products stay gated
-- behind login + customer.shop_access membership.
--
-- Sprint 6.1 will follow with the actual guest checkout flow (capture
-- email + name, ad-hoc customer creation, card-only payment, tokenized
-- receipt link).

ALTER TABLE public.shop_config
  ADD COLUMN IF NOT EXISTS retail_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.shop_config.retail_enabled IS
  'When true, the storefront is browsable without authentication and shows products on the retail channel. Default false.';
