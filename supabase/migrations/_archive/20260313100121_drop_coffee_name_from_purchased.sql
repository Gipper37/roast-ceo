-- Migration 00121: Drop coffee_name from coffee_inventory_purchased
--
-- coffee_source_id (added in 00114) is the proper FK to coffee_source and holds
-- all correct UUIDs. coffee_name was the original free-text column kept for legacy
-- purposes, but is now fully redundant. All trigger functions already reference
-- coffee_source_id. AppSheet switches its Ref from Coffee_Name → Coffee_Source_Id.
--
-- Pre-flight verified: 0 rows have coffee_name set without a coffee_source_id.

ALTER TABLE public.coffee_inventory_purchased
    DROP COLUMN coffee_name;
