-- Drop vestigial company_id from standard_parameters
--
-- standard_parameters is a global/system-wide defaults table.
-- company_id was added when the table was per-company; it was never
-- used as a filter in any function or view (all queries filter only
-- by parameter_id / parameters_id). The FK constraint is also removed.

ALTER TABLE public.standard_parameters
    DROP CONSTRAINT IF EXISTS standard_parameters_company_id_fkey;

ALTER TABLE public.standard_parameters
    DROP COLUMN IF EXISTS company_id;
