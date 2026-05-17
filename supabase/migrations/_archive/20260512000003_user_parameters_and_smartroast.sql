-- SMARTroast feature foundation: per-user parameter overrides + the
-- SMARTroast on/off toggle.
--
-- ── Why a new table ────────────────────────────────────────────────
-- standard_parameters (system defaults) → company_parameters
-- (per-facility overrides) is the existing chain. SMARTroast is an
-- *operator preference* — Bob the roastmaster wants auto-detect on
-- his shifts, Alice prefers manual. That can't live on
-- company_parameters (would override for everyone at the facility) or
-- localStorage (wouldn't follow the user across the macOS app, the
-- tablet at the drum, and the desktop browser).
--
-- ── Resolution chain after this ───────────────────────────────────
--   1. user_parameters (user_id, [facility_id])    — operator pref
--   2. company_parameters (facility_id)            — facility default
--   3. standard_parameters                         — system default
--
-- facility_id on user_parameters is nullable. NULL = "this preference
-- applies to me everywhere"; non-null = "only at this facility". Most
-- prefs (SMARTroast on/off) use NULL — set once, follows everywhere.
--
-- ── Why same shape as company_parameters ──────────────────────────
-- value (text) + value_number (numeric) + day_of_week (text) so the
-- existing parameter UI can drop in a per-user version without a new
-- field-handling pathway. Note: company_id + facility_id are TEXT
-- (matching companies.company_id and facilities.facility_id), not
-- uuid.

BEGIN;

CREATE TABLE IF NOT EXISTS user_parameters (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL,                -- auth.users.id
  parameter_id  text        NOT NULL,
  facility_id   text        NULL,                    -- NULL = applies everywhere
  company_id    text        NOT NULL,                -- tenant scope
  value         text        NULL,
  value_number  numeric     NULL,
  day_of_week   text        NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NULL,
  updated_by    text        NULL,

  -- One row per (user, param, facility) tuple. NULL facility_id is a
  -- distinct row from any specific facility — that's the global pref.
  CONSTRAINT user_parameters_unique
    UNIQUE NULLS NOT DISTINCT (user_id, parameter_id, facility_id),

  CONSTRAINT user_parameters_param_fk
    FOREIGN KEY (parameter_id) REFERENCES standard_parameters(parameters_id)
    ON DELETE CASCADE,

  CONSTRAINT user_parameters_company_fk
    FOREIGN KEY (company_id) REFERENCES companies(company_id),

  CONSTRAINT user_parameters_facility_fk
    FOREIGN KEY (facility_id) REFERENCES facilities(facility_id)
);

CREATE INDEX IF NOT EXISTS idx_user_parameters_user
  ON user_parameters (user_id, parameter_id);

CREATE INDEX IF NOT EXISTS idx_user_parameters_company
  ON user_parameters (company_id);

-- Audit trigger to keep updated_at fresh on writes (matches the
-- pattern used by company_parameters and friends).
CREATE TRIGGER trg_user_parameters_updated
  BEFORE UPDATE ON user_parameters
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_record();

-- ── Standard parameters for SMARTroast ────────────────────────────
-- All boolean toggles in this codebase use data_type='boolean' with
-- text_value 'on' | 'off'. Sensitivity uses data_type='text' (no
-- 'enum' in the CHECK constraint). Cancel window uses 'number' on
-- the amount column.

INSERT INTO standard_parameters (parameters_id, parameter, data_type, text_value)
VALUES (
  'smartroast_enabled',
  'SMARTroast — auto-detect CHARGE/DROP',
  'boolean',
  'off'
)
ON CONFLICT (parameters_id) DO NOTHING;

INSERT INTO standard_parameters (parameters_id, parameter, data_type, text_value)
VALUES (
  'smartroast_sensitivity',
  'SMARTroast detection sensitivity',
  'text',
  'normal'
)
ON CONFLICT (parameters_id) DO NOTHING;

INSERT INTO standard_parameters (parameters_id, parameter, data_type, amount)
VALUES (
  'smartroast_cancel_window_secs',
  'SMARTroast cancel window (seconds)',
  'number',
  5
)
ON CONFLICT (parameters_id) DO NOTHING;

COMMIT;
