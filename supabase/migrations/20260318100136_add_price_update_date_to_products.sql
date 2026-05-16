-- Migration 00136: Add price_update_date user-input column to products

ALTER TABLE public.products
    ADD COLUMN price_update_date date;
