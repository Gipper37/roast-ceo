-- Create stock_types reference table and FK from roast_stock_log
--
-- Replaces the CHECK constraint on roast_stock_log.stock_type with a proper FK
-- to a lookup table. Stable lowercase IDs ('blend', 'origin') are stored in the
-- column; the label column ('Blend', 'Origin') is what AppSheet and the future
-- proprietary frontend display in dropdowns.
-- Changing a display label = one row UPDATE, no schema migration needed.

-- ─── 1. Create stock_types lookup table ──────────────────────────────────────

CREATE TABLE public.stock_types (
    stock_type_id  text     NOT NULL,
    label          text     NOT NULL,
    sort_order     integer,
    CONSTRAINT stock_types_pkey PRIMARY KEY (stock_type_id)
);

-- ─── 2. Seed rows ─────────────────────────────────────────────────────────────

INSERT INTO public.stock_types (stock_type_id, label, sort_order) VALUES
    ('blend',  'Blend',  1),
    ('origin', 'Origin', 2);

-- ─── 3. Update roast_stock_log ────────────────────────────────────────────────
-- Drop the CHECK constraint (FK now enforces valid values)
-- Keep roast_stock_log_ids_check — still valid, references same 'blend'/'origin' IDs
-- Add FK to stock_types

ALTER TABLE public.roast_stock_log
    DROP CONSTRAINT roast_stock_log_type_check,
    ADD CONSTRAINT roast_stock_log_stock_type_fk
        FOREIGN KEY (stock_type) REFERENCES public.stock_types (stock_type_id);
