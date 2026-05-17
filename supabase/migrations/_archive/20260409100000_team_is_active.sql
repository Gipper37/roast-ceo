-- Add is_active to team table for archive/restore support
ALTER TABLE team ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
