-- Migration 00116: Add descriptive columns to coffee_source
--
-- Adds: process, region, farm, elevation, certifications
-- All nullable text — filled in over time as the coffee library is built out.

ALTER TABLE public.coffee_source
    ADD COLUMN IF NOT EXISTS process        text,
    ADD COLUMN IF NOT EXISTS region         text,
    ADD COLUMN IF NOT EXISTS farm           text,
    ADD COLUMN IF NOT EXISTS elevation      text,
    ADD COLUMN IF NOT EXISTS certifications text;
