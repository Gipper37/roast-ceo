-- Add name snapshot columns to transaction/log tables
-- Backfill is run separately via psql due to statement timeout constraints

-- roast_log: capture recipe name and coffee/origin name at time of roast
ALTER TABLE public.roast_log
  ADD COLUMN IF NOT EXISTS recipe_name_snapshot text,
  ADD COLUMN IF NOT EXISTS coffee_name_snapshot text;

-- order_details: capture product name at time of order
ALTER TABLE public.order_details
  ADD COLUMN IF NOT EXISTS product_name_snapshot text;

-- Add is_active flag to reference tables (default true covers all new rows)
ALTER TABLE public.roast_recipes ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.coffee_source ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
ALTER TABLE public.supplier     ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
