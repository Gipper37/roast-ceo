-- ============================================================================
-- Shop membership foundation — explicit products.in_shop (Model B)
-- ----------------------------------------------------------------------------
-- Decouples shop membership from `channel` (which is reverting to pricing-tier
-- only). `in_shop` becomes the single explicit "this product is listed in the
-- shop" fact. DORMANT for now: the shop query still uses product_groups.is_visible
-- until the Shop-membership redesign project switches it over and builds the
-- tabbed shop-management UI. See memory/project_product_taxonomy.md.
-- ============================================================================

BEGIN;

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS in_shop boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.products.in_shop IS
    'Explicit shop membership (Model B, 2026-06-12). channel = pricing tier only; '
    'in_shop is the membership gate. Wired into the shop query + UI in the '
    'shop-membership redesign project; dormant until then.';

-- Backfill to current effective shop visibility so the column is meaningful from
-- day one. New model: membership is group-visibility driven, NOT channel-gated.
UPDATE public.products p
SET    in_shop = true
FROM   public.product_groups g
WHERE  p.group_id    = g.group_id
  AND  p.is_active   = true
  AND  COALESCE(g.is_visible, false) = true
  AND  p.in_shop IS DISTINCT FROM true;

COMMIT;
