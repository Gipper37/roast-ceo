-- 20260504000007_roaster_unit_brand_and_driver.sql
-- Add brand + driver columns to roaster_units so the live-session
-- integration can pick the right Modbus driver per machine.
--
-- WHY
--   We're adding direct integrations with commercial roaster controllers
--   (Loring first, Probat / Giesen / Diedrich / etc. to follow). Each
--   driver only makes sense for the matching brand — Loring's Modbus
--   driver shouldn't appear as an option on a Probat unit. Brand
--   gates the driver picker; driver_config holds the per-unit network
--   settings (IP / port for Modbus drivers, BLE device id for the
--   thermometer).
--
-- WHAT
--   - brand           : text (nullable). One of a code-level list:
--                       'Loring', 'Probat', 'Giesen', 'Diedrich',
--                       'San Franciscan', 'Mill City', 'Has Garanti',
--                       'Toper', 'Other'. Stored as plain text — no
--                       FK to a brands table since the list changes
--                       slowly and code-level is the single source.
--   - driver_id       : text (nullable). Matches a RoasterDriver
--                       registration id ('ble', 'loring', etc.). NULL
--                       means "no native data integration; manual
--                       events only."
--   - driver_config   : jsonb (nullable). Driver-specific settings.
--                       Loring: { ip: "192.168.1.199", port: 502 }
--                       BLE:    {} (BLE scans by name)
--
-- BACKWARDS COMPATIBLE
--   All three columns are nullable. Existing units stay functional;
--   they just have no brand set and no driver wired. The Roaster Units
--   form will surface a "Set up data integration" affordance.

BEGIN;

ALTER TABLE public.roaster_units
  ADD COLUMN IF NOT EXISTS brand          text,
  ADD COLUMN IF NOT EXISTS driver_id      text,
  ADD COLUMN IF NOT EXISTS driver_config  jsonb;

COMMENT ON COLUMN public.roaster_units.brand IS
  'Roaster manufacturer (Loring, Probat, Giesen, …). Stored as plain text; the canonical list lives in code. Drives the driver-picker filter.';
COMMENT ON COLUMN public.roaster_units.driver_id IS
  'RoasterDriver registration id matching this unit''s data source (e.g. ''loring'' or ''ble''). NULL = manual / no integration.';
COMMENT ON COLUMN public.roaster_units.driver_config IS
  'Per-driver connection config (e.g. { ip, port } for Modbus drivers). Schema is driver-specific — see lib/roaster/<driver>Driver.ts configFields.';

COMMIT;
