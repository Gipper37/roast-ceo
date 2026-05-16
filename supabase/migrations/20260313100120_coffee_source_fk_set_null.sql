-- Migration 00120: Change coffee_source FK to ON DELETE SET NULL
--
-- Deleting a coffee_source record was blocked by the FK constraint on
-- coffee_inventory_purchased.coffee_source_id. ON DELETE SET NULL is the correct
-- behaviour: the purchase history is preserved, the coffee_source link is just cleared.
-- The legacy coffee_name text column on the purchase retains the original value.

ALTER TABLE public.coffee_inventory_purchased
    DROP CONSTRAINT fk_coffee_inventory_purchased_source;

ALTER TABLE public.coffee_inventory_purchased
    ADD CONSTRAINT fk_coffee_inventory_purchased_source
    FOREIGN KEY (coffee_source_id)
    REFERENCES public.coffee_source (coffee_source_id)
    ON DELETE SET NULL;
