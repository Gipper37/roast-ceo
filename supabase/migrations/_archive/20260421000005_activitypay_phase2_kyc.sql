-- =============================================================================
-- Activity Pay — Phase 2: KYC, 3DS columns, bank link, payouts, statements
-- =============================================================================
-- Schema only. Business logic lives in the app (TS).
--
-- Sensitive identifiers (EIN, SSN) are encrypted in the app layer (Node crypto
-- AES-256-GCM, key from Vercel env KYC_ENCRYPTION_KEY). DB sees ciphertext
-- only. Last-4 of SSN stored in plaintext for UX (display).
--
-- Design notes:
--   * company_kyc is one-to-one with companies (PK = company_id).
--   * company_kyc_beneficial_owners — one row per person with >= 25% ownership
--     (FinCEN rule). Plus always include one "control person".
--   * company_kyc_documents — uploaded business docs (EIN letter, formation,
--     driver's license). Private storage bucket kyc-documents.
--   * roaster_bank_accounts — ACH destination for payouts. Plaid token + last4.
--   * payouts + payout_line_items — one payout header, many transactions.
--   * statements — one per company per month, PDF storage path.
--   * tax_forms — annual 1099-K per company per year. Tax1099 filing id.
--   * chargebacks — populated from AP webhooks.
--
-- Also on this migration:
--   * payment_transactions: add 3DS columns + risk_score
--   * orders: add settled + settled_at + paid_out flags (payout book-keeping)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1.  payment_transactions  —  3DS + risk score columns
-- -----------------------------------------------------------------------------
ALTER TABLE payment_transactions
  ADD COLUMN IF NOT EXISTS threeds_status     text,
  ADD COLUMN IF NOT EXISTS threeds_eci        text,
  ADD COLUMN IF NOT EXISTS threeds_cavv       text,
  ADD COLUMN IF NOT EXISTS threeds_xid        text,
  ADD COLUMN IF NOT EXISTS risk_score         numeric,
  ADD COLUMN IF NOT EXISTS settled            boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS settled_at         timestamptz,
  ADD COLUMN IF NOT EXISTS paid_out           boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payout_id          uuid;

-- Liability shift is derived — safer than a trigger-maintained column.
ALTER TABLE payment_transactions
  DROP COLUMN IF EXISTS threeds_liability_shifted;
ALTER TABLE payment_transactions
  ADD COLUMN threeds_liability_shifted boolean
    GENERATED ALWAYS AS (threeds_status IN ('Y','A')) STORED;

COMMENT ON COLUMN payment_transactions.threeds_status             IS 'PAAY 3DS status. Y=authenticated, A=attempted, N=no, R=rejected, U=unavailable, C=challenge.';
COMMENT ON COLUMN payment_transactions.threeds_liability_shifted  IS 'True when liability shifts to issuer (status Y or A). Generated column.';
COMMENT ON COLUMN payment_transactions.risk_score                 IS 'reCAPTCHA v3 score at submit time. 0.0 (bot) to 1.0 (human).';
COMMENT ON COLUMN payment_transactions.settled                    IS 'AP has settled this charge (funds arrived at our master account).';
COMMENT ON COLUMN payment_transactions.paid_out                   IS 'This transaction has been rolled into a roaster payout.';
COMMENT ON COLUMN payment_transactions.payout_id                  IS 'FK to payouts when paid_out=true.';

CREATE INDEX IF NOT EXISTS idx_payment_txn_payout_eligible
  ON payment_transactions (company_id, settled_at)
  WHERE settled = true AND paid_out = false AND status = 'approved';

CREATE INDEX IF NOT EXISTS idx_payment_txn_payout_id
  ON payment_transactions (payout_id)
  WHERE payout_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 2.  company_kyc  —  PayFac sub-merchant onboarding
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS company_kyc (
  company_id            text        PRIMARY KEY REFERENCES companies (company_id) ON DELETE CASCADE,

  -- Status machine
  status                text        NOT NULL DEFAULT 'not_started',
  -- not_started | submitted | under_review | approved | rejected

  -- Legal business identity
  legal_name            text,
  dba                   text,
  business_type         text,       -- sole_prop | llc | s_corp | c_corp | partnership | nonprofit
  ein_encrypted         bytea,      -- AES-256-GCM ciphertext from app
  ein_last4             text,       -- plaintext last-4 for display
  business_phone        text,
  business_website      text,
  industry_mcc          text,       -- merchant category code

  -- Business address
  business_address_line1    text,
  business_address_line2    text,
  business_address_city     text,
  business_address_state    text,   -- 2-letter
  business_address_postal   text,
  business_address_country  text    DEFAULT 'US',

  -- Expected volume (for fraud modeling + reserve decisions)
  expected_monthly_volume_cents   bigint,
  expected_average_ticket_cents   bigint,

  -- Reserve policy
  rolling_reserve_pct       numeric NOT NULL DEFAULT 0,    -- 0.00–1.00
  rolling_reserve_days      integer NOT NULL DEFAULT 0,    -- e.g. 90 for new roasters

  -- Workflow timestamps + reviewer
  submitted_at          timestamptz,
  reviewed_at           timestamptz,
  reviewed_by           text,       -- STRATA admin user email
  rejection_reason      text,

  -- Provider linkage (if AP adds a real sub-merchant API later)
  provider_submerchant_id text,

  -- Audit
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            text,
  updated_by            text
);

COMMENT ON TABLE  company_kyc               IS 'PayFac sub-merchant onboarding data. One-to-one with companies. SSN/EIN are encrypted at the app layer before insert.';
COMMENT ON COLUMN company_kyc.status        IS 'not_started → submitted → under_review → approved | rejected';
COMMENT ON COLUMN company_kyc.ein_encrypted IS 'AES-256-GCM ciphertext of EIN. Key in Vercel env KYC_ENCRYPTION_KEY. Never SELECT this from anywhere except the decrypt helper.';
COMMENT ON COLUMN company_kyc.rolling_reserve_pct IS 'Fraction of each charge held back (0.00–1.00). Default 0. Set to e.g. 0.05 for high-risk or new.';

ALTER TABLE company_kyc
  DROP CONSTRAINT IF EXISTS company_kyc_status_chk,
  DROP CONSTRAINT IF EXISTS company_kyc_business_type_chk,
  DROP CONSTRAINT IF EXISTS company_kyc_reserve_pct_chk;
ALTER TABLE company_kyc
  ADD CONSTRAINT company_kyc_status_chk
    CHECK (status IN ('not_started','submitted','under_review','approved','rejected')),
  ADD CONSTRAINT company_kyc_business_type_chk
    CHECK (business_type IS NULL OR business_type IN
      ('sole_prop','llc','s_corp','c_corp','partnership','nonprofit')),
  ADD CONSTRAINT company_kyc_reserve_pct_chk
    CHECK (rolling_reserve_pct >= 0 AND rolling_reserve_pct <= 1);

CREATE INDEX IF NOT EXISTS idx_company_kyc_status
  ON company_kyc (status) WHERE status IN ('submitted','under_review');

-- updated_at trigger + audit hooks
CREATE OR REPLACE FUNCTION trg_set_company_kyc_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_company_kyc_updated_at ON company_kyc;
CREATE TRIGGER trg_company_kyc_updated_at
  BEFORE UPDATE ON company_kyc
  FOR EACH ROW EXECUTE FUNCTION trg_set_company_kyc_updated_at();

DROP TRIGGER IF EXISTS trg_audit_insert ON company_kyc;
CREATE TRIGGER trg_audit_insert
  BEFORE INSERT ON company_kyc
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();

DROP TRIGGER IF EXISTS trg_audit_update ON company_kyc;
CREATE TRIGGER trg_audit_update
  BEFORE UPDATE ON company_kyc
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 3.  company_kyc_beneficial_owners  —  FinCEN "beneficial owner" rule
-- -----------------------------------------------------------------------------
-- One row per person with >= 25% ownership, plus one control person
-- (CEO, COO, CFO, etc.) regardless of ownership.
CREATE TABLE IF NOT EXISTS company_kyc_beneficial_owners (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        text        NOT NULL REFERENCES company_kyc (company_id) ON DELETE CASCADE,

  role              text        NOT NULL DEFAULT 'owner',   -- owner | control

  full_name         text        NOT NULL,
  date_of_birth     date        NOT NULL,
  ssn_encrypted     bytea,      -- nullable for non-US owners (use id_doc instead)
  ssn_last4         text,
  id_document_type  text,       -- passport | drivers_license | national_id (for non-US)
  id_document_country text,

  ownership_pct     numeric     NOT NULL DEFAULT 0,   -- 0.00–1.00

  address_line1     text,
  address_line2     text,
  address_city      text,
  address_state     text,
  address_postal    text,
  address_country   text        DEFAULT 'US',

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text,
  updated_by        text
);

COMMENT ON TABLE company_kyc_beneficial_owners IS 'Persons with >=25% ownership (FinCEN rule). One control person required regardless of ownership percentage.';

ALTER TABLE company_kyc_beneficial_owners
  DROP CONSTRAINT IF EXISTS company_kyc_bo_role_chk,
  DROP CONSTRAINT IF EXISTS company_kyc_bo_ownership_chk;
ALTER TABLE company_kyc_beneficial_owners
  ADD CONSTRAINT company_kyc_bo_role_chk CHECK (role IN ('owner','control')),
  ADD CONSTRAINT company_kyc_bo_ownership_chk
    CHECK (ownership_pct >= 0 AND ownership_pct <= 1);

CREATE INDEX IF NOT EXISTS idx_kyc_bo_company ON company_kyc_beneficial_owners (company_id);

DROP TRIGGER IF EXISTS trg_audit_insert ON company_kyc_beneficial_owners;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON company_kyc_beneficial_owners
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON company_kyc_beneficial_owners;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON company_kyc_beneficial_owners
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 4.  company_kyc_documents  —  uploaded business docs
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS company_kyc_documents (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    text        NOT NULL REFERENCES company_kyc (company_id) ON DELETE CASCADE,
  document_type text        NOT NULL,  -- ein_letter | formation_docs | id_front | id_back | bank_statement | other
  storage_path  text        NOT NULL,  -- relative path in kyc-documents bucket
  file_name     text,
  file_size     integer,
  mime_type     text,
  uploaded_by   text,
  uploaded_at   timestamptz NOT NULL DEFAULT now(),
  notes         text
);

CREATE INDEX IF NOT EXISTS idx_kyc_docs_company ON company_kyc_documents (company_id);


-- -----------------------------------------------------------------------------
-- 5.  roaster_bank_accounts  —  ACH destination for payouts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roaster_bank_accounts (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            text        NOT NULL REFERENCES companies (company_id) ON DELETE CASCADE,

  account_holder_name   text        NOT NULL,
  account_type          text        NOT NULL DEFAULT 'checking',  -- checking | savings
  routing_number_last4  text,                         -- full routing never stored
  account_number_last4  text        NOT NULL,

  -- Plaid linkage (preferred path)
  plaid_access_token_encrypted  bytea,
  plaid_account_id              text,
  plaid_item_id                 text,

  -- Manual micro-deposit fallback
  verification_method   text        NOT NULL,        -- plaid | micro_deposit | manual
  verification_status   text        NOT NULL DEFAULT 'pending',  -- pending | verified | failed
  verified_at           timestamptz,

  -- NACHA authorization (we must keep this on file)
  nacha_authorized_at   timestamptz,
  nacha_auth_ip         text,
  nacha_auth_user_agent text,

  is_active             boolean     NOT NULL DEFAULT true,

  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            text,
  updated_by            text
);

COMMENT ON TABLE roaster_bank_accounts IS 'ACH destination for payouts. Full account/routing numbers are NEVER stored — only last 4. Plaid tokens give us the real-time balance + verified-identity handshake.';

ALTER TABLE roaster_bank_accounts
  DROP CONSTRAINT IF EXISTS roaster_bank_verification_method_chk,
  DROP CONSTRAINT IF EXISTS roaster_bank_verification_status_chk,
  DROP CONSTRAINT IF EXISTS roaster_bank_account_type_chk;
ALTER TABLE roaster_bank_accounts
  ADD CONSTRAINT roaster_bank_verification_method_chk
    CHECK (verification_method IN ('plaid','micro_deposit','manual')),
  ADD CONSTRAINT roaster_bank_verification_status_chk
    CHECK (verification_status IN ('pending','verified','failed')),
  ADD CONSTRAINT roaster_bank_account_type_chk
    CHECK (account_type IN ('checking','savings'));

-- Only one active bank account per company at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_roaster_bank_active_one
  ON roaster_bank_accounts (company_id)
  WHERE is_active = true;

DROP TRIGGER IF EXISTS trg_audit_insert ON roaster_bank_accounts;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON roaster_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON roaster_bank_accounts;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON roaster_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 6.  payouts + payout_line_items  —  weekly ACH batch to roaster
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payouts (
  payout_id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              text        NOT NULL REFERENCES companies (company_id) ON DELETE RESTRICT,
  bank_account_id         uuid        REFERENCES roaster_bank_accounts (id) ON DELETE SET NULL,

  status                  text        NOT NULL DEFAULT 'pending',
  -- pending | submitted | in_transit | paid | returned | canceled

  -- Money
  gross_cents             bigint      NOT NULL,       -- sum of included txns gross
  gateway_fees_cents      bigint      NOT NULL DEFAULT 0,
  platform_fees_cents     bigint      NOT NULL DEFAULT 0,
  refunds_cents           bigint      NOT NULL DEFAULT 0,
  chargebacks_cents       bigint      NOT NULL DEFAULT 0,
  reserve_held_cents      bigint      NOT NULL DEFAULT 0,
  net_cents               bigint      NOT NULL,       -- final ACH amount

  -- Rail info
  ach_provider            text,                        -- dwolla | increase | ap | manual
  ach_transfer_id         text,                        -- provider-side transfer id
  return_code             text,                        -- NACHA R01/R02/R03/...
  return_reason           text,

  period_start            date        NOT NULL,
  period_end              date        NOT NULL,
  submitted_at            timestamptz,
  paid_at                 timestamptz,

  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              text,
  updated_by              text
);

ALTER TABLE payouts
  DROP CONSTRAINT IF EXISTS payouts_status_chk;
ALTER TABLE payouts
  ADD CONSTRAINT payouts_status_chk CHECK (status IN
    ('pending','submitted','in_transit','paid','returned','canceled'));

CREATE INDEX IF NOT EXISTS idx_payouts_company     ON payouts (company_id);
CREATE INDEX IF NOT EXISTS idx_payouts_status      ON payouts (status);
CREATE INDEX IF NOT EXISTS idx_payouts_period      ON payouts (company_id, period_end DESC);

-- Now that payouts exists, add the FK from payment_transactions.payout_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payment_transactions_payout_id_fkey'
  ) THEN
    ALTER TABLE payment_transactions
      ADD CONSTRAINT payment_transactions_payout_id_fkey
      FOREIGN KEY (payout_id) REFERENCES payouts (payout_id) ON DELETE SET NULL;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_audit_insert ON payouts;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON payouts
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON payouts;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 7.  statements  —  monthly roaster statement
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS statements (
  statement_id      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        text        NOT NULL REFERENCES companies (company_id) ON DELETE CASCADE,

  period_start      date        NOT NULL,
  period_end        date        NOT NULL,

  -- Snapshot totals in cents
  opening_balance_cents     bigint  NOT NULL DEFAULT 0,
  gross_sales_cents         bigint  NOT NULL DEFAULT 0,
  gateway_fees_cents        bigint  NOT NULL DEFAULT 0,
  platform_fees_cents       bigint  NOT NULL DEFAULT 0,
  refunds_cents             bigint  NOT NULL DEFAULT 0,
  chargebacks_cents         bigint  NOT NULL DEFAULT 0,
  payouts_cents             bigint  NOT NULL DEFAULT 0,
  closing_balance_cents     bigint  NOT NULL DEFAULT 0,
  transaction_count         integer NOT NULL DEFAULT 0,

  pdf_storage_path          text,
  sent_at                   timestamptz,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text,
  updated_by        text,

  UNIQUE (company_id, period_start)
);

