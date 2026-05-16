-- Add shop_product_limit to shop_config
-- NULL = unlimited (Enterprise+). Other plans get a cap enforced in the UI/actions.
ALTER TABLE shop_config
  ADD COLUMN IF NOT EXISTS shop_product_limit integer;

COMMENT ON COLUMN shop_config.shop_product_limit IS
  'Max number of product groups visible in the shop. NULL = unlimited (Enterprise+). '
  'Set at signup based on plan. Enforced in the shop admin UI.';
