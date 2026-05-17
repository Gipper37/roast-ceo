-- Add probe calibration offset columns to roaster_units. These represent
-- a permanent BT/ET correction for a specific physical roaster — applied to
-- BLE readings at INGEST so the saved roast_temp_nodes are already calibrated.
-- Industry-standard model (Cropster / Artisan / Roastmaster all do the same).

ALTER TABLE roaster_units
  ADD COLUMN IF NOT EXISTS probe_offset_bt numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS probe_offset_et numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN roaster_units.probe_offset_bt IS
  'BT probe calibration offset in degrees Fahrenheit. Added to every BLE reading on this roaster before storage.';

COMMENT ON COLUMN roaster_units.probe_offset_et IS
  'ET probe calibration offset in degrees Fahrenheit. Added to every BLE reading on this roaster before storage.';
