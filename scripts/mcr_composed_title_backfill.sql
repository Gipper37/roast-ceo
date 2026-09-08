-- MCR composed-title backfill PROPOSAL (idempotent, additive/guarded)
-- company_id = '9ShiyDAXhV', ACTIVE sources only.
-- Composed title = [country] [region] [grade_label] [process] [+ Decaf]; varietals excluded.
-- REVIEW ONLY -- do not run without explicit approval.

BEGIN;

-- New structured flag for decaf (additive, safe to re-run).
ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = 'Mogiana',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e6cac7ee284067a7'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Brazil Mogiana  =>  Brazil Mogiana

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = 'Mogiana',
    grade_label       = '15/16',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_5de796c028876030'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Brazil Mogiana 15/16  =>  Brazil Mogiana 15/16

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = 'Mogiana',
    grade_label       = '15/17',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_d7988f5e334bbb0f'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Brazil Mogiana 15/17  =>  Brazil Mogiana 15/17

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = 'Mogiana',
    grade_label       = '17/18',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_81f73985aac71db7'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Brazil Mogiana 17/18  =>  Brazil Mogiana 17/18

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = 'Sul de Minas',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_7d11bddf8db2e72d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Brazil Sul De Minas  =>  Brazil Sul de Minas

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = NULL,
    grade_label       = 'Excelso',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_0a84d7ad205487c5'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Colombia Excelso  =>  Colombia Excelso

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = 'Huila',
    grade_label       = 'Supremo',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e59e36a550ac6cfe'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Colombia Hulia Supremo  =>  Colombia Huila Supremo

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = 'Medellin',
    grade_label       = 'Excelso',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_a62b479c16f3a46f'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Colombia Medelin Excelso  =>  Colombia Medellin Excelso

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = NULL,
    grade_label       = 'Supremo',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_1619c377f98171c9'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Colombia Supremo  =>  Colombia Supremo

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Gesha}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_241e8bed4968e9f0'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Colombian Gesha  =>  Colombia

UPDATE coffee_source SET
    country_of_origin = 'Costa Rica',
    region            = 'Tarrazu',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c66f57af57b8205f'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Costa Rica Tarrazu  =>  Costa Rica Tarrazu

UPDATE coffee_source SET
    country_of_origin = 'Brazil',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_23753f1ab6d3f9c9'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Decaf Brazil (FLAVOR)  =>  Brazil Decaf

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_058f4808fbf5f03e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Decaf Colombia (DECAF BLENDS)  =>  Colombia Decaf

UPDATE coffee_source SET
    country_of_origin = 'Mexico',
    region            = 'Esmeralda',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_167feec140bf4ccc'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Decaf Mexico Esmeralda  =>  Mexico Esmeralda Decaf

UPDATE coffee_source SET
    country_of_origin = 'El Salvador',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_214aa09f8d6df8d9'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- El Salvador  =>  El Salvador

UPDATE coffee_source SET
    country_of_origin = 'El Salvador',
    region            = 'Everest',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '15c8cf88-62f9-4dbf-8d3a-eae6854e1c14'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- El Salvador Everest  =>  El Salvador Everest

