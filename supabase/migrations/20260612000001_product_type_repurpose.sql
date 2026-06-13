-- ============================================================================
-- Repurpose products.product_type as the item-nature axis (platform-wide)
-- ----------------------------------------------------------------------------
-- OLD product_type (Wholesale Retail/Bulk/Retail DTC/Sample/Merged) was vestigial
-- (a "legacy AppSheet column, only live writer is the merge trigger"). Its only
-- real job was the 'Merged' tombstone, and product_type='Merged' <=> merge_into_id
-- IS NOT NULL. We retire that meaning and take over the column to mean WHAT the
-- item is: Coffee / Consumable / Equipment / Service / Discount.
--
-- This migration is ADDITIVE + SAFE: every existing product (all tenants) is
-- backfilled to Coffee, so existing COGS behavior is byte-identical. The engine
-- gating that makes only Coffee trigger the roast/COGS chain lands in migration
-- 20260612000002. See memory/project_product_taxonomy.md.
-- ============================================================================

BEGIN;

-- 1. product_type lookup: add QuickBooks-equivalent + orderability columns ------
--    is_sellable = can a customer order this kind at all? Service (shipping/fees)
--    and Discount are invoice-side mechanics, never cart items -> false. The shop
--    + order picker exclude non-sellable kinds (frontend filter, added later).
ALTER TABLE public.product_type
    ADD COLUMN IF NOT EXISTS qb_item_type text,
    ADD COLUMN IF NOT EXISTS is_sellable  boolean NOT NULL DEFAULT true;

-- 2. Insert the 5 new GLOBAL item-nature rows (company_id = NULL) ---------------
INSERT INTO public.product_type (product_type_id, product_type, qb_item_type, is_sellable, company_id, is_active, created_at, updated_at)
VALUES
    ('ptype_coffee',     'Coffee',     'Inventory Part',                 true,  NULL, true, now(), now()),
    ('ptype_consumable', 'Consumable', 'Inventory / Non-inventory Part', true,  NULL, true, now(), now()),
    ('ptype_equipment',  'Equipment',  'Non-inventory Part',             true,  NULL, true, now(), now()),
    ('ptype_service',    'Service',    'Service / Other Charge',         false, NULL, true, now(), now()),
    ('ptype_discount',   'Discount',   'Discount',                       false, NULL, true, now(), now())
ON CONFLICT (product_type_id) DO UPDATE
    SET product_type = EXCLUDED.product_type,
        qb_item_type = EXCLUDED.qb_item_type,
        is_sellable  = EXCLUDED.is_sellable,
        is_active    = true;

-- 3. New columns on products ---------------------------------------------------
--    unit_cost          : flat per-unit COGS for NON-coffee items (auto-pulled
--                         from a linked consumable's last_cost_unit, else manual).
--    source_consumable_id: optional link to the consumable_inventory row this
--                         resale item is bought as (drives unit_cost auto-pull).
--    qb_item_id         : dormant QuickBooks sync mapping.
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS unit_cost            numeric,
    ADD COLUMN IF NOT EXISTS source_consumable_id text,
    ADD COLUMN IF NOT EXISTS qb_item_id           text;

ALTER TABLE public.products
    DROP CONSTRAINT IF EXISTS products_source_consumable_id_fkey;
ALTER TABLE public.products
    ADD CONSTRAINT products_source_consumable_id_fkey
    FOREIGN KEY (source_consumable_id)
    REFERENCES public.consumable_inventory(consumable_inventory_id)
    ON DELETE SET NULL;

-- 4. Backfill EVERY product (all tenants) -> Coffee ----------------------------
--    Identical to today's behavior (everything is coffee now). Fires the existing
--    COGS trigger harmlessly (recomputes to the same values; inactive/merged rows
--    short-circuit). product_type is NOT in build_product_name's UPDATE-OF list,
--    so names are untouched.
UPDATE public.products
SET    product_type = 'ptype_coffee'
WHERE  product_type IS DISTINCT FROM 'ptype_coffee';

-- 5. Retire the OLD product_type rows (keep for audit; FK is ON DELETE SET NULL)
UPDATE public.product_type
SET    is_active = false
WHERE  product_type_id NOT IN
       ('ptype_coffee','ptype_consumable','ptype_equipment','ptype_service','ptype_discount');

-- 6. Reserve dormant QuickBooks-sync mapping columns ---------------------------
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS qb_customer_id text;

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS qb_txn_id       text,
    ADD COLUMN IF NOT EXISTS qb_sync_status  text,
    ADD COLUMN IF NOT EXISTS discount_total  numeric;  -- cached; Discount line stays source of truth

COMMIT;