COMMENT ON TABLE statements IS 'Monthly roaster statement. Totals are point-in-time snapshots; PDF stored in statements bucket.';

CREATE INDEX IF NOT EXISTS idx_statements_company_period
  ON statements (company_id, period_end DESC);


-- -----------------------------------------------------------------------------
-- 8.  tax_forms  —  annual 1099-K
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tax_forms (
  tax_form_id       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        text        NOT NULL REFERENCES companies (company_id) ON DELETE CASCADE,

  form_type         text        NOT NULL DEFAULT '1099-K',
  tax_year          integer     NOT NULL,

  -- Box totals in cents (1099-K box 1a + monthly breakdown)
  gross_annual_cents        bigint  NOT NULL,
  gross_jan_cents           bigint  NOT NULL DEFAULT 0,
  gross_feb_cents           bigint  NOT NULL DEFAULT 0,
  gross_mar_cents           bigint  NOT NULL DEFAULT 0,
  gross_apr_cents           bigint  NOT NULL DEFAULT 0,
  gross_may_cents           bigint  NOT NULL DEFAULT 0,
  gross_jun_cents           bigint  NOT NULL DEFAULT 0,
  gross_jul_cents           bigint  NOT NULL DEFAULT 0,
  gross_aug_cents           bigint  NOT NULL DEFAULT 0,
  gross_sep_cents           bigint  NOT NULL DEFAULT 0,
  gross_oct_cents           bigint  NOT NULL DEFAULT 0,
  gross_nov_cents           bigint  NOT NULL DEFAULT 0,
  gross_dec_cents           bigint  NOT NULL DEFAULT 0,
  transaction_count         integer NOT NULL,

  -- Filing lifecycle
  status                    text        NOT NULL DEFAULT 'draft',
  -- draft | filed | corrected | void
  tax1099_submission_id     text,
  filed_at                  timestamptz,
  payee_delivered_at        timestamptz,
  pdf_storage_path          text,
  correction_reason         text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text,
  updated_by        text,

  UNIQUE (company_id, form_type, tax_year)
);

