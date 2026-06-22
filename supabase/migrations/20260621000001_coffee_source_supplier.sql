-- ============================================================================
-- coffee_source: add source-level supplier_id
-- ----------------------------------------------------------------------------
-- Supplier previously lived ONLY at the coffee-group level
-- (coffee_inventory.supplier_id). That works for international origins (every
-- MCR international group = Royal Coffee) but cannot represent Hawaiian groups,
-- where a single group spans multiple farms/suppliers across its sources
-- (e.g. Kona Organic = Aloha Hills + Mele Mahina Farms; Maui = Mahi Pono +
-- Maui Grown Coffee). Moving supplier to the source level lets each lot record
-- its own supplier/farm:
--   • International source -> supplier = Royal Coffee (importer); farm blank.
--   • Hawaiian source      -> supplier = the farm (Mahi Pono, Aloha Hills,
--                             Kau Coffee Mill, ...); farm = same name.
-- coffee_inventory.supplier_id stays as the group-level default.
-- Nullable + ON DELETE SET NULL so archiving a supplier never blocks/orphans.
-- ============================================================================

BEGIN;

ALTER TABLE public.coffee_source
    ADD COLUMN IF NOT EXISTS supplier_id text
        REFERENCES public.supplier(supplier_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_coffee_source_supplier_id
    ON public.coffee_source(supplier_id);

COMMIT;