UPDATE coffee_source SET
    country_of_origin = 'Guatemala',
    region            = NULL,
    grade_label       = 'SHB',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_254a56c3c710f2c2'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Guatemala SHB  =>  Guatemala SHB

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = '#3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '4574235f-7e3a-4bf1-8560-0ce2619e748d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Hawaii Kona No.3  =>  USA Kona #3

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = '#3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_b95b8329674802f0'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Hawaii No.3 (Kona)  =>  USA Kona #3

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Calan',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_f48911ac42eb8b84'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Honduras Calan  =>  Honduras Calan

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Comsa',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_2c416abfbff80f03'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Honduras Comsa  =>  Honduras Comsa

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Copan',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_548695e94eeac96e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Honduras Copan  =>  Honduras Copan

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Siguatepeque',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_fec67ce029c1abd0'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Honduras Siguatepeque  =>  Honduras Siguatepeque

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#16-19',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_419905aff309b85a'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Ka'u #16,17,18,19  =>  USA Ka'u #16-19

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#18',
    process           = 'Honey',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_b12267adaddfb9fb'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Ka'u #18 Semi Washed (Honey)  =>  USA Ka'u #18 Honey

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#19',
    process           = 'Natural',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_a110e005da5a37f0'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Ka'u #19 Natural  =>  USA Ka'u #19 Natural

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = NULL,
    process           = 'Honey',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c46a36549e65eff7'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Ka'u Honey  =>  USA Ka'u Honey

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#18',
    process           = 'Natural',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_22b6cff651892be0'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Ka'u Natutal # 18  =>  USA Ka'u #18 Natural

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#18',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'aae70ef1-a9ce-4152-a760-aabeedfd8dba'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kau 18  =>  USA Ka'u #18

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#18',
    process           = 'Honey',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '4cb216bb-e7e2-4d87-bd69-9674ad39d908'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kau 18 Honey  =>  USA Ka'u #18 Honey

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Ka''u',
    grade_label       = '#19',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '2d7716a7-bbc3-4dff-880c-df2679640626'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kau 19  =>  USA Ka'u #19

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = '#3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e912e88bdc7bb317'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona #3  =>  USA Kona #3

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Castaway Estate',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_54f520e29c3c78d2'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Castaway Estate  =>  USA Kona Castaway Estate

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Castaway Reserve',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_3983ca85110c4fa5'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Castaway Reserve  =>  USA Kona Castaway Reserve

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_3ee355aeaa090e0d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Decaf  =>  USA Kona Decaf

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_cd00fb0683a9171d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Organic  =>  USA Kona

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_5b2aa7260e08ff80'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Peaberry  =>  USA Kona Peaberry

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Prime 16/17',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e2a2740c094d113c'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Prime 16/17  =>  USA Kona Prime 16/17

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Prime 18/19',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_4952616625ead19a'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Prime 18/19  =>  USA Kona Prime 18/19

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = 'Prime Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e8146f2795c12d52'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Kona Prime Peaberry  =>  USA Kona Prime Peaberry

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Mahi Pono H3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '107396af-3b99-4c29-bf49-ecd6e8f05678'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Mahi Pono h3  =>  USA Maui Mahi Pono H3

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Yellow 14',
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_05fece7c03fc47c7'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Dec Yellow 14  =>  USA Maui Yellow 14 Decaf

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'H3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_a6837a97a66e2a7e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui H3  =>  USA Maui H3

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Mokka 11',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Mokka}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_44109ca9903ae026'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Moka 11  =>  USA Maui Mokka 11

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Mokka 14',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Mokka}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_487d98cba93b6956'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Moka 14  =>  USA Maui Mokka 14

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Mokka 11',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Mokka}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'f47482ad-0c29-41e8-a85d-132cf6a61271'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Mokka 11  =>  USA Maui Mokka 11

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Mokka 14',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Mokka}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'b41d7af7-e06d-4ca5-87c8-6b3cc480ac40'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui mokka 14  =>  USA Maui Mokka 14

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red/Yellow Natural/Washed',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_0d41704569f55641'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red / Yellow Natural/Wash  =>  USA Maui Red/Yellow Natural/Washed

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red 14',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_ae0824323728699f'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red 14  =>  USA Maui Red 14

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red',
    process           = 'Washed',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Catuai}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_0f87e935cf02c610'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red Catuai Wash  =>  USA Maui Red Washed

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red H3',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e9a889b35f8b992e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red H3  =>  USA Maui Red H3

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red 16',
    process           = 'Natural',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_4e30e28a5edaac06'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red Natural 16  =>  USA Maui Red 16 Natural

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Red Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_8cac746b77fa5e30'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Red Peaberry  =>  USA Maui Red Peaberry

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Yellow',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'a1b7c502-64c5-4d6e-98a4-9d8745e40e1a'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Yellow  =>  USA Maui Yellow

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Yellow 16',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_d11df67fcd1d3bd9'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Yellow 16  =>  USA Maui Yellow 16

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Yellow H3',
    process           = 'Natural',
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_d793c3dba1f9c7d9'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Yellow H3 Natural  =>  USA Maui Yellow H3 Natural

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Maui',
    grade_label       = 'Yellow Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_bfd0fd07d8f36e9e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Maui Yellow Peaberry  =>  USA Maui Yellow Peaberry

UPDATE coffee_source SET
    country_of_origin = 'Mexico',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = true,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '798a628f-d9d0-42ea-ba65-77629775a8d3'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Mexico Decaf  =>  Mexico Decaf

UPDATE coffee_source SET
    country_of_origin = 'Mexico',
    region            = 'Veracruz',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c8bfd38d18d2a86b'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Mexico Veracruz  =>  Mexico Veracruz

