-- Step 1: Add text UUID id column (AppSheet-compatible — text, not uuid type)
ALTER TABLE public.charge_weight_options
  ADD COLUMN id text DEFAULT gen_random_uuid()::text;

-- Step 2: Populate id for all existing rows
UPDATE public.charge_weight_options SET id = gen_random_uuid()::text WHERE id IS NULL;

-- Step 3: Drop old primary key on charge_weight
ALTER TABLE public.charge_weight_options DROP CONSTRAINT charge_weight_options_pkey;

-- Step 4: Make id the new primary key
ALTER TABLE public.charge_weight_options ALTER COLUMN id SET NOT NULL;
ALTER TABLE public.charge_weight_options ADD CONSTRAINT charge_weight_options_pkey PRIMARY KEY (id);

-- Step 5: Add unique constraint on (facility_id, charge_weight)
ALTER TABLE public.charge_weight_options
  ADD CONSTRAINT charge_weight_options_facility_weight_key UNIQUE (facility_id, charge_weight);

-- Step 6: Fill in Waikapu facility_id for all Social Hour rows
UPDATE public.charge_weight_options
SET facility_id = 'cc844abb-db0b-48db-9aeb-abd8df9117de'
WHERE company_id = 'R7CbqHmA1j' AND facility_id IS NULL;
