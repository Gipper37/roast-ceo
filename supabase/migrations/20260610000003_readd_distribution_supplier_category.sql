-- Re-add Distribution as a supplier category.
-- 20260610000002 removed it on the (mistaken) assumption it should only be a
-- consumable type. It's needed as BOTH: a consumable type (for distributed
-- items) AND a supplier category (for suppliers that distribute to cafes —
-- Monin, Bhakti Chai, Meraki, Guittard, etc.). This re-adds the supplier
-- category and restores the MCR distribution-supplier assignments.

INSERT INTO public.supplier_category (supplier_category_id, supplier_category, company_id)
VALUES ('Ds7mKP', 'Distribution', NULL)
ON CONFLICT (supplier_category_id) DO NOTHING;

-- Restore MCR's distribution suppliers (reverted to Consumables by 00002)
UPDATE public.supplier
SET supplier_category = 'Ds7mKP'
WHERE company_id = '9ShiyDAXhV'
  AND supplier IN (
    'Monin - INV I25', 'Monin - INV I26', 'Bhakti Chai',
    'Meraki Tea', 'Guittard - SO126396', 'John D Walsh Co. Flavor'
  );
