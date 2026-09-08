-- MCR coffee_source cleanup — archive dup/typos + safe additive backfill.
-- Approved 2026-06-23. Reversible (soft archive + additive only); snapshot in
-- scripts/mcr_coffee_archive_backfill_snapshot_2026-06-23.tsv.
-- NO flavor-group rows (that was NO-GO — pollutes ~9 surfaces).
BEGIN;

-- 1. Archive dup/typo sources (soft is_active=false). All 8 verified 0-purchase.
--    PNG: archive the proper-cased cert-only row; the lowercase row (which has
--    country) is KEPT + fixed below. Maui peaberries: archive the 0-purchase /
--    no-country dup, keep the 1-purchase real one.
UPDATE coffee_source SET is_active = false, updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND is_active AND coffee_source_id IN (
  'e498f99c-8cbb-4ff2-bb46-521f52eae9a4', -- Brazil Alta Mogiana 17/18
  'b70fd2e2-bf3e-4cbe-a9f0-5f61b6fb51e5', -- Brazil SS FC 15/16
  'b33fe4ed-308f-4606-92ba-f5adc86284a1', -- Guatemala (bare)
  'csrc_42bc54fd2e84d170',                -- Mexico (bare)
  'csrc_c3d0eb4019e21b9b',                -- Nicaragu a Segovia (typo)
  '39b0d699-07ce-4511-93a1-2d4427c31a4b', -- Organic Papa New Guinea (dup, cert-only)
  '1386d9fe-da72-4469-8e95-64b170f7dd92', -- Maui Red Peaberry (0-purchase dup)
  '32eef649-9bb9-404e-b50d-e12dcbfa6691'  -- Maui Yellow Peaberry (0-purchase dup)
);

-- 2. PNG keeper: fix casing Papa->Papua + add the Organic cert it lost to the
--    archived dup. (Country already present.)
UPDATE coffee_source
SET coffee_name = 'Organic Papua New Guinea',
    certifications = CASE WHEN NOT ('Organic' = ANY(certifications))
                         THEN array_append(certifications, 'Organic') ELSE certifications END,
    updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND coffee_source_id = 'csrc_209100c254f6e64d';

-- 3. Process backfill (additive; only where currently NULL). Honey first so a
--    "Semi Washed (Honey)" reads as Honey. The ambiguous mixed label
--    'Maui Red / Yellow Natural/Wash' is excluded (left NULL).
UPDATE coffee_source SET process = 'Honey', updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND is_active AND process IS NULL
  AND coffee_name ILIKE '%honey%';
UPDATE coffee_source SET process = 'Natural', updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND is_active AND process IS NULL
  AND coffee_name ILIKE '%natural%' AND coffee_name <> 'Maui Red / Yellow Natural/Wash';
UPDATE coffee_source SET process = 'Washed', updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND is_active AND process IS NULL
  AND coffee_name ILIKE '%wash%' AND coffee_name <> 'Maui Red / Yellow Natural/Wash';

-- 4. Organic cert backfill (additive; any active source named Organic that
--    isn't already tagged). Covers Kona Organic, Organic Timor Peaberry, etc.
UPDATE coffee_source
SET certifications = array_append(certifications, 'Organic'), updated_at = now()
WHERE company_id = '9ShiyDAXhV' AND is_active
  AND coffee_name ILIKE '%organic%' AND NOT ('Organic' = ANY(certifications));

COMMIT;
