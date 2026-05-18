-- ============================================================
-- Global parts catalog — strip to confirmed-real data only
-- ============================================================
-- Background: the original seed (00021) included synthesized part
-- numbers, retailer-sourced suppliers, and estimated mid-2026 street
-- prices. None of those were grounded in real OEM catalogs and they
-- go stale immediately. This migration honors the rule "if you can't
-- confirm it's real, leave it blank."
--
-- What we keep on every global row:
--   part_name        — real / standardized terminology
--   category         — unchanged
--   applies_to_brand — kept where the model is genuinely brand-locked
--
-- What we strip across the board:
--   part_number      — NULL (all original SKUs were invented)
--   default_unit_cost — NULL (no authoritative pricing source)
--   default_markup_pct — 0 (rely on company default fallback)
--   notes            — NULL except a tiny whitelist of useful specs
--
-- Supplier is whitelisted to manufacturers of single-source items:
--   Mahlkönig, Mazzer, Eureka, Loring, Probat, Diedrich, BWT,
--   Pentair, 3M, Urnex, Puly. Retailer / multi-source fields → NULL.
--
-- "CafiBlu" was a hallucinated brand and is removed.
-- ============================================================

-- 1. Bulk wipe: strip all fake numbers + retailer suppliers from globals.
UPDATE public.parts_catalog
SET part_number        = NULL,
    default_unit_cost  = NULL,
    default_markup_pct = 0,
    supplier           = NULL,
    notes              = NULL
WHERE company_id IS NULL;


-- 2. Restore supplier ONLY where it equals the manufacturer of a
--    genuinely single-source item.
UPDATE public.parts_catalog SET supplier = 'Mahlkönig' WHERE company_id IS NULL AND part_id IN (
  'part_burrs_ek43_98mm', 'part_burrs_e80_80mm', 'part_burrs_e65_64mm'
);
UPDATE public.parts_catalog SET supplier = 'Mazzer' WHERE company_id IS NULL AND part_id IN (
  'part_burrs_robur_71mm', 'part_burrs_major_83mm', 'part_burrs_kony_71mm', 'part_burrs_super_jolly'
);
UPDATE public.parts_catalog SET supplier = 'Eureka'   WHERE company_id IS NULL AND part_id = 'part_burrs_atom_75';
UPDATE public.parts_catalog SET supplier = 'Loring'   WHERE company_id IS NULL AND part_id = 'part_drum_gasket_loring_s15';
UPDATE public.parts_catalog SET supplier = 'Probat'   WHERE company_id IS NULL AND part_id = 'part_drum_gasket_probat_l12';
UPDATE public.parts_catalog SET supplier = 'Diedrich' WHERE company_id IS NULL AND part_id = 'part_drum_gasket_diedrich';
UPDATE public.parts_catalog SET supplier = 'BWT'      WHERE company_id IS NULL AND part_id = 'part_water_filter_bwt';
UPDATE public.parts_catalog SET supplier = 'Pentair'  WHERE company_id IS NULL AND part_id IN (
  'part_water_filter_cuno', 'part_wf_pentair_h300'
);
UPDATE public.parts_catalog SET supplier = '3M'       WHERE company_id IS NULL AND part_id = 'part_wf_3m_hf45';
UPDATE public.parts_catalog SET supplier = 'Urnex'    WHERE company_id IS NULL AND part_id IN (
  'part_cafiza_bottle', 'part_rinza_bottle', 'part_grindz_jar'
);
UPDATE public.parts_catalog SET supplier = 'Puly'     WHERE company_id IS NULL AND part_id = 'part_descaler_puly';


-- 3. Drop hallucinated rows. "CafiBlu" was invented — the brewer
--    descaler category exists but the specific product doesn't.
DELETE FROM public.maintenance_template_part
  WHERE part_id = 'part_brewer_descaler';
DELETE FROM public.parts_catalog
  WHERE company_id IS NULL AND part_id = 'part_brewer_descaler';


-- 4. Fix name accuracy issues found during audit:
--      - "Drum face gasket" → "Drum gasket" (correct terminology)
--      - E65 burr diameter is 65mm not 64mm
--      - Curtis/Bunn brewer filters: real products exist but I don't
--        know the OEM SKUs, so generic descriptors are honest
UPDATE public.parts_catalog
  SET part_name = 'Drum gasket — Loring S15'
  WHERE company_id IS NULL AND part_id = 'part_drum_gasket_loring_s15';
UPDATE public.parts_catalog
  SET part_name = 'Burrs — E65 (65mm flat)'
  WHERE company_id IS NULL AND part_id = 'part_burrs_e65_64mm';
UPDATE public.parts_catalog
  SET part_name = 'Brewer water filter (Wilbur Curtis)'
  WHERE company_id IS NULL AND part_id = 'part_brewer_filter_curtis';
UPDATE public.parts_catalog
  SET part_name = 'Brewer water filter (BUNN)'
  WHERE company_id IS NULL AND part_id = 'part_brewer_filter_bunn';

COMMENT ON COLUMN public.parts_catalog.default_unit_cost IS
  'Default wholesale (vendor → roaster) cost. NULL on global rows by policy — tenants set their own pricing from real invoices via per-tenant override.';
COMMENT ON COLUMN public.parts_catalog.default_markup_pct IS
  'Default markup applied on top of unit_cost when billing customers. Sell price = unit_cost × (1 + markup/100). When 0 on a tenant row, the company-wide default applies (fallback) or overrides (flat-markup mode).';
