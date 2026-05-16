-- Migration 00034: Expand lookup tables + Australian geographic data
-- 1. Fix UK → GB in setup_countries (ISO 3166-1 alpha-2 correction)
-- 2. Add Australia to setup_countries
-- 3. Add 5 Australian timezones to setup_timezones
-- 4. Add 5 Australian sales_regions + 8 states/territories to sales_state

-- ============================================================
-- 1. Fix country code: UK → GB
-- ============================================================
UPDATE public.setup_countries
SET country_code = 'GB'
WHERE country_code = 'UK';

-- Also fix any FK references in customers and facilities
-- (setup_countries.country_code is the PK; these tables reference it)
UPDATE public.customers  SET country_id    = 'GB' WHERE country_id    = 'UK';
UPDATE public.facilities SET country_code  = 'GB' WHERE country_code  = 'UK';

-- ============================================================
-- 2. Add Australia
-- ============================================================
INSERT INTO public.setup_countries (country_code, country_name)
VALUES ('AU', 'Australia')
ON CONFLICT (country_code) DO NOTHING;

-- ============================================================
-- 3. Add 5 Australian timezones
-- ============================================================
INSERT INTO public.setup_timezones (timezone_name, display_label) VALUES
  ('Australia/Perth',    '(UTC+08:00) Western Australia – Perth'),
  ('Australia/Darwin',   '(UTC+09:30) Central Australia – Darwin (no DST)'),
  ('Australia/Adelaide', '(UTC+09:30) Central Australia – Adelaide'),
  ('Australia/Brisbane', '(UTC+10:00) Eastern Australia – Brisbane (no DST)'),
  ('Australia/Sydney',   '(UTC+10:00) Eastern Australia – Sydney, Melbourne')
ON CONFLICT (timezone_name) DO NOTHING;

-- ============================================================
-- 4. Add Australian regions and states/territories
--    country_code in sales_region/sales_state stores a UUID-format
--    text identifier (matching the pattern used for US/CA/GB entries).
--    Generate consistent UUIDs within this block.
-- ============================================================
DO $$
DECLARE
  au_id  text := gen_random_uuid()::text;
  r_nsw  text := gen_random_uuid()::text;
  r_vic  text := gen_random_uuid()::text;
  r_qld  text := gen_random_uuid()::text;
  r_wa   text := gen_random_uuid()::text;
  r_sant text := gen_random_uuid()::text;
BEGIN
  -- Regions (5)
  INSERT INTO public.sales_region (id, name, country_code, created_at, updated_at) VALUES
    (r_nsw,  'New South Wales',                au_id, now(), now()),
    (r_vic,  'Victoria & Tasmania',            au_id, now(), now()),
    (r_qld,  'Queensland',                     au_id, now(), now()),
    (r_wa,   'Western Australia',              au_id, now(), now()),
    (r_sant, 'South Australia & Territories',  au_id, now(), now());

  -- States / Territories (8)
  INSERT INTO public.sales_state (id, country_code, state_name, state_abbrev, region_id) VALUES
    (gen_random_uuid()::text, au_id, 'New South Wales',              'NSW', r_nsw),
    (gen_random_uuid()::text, au_id, 'Australian Capital Territory', 'ACT', r_nsw),
    (gen_random_uuid()::text, au_id, 'Victoria',                     'VIC', r_vic),
    (gen_random_uuid()::text, au_id, 'Tasmania',                     'TAS', r_vic),
    (gen_random_uuid()::text, au_id, 'Queensland',                   'QLD', r_qld),
    (gen_random_uuid()::text, au_id, 'Western Australia',            'WA',  r_wa),
    (gen_random_uuid()::text, au_id, 'South Australia',              'SA',  r_sant),
    (gen_random_uuid()::text, au_id, 'Northern Territory',           'NT',  r_sant);
END $$;
