-- ─────────────────────────────────────────────────────────────────────────────
-- shop_config.emblem_url — square brand mark for product card fallbacks
--
-- The full logo (logo_url) is the horizontal "STRATA"-style word mark that
-- lives in the storefront header. It looks bad squashed into a square product
-- card. Most roasters also have a square emblem (the icon-only / favicon
-- variant), so we let them upload that separately and use it as the fallback
-- for product cards that don't have their own image.
--
-- Fallback chain on the storefront product grid:
--   1. product_groups.image     (specific to that product line)
--   2. shop_config.emblem_url   (THIS column — roaster's brand mark)
--   3. monogram placeholder     (rendered client-side, no asset)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.shop_config
  ADD COLUMN IF NOT EXISTS emblem_url text;
