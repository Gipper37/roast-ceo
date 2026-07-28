-- "Distribution" → "Resale" for the consumable type that means bought-and-resold.
--
-- This is the one consumable type that is NOT consumed in production: it's stock a
-- roaster buys wholesale and sells on as-is (syrups, matcha, merch). Since the
-- consumable/product unification it already IS a product — a product_groups row with
-- a variant linked back via products.source_consumable_id — and the consumable
-- record is just its stock-and-cost ledger.
--
-- "Distribution" is internal jargon; nobody in a roastery says it out loud, and it
-- describes a logistics function rather than what the operator is actually marking:
-- this is for resale. "Resale" is one word, it's what the trade and the accountants
-- say ("we buy it for resale"), and it's already the vocabulary of this schema —
-- customers.resale_number and customers.resale_cert_received.
--
-- The ID (global_consumable_type_distribution) is deliberately UNCHANGED: it is an
-- FK target on 80 live MCR consumable_inventory rows and is referenced by name in
-- application code. Only the human-facing label moves.
--
-- Checked before writing: no DB function or view compares against the 'Distribution'
-- string, and supplier_category's separate "Distribution" row (Ds7mKP) is a
-- different concept — the KIND OF SUPPLIER you buy from — and is left alone.

update public.consumable_type
set consumable_type = 'Resale'
where consumable_type_id = 'global_consumable_type_distribution'
  and consumable_type is distinct from 'Resale';
