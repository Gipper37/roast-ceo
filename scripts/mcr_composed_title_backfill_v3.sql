-- MCR composed-title v3 backfill — generated, idempotent, NOT executed.
-- Review before applying. company_id='9ShiyDAXhV', active sources only.
BEGIN;

-- 0. is_decaf column (idempotent)
ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;

-- 1. Archive dup extras FIRST so titles don't collide on uq_coffee_source.
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='4574235f-7e3a-4bf1-8560-0ce2619e748d' AND company_id='9ShiyDAXhV';  -- Hawaii Kona No.3
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='aae70ef1-a9ce-4152-a760-aabeedfd8dba' AND company_id='9ShiyDAXhV';  -- Kau 18
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='4cb216bb-e7e2-4d87-bd69-9674ad39d908' AND company_id='9ShiyDAXhV';  -- Kau 18 Honey
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='2d7716a7-bbc3-4dff-880c-df2679640626' AND company_id='9ShiyDAXhV';  -- Kau 19
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='csrc_e912e88bdc7bb317' AND company_id='9ShiyDAXhV';  -- Kona #3
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='107396af-3b99-4c29-bf49-ecd6e8f05678' AND company_id='9ShiyDAXhV';  -- Mahi Pono h3
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='f47482ad-0c29-41e8-a85d-132cf6a61271' AND company_id='9ShiyDAXhV';  -- Maui Mokka 11
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='b41d7af7-e06d-4ca5-87c8-6b3cc480ac40' AND company_id='9ShiyDAXhV';  -- Maui mokka 14
UPDATE coffee_source SET is_active=false WHERE coffee_source_id='d439446a-6523-4365-b18b-3fc98fb48a57' AND company_id='9ShiyDAXhV';  -- Organic Kona

-- 1b. Free name slots held by already-INACTIVE rows that equal a surviving
--     title on the same origin_id (uq_coffee_source spans inactive rows).
UPDATE coffee_source SET coffee_name='Nicaragua Robusta (archived 072387f0)' WHERE coffee_source_id='072387f0-483c-424c-8886-b0bdae097094' AND company_id='9ShiyDAXhV' AND NOT is_active AND coffee_name='Nicaragua Robusta';  -- frees 'Nicaragua Robusta'

