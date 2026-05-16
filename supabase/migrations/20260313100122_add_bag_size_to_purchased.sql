-- Migration 00122: Add bag_size to coffee_inventory_purchased
--
-- Problem: When recording a purchase in AppSheet, there's no way to confirm the
-- bag size of the selected coffee without leaving the form. This column surfaces
-- coffee_source.bag_size directly on the purchase row as a read-only confirmation.
--
-- The column is auto-populated by two existing functions:
--   - compute_coffee_purchase_amount() — fires on INSERT/UPDATE of coffee_source_id
--   - propagate_coffee_source_bag_size() — fires when coffee_source.bag_size changes


-- ─── 1. Add column ────────────────────────────────────────────────────────────

ALTER TABLE public.coffee_inventory_purchased
    ADD COLUMN bag_size text;


-- ─── 2. Backfill existing rows ────────────────────────────────────────────────

UPDATE public.coffee_inventory_purchased p
SET bag_size = cs.bag_size
FROM public.coffee_source cs
WHERE p.coffee_source_id = cs.coffee_source_id;


-- ─── 3. Update compute_coffee_purchase_amount() ───────────────────────────────
-- Already reads coffee_source.bag_size into v_bag_size — now also writes it to
-- the row so it's visible in AppSheet without joining to coffee_source.

CREATE OR REPLACE FUNCTION public.compute_coffee_purchase_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_bag_size NUMERIC;
    v_bag_size_text TEXT;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        -- 1. coffee_source.bag_size (most specific — the actual coffee)
        -- 2. coffee_inventory.bag_size (operative size for this origin category)
        -- 3. 154 (universal fallback)
        SELECT cs.bag_size
        INTO v_bag_size_text
        FROM public.coffee_source cs
        WHERE cs.coffee_source_id = NEW.coffee_source_id
        LIMIT 1;

        v_bag_size := COALESCE(
            v_bag_size_text::numeric,
            (SELECT ci.bag_size::numeric
             FROM public.coffee_inventory ci
             WHERE ci.origin_id = NEW.origin AND ci.facility_id = NEW.facility_id
             LIMIT 1),
            154
        );

        NEW.bag_size := v_bag_size_text;
        NEW.amount   := NEW.bags_ordered * v_bag_size;
    END IF;
    RETURN NEW;
END;
$$;


-- ─── 4. Update propagate_coffee_source_bag_size() ────────────────────────────
-- Already pushes bag_size changes to coffee_inventory. Now also updates
-- coffee_inventory_purchased so the display column stays in sync.

CREATE OR REPLACE FUNCTION public.propagate_coffee_source_bag_size()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    -- Skip if bag_size didn't change or has no value to propagate
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NEW;
    END IF;
    IF NEW.bag_size IS NULL THEN
        RETURN NEW;
    END IF;

    -- Update coffee_inventory (operative bag size for the origin category)
    FOR r IN
        SELECT DISTINCT p.origin, p.facility_id
        FROM public.coffee_inventory_purchased p
        WHERE p.coffee_source_id = NEW.coffee_source_id
          AND p.facility_id IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = NEW.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    -- Update coffee_inventory_purchased display column
    UPDATE public.coffee_inventory_purchased
    SET bag_size = NEW.bag_size
    WHERE coffee_source_id = NEW.coffee_source_id;

    RETURN NEW;
END;
$$;
