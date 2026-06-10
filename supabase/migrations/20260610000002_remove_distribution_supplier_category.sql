-- Undo: Distribution was mistakenly added as a SUPPLIER category in
-- 20260609000003. It belongs as a CONSUMABLE type (added in
-- 20260610000001), not a supplier category.
--
-- Revert any suppliers assigned to the bad Distribution category back to
-- Consumables, then remove the category row. The global-read policy added
-- in 20260609000003 stays — it fixed a real bug (category IDs showing
-- instead of names).

UPDATE public.supplier
SET supplier_category = 'PlmoC2'   -- Consumables
WHERE supplier_category = 'Ds7mKP';

DELETE FROM public.supplier_category
WHERE supplier_category_id = 'Ds7mKP';
