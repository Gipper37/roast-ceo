-- MCR coffee-group cleanup (grounded by workflow w92jsea0v, 2026-06-23).
--
-- FINDING: MCR's group structure is already correct — single-origin country
-- homes + Hawaiian estate sub-lines, with blends living in recipes (not groups).
-- There is NO flavor taxonomy to build. Work = cleanup only:
--   1. Re-home the retired "Maui" parent (orig_142ffc976e750f22) footprint:
--      - its one 957.5 lb lot + that lot's source  -> Maui Red  (both recipes
--        on the parent are "Maui Red Bag" 100% + "Mama's Maui Red" -> Red)
--      - its 2 archived Mokka sources               -> Maui Moka
--      - its 2 recipe components                    -> Maui Red
--   2. Archive the empty Timor group (Kona parent already archived + empty).
--
-- DELIBERATELY NOT repointing the 4 old roast_log.origin_id rows: that UPDATE
-- fires trg_lot_consumption_recompute -> recompute(Maui Red), which re-seeds
-- against Maui Red's 2026-06-12 count anchor and would ZERO the re-homed 957.5 lb
-- lot (it has no count row at that anchor + predates it). Those roasts are
-- pre-count historical garbage and a physical recount is coming, so leaving them
-- on the archived parent is harmless. Plain origin/origin_id/coffee_item repoints
-- do NOT fire a recompute, so remaining_lbs is preserved; totals are refreshed
-- with recalculate_origin_total_stock (SUM of lots, no re-seed, no zeroing).

-- 1a. the 957.5 lb lot -> Maui Red (preserve remaining_lbs)
UPDATE public.coffee_inventory_purchased
   SET origin = 'orig_mcr_maui_red'
 WHERE origin_purchase_id = '562d98ab-5ec0-416c-a403-66383b344729';

-- 1b. that lot's source ("USA - Maui Red / Yellow Natural / Washed") -> Maui Red
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_red'
 WHERE coffee_source_id = 'csrc_0d41704569f55641';

-- 1c. the 2 archived Mokka sources -> Maui Moka
UPDATE public.coffee_source SET origin_id = 'orig_mcr_maui_moka'
 WHERE coffee_source_id IN ('b41d7af7-e06d-4ca5-87c8-6b3cc480ac40',
                            'f47482ad-0c29-41e8-a85d-132cf6a61271');

-- 1d. the 2 recipe components (Maui Red Bag, Mama's Maui Red) -> Maui Red
UPDATE public.recipe_components SET coffee_item = 'orig_mcr_maui_red'
 WHERE coffee_item = 'orig_142ffc976e750f22';

-- 2. archive the empty Timor group
UPDATE public.coffee_inventory SET is_active = false
 WHERE origin_id = 'orig_48164153d732217b';

-- refresh totals for the 3 touched live groups + the now-empty parent (SUM-based)
SELECT public.recalculate_origin_total_stock('orig_mcr_maui_red',
         (SELECT facility_id FROM public.coffee_inventory WHERE origin_id='orig_mcr_maui_red' LIMIT 1));
SELECT public.recalculate_origin_total_stock('orig_mcr_maui_moka',
         (SELECT facility_id FROM public.coffee_inventory WHERE origin_id='orig_mcr_maui_moka' LIMIT 1));
SELECT public.recalculate_origin_total_stock('orig_142ffc976e750f22',
         (SELECT facility_id FROM public.coffee_inventory WHERE origin_id='orig_142ffc976e750f22' LIMIT 1));
