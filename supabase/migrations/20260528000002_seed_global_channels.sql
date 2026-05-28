-- ============================================================
-- Seed the 4 global channel rows (wholesale / retail / vip / sample)
-- ============================================================
-- Same archived-migration problem as customer_category: these were
-- created on prod by historical migrations but lost during the
-- baseline squash. Without them, any fresh project's products
-- reference channel IDs that don't resolve in channelMap → UI shows
-- raw UUIDs instead of channel names (NewOrderForm Suggested-pick
-- regression).
--
-- Idempotent: ON CONFLICT DO NOTHING on the primary key.
-- ============================================================

INSERT INTO public.channel (channel_id, channel, company_id, is_active)
VALUES
  ('6e6f4b92-8d17-4858-913a-b38b85b178a6', 'wholesale', NULL, true),
  ('e70c0ef4-84c2-41d2-8b3a-da71c721b445', 'vip',       NULL, true),
  ('056d4860-c6a7-4eba-84e0-162a594421fb', 'sample',    NULL, true),
  ('87f69426-eb0f-4b67-a160-62c8be988323', 'retail',    NULL, true)
ON CONFLICT (channel_id) DO NOTHING;
