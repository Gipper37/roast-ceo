-- Migration: Enforce company_id IS NOT NULL on all tenant-scoped tables
--
-- Issue 10: company_id is the multi-tenancy discriminator. A NULL company_id
-- means a row is invisible to tenant-scoped filters, could leak across tenants,
-- and breaks AppSheet filters that rely on company_id equality.
--
-- WHY NOT "ALTER COLUMN company_id SET NOT NULL":
--   PostgreSQL's SET NOT NULL always performs a full table scan, taking an
--   ACCESS EXCLUSIVE lock that blocks all reads and writes. Not safe in production.
--
-- THE WORKAROUND — CHECK (company_id IS NOT NULL) NOT VALID:
--   - Enforces the rule on all future INSERTs and UPDATEs immediately.
--   - Skips scanning existing rows (NOT VALID suppresses the table scan).
--   - To harden existing data later, run VALIDATE CONSTRAINT — it uses a weaker
--     ShareUpdateExclusiveLock and does NOT block normal reads/writes:
--       ALTER TABLE <table> VALIDATE CONSTRAINT <name>;
--
-- Tables included: all operational tables that are tenant-scoped.
-- Tables excluded: global lookup tables (setup_countries, setup_timezones,
--   user_roles, sales_region, sales_state, customer_category, management_type,
--   contact_role, supplier_category, team_member_role, sales_category, size, etc.)

ALTER TABLE public.facilities
    ADD CONSTRAINT facilities_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.orders
    ADD CONSTRAINT orders_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.order_details
    ADD CONSTRAINT order_details_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.customers
    ADD CONSTRAINT customers_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.products
    ADD CONSTRAINT products_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.products_price_log
    ADD CONSTRAINT products_price_log_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.product_consumables
    ADD CONSTRAINT product_consumables_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.roast_log
    ADD CONSTRAINT roast_log_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.roast_recipes
    ADD CONSTRAINT roast_recipes_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.recipe_components
    ADD CONSTRAINT recipe_components_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.roast_detail
    ADD CONSTRAINT roast_detail_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.roast_detail_by_blend
    ADD CONSTRAINT roast_detail_by_blend_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.shipment_received
    ADD CONSTRAINT shipment_received_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.supplier
    ADD CONSTRAINT supplier_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.team
    ADD CONSTRAINT team_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_notes
    ADD CONSTRAINT sales_notes_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_tasks
    ADD CONSTRAINT sales_tasks_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_goals
    ADD CONSTRAINT sales_goals_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_parameters
    ADD CONSTRAINT sales_parameters_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_activity
    ADD CONSTRAINT sales_activity_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

ALTER TABLE public.sales_area
    ADD CONSTRAINT sales_area_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;

-- To validate existing data (run one at a time in low-traffic windows):
-- ALTER TABLE public.facilities VALIDATE CONSTRAINT facilities_company_id_not_null;
-- ALTER TABLE public.orders VALIDATE CONSTRAINT orders_company_id_not_null;
-- ALTER TABLE public.order_details VALIDATE CONSTRAINT order_details_company_id_not_null;
-- ALTER TABLE public.customers VALIDATE CONSTRAINT customers_company_id_not_null;
-- ALTER TABLE public.customer_notes_detail VALIDATE CONSTRAINT customer_notes_detail_company_id_not_null;
-- ALTER TABLE public.products VALIDATE CONSTRAINT products_company_id_not_null;
-- ALTER TABLE public.products_price_log VALIDATE CONSTRAINT products_price_log_company_id_not_null;
-- ALTER TABLE public.product_consumables VALIDATE CONSTRAINT product_consumables_company_id_not_null;
-- ALTER TABLE public.coffee_inventory VALIDATE CONSTRAINT coffee_inventory_company_id_not_null;
-- ALTER TABLE public.coffee_inventory_history VALIDATE CONSTRAINT coffee_inventory_history_company_id_not_null;
-- ALTER TABLE public.coffee_inventory_purchased VALIDATE CONSTRAINT coffee_inventory_purchased_company_id_not_null;
-- ALTER TABLE public.consumable_inventory VALIDATE CONSTRAINT consumable_inventory_company_id_not_null;
-- ALTER TABLE public.consumable_inventory_history VALIDATE CONSTRAINT consumable_inventory_history_company_id_not_null;
-- ALTER TABLE public.consumable_inventory_purchased VALIDATE CONSTRAINT consumable_inventory_purchased_company_id_not_null;
-- ALTER TABLE public.roast_log VALIDATE CONSTRAINT roast_log_company_id_not_null;
-- ALTER TABLE public.roast_recipes VALIDATE CONSTRAINT roast_recipes_company_id_not_null;
-- ALTER TABLE public.recipe_components VALIDATE CONSTRAINT recipe_components_company_id_not_null;
-- ALTER TABLE public.roast_detail VALIDATE CONSTRAINT roast_detail_company_id_not_null;
-- ALTER TABLE public.roast_detail_by_blend VALIDATE CONSTRAINT roast_detail_by_blend_company_id_not_null;
-- ALTER TABLE public.shipment_received VALIDATE CONSTRAINT shipment_received_company_id_not_null;
-- ALTER TABLE public.supplier VALIDATE CONSTRAINT supplier_company_id_not_null;
-- ALTER TABLE public.team VALIDATE CONSTRAINT team_company_id_not_null;
-- ALTER TABLE public.sales_notes VALIDATE CONSTRAINT sales_notes_company_id_not_null;
-- ALTER TABLE public.sales_tasks VALIDATE CONSTRAINT sales_tasks_company_id_not_null;
-- ALTER TABLE public.sales_goals VALIDATE CONSTRAINT sales_goals_company_id_not_null;
-- ALTER TABLE public.sales_parameters VALIDATE CONSTRAINT sales_parameters_company_id_not_null;
-- ALTER TABLE public.sales_activity VALIDATE CONSTRAINT sales_activity_company_id_not_null;
-- ALTER TABLE public.sales_area VALIDATE CONSTRAINT sales_area_company_id_not_null;
