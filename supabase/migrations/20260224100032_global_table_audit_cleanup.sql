-- Migration 00032: Global table audit column cleanup
--
-- Standard for global tables (no company_id): created_at + updated_at only.
-- No created_by / updated_by — those reference team, which is company-scoped.
--
-- Changes:
--   DROP created_by/updated_by from: setup_timezones, standard_parameters,
--                                    sales_state, customer_category
--   ADD updated_at to:               sales_region, user_roles
--   ADD created_at + updated_at to:  setup_countries, stock_types
--   ADD audit triggers wherever updated_at is newly present


-- ── 1. Drop created_by / updated_by from tables that have them ─────────────

ALTER TABLE public.setup_timezones
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS updated_by;

ALTER TABLE public.standard_parameters
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS updated_by;

ALTER TABLE public.sales_state
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS updated_by;

ALTER TABLE public.customer_category
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS updated_by;


-- ── 2. Add updated_at to tables that only have created_at ─────────────────

ALTER TABLE public.sales_region
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.user_roles
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();


-- ── 3. Add both timestamps to tables that have neither ────────────────────

ALTER TABLE public.setup_countries
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.stock_types
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();


-- ── 4. Add audit triggers wherever updated_at is newly present ────────────
-- trg_audit_update keeps updated_at current on every UPDATE.
-- trg_audit_insert guards created_at on INSERT (DEFAULT now() already handles
-- it, but the trigger also protects against AppSheet sending NULL).

-- sales_region
CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.sales_region
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- user_roles
CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.user_roles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- setup_countries
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.setup_countries
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.setup_countries
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- stock_types
CREATE TRIGGER trg_audit_insert
    BEFORE INSERT ON public.stock_types
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();

CREATE TRIGGER trg_audit_update
    BEFORE UPDATE ON public.stock_types
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();
