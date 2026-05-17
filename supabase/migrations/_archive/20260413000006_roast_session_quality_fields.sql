-- Add quality and environment fields to roast_sessions
-- Needed for full Roastmaster import + future Artisan/Cropster imports

ALTER TABLE roast_sessions
  ADD COLUMN IF NOT EXISTS agtron_color numeric,
  ADD COLUMN IF NOT EXISTS post_moisture numeric,
  ADD COLUMN IF NOT EXISTS post_density numeric,
  ADD COLUMN IF NOT EXISTS ambient_temp numeric,
  ADD COLUMN IF NOT EXISTS ambient_humidity numeric,
  ADD COLUMN IF NOT EXISTS roast_degree text,
  ADD COLUMN IF NOT EXISTS rating integer;

COMMENT ON COLUMN roast_sessions.agtron_color IS 'Agtron/colorimeter reading (roast color)';
COMMENT ON COLUMN roast_sessions.post_moisture IS 'Post-roast moisture reading (percentage)';
COMMENT ON COLUMN roast_sessions.post_density IS 'Post-roast density reading';
COMMENT ON COLUMN roast_sessions.ambient_temp IS 'Ambient/environment temperature at roast time (same unit as roast)';
COMMENT ON COLUMN roast_sessions.ambient_humidity IS 'Ambient humidity at roast time (percentage)';
COMMENT ON COLUMN roast_sessions.roast_degree IS 'Roast degree label (e.g. City, Full City+, French)';
COMMENT ON COLUMN roast_sessions.rating IS 'Roaster rating of this roast (1-5 or similar scale)';
