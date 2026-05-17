-- =============================================================================
-- Activity Pay — Phase 1: Shop checkout payments (PayFac model)
-- =============================================================================
-- STRATA is the merchant-of-record. Activity Pay is our partner processor.
-- Roasters do NOT each have their own AP account — all charges run through
-- STRATA's single merchant account. Platform fee: AP gateway cost + 0.5%
-- STRATA markup. Payouts to roasters are owed by STRATA (Phase 2).
--
-- This migration covers Phase 1 (card-at-checkout only):
--   1. orders       — add payment status / transaction ref columns
--   2. orders       — add shop_order_ref (human-friendly "SH-000123")
--   3. customers    — add payment_terms (card | net_15 | net_30 | net_60)
--   4. shop_config  — add payments_enabled gate
--   5. subscription_plans — add can_accept_payments (Pro & Enterprise only)
--   6. payment_transactions — ledger of every gateway call (charge/refund/void)
--   7. payment_webhook_events — idempotency + full audit of AP webhooks
--   8. shop_order_ref_counter + allocate_shop_order_ref(company_id) — PER-
--      COMPANY monotonic counter for customer-facing order refs.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1 + 2.  orders — payment + shop_order_ref
-- -----------------------------------------------------------------------------
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS shop_order_ref          text,
  ADD COLUMN IF NOT EXISTS payment_status          text,
  ADD COLUMN IF NOT EXISTS payment_transaction_id  text,
  ADD COLUMN IF NOT EXISTS payment_amount_cents    integer,
  ADD COLUMN IF NOT EXISTS paid_at                 timestamptz,
  ADD COLUMN IF NOT EXISTS payment_failed_at       timestamptz,
  ADD COLUMN IF NOT EXISTS payment_failure_reason  text;

COMMENT ON COLUMN orders.shop_order_ref         IS 'Human-friendly shop order ref (e.g. "SH-000123"). Allocated per company via allocate_shop_order_ref().';
COMMENT ON COLUMN orders.payment_status         IS 'NULL=no payment required (internal order or net-terms open) | pending | authorized | captured | failed | refunded | partially_refunded | voided';
COMMENT ON COLUMN orders.payment_transaction_id IS 'Activity Pay transaction id of the successful charge. NULL until captured.';
COMMENT ON COLUMN orders.payment_amount_cents   IS 'Amount captured in cents. Snapshot at charge time — survives future price changes.';
COMMENT ON COLUMN orders.paid_at                IS 'Timestamp of successful capture.';
COMMENT ON COLUMN orders.payment_failed_at      IS 'Most recent failure timestamp (overwrites on retry).';
COMMENT ON COLUMN orders.payment_failure_reason IS 'Gateway response text for the most recent failure.';

-- Payment status must be one of a known set (NULL allowed for non-shop / net-terms orders).
ALTER TABLE orders
  DROP CONSTRAINT IF EXISTS orders_payment_status_chk;
