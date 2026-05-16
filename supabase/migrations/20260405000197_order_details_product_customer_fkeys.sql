-- Add missing FK: order_details.product_id → products.product_id
-- (0 orphaned product_ids confirmed before this migration)
ALTER TABLE public.order_details
  ADD CONSTRAINT order_details_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(product_id)
  ON DELETE SET NULL;

-- Null out the 9 orphaned customer_ids on orders before adding FK
UPDATE public.orders
SET customer_id = NULL
WHERE customer_id IS NOT NULL
  AND customer_id NOT IN (SELECT customer_id FROM public.customers);

-- Add missing FK: orders.customer_id → customers.customer_id
ALTER TABLE public.orders
  ADD CONSTRAINT orders_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id)
  ON DELETE SET NULL;
