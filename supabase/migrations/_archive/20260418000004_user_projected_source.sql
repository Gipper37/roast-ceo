-- 00219: Per-user "Projected" source preference
--
-- Stores the user's preferred default for the Projected card source toggle
-- on /roast (avg vs orders). Synced across devices for the same logged-in
-- email. URL ?src=avg|orders still wins for the current request — the
-- preference is just the fallback when no URL override is present.

BEGIN;

ALTER TABLE user_roaster_settings
  ADD COLUMN IF NOT EXISTS projected_source text;

ALTER TABLE user_roaster_settings
  DROP CONSTRAINT IF EXISTS user_roaster_settings_projected_source_check;
ALTER TABLE user_roaster_settings
  ADD CONSTRAINT user_roaster_settings_projected_source_check
  CHECK (projected_source IS NULL OR projected_source IN ('avg', 'orders'));

COMMENT ON COLUMN user_roaster_settings.projected_source IS
  'User preference for the /roast Projected card source toggle (avg or orders). Synced per email across devices. NULL means "auto" (avg in ambiguous period, orders otherwise).';

COMMIT;