ALTER TABLE tax_forms
  DROP CONSTRAINT IF EXISTS tax_forms_status_chk,
  DROP CONSTRAINT IF EXISTS tax_forms_form_type_chk;
ALTER TABLE tax_forms
  ADD CONSTRAINT tax_forms_status_chk
    CHECK (status IN ('draft','filed','corrected','void')),
  ADD CONSTRAINT tax_forms_form_type_chk
    CHECK (form_type IN ('1099-K','1099-MISC'));

CREATE INDEX IF NOT EXISTS idx_tax_forms_year ON tax_forms (tax_year, company_id);


-- -----------------------------------------------------------------------------
-- 9.  chargebacks  —  disputes from AP
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chargebacks (
  chargeback_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        text        NOT NULL REFERENCES companies (company_id) ON DELETE RESTRICT,
  payment_transaction_id  uuid  NOT NULL REFERENCES payment_transactions (payment_transaction_id) ON DELETE RESTRICT,
  order_id          text        REFERENCES orders (order_id) ON DELETE SET NULL,

  provider          text        NOT NULL DEFAULT 'activitypay',
  provider_case_id  text        NOT NULL,

  status            text        NOT NULL DEFAULT 'open',
  -- open | evidence_submitted | won | lost | accepted

  reason_code       text,
  reason_text       text,
  amount_cents      bigint      NOT NULL,

  due_by            timestamptz,
  submitted_at      timestamptz,
  resolved_at       timestamptz,

  evidence_storage_path text,
  notes             text,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text,
  updated_by        text,

  UNIQUE (provider, provider_case_id)
);

