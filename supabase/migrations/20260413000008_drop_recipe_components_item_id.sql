-- Drop legacy item_id column from recipe_components.
-- coffee_item is the authoritative column used by all 14+ DB functions
-- (COGS, stock, cost propagation, etc). item_id was a duplicate that
-- frequently drifted out of sync, causing stale data on inventory pages.

-- First drop the FK constraint
ALTER TABLE recipe_components DROP CONSTRAINT IF EXISTS recipe_components_item_id_fkey;

-- Then drop the column
ALTER TABLE recipe_components DROP COLUMN IF EXISTS item_id;
