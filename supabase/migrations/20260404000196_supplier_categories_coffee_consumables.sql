-- Rename supplier categories to Coffee / Consumables
-- GG1a6L (Local By Each) → Coffee
-- PlmoC2 (Remote By Pallet/Case) → Consumables
-- Fr1WMM (Remote By Each) → delete (unused)

UPDATE public.supplier_category
SET supplier_category = 'Coffee'
WHERE supplier_category_id = 'GG1a6L';

UPDATE public.supplier_category
SET supplier_category = 'Consumables'
WHERE supplier_category_id = 'PlmoC2';

DELETE FROM public.supplier_category
WHERE supplier_category_id = 'Fr1WMM';

-- Move Royal Coffee into the Coffee category
UPDATE public.supplier
SET supplier_category = 'GG1a6L'
WHERE supplier_id = 'BiSv0a';
