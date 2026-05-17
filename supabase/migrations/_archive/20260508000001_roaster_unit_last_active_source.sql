-- Per-unit memory of which BLE/network source last produced readings.
--
-- Lets the source picker in RoastSessionProvider prioritize what worked
-- last for THIS unit instead of always falling through to ThermaQ Blue.
-- Example: a Giesen W15A user with no driver_id but a ThermaQ paired —
-- on first connect we record last_active_source='thermaq', and on
-- subsequent picks of the same unit we go straight to ThermaQ rather
-- than the generic priority chain.
--
-- For units WITH a driver_id (Loring etc.), driver_id stays the
-- primary signal — last_active_source is just a tiebreaker /
-- recovery hint.
--
-- last_active_at is updated alongside so future analytics ("which
-- units haven't seen a reading in 30 days?") can use the timestamp.
-- Both nullable; null means "no source has produced readings yet".

BEGIN;

ALTER TABLE roaster_units
  ADD COLUMN IF NOT EXISTS last_active_source text,
  ADD COLUMN IF NOT EXISTS last_active_at     timestamptz;

COMMENT ON COLUMN roaster_units.last_active_source IS
  'Most recent source that produced readings for this roaster unit. One of: loring | thermaq | helper | web | mock | null. Throttled to one write per minute by the client.';
COMMENT ON COLUMN roaster_units.last_active_at IS
  'When last_active_source was most recently observed producing readings.';

COMMIT;
