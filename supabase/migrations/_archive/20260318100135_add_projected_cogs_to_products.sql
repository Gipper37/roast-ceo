-- Migration 00135: Add projected_cogs_pct generated column to products
-- Calculates COGS% at the proposed new_price_input: total_unit_cogs / new_price_input * 100

ALTER TABLE public.products
    ADD COLUMN projected_cogs_pct numeric
        GENERATED ALWAYS AS (
            ROUND(total_unit_cogs / NULLIF(new_price_input, 0) * 100, 1)
        ) STORED;
