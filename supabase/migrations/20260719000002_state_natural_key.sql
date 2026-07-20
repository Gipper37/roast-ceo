-- State model: move customers.state off the opaque sales_state.id (a UUID) onto a
-- readable, filterable, country-qualified natural-key code (e.g. "US-HI", "GB-ABD").
--
-- Why: customers.state was FK'd to sales_state(id) — a surrogate UUID. That meant
-- every writer had to resolve "HI" → uuid first or the write FK-failed (it broke
-- the QB customer import, and it silently breaks the quick-add customer form).
-- It's also inconsistent with billing_state (free text) and opaque for the
-- filter-by-state / revenue-by-state analytics this column exists to power.
--
-- This keeps sales_state.id for the sales_city / sales_area FKs (untouched); it
-- only adds a `code` natural key and repoints customers.state onto it. All the
-- columns are already text, so no type changes are needed — just value remaps.
-- Data volume is tiny (43 customers company-wide have a non-null state).

BEGIN;

-- 1) Dedup sales_state on (country_code, state_abbrev). Five GB rows are exact
--    duplicates (Kent, Cumbria, Cambridgeshire, Lancashire, Isle of Wight) which
--    would block a unique code. Keep the lowest id per pair, repoint every
--    reference (city / area / customer), then delete the extras.
CREATE TEMP TABLE _state_dedup ON COMMIT DROP AS
  SELECT id AS dup_id,
         min(id) OVER (PARTITION BY upper(country_code), upper(state_abbrev)) AS keep_id
  FROM sales_state;
UPDATE sales_city c  SET state_id = d.keep_id FROM _state_dedup d WHERE c.state_id = d.dup_id AND d.dup_id <> d.keep_id;
UPDATE sales_area a  SET state_id = d.keep_id FROM _state_dedup d WHERE a.state_id = d.dup_id AND d.dup_id <> d.keep_id;
UPDATE customers cu  SET state    = d.keep_id FROM _state_dedup d WHERE cu.state   = d.dup_id AND d.dup_id <> d.keep_id;
DELETE FROM sales_state s USING _state_dedup d WHERE s.id = d.dup_id AND d.dup_id <> d.keep_id;

-- 2) Add the natural key: a readable country-qualified code, unique. sales_state.id
--    stays as-is (sales_city / sales_area keep FK'ing to it).
ALTER TABLE sales_state ADD COLUMN IF NOT EXISTS code text;
UPDATE sales_state
   SET code = upper(country_code) || '-' || upper(state_abbrev)
 WHERE code IS NULL AND country_code IS NOT NULL AND state_abbrev IS NOT NULL;
ALTER TABLE sales_state ALTER COLUMN code SET NOT NULL;
ALTER TABLE sales_state ADD CONSTRAINT sales_state_code_key UNIQUE (code);

-- 3) Remap customers.state from the UUID id → the new code, then clean any legacy
--    value that never resolved to a real state so the fresh FK validates.
ALTER TABLE customers DROP CONSTRAINT IF EXISTS customers_state_fkey;
UPDATE customers cu SET state = s.code FROM sales_state s WHERE cu.state = s.id AND cu.state IS NOT NULL;
UPDATE customers SET state = NULL
 WHERE state IS NOT NULL AND state NOT IN (SELECT code FROM sales_state);

-- 4) New FK on the readable key — VALID this time (the old one was NOT VALID).
ALTER TABLE customers
  ADD CONSTRAINT customers_state_fkey FOREIGN KEY (state) REFERENCES sales_state(code);

COMMIT;
