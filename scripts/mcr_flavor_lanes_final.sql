-- =====================================================================
-- MCR Coffee Source / Flavor-Group project — FINAL idempotent SQL
-- Company: 9ShiyDAXhV   Facility: 5cc581b9-2803-42c2-98de-0ba16ae42f8e
-- Safe to re-run. READ-ONLY review artifact until explicitly executed.
--
-- invSafety = {"safe": false}.  Per its recommendation we DO NOT insert
-- bare stockless rows into coffee_inventory. Instead we add the mitigation
-- column `is_group boolean NOT NULL DEFAULT false` and insert the 4 flavor
-- groups behind that flag (origin_id/company_id/facility_id/origin set).
-- Frontend/view leak-sites (the ~9 filter sites in invSafety.filterSites)
-- MUST be patched separately before this is considered user-visible-safe;
-- the flag is the prerequisite for those patches.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0) MITIGATION COLUMN (idempotent): discriminator for virtual group rows
-- ---------------------------------------------------------------------
ALTER TABLE public.coffee_inventory
  ADD COLUMN IF NOT EXISTS is_group boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.coffee_inventory.is_group IS
  'TRUE = virtual flavor-group row (e.g. Chocolate), NOT a physical green coffee. Must be filtered out of inventory lists, roast-logger origin pickers, data_quality_issues, and stock matviews. See coffee_source.allowed_origin_ids flavor lanes.';

-- ---------------------------------------------------------------------
-- 1) INSERT the 4 flavor-group rows (stockless, flagged is_group=true)
--    PK = origin_id, so ON CONFLICT (origin_id) DO NOTHING is idempotent.
--    par/restock_level/in_stock are auto-zeroed by the INSERT triggers;
--    is_group (not those) is the discriminator.
-- ---------------------------------------------------------------------
INSERT INTO public.coffee_inventory (origin_id, origin, company_id, facility_id, is_active, is_group)
VALUES
  ('orig_mcr_grp_brazil',       'Brazil (Base)', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, true),
  ('orig_mcr_grp_chocolate',    'Chocolate',     '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, true),
  ('orig_mcr_grp_fruit',        'Fruit',         '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, true),
  ('orig_mcr_grp_organic_fruit','Organic Fruit', '9ShiyDAXhV', '5cc581b9-2803-42c2-98de-0ba16ae42f8e', true, true)
ON CONFLICT (origin_id) DO NOTHING;

-- Re-run safety: ensure flag/origin label correct even if rows pre-existed.
UPDATE public.coffee_inventory
SET is_group = true
WHERE origin_id IN ('orig_mcr_grp_brazil','orig_mcr_grp_chocolate','orig_mcr_grp_fruit','orig_mcr_grp_organic_fruit')
  AND company_id = '9ShiyDAXhV'
  AND is_group IS DISTINCT FROM true;

-- ---------------------------------------------------------------------
-- 3) ARCHIVE exactly the 6 spreadsheet dups/typos. (Numbered #3 here to
--    match plan ordering; runs before the lane appends so archived rows
--    are never lane-tagged.) ASSERT exactly 6 match, else ABORT.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n
  FROM public.coffee_source
  WHERE company_id = '9ShiyDAXhV'
    AND is_active
    AND coffee_name IN (
      'Brazil Alta Mogiana 17/18',
      'Brazil SS FC 15/16',
      'Guatemala',
      'Mexico',
      'Nicaragu a Segovia',
      'Organic Papa New Guinea'
    );
  IF n <> 6 THEN
    RAISE EXCEPTION 'ABORT: expected exactly 6 active archive-target rows, found %. Refusing to archive.', n;
  END IF;
END $$;

UPDATE public.coffee_source
SET is_active = false
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND coffee_name IN (
    'Brazil Alta Mogiana 17/18',
    'Brazil SS FC 15/16',
    'Guatemala',
    'Mexico',
    'Nicaragu a Segovia',
    'Organic Papa New Guinea'
  );

-- ---------------------------------------------------------------------
-- 2) APPEND flavor-group origin_id(s) to allowed_origin_ids (dedup).
--    Helper pattern: only append when not already present, so re-runs are
--    no-ops. Each source KEEPS its country origin_id as primary.
--    Scoped to is_active so archived rows (step 3) are never tagged.
-- ---------------------------------------------------------------------