ALTER TABLE orders
  ADD CONSTRAINT orders_payment_status_chk CHECK (
    payment_status IS NULL OR payment_status IN (
      'pending','authorized','captured','failed',
      'refunded','partially_refunded','voided'
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_shop_order_ref
  ON orders (shop_order_ref)
  WHERE shop_order_ref IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_payment_status
  ON orders (payment_status)
  WHERE payment_status IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_payment_transaction_id
  ON orders (payment_transaction_id)
  WHERE payment_transaction_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 3.  customers — payment_terms
-- -----------------------------------------------------------------------------
-- 'card' = must pay at checkout (default for new shop customers)
-- 'net_15' / 'net_30' / 'net_60' = invoice later, paid by roaster-defined flow
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS payment_terms text NOT NULL DEFAULT 'card';

COMMENT ON COLUMN customers.payment_terms IS 'How this customer pays. card=pay at shop checkout. net_X=invoice with X days to pay. Roaster-configurable per customer.';

ALTER TABLE customers
  DROP CONSTRAINT IF EXISTS customers_payment_terms_chk;
ALTER TABLE customers
  ADD CONSTRAINT customers_payment_terms_chk CHECK (
    payment_terms IN ('card','net_15','net_30','net_60')
  );


-- -----------------------------------------------------------------------------
-- 4.  shop_config — payments_enabled
-- -----------------------------------------------------------------------------
ALTER TABLE shop_config
  ADD COLUMN IF NOT EXISTS payments_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN shop_config.payments_enabled IS 'Shop accepts card payments at checkout via Activity Pay. Requires subscription_plans.can_accept_payments=true.';


-- -----------------------------------------------------------------------------
-- 5.  subscription_plans — can_accept_payments (Pro & Enterprise only)
-- -----------------------------------------------------------------------------
ALTER TABLE subscription_plans
  ADD COLUMN IF NOT EXISTS can_accept_payments boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN subscription_plans.can_accept_payments IS 'Whether this tier is allowed to enable shop payments. Pro+ only.';

UPDATE subscription_plans
  SET can_accept_payments = true
  WHERE plan_id IN ('pro','enterprise','enterprise_plus');


-- -----------------------------------------------------------------------------
-- 6.  payment_transactions — gateway call ledger
-- -----------------------------------------------------------------------------
-- One row per Activity Pay API call that touches money.  Captures the fee
-- split so we can bill roasters monthly without re-deriving it.
CREATE TABLE IF NOT EXISTS payment_transactions (
  payment_transaction_id  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              text        NOT NULL REFERENCES companies (company_id) ON DELETE RESTRICT,
  order_id                text        REFERENCES orders (order_id) ON DELETE SET NULL,

  -- Gateway identifiers
  provider                text        NOT NULL DEFAULT 'activitypay',
  provider_transaction_id text,        -- AP's transaction id
  idempotency_key         text,        -- key we sent to AP for safe retry

  -- What this row represents
  type                    text        NOT NULL,  -- sale | auth | capture | refund | void
  status                  text        NOT NULL,  -- pending | approved | declined | failed | voided

  -- Money (all in cents, integer, STRATA's reporting currency — USD)
  gross_amount_cents      integer     NOT NULL,  -- total charged / refunded
  gateway_fee_cents       integer,               -- AP's fee on this txn
  platform_fee_cents      integer,               -- STRATA's 0.5% markup
  roaster_payout_cents    integer,               -- gross − gateway − platform (owed to roaster)

  -- Response
  response_code           text,
  response_text           text,
  raw_response            jsonb,

  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              text,
  updated_by              text
);

COMMENT ON TABLE  payment_transactions                         IS 'Immutable-ish ledger of every Activity Pay money-touching call. Feeds monthly roaster statements.';
COMMENT ON COLUMN payment_transactions.idempotency_key         IS 'Key sent to AP so that network retries do not double-charge. Unique per logical attempt.';
COMMENT ON COLUMN payment_transactions.gateway_fee_cents       IS 'AP fee for this transaction. Negative for refunds (fee returned).';
COMMENT ON COLUMN payment_transactions.platform_fee_cents      IS 'STRATA 0.5% markup on this transaction. Negative for refunds.';
COMMENT ON COLUMN payment_transactions.roaster_payout_cents    IS 'Net amount owed to the roaster for this transaction. gross − gateway − platform.';

ALTER TABLE payment_transactions
  DROP CONSTRAINT IF EXISTS payment_transactions_type_chk,
  DROP CONSTRAINT IF EXISTS payment_transactions_status_chk;
ALTER TABLE payment_transactions
  ADD CONSTRAINT payment_transactions_type_chk
    CHECK (type IN ('sale','auth','capture','refund','void')),
  ADD CONSTRAINT payment_transactions_status_chk
    CHECK (status IN ('pending','approved','declined','failed','voided'));

CREATE INDEX IF NOT EXISTS idx_payment_txn_company ON payment_transactions (company_id);
CREATE INDEX IF NOT EXISTS idx_payment_txn_order   ON payment_transactions (order_id);
CREATE INDEX IF NOT EXISTS idx_payment_txn_provider_ref
  ON payment_transactions (provider_transaction_id)
  WHERE provider_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_txn_idempotency
  ON payment_transactions (idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_txn_company_created
  ON payment_transactions (company_id, created_at DESC);  -- monthly statement query

-- updated_at trigger
CREATE OR REPLACE FUNCTION trg_set_payment_txn_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_txn_updated_at ON payment_transactions;
CREATE TRIGGER trg_payment_txn_updated_at
  BEFORE UPDATE ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION trg_set_payment_txn_updated_at();

-- Audit hooks (same pattern as rest of app)
DROP TRIGGER IF EXISTS trg_audit_insert ON payment_transactions;
CREATE TRIGGER trg_audit_insert
  BEFORE INSERT ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION handle_new_record();

DROP TRIGGER IF EXISTS trg_audit_update ON payment_transactions;
CREATE TRIGGER trg_audit_update
  BEFORE UPDATE ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION handle_updated_record();


-- -----------------------------------------------------------------------------
-- 7.  payment_webhook_events — idempotency + audit for AP webhooks
-- -----------------------------------------------------------------------------
-- Every webhook AP sends lands here first. We dedupe on provider_event_id
-- so re-deliveries don't double-apply. Processing status lets us retry on
-- transient errors.
CREATE TABLE IF NOT EXISTS payment_webhook_events (
  webhook_event_id    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider            text        NOT NULL DEFAULT 'activitypay',
  provider_event_id   text        NOT NULL,   -- AP's event id
  event_type          text        NOT NULL,   -- 'transaction.approved' | etc.
  provider_transaction_id text,

  signature_valid     boolean     NOT NULL,
  processed           boolean     NOT NULL DEFAULT false,
  processed_at        timestamptz,
  processing_error    text,

  payload             jsonb       NOT NULL,
  received_at         timestamptz NOT NULL DEFAULT now(),

  UNIQUE (provider, provider_event_id)
);

COMMENT ON TABLE  payment_webhook_events IS 'Every Activity Pay webhook lands here. provider+provider_event_id is unique so redeliveries are no-ops.';

CREATE INDEX IF NOT EXISTS idx_webhook_events_unprocessed
  ON payment_webhook_events (received_at)
  WHERE processed = false;
CREATE INDEX IF NOT EXISTS idx_webhook_events_txn_ref
  ON payment_webhook_events (provider_transaction_id)
  WHERE provider_transaction_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 8.  shop_order_ref_counter  +  allocate_shop_order_ref(company_id)
-- -----------------------------------------------------------------------------
-- Customer-facing order numbers like "SH-000123". Counter is per-company so
-- each roaster gets their own clean sequence starting at 1.
CREATE TABLE IF NOT EXISTS shop_order_ref_counter (
  company_id  text    PRIMARY KEY REFERENCES companies (company_id) ON DELETE CASCADE,
  next_value  bigint  NOT NULL DEFAULT 1
);

COMMENT ON TABLE shop_order_ref_counter IS 'Per-company counter for shop_order_ref allocation. Row is lazily created on first call to allocate_shop_order_ref().';

CREATE OR REPLACE FUNCTION allocate_shop_order_ref(p_company_id text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_next bigint;
BEGIN
  -- Upsert-and-return in one shot. ON CONFLICT takes the row lock so
  -- concurrent callers serialize cleanly.
  INSERT INTO shop_order_ref_counter (company_id, next_value)
    VALUES (p_company_id, 2)
  ON CONFLICT (company_id) DO UPDATE
    SET next_value = shop_order_ref_counter.next_value + 1
  RETURNING next_value - 1 INTO v_next;

  RETURN 'SH-' || lpad(v_next::text, 6, '0');
END;
$$;

COMMENT ON FUNCTION allocate_shop_order_ref(text) IS 'Atomically allocates the next shop_order_ref for a company. Format: SH-000001, SH-000002, ...';
