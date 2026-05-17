-- Add roaster_unit_id to charge_weight_options so charge weights can be
-- scoped to a specific roaster unit rather than facility-wide.
-- Existing rows get NULL (treated as facility-wide / legacy).

ALTER TABLE charge_weight_options
  ADD COLUMN IF NOT EXISTS roaster_unit_id uuid
    REFERENCES roaster_units(roaster_unit_id)
    ON DELETE SET NULL;

COMMENT ON COLUMN charge_weight_options.roaster_unit_id IS
  'When set, this charge weight belongs to a specific roaster unit. NULL = facility-wide (legacy).';