UPDATE coffee_source SET
    country_of_origin = 'Nicaragua',
    region            = 'Olomega',
    grade_label       = 'Supremo',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_7c9c7f0eca21d029'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Nicaragu Olomega Supreme  =>  Nicaragua Olomega Supremo

UPDATE coffee_source SET
    country_of_origin = 'Nicaragua',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Robusta}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_0c03c745fe7bc804'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Nicaragu Robusta  =>  Nicaragua

UPDATE coffee_source SET
    country_of_origin = 'Nicaragua',
    region            = 'Olomega',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = '53b6f685-6a2f-4dcd-b9ad-732aac9fcb12'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Nicaragua Olomega  =>  Nicaragua Olomega

UPDATE coffee_source SET
    country_of_origin = 'Colombia',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_51dc895c7e973ba2'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Colombia  =>  Colombia

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Comsa',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_e58386e99c4408e6'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Honduras Comsa  =>  Honduras Comsa

UPDATE coffee_source SET
    country_of_origin = 'Honduras',
    region            = 'Copan',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_90760e479a2af138'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Honduras Copan  =>  Honduras Copan

UPDATE coffee_source SET
    country_of_origin = 'USA',
    region            = 'Kona',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'd439446a-6523-4365-b18b-3fc98fb48a57'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Kona  =>  USA Kona

UPDATE coffee_source SET
    country_of_origin = 'Mexico',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_211af3db661e89ed'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Mexico  =>  Mexico

UPDATE coffee_source SET
    country_of_origin = 'Nicaragua',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_10b5149aecee5e0d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Nicaragua  =>  Nicaragua

UPDATE coffee_source SET
    country_of_origin = 'Papua New Guinea',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_209100c254f6e64d'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Papua New Guinea  =>  Papua New Guinea

UPDATE coffee_source SET
    country_of_origin = 'Peru',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_1483d3f39c6ded9f'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Peru  =>  Peru

UPDATE coffee_source SET
    country_of_origin = 'Peru',
    region            = 'Selva Andina',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c8a7362b8bc1d2fc'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Peru Selva Andina  =>  Peru Selva Andina

UPDATE coffee_source SET
    country_of_origin = 'Papua New Guinea',
    region            = 'Simbu',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c9f7cf5ed2d057ae'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic PNG Simbu  =>  Papua New Guinea Simbu

UPDATE coffee_source SET
    country_of_origin = 'Timor',
    region            = NULL,
    grade_label       = 'Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{Organic}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_936ef021d0846852'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Organic Timor Peaberry  =>  Timor Peaberry

UPDATE coffee_source SET
    country_of_origin = 'Papua New Guinea',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_27019e3a8b1d2c6a'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Papa New Guinea (not peaberry)  =>  Papua New Guinea

UPDATE coffee_source SET
    country_of_origin = 'Papua New Guinea',
    region            = NULL,
    grade_label       = 'Peaberry',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = true,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_d2bed255e650be0e'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Papa New Guinea Peaberry  =>  Papua New Guinea Peaberry

UPDATE coffee_source SET
    country_of_origin = 'Peru',
    region            = 'APROCCURMA Cafe de Mujer',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{Organic,Fair Trade}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_9e22c4ecd79db3bb'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- PERU FT-FLO/USA ORGANIC CAFE DE MUJER APROCCURMA  =>  Peru APROCCURMA Cafe de Mujer

UPDATE coffee_source SET
    country_of_origin = 'Peru',
    region            = 'Vida Alta',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_c3692df4e5b76f59'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Peru Vida Alta  =>  Peru Vida Alta

UPDATE coffee_source SET
    country_of_origin = 'Sumatra',
    region            = NULL,
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_ce35b4d21f498f12'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Sumatra  =>  Sumatra

UPDATE coffee_source SET
    country_of_origin = 'Sumatra',
    region            = 'Takengon & Sulawesi',
    grade_label       = NULL,
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_b39931a7edd8a6e3'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Sumatra Takengon & Sulawesi  =>  Sumatra Takengon & Sulawesi

UPDATE coffee_source SET
    country_of_origin = 'Yemen',
    region            = NULL,
    grade_label       = 'Mocca',
    process           = NULL,
    is_decaf          = false,
    is_peaberry       = false,
    certifications    = '{}'::text[],
    varietals         = '{Mokka}'::text[],
    updated_at        = now()
WHERE coffee_source_id = 'csrc_f9c78ea8c2cdba62'
  AND company_id = '9ShiyDAXhV' AND is_active;  -- Yemen Mocca  =>  Yemen Mocca

COMMIT;
