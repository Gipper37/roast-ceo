-- Drop trigger that tried to UPDATE roast_detail (a non-updatable CTE view)
-- on every roast_type change. Was an AppSheet cache-nudge that has been broken
-- since roast_detail became a CTE-based view. No longer needed on new frontend.

DROP TRIGGER IF EXISTS trg_recipe_header_changes ON roast_recipes;
DROP FUNCTION IF EXISTS propagate_recipe_header_changes();
