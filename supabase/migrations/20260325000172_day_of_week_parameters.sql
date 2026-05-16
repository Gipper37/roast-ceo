-- Add day_of_week column to both parameter tables
ALTER TABLE public.standard_parameters
    ADD COLUMN IF NOT EXISTS day_of_week text;

ALTER TABLE public.company_parameters
    ADD COLUMN IF NOT EXISTS day_of_week text;

-- Allow 'day' as a valid data_type in standard_parameters
ALTER TABLE public.standard_parameters
    DROP CONSTRAINT IF EXISTS standard_parameters_data_type_check;

ALTER TABLE public.standard_parameters
    ADD CONSTRAINT standard_parameters_data_type_check
    CHECK (data_type = ANY (ARRAY['text','number','decimal','timezone','boolean','day']));

-- Function to map day name → number (Sunday=0 … Saturday=6)
CREATE OR REPLACE FUNCTION public.day_of_week_to_number(p_day text)
RETURNS integer LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    RETURN CASE LOWER(TRIM(p_day))
        WHEN 'sunday'    THEN 0
        WHEN 'monday'    THEN 1
        WHEN 'tuesday'   THEN 2
        WHEN 'wednesday' THEN 3
        WHEN 'thursday'  THEN 4
        WHEN 'friday'    THEN 5
        WHEN 'saturday'  THEN 6
        ELSE NULL
    END;
END;
$$;

-- Trigger function for standard_parameters
CREATE OR REPLACE FUNCTION public.trg_sync_day_of_week_standard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_num integer;
BEGIN
    IF NEW.day_of_week IS NOT NULL THEN
        v_num := public.day_of_week_to_number(NEW.day_of_week);
        IF v_num IS NOT NULL THEN
            NEW.amount := v_num;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_day_of_week_standard
BEFORE INSERT OR UPDATE OF day_of_week ON public.standard_parameters
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_day_of_week_standard();

-- Trigger function for company_parameters
CREATE OR REPLACE FUNCTION public.trg_sync_day_of_week_company()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_num integer;
BEGIN
    IF NEW.day_of_week IS NOT NULL THEN
        v_num := public.day_of_week_to_number(NEW.day_of_week);
        IF v_num IS NOT NULL THEN
            NEW.value_number := v_num;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_day_of_week_company
BEFORE INSERT OR UPDATE OF day_of_week ON public.company_parameters
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_day_of_week_company();

-- Backfill day_of_week and set data_type for existing reset day parameters
UPDATE public.standard_parameters SET day_of_week = 'Thursday', data_type = 'day' WHERE parameters_id = 'RF1iFWjOh7';
UPDATE public.standard_parameters SET day_of_week = 'Saturday',  data_type = 'day' WHERE parameters_id = 'orders_reset_day';

-- Backfill day_of_week in company_parameters from existing value_number
UPDATE public.company_parameters
SET day_of_week = CASE value_number
    WHEN 0 THEN 'Sunday'
    WHEN 1 THEN 'Monday'
    WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday'
    WHEN 4 THEN 'Thursday'
    WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
END
WHERE parameter_id IN ('RF1iFWjOh7', 'orders_reset_day')
  AND day_of_week IS NULL
  AND value_number IS NOT NULL;
