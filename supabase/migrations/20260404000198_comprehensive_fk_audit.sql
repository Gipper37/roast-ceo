-- Comprehensive FK audit migration
-- Adds all missing FK constraints identified by the 2026-04-04 audit.
-- Orphaned rows handled with NOT VALID where needed; others added directly.
-- All NOT VALID constraints should be validated in a future maintenance window.

-- ─── Zero-orphan FKs (add directly) ─────────────────────────────────────────

-- roast_log.origin_id → coffee_inventory (PK = origin_id)
ALTER TABLE public.roast_log
  ADD CONSTRAINT roast_log_origin_id_fkey
  FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id)
  ON DELETE RESTRICT;

-- recipe_components.recipe_id → roast_recipes
ALTER TABLE public.recipe_components
  ADD CONSTRAINT recipe_components_recipe_id_fkey
  FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id)
  ON DELETE CASCADE;

-- recipe_components.coffee_item → coffee_inventory (origin_id)
ALTER TABLE public.recipe_components
  ADD CONSTRAINT recipe_components_coffee_item_fkey
  FOREIGN KEY (coffee_item) REFERENCES public.coffee_inventory(origin_id)
  ON DELETE SET NULL;

-- coffee_inventory_purchased.origin → coffee_inventory (origin_id)
ALTER TABLE public.coffee_inventory_purchased
  ADD CONSTRAINT coffee_inventory_purchased_origin_fkey
  FOREIGN KEY (origin) REFERENCES public.coffee_inventory(origin_id)
  ON DELETE RESTRICT;

-- coffee_inventory_purchased.shipment_id → shipment_received (12 orphans → NOT VALID)
ALTER TABLE public.coffee_inventory_purchased
  ADD CONSTRAINT coffee_inventory_purchased_shipment_id_fkey
  FOREIGN KEY (shipment_id) REFERENCES public.shipment_received(shipment_id)
  ON DELETE SET NULL
  NOT VALID;

-- consumable_inventory_purchased.consumable_inventory_item → consumable_inventory (id)
ALTER TABLE public.consumable_inventory_purchased
  ADD CONSTRAINT consumable_inventory_purchased_item_fkey
  FOREIGN KEY (consumable_inventory_item) REFERENCES public.consumable_inventory(consumable_inventory_id)
  ON DELETE RESTRICT;

-- consumable_inventory_purchased.shipment_id → shipment_received
ALTER TABLE public.consumable_inventory_purchased
  ADD CONSTRAINT consumable_inventory_purchased_shipment_id_fkey
  FOREIGN KEY (shipment_id) REFERENCES public.shipment_received(shipment_id)
  ON DELETE SET NULL;

-- shipment_received.supplier_id → supplier
ALTER TABLE public.shipment_received
  ADD CONSTRAINT shipment_received_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES public.supplier(supplier_id)
  ON DELETE SET NULL;

-- coffee_inventory.bag_size → bag_sizes
ALTER TABLE public.coffee_inventory
  ADD CONSTRAINT coffee_inventory_bag_size_fkey
  FOREIGN KEY (bag_size) REFERENCES public.bag_sizes(bag_size_id)
  ON DELETE SET NULL;

-- coffee_inventory.supplier_id → supplier (1 orphan → NOT VALID)
ALTER TABLE public.coffee_inventory
  ADD CONSTRAINT coffee_inventory_supplier_id_fkey
  FOREIGN KEY (supplier_id) REFERENCES public.supplier(supplier_id)
  ON DELETE SET NULL
  NOT VALID;

-- coffee_source.origin_id → coffee_inventory (origin_id)
ALTER TABLE public.coffee_source
  ADD CONSTRAINT coffee_source_origin_id_fkey
  FOREIGN KEY (origin_id) REFERENCES public.coffee_inventory(origin_id)
  ON DELETE RESTRICT;

-- coffee_source.bag_size → bag_sizes
ALTER TABLE public.coffee_source
  ADD CONSTRAINT coffee_source_bag_size_fkey
  FOREIGN KEY (bag_size) REFERENCES public.bag_sizes(bag_size_id)
  ON DELETE SET NULL;

-- products_price_log.product_id → products
ALTER TABLE public.products_price_log
  ADD CONSTRAINT products_price_log_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(product_id)
  ON DELETE CASCADE;

-- products.recipe_id → roast_recipes
ALTER TABLE public.products
  ADD CONSTRAINT products_recipe_id_fkey
  FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id)
  ON DELETE SET NULL;

-- blending_worksheet.roast_recipe_id → roast_recipes
ALTER TABLE public.blending_worksheet
  ADD CONSTRAINT blending_worksheet_roast_recipe_id_fkey
  FOREIGN KEY (roast_recipe_id) REFERENCES public.roast_recipes(recipe_id)
  ON DELETE SET NULL;

-- sales_tasks.customer_id → customers
ALTER TABLE public.sales_tasks
  ADD CONSTRAINT sales_tasks_customer_id_fkey
  FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id)
  ON DELETE SET NULL;

-- ─── Orphan FKs (NOT VALID) ──────────────────────────────────────────────────

-- recipe_components.item_id → products (50 orphans — likely merged/archived products)
ALTER TABLE public.recipe_components
  ADD CONSTRAINT recipe_components_item_id_fkey
  FOREIGN KEY (item_id) REFERENCES public.products(product_id)
  ON DELETE SET NULL
  NOT VALID;

-- roast_log.recipe_id → roast_recipes (12 orphans — deleted recipes)
ALTER TABLE public.roast_log
  ADD CONSTRAINT roast_log_recipe_id_fkey
  FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id)
  ON DELETE SET NULL
  NOT VALID;

-- order_details.recipe_id → roast_recipes (4 orphans — deleted recipes)
ALTER TABLE public.order_details
  ADD CONSTRAINT order_details_recipe_id_fkey
  FOREIGN KEY (recipe_id) REFERENCES public.roast_recipes(recipe_id)
  ON DELETE SET NULL
  NOT VALID;