-- BRAZIL (Base): non-organic Brazil + non-organic Mexico
UPDATE public.coffee_source
SET allowed_origin_ids =
      array_append(COALESCE(allowed_origin_ids, '{}'), 'orig_mcr_grp_brazil')
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND NOT ('orig_mcr_grp_brazil' = ANY(COALESCE(allowed_origin_ids, '{}')))
  AND coffee_name IN (
    -- Brazil non-organic
    'Brazil Mogiana','Brazil Mogiana 15/16','Brazil Mogiana 15/17','Brazil Mogiana 17/18','Brazil Sul De Minas',
    -- Mexico non-organic
    'Mexico Veracruz'
  );

-- CHOCOLATE: non-organic Colombia + non-organic Honduras + non-organic Peru
UPDATE public.coffee_source
SET allowed_origin_ids =
      array_append(COALESCE(allowed_origin_ids, '{}'), 'orig_mcr_grp_chocolate')
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND NOT ('orig_mcr_grp_chocolate' = ANY(COALESCE(allowed_origin_ids, '{}')))
  AND coffee_name IN (
    -- Colombia non-organic
    'Colombia Excelso','Colombia Hulia Supremo','Colombia Medelin Excelso','Colombia Supremo','Colombian Gesha',
    -- Honduras non-organic (primary stays Honduras, Chocolate is added)
    'Honduras Calan','Honduras Comsa','Honduras Copan','Honduras Siguatepeque',
    -- Peru non-organic
    'Peru Vida Alta'
  );

-- FRUIT: non-organic Costa Rica + El Salvador + Guatemala + Nicaragua
UPDATE public.coffee_source
SET allowed_origin_ids =
      array_append(COALESCE(allowed_origin_ids, '{}'), 'orig_mcr_grp_fruit')
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND NOT ('orig_mcr_grp_fruit' = ANY(COALESCE(allowed_origin_ids, '{}')))
  AND coffee_name IN (
    -- Costa Rica
    'Costa Rica Tarrazu',
    -- El Salvador
    'El Salvador','El Salvador Everest',
    -- Guatemala non-organic (bare "Guatemala" archived above)
    'Guatemala SHB',
    -- Nicaragua non-organic (primary stays Nicaragua, Fruit is added)
    'Nicaragu Olomega Supreme','Nicaragu Robusta','Nicaragua Olomega'
  );

-- ORGANIC FRUIT: organic Peru + organic Mexico
UPDATE public.coffee_source
SET allowed_origin_ids =
      array_append(COALESCE(allowed_origin_ids, '{}'), 'orig_mcr_grp_organic_fruit')
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND NOT ('orig_mcr_grp_organic_fruit' = ANY(COALESCE(allowed_origin_ids, '{}')))
  AND coffee_name IN (
    -- Organic Peru
    'Organic Peru','Organic Peru Selva Andina','PERU FT-FLO/USA ORGANIC CAFE DE MUJER APROCCURMA',
    -- Organic Mexico
    'Organic Mexico'
  );

-- ---------------------------------------------------------------------
-- 4) SAFE-ADDITIVE BACKFILL (never touches display name)
-- ---------------------------------------------------------------------

-- 4a) certifications += 'Organic' for any active source whose name contains
--     "Organic" or "ORG" (case-insensitive), if not already present.
UPDATE public.coffee_source
SET certifications = array_append(COALESCE(certifications, '{}'), 'Organic')
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND (coffee_name ILIKE '%organic%' OR coffee_name ~* '\mORG\M')
  AND NOT ('Organic' = ANY(COALESCE(certifications, '{}')));

-- 4b) process: set ONLY when unambiguous from name. Never overwrite an
--     existing non-null process. Leave null when ambiguous.
--     Honey: names containing "Honey".
UPDATE public.coffee_source
SET process = 'Honey'
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND process IS NULL
  AND coffee_name ILIKE '%honey%';

--     Natural: names containing "Natural" but NOT "Semi Washed"/"Wash"
--     (skip mixed "Natural/Wash" labels — ambiguous).
UPDATE public.coffee_source
SET process = 'Natural'
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND process IS NULL
  AND coffee_name ILIKE '%natural%'
  AND coffee_name NOT ILIKE '%wash%'
  AND coffee_name NOT ILIKE '%honey%';

--     Washed: names containing standalone "Washed"/"Wash" but NOT
--     "Natural", NOT "Semi Washed" (semi-washed != washed), NOT "Honey".
UPDATE public.coffee_source
SET process = 'Washed'
WHERE company_id = '9ShiyDAXhV'
  AND is_active
  AND process IS NULL
  AND coffee_name ILIKE '%wash%'
  AND coffee_name NOT ILIKE '%semi washed%'
  AND coffee_name NOT ILIKE '%natural%'
  AND coffee_name NOT ILIKE '%honey%';

COMMIT;