ALTER TABLE chargebacks
  DROP CONSTRAINT IF EXISTS chargebacks_status_chk;
ALTER TABLE chargebacks
  ADD CONSTRAINT chargebacks_status_chk CHECK (status IN
    ('open','evidence_submitted','won','lost','accepted'));

CREATE INDEX IF NOT EXISTS idx_chargebacks_company ON chargebacks (company_id);
CREATE INDEX IF NOT EXISTS idx_chargebacks_status  ON chargebacks (status)
  WHERE status IN ('open','evidence_submitted');

DROP TRIGGER IF EXISTS trg_audit_insert ON chargebacks;
CREATE TRIGGER trg_audit_insert BEFORE INSERT ON chargebacks
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();
DROP TRIGGER IF EXISTS trg_audit_update ON chargebacks;
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON chargebacks
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 10.  Storage buckets — kyc-documents (PRIVATE) + statements (PRIVATE)
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'kyc-documents', 'kyc-documents', false, 10485760,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf']
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'statements', 'statements', false, 10485760,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Authenticated users can upload their own KYC docs (write); no read policy
-- at this level — reads happen through a signed-URL server action.
DROP POLICY IF EXISTS kyc_docs_auth_upload ON storage.objects;
CREATE POLICY kyc_docs_auth_upload
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'kyc-documents' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS kyc_docs_auth_update ON storage.objects;
CREATE POLICY kyc_docs_auth_update
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'kyc-documents' AND auth.role() = 'authenticated');
