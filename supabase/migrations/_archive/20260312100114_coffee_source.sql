-- Migration 00114: coffee_source table
--
-- Problem: coffee_inventory_purchased.coffee_name is a free-text field describing
-- the specific sourced coffee (e.g., "Brazil Alta Mogiana SS FC 14/16"). The same
-- coffee recurs across seasons — only lot_id and harvest_year differ. Bag size is
-- a property of the specific coffee, not the origin category or the purchase row.
--
-- Fix:
--   1. New coffee_source reference table — reusable coffee library, company-scoped
--   2. bag_size lives here (not on origin category, not on purchase)
--   3. harvest_year added to coffee_inventory_purchased
--   4. Import distinct coffee_name values from coffee_inventory_purchased
--   5. Backfill coffee_source_id FK on all matching purchase rows
--   6. Update compute_coffee_purchase_amount() to read bag_size from coffee_source
--      (priority: coffee_source → coffee_inventory → 154)


-- ─── 1. coffee_source table ───────────────────────────────────────────────────

CREATE TABLE public.coffee_source (
    coffee_source_id  text        PRIMARY KEY DEFAULT gen_random_uuid()::text,
    coffee_name       text        NOT NULL,
    origin_id         text,       -- logical ref to coffee_inventory.origin_id
                                  -- no FK constraint: coffee_inventory has a compound key
    bag_size          text,       -- ref to bag_sizes.bag_size_id ('154', '132', '100')
    company_id        text,
    created_at        timestamptz DEFAULT now(),
    updated_at        timestamptz DEFAULT now(),
    created_by        text,
    updated_by        text
);

-- Prevent duplicate coffee entries for the same company + origin + name
CREATE UNIQUE INDEX uq_coffee_source
    ON public.coffee_source (company_id, origin_id, coffee_name);


-- ─── 2. Audit triggers ────────────────────────────────────────────────────────

CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.coffee_source
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.coffee_source
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


-- ─── 3. Add coffee_source_id and harvest_year to coffee_inventory_purchased ───

ALTER TABLE public.coffee_inventory_purchased
    ADD COLUMN coffee_source_id text,
    ADD COLUMN harvest_year     integer;

ALTER TABLE public.coffee_inventory_purchased
    ADD CONSTRAINT fk_coffee_inventory_purchased_source
    FOREIGN KEY (coffee_source_id) REFERENCES public.coffee_source (coffee_source_id);


-- ─── 4. Backfill coffee_source from distinct coffee_name values ───────────────
-- Groups by company_id + origin + coffee_name to avoid duplicates.
-- bag_size is pulled from coffee_inventory for that origin (all currently '154').

INSERT INTO public.coffee_source (coffee_source_id, coffee_name, origin_id, bag_size, company_id)
SELECT
    gen_random_uuid()::text,
    d.coffee_name,
    d.origin,
    COALESCE(
        (SELECT ci.bag_size
         FROM public.coffee_inventory ci
         WHERE ci.origin_id = d.origin AND ci.company_id = d.company_id
         LIMIT 1),
        '154'
    ),
    d.company_id
FROM (
    SELECT DISTINCT coffee_name, origin, company_id
    FROM public.coffee_inventory_purchased
    WHERE coffee_name IS NOT NULL AND TRIM(coffee_name) != ''
) d;


-- ─── 5. Backfill coffee_source_id on coffee_inventory_purchased ───────────────
-- Matches on company_id + origin + coffee_name — same key used in the unique index.
-- Rows with NULL/empty coffee_name stay with coffee_source_id = NULL (legacy).

UPDATE public.coffee_inventory_purchased p
SET coffee_source_id = cs.coffee_source_id
FROM public.coffee_source cs
WHERE p.company_id  = cs.company_id
  AND p.origin      = cs.origin_id
  AND p.coffee_name = cs.coffee_name;


-- ─── 6. Update compute_coffee_purchase_amount() ───────────────────────────────
-- Bag_size priority: coffee_source.bag_size → coffee_inventory.bag_size → 154.
-- Add coffee_source_id to the trigger's UPDATE OF list so changing the source
-- on a purchase (which changes bag_size) recalculates the amount.

DROP TRIGGER IF EXISTS trg_compute_coffee_purchase_amount ON public.coffee_inventory_purchased;

CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        -- 1. coffee_source.bag_size (most specific — the actual coffee)
        -- 2. coffee_inventory.bag_size (operative size for this origin category)
        -- 3. 154 (universal fallback)
        SELECT COALESCE(
            (SELECT cs.bag_size::numeric
             FROM public.coffee_source cs
             WHERE cs.coffee_source_id = NEW.coffee_source_id
             LIMIT 1),
            (SELECT ci.bag_size::numeric
             FROM public.coffee_inventory ci
             WHERE ci.origin_id = NEW.origin AND ci.facility_id = NEW.facility_id
             LIMIT 1),
            154
        ) INTO v_bag_size;

        NEW.amount := NEW.bags_ordered * v_bag_size;
    END IF;
    RETURN NEW;
END;
$$;

-- Recreate trigger — coffee_source_id added to UPDATE OF list
CREATE TRIGGER trg_compute_coffee_purchase_amount
    BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, coffee_source_id
    ON public.coffee_inventory_purchased
    FOR EACH ROW
    EXECUTE FUNCTION public.compute_coffee_purchase_amount();
