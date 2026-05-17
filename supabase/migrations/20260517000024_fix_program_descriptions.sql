-- ============================================================
-- Fix program descriptions to match their actual cadences
-- ============================================================
-- The original program seed (..014) wrote descriptions like
-- "Monthly shower screens" that were accurate at the time. The
-- refined cadences in migration ..016 changed the actual intervals
-- (Standard PM is now quarterly screens, not monthly), but the
-- descriptions were never updated. Operators saw mismatched copy.
--
-- This UPDATE syncs every program's description to its real cadences.
-- ============================================================

UPDATE public.maintenance_program SET description =
  'Quarterly shower screens + brew/steam pressure checks, semi-annual gaskets + basket-rim + pressure-relief test, annual boiler descale + water filter + full PM. The baseline cadence for most cafes.'
WHERE program_id = 'pgm_espresso_standard';

UPDATE public.maintenance_program SET description =
  'High-volume specialty cafes (200+ drinks/day). Weekly brew-pressure check, monthly shower screens, quarterly gaskets + volumetric calibration + water filter, semi-annual descale + temp calibration + full PM.'
WHERE program_id = 'pgm_espresso_premium';

UPDATE public.maintenance_program SET description =
  'Monthly burr cleaning tablets + motor mount check, quarterly burr alignment + deep clean + thread lube, annual motor brush replacement, burr replacement based on lbs processed.'
WHERE program_id = 'pgm_grinder_standard';

UPDATE public.maintenance_program SET description =
  'Operator''s own roaster, 1-2 batches/day. 6 daily tasks (chaff, drum brush, cooling tray, sight glass, hopper, floor sweep), 6 weekly (gas, cyclone vacuum, under-vacuum, exhaust trend, drum rotation, damper), monthly exhaust + thermo + ductwork + afterburner + drum entry, quarterly bearings + chain + motor compartment + safety interlocks + thermo wire + flame, semi-annual bearing-play + fan inspection, annual gaskets + burner + electrical + high-limit + full PM.'
WHERE program_id = 'pgm_roaster_standard';

UPDATE public.maintenance_program SET description =
  'High-output roasters (5+ batches/day, 30+ batches/week). Per-batch chaff cleanout (every 100 lbs roasted), daily exhaust + damper + drum-rotation checks, weekly thermocouple + ductwork inspections, monthly bearing greasing + burner flame check + motor compartment, quarterly burner clean + bearing-play check, semi-annual gaskets + electrical, annual high-limit + full PM.'
WHERE program_id = 'pgm_roaster_heavy';
