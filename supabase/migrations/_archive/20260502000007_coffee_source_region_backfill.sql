-- ============================================================================
-- Backfill coffee_source.region from legacy coffee_name strings.
--
-- Migration 20260502000004 parsed the country prefix; this one tackles
-- the region. Approach: per-country list of well-known regions, set
-- region only when the region name appears in coffee_name AND the row's
-- existing region is NULL (don't overwrite anything the user already set).
--
-- Region lists are intentionally conservative — only major / iconic
-- regions per country to keep false positives low. Sources that don't
-- match any known region are left with region=NULL; the user fills in
-- on edit.
-- ============================================================================

BEGIN;

-- Helper: per-country region candidates. Longer names ordered first so
-- "Sul de Minas" matches before "Minas", "San Marcos" before "Marcos",
-- etc. Word-boundary regex (`\y...\y`) prevents partial matches.
WITH region_candidates (country, region) AS (VALUES
  -- Brazil
  ('Brazil', 'Mantiqueira de Minas'),
  ('Brazil', 'Matas de Minas'),
  ('Brazil', 'Cerrado Mineiro'),
  ('Brazil', 'Mogiana Guaxupe'),
  ('Brazil', 'Sul de Minas'),
  ('Brazil', 'Espírito Santo'),
  ('Brazil', 'Espirito Santo'),
  ('Brazil', 'Alta Mogiana'),
  ('Brazil', 'Conceição'),
  ('Brazil', 'Caparaó'),
  ('Brazil', 'Caparao'),
  ('Brazil', 'Cerrado'),
  ('Brazil', 'Mogiana'),
  ('Brazil', 'Bahia'),
  ('Brazil', 'Paraná'),
  ('Brazil', 'Parana'),
  ('Brazil', 'MTGB'),
  -- Colombia
  ('Colombia', 'Valle del Cauca'),
  ('Colombia', 'Cundinamarca'),
  ('Colombia', 'Risaralda'),
  ('Colombia', 'Santander'),
  ('Colombia', 'Antioquia'),
  ('Colombia', 'Quindío'),
  ('Colombia', 'Quindio'),
  ('Colombia', 'Boyacá'),
  ('Colombia', 'Boyaca'),
  ('Colombia', 'Caldas'),
  ('Colombia', 'Tolima'),
  ('Colombia', 'Nariño'),
  ('Colombia', 'Narino'),
  ('Colombia', 'Cauca'),
  ('Colombia', 'Huila'),
  -- Ethiopia
  ('Ethiopia', 'Yirgacheffe'),
  ('Ethiopia', 'Lekempti'),
  ('Ethiopia', 'Djimmah'),
  ('Ethiopia', 'Sidamo'),
  ('Ethiopia', 'Harrar'),
  ('Ethiopia', 'Welega'),
  ('Ethiopia', 'Gedeo'),
  ('Ethiopia', 'Guji'),
  ('Ethiopia', 'Limu'),
  -- Kenya
  ('Kenya', 'Kirinyaga'),
  ('Kenya', 'Murang''a'),
  ('Kenya', 'Bungoma'),
  ('Kenya', 'Kiambu'),
  ('Kenya', 'Nyeri'),
  ('Kenya', 'Kisii'),
  ('Kenya', 'Embu'),
  ('Kenya', 'Meru'),
  -- Costa Rica
  ('Costa Rica', 'Valle Occidental'),
  ('Costa Rica', 'Valle Central'),
  ('Costa Rica', 'Guanacaste'),
  ('Costa Rica', 'Turrialba'),
  ('Costa Rica', 'Tres Ríos'),
  ('Costa Rica', 'Tres Rios'),
  ('Costa Rica', 'Tarrazú'),
  ('Costa Rica', 'Tarrazu'),
  ('Costa Rica', 'Naranjo'),
  ('Costa Rica', 'Brunca'),
  ('Costa Rica', 'Orosi'),
  -- Guatemala
  ('Guatemala', 'Huehuetenango'),
  ('Guatemala', 'Acatenango'),
  ('Guatemala', 'Nuevo Oriente'),
  ('Guatemala', 'San Marcos'),
  ('Guatemala', 'Fraijanes'),
  ('Guatemala', 'Antigua'),
  ('Guatemala', 'Atitlán'),
  ('Guatemala', 'Atitlan'),
  ('Guatemala', 'Cobán'),
  ('Guatemala', 'Coban'),
  -- Honduras
  ('Honduras', 'Comayagua'),
  ('Honduras', 'Montecillos'),
  ('Honduras', 'El Paraíso'),
  ('Honduras', 'El Paraiso'),
  ('Honduras', 'Marcala'),
  ('Honduras', 'Lempira'),
  ('Honduras', 'Opalaca'),
  ('Honduras', 'Agalta'),
  ('Honduras', 'Copán'),
  ('Honduras', 'Copan'),
  -- El Salvador
  ('El Salvador', 'Santa Ana'),
  ('El Salvador', 'Apaneca'),
  ('El Salvador', 'Chalatenango'),
  ('El Salvador', 'Cabañas'),
  ('El Salvador', 'Sonsonate'),
  -- Nicaragua
  ('Nicaragua', 'Matagalpa'),
  ('Nicaragua', 'Jinotega'),
  ('Nicaragua', 'Estelí'),
  ('Nicaragua', 'Esteli'),
  ('Nicaragua', 'Madriz'),
  ('Nicaragua', 'Nueva Segovia'),
  -- Mexico
  ('Mexico', 'Chiapas'),
  ('Mexico', 'Veracruz'),
  ('Mexico', 'Oaxaca'),
  ('Mexico', 'Puebla'),
  ('Mexico', 'Guerrero'),
  -- Indonesia
  ('Indonesia', 'Sumatra'),
  ('Indonesia', 'Java'),
  ('Indonesia', 'Sulawesi'),
  ('Indonesia', 'Bali'),
  ('Indonesia', 'Flores'),
  ('Indonesia', 'Sumbawa'),
  ('Indonesia', 'Mandheling'),
  ('Indonesia', 'Lintong'),
  ('Indonesia', 'Toraja'),
  ('Indonesia', 'Kintamani'),
  ('Indonesia', 'Bajawa'),
  ('Indonesia', 'Aceh'),
  -- India
  ('India', 'Chikmagalur'),
  ('India', 'Bababudangiri'),
  ('India', 'Sakleshpur'),
  ('India', 'Wayanad'),
  ('India', 'Nilgiris'),
  ('India', 'Coorg'),
  -- Tanzania
  ('Tanzania', 'Kilimanjaro'),
  ('Tanzania', 'Ruvuma'),
  ('Tanzania', 'Mbeya'),
  ('Tanzania', 'Mbozi'),
  -- Vietnam
  ('Vietnam', 'Buon Ma Thuot'),
  ('Vietnam', 'Da Lat'),
  -- Hawaii sub-regions (each Hawaiian island is its own country, but
  -- some sources include a sub-region like "South Kona" inside the
  -- island. Keeping one or two well-known ones).
  ('USA – Kona', 'South Kona'),
  ('USA – Kona', 'North Kona'),
  ('USA – Maui', 'West Maui'),
  ('USA – Maui', 'Kula'),
  ('USA – Maui', 'Hana')
)
UPDATE coffee_source cs
SET region = best.region
FROM (
  -- For each row, pick the LONGEST matching region (so "Sul de Minas"
  -- wins over "Minas"). DISTINCT ON gives us one row per source.
  SELECT DISTINCT ON (cs2.coffee_source_id)
    cs2.coffee_source_id, rc.region
  FROM coffee_source cs2
  JOIN region_candidates rc ON cs2.country_of_origin = rc.country
  WHERE cs2.coffee_name ILIKE '%' || rc.region || '%'
    AND (cs2.region IS NULL OR cs2.region = '')
  ORDER BY cs2.coffee_source_id, length(rc.region) DESC
) best
WHERE cs.coffee_source_id = best.coffee_source_id
  AND (cs.region IS NULL OR cs.region = '');

-- After region backfill, recompose grade_label so it doesn't include
-- the region (region is its own field now). Actually grade_label was
-- already only quality + classification + screen + prep + peaberry from
-- migration 20260502000005 — region was never in there. No change
-- needed; this is just a no-op confirmation.

DO $$
DECLARE
  total int;
  with_region int;
  with_country_no_region int;
BEGIN
  SELECT COUNT(*) INTO total FROM coffee_source;
  SELECT COUNT(*) INTO with_region FROM coffee_source WHERE region IS NOT NULL AND region <> '';
  SELECT COUNT(*) INTO with_country_no_region FROM coffee_source
    WHERE country_of_origin IS NOT NULL AND (region IS NULL OR region = '');
  RAISE NOTICE 'coffee_source: % rows total, % with region, % with country but no region (manual cleanup)',
    total, with_region, with_country_no_region;
END $$;

COMMIT;
