-- Reference data: a "Shipping" product type + a "Toll Roast" customer category.
--
-- Both product_type and customer_category are GLOBAL reference tables
-- (company_id NULL / no company scope), consistent with the existing rows.
-- Shipping is a non-coffee, sellable type (freight lines charged to customers);
-- the engine gating keys off 'Coffee' so Shipping is never roast-planned.
-- Toll Roast = roasting a customer's own green for a fee.

INSERT INTO public.product_type (product_type_id, product_type, company_id, is_active, is_sellable, qb_item_type)
VALUES ('ptype_shipping', 'Shipping', NULL, true, true, 'Service')
ON CONFLICT (product_type_id) DO NOTHING;

-- id defaults to gen_random_uuid(); the unique index is on the (name, company)
-- expression, so guard with NOT EXISTS rather than ON CONFLICT.
INSERT INTO public.customer_category (customer_category, company_id)
SELECT 'Toll Roast', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM public.customer_category WHERE customer_category = 'Toll Roast' AND company_id IS NULL
);

NOTIFY pgrst, 'reload schema';