-- 2. Per-surviving-source backfill (structured fields + composed coffee_name).
UPDATE coffee_source SET country_of_origin='Brazil', region='Mogiana', grade_label='SS FC', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Mogiana SS FC' WHERE coffee_source_id='csrc_e6cac7ee284067a7' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Brazil', region='Mogiana', grade_label='SS FC 15/16', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Mogiana SS FC 15/16' WHERE coffee_source_id='csrc_5de796c028876030' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Brazil', region='Mogiana', grade_label='SS FC 15/17', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Mogiana SS FC 15/17' WHERE coffee_source_id='csrc_d7988f5e334bbb0f' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Brazil', region='Mogiana', grade_label='SS FC 17/18', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Mogiana SS FC 17/18' WHERE coffee_source_id='csrc_81f73985aac71db7' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Brazil', region='Sul de Minas', grade_label='SS FC', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Sul de Minas SS FC' WHERE coffee_source_id='csrc_7d11bddf8db2e72d' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region=NULL, grade_label='Excelso EP', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Colombia Excelso EP' WHERE coffee_source_id='csrc_0a84d7ad205487c5' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region='Huila', grade_label='Supremo', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Colombia Huila Supremo' WHERE coffee_source_id='csrc_e59e36a550ac6cfe' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region='Medellín', grade_label='Excelso', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Colombia Medellín Excelso' WHERE coffee_source_id='csrc_a62b479c16f3a46f' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region=NULL, grade_label='Supremo', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Colombia Supremo' WHERE coffee_source_id='csrc_1619c377f98171c9' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{"Gesha"}', certifications='{}', coffee_name='Colombia Gesha' WHERE coffee_source_id='csrc_241e8bed4968e9f0' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Costa Rica', region='Tarrazú', grade_label='SHB', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Costa Rica Tarrazú SHB' WHERE coffee_source_id='csrc_c66f57af57b8205f' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Brazil', region=NULL, grade_label=NULL, process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Brazil Decaf' WHERE coffee_source_id='csrc_23753f1ab6d3f9c9' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region=NULL, grade_label=NULL, process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Colombia Decaf' WHERE coffee_source_id='csrc_058f4808fbf5f03e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Mexico', region='Esmeralda', grade_label=NULL, process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Mexico Esmeralda Decaf' WHERE coffee_source_id='csrc_167feec140bf4ccc' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='El Salvador', region=NULL, grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='El Salvador SHG' WHERE coffee_source_id='csrc_214aa09f8d6df8d9' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='El Salvador', region='Everest', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='El Salvador Everest' WHERE coffee_source_id='15c8cf88-62f9-4dbf-8d3a-eae6854e1c14' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Guatemala', region=NULL, grade_label='SHB', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Guatemala SHB' WHERE coffee_source_id='csrc_254a56c3c710f2c2' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label='#3', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona #3' WHERE coffee_source_id='csrc_b95b8329674802f0' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='Calán', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Honduras Calán SHG' WHERE coffee_source_id='csrc_f48911ac42eb8b84' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='COMSA', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Honduras COMSA SHG' WHERE coffee_source_id='csrc_2c416abfbff80f03' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='Copán', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Honduras Copán SHG' WHERE coffee_source_id='csrc_548695e94eeac96e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='Siguatepeque', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Honduras Siguatepeque SHG' WHERE coffee_source_id='csrc_fec67ce029c1abd0' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Ka''u', region=NULL, grade_label='#16/17/18/19', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Ka''u #16/17/18/19' WHERE coffee_source_id='csrc_419905aff309b85a' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Ka''u', region=NULL, grade_label='#18', process='Honey', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Ka''u #18 Honey' WHERE coffee_source_id='csrc_b12267adaddfb9fb' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Ka''u', region=NULL, grade_label='#19', process='Natural', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Ka''u #19 Natural' WHERE coffee_source_id='csrc_a110e005da5a37f0' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Ka''u', region=NULL, grade_label=NULL, process='Honey', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Ka''u Honey' WHERE coffee_source_id='csrc_c46a36549e65eff7' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Ka''u', region=NULL, grade_label='#18', process='Natural', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Ka''u #18 Natural' WHERE coffee_source_id='csrc_22b6cff651892be0' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region='Castaway Estate', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona Castaway Estate' WHERE coffee_source_id='csrc_54f520e29c3c78d2' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region='Castaway Reserve', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona Castaway Reserve' WHERE coffee_source_id='csrc_3983ca85110c4fa5' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label=NULL, process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona Decaf' WHERE coffee_source_id='csrc_3ee355aeaa090e0d' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='USA - Kona Organic' WHERE coffee_source_id='csrc_cd00fb0683a9171d' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{}', coffee_name='USA - Kona Peaberry' WHERE coffee_source_id='csrc_5b2aa7260e08ff80' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label='Prime 16/17', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona Prime 16/17' WHERE coffee_source_id='csrc_e2a2740c094d113c' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label='Prime 18/19', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Kona Prime 18/19' WHERE coffee_source_id='csrc_4952616625ead19a' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Kona', region=NULL, grade_label='Prime', process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{}', coffee_name='USA - Kona Prime Peaberry' WHERE coffee_source_id='csrc_e8146f2795c12d52' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Yellow', grade_label='14', process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Yellow 14 Decaf' WHERE coffee_source_id='csrc_05fece7c03fc47c7' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region=NULL, grade_label='H3', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui H3' WHERE coffee_source_id='csrc_a6837a97a66e2a7e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region=NULL, grade_label='11', process=NULL, is_decaf=false, is_peaberry=false, varietals='{"Mokka"}', certifications='{}', coffee_name='USA - Maui 11' WHERE coffee_source_id='csrc_44109ca9903ae026' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region=NULL, grade_label='14', process=NULL, is_decaf=false, is_peaberry=false, varietals='{"Mokka"}', certifications='{}', coffee_name='USA - Maui 14' WHERE coffee_source_id='csrc_487d98cba93b6956' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red / Yellow', grade_label=NULL, process='Natural / Washed', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Red / Yellow Natural / Washed' WHERE coffee_source_id='csrc_0d41704569f55641' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red', grade_label='14', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Red 14' WHERE coffee_source_id='csrc_ae0824323728699f' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red', grade_label=NULL, process='Washed', is_decaf=false, is_peaberry=false, varietals='{"Catuai"}', certifications='{}', coffee_name='USA - Maui Red Washed' WHERE coffee_source_id='csrc_0f87e935cf02c610' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red', grade_label='H3', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Red H3' WHERE coffee_source_id='csrc_e9a889b35f8b992e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red', grade_label='16', process='Natural', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Red 16 Natural' WHERE coffee_source_id='csrc_4e30e28a5edaac06' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Red', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{}', coffee_name='USA - Maui Red Peaberry' WHERE coffee_source_id='csrc_8cac746b77fa5e30' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Yellow', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Yellow' WHERE coffee_source_id='a1b7c502-64c5-4d6e-98a4-9d8745e40e1a' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Yellow', grade_label='16', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Yellow 16' WHERE coffee_source_id='csrc_d11df67fcd1d3bd9' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Yellow', grade_label='H3', process='Natural', is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='USA - Maui Yellow H3 Natural' WHERE coffee_source_id='csrc_d793c3dba1f9c7d9' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='USA - Maui', region='Yellow', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{}', coffee_name='USA - Maui Yellow Peaberry' WHERE coffee_source_id='csrc_bfd0fd07d8f36e9e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Mexico', region=NULL, grade_label=NULL, process=NULL, is_decaf=true, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Mexico Decaf' WHERE coffee_source_id='798a628f-d9d0-42ea-ba65-77629775a8d3' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Mexico', region='Veracruz', grade_label='HG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Mexico Veracruz HG' WHERE coffee_source_id='csrc_c8bfd38d18d2a86b' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Nicaragua', region='Olomega', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Nicaragua Olomega SHG' WHERE coffee_source_id='csrc_7c9c7f0eca21d029' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Nicaragua', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{"Robusta"}', certifications='{}', coffee_name='Nicaragua Robusta' WHERE coffee_source_id='csrc_0c03c745fe7bc804' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Nicaragua', region='Olomega', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Nicaragua Olomega' WHERE coffee_source_id='53b6f685-6a2f-4dcd-b9ad-732aac9fcb12' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Colombia', region=NULL, grade_label='Excelso EP', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Colombia Excelso EP Organic' WHERE coffee_source_id='csrc_51dc895c7e973ba2' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='COMSA', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Honduras COMSA SHG Organic' WHERE coffee_source_id='csrc_e58386e99c4408e6' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Honduras', region='Copán', grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Honduras Copán SHG Organic' WHERE coffee_source_id='csrc_90760e479a2af138' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Mexico', region=NULL, grade_label='HG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Mexico HG Organic' WHERE coffee_source_id='csrc_211af3db661e89ed' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Nicaragua', region=NULL, grade_label='SHG', process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Nicaragua SHG Organic' WHERE coffee_source_id='csrc_10b5149aecee5e0d' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Papua New Guinea', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Papua New Guinea Organic' WHERE coffee_source_id='csrc_209100c254f6e64d' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Peru', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Peru Organic' WHERE coffee_source_id='csrc_1483d3f39c6ded9f' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Peru', region='Selva Andina', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Peru Selva Andina Organic' WHERE coffee_source_id='csrc_c8a7362b8bc1d2fc' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Papua New Guinea', region='Simbu', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic"}', coffee_name='Papua New Guinea Simbu Organic' WHERE coffee_source_id='csrc_c9f7cf5ed2d057ae' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Timor', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{"Organic"}', coffee_name='Timor Peaberry Organic' WHERE coffee_source_id='csrc_936ef021d0846852' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Papua New Guinea', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Papua New Guinea' WHERE coffee_source_id='csrc_27019e3a8b1d2c6a' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Papua New Guinea', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=true, varietals='{}', certifications='{}', coffee_name='Papua New Guinea Peaberry' WHERE coffee_source_id='csrc_d2bed255e650be0e' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Peru', region='Café de Mujer APROCCURMA', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{"Organic","Fair Trade"}', coffee_name='Peru Café de Mujer APROCCURMA Organic Fair Trade' WHERE coffee_source_id='csrc_9e22c4ecd79db3bb' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Peru', region='Vida Alta', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Peru Vida Alta' WHERE coffee_source_id='csrc_c3692df4e5b76f59' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Indonesia', region='Sumatra', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Indonesia Sumatra' WHERE coffee_source_id='csrc_ce35b4d21f498f12' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Indonesia', region='Sumatra Takengon & Sulawesi', grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{}', certifications='{}', coffee_name='Indonesia Sumatra Takengon & Sulawesi' WHERE coffee_source_id='csrc_b39931a7edd8a6e3' AND company_id='9ShiyDAXhV';
UPDATE coffee_source SET country_of_origin='Yemen', region=NULL, grade_label=NULL, process=NULL, is_decaf=false, is_peaberry=false, varietals='{"Mokka"}', certifications='{}', coffee_name='Yemen Mokka' WHERE coffee_source_id='csrc_f9c78ea8c2cdba62' AND company_id='9ShiyDAXhV';

-- 3. Guard: (origin_id, coffee_name) must be UNIQUE before COMMIT.
--    Two checks: (a) among SURVIVING ACTIVE rows (the deliverable);
--    (b) across ALL rows (matches uq_coffee_source, which spans inactive).
DO $$
DECLARE active_dups int; all_dups int;
BEGIN
  SELECT count(*) INTO active_dups FROM (
    SELECT origin_id, coffee_name FROM coffee_source
    WHERE company_id='9ShiyDAXhV' AND is_active
    GROUP BY origin_id, coffee_name HAVING count(*) > 1
  ) d;
  IF active_dups > 0 THEN
    RAISE EXCEPTION 'composed-title v3: % duplicate (origin_id, coffee_name) among active survivors — aborting', active_dups;
  END IF;
  SELECT count(*) INTO all_dups FROM (
    SELECT origin_id, coffee_name FROM coffee_source
    WHERE company_id='9ShiyDAXhV'
    GROUP BY origin_id, coffee_name HAVING count(*) > 1
  ) d;
  IF all_dups > 0 THEN
    RAISE EXCEPTION 'composed-title v3: % duplicate (origin_id, coffee_name) across all rows (uq_coffee_source) — aborting', all_dups;
  END IF;
END $$;

COMMIT;
