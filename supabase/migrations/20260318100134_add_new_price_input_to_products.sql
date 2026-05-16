-- Migration 00134: Add new_price_input column to products for AppSheet price update bot

ALTER TABLE public.products
    ADD COLUMN new_price_input numeric;
