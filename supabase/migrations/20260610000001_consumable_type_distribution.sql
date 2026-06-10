-- Add Distribution as a global consumable type.
-- For items a roaster resells / distributes to cafes (Monin syrups, chai
-- concentrates, teas, chocolate sauces) — distinct from BOM packaging,
-- BOM flavoring, and internal operational supplies.
INSERT INTO public.consumable_type (consumable_type_id, consumable_type, company_id)
VALUES ('global_consumable_type_distribution', 'Distribution', NULL)
ON CONFLICT (consumable_type_id) DO NOTHING;
