-- 20260423000002_shop_config_reply_to_email.sql
--
-- Adds reply_to_email to shop_config so order-confirmation emails sent
-- by STRATA on the roaster's behalf can include the roaster's own
-- support address as the Reply-To header. From: stays roast@strataroast.com
-- (we own deliverability + DKIM); replies bounce back to the roaster.
--
-- Nullable: when null, the confirmation email goes out with no Reply-To
-- and replies route to roast@strataroast.com (we'll forward / drop).

ALTER TABLE shop_config
  ADD COLUMN IF NOT EXISTS reply_to_email text;

COMMENT ON COLUMN shop_config.reply_to_email IS
  'Reply-To header for buyer-facing emails sent by STRATA on the roaster''s behalf. Null = no Reply-To.';
