-- Invoice-of-record SPINE (Phase 0). ADDITIVE schema only — NO behavior change.
-- Adds the invoice numbering + lifecycle columns to `orders`, a per-company
-- `billing_settings` (the mode flag + gap-free invoice/credit-memo counters +
-- cutover date), and `qb_import_batches` (reversible import runs, modeled on the
-- existing `data_imports`). All numbering/AR machinery stays DORMANT until later
-- phases wire the functions/triggers/UI. Nothing here changes existing behavior:
-- every new orders column is nullable or defaulted; companies with no
-- billing_settings row are treated as Mode B ("keep QuickBooks") by the app.
-- Plan: memory/project_invoice_of_record.md.

-- ── orders: invoice document spine ────────────────────────────────────────────
-- invoice_state is the A/R lifecycle axis, DISTINCT from order_status (which
-- stays fulfillment: Open/Packed/Delivered/Canceled). Null until an order is
-- finalized as an invoice.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS invoice_number         text,
  ADD COLUMN IF NOT EXISTS invoice_sequence       bigint,
  ADD COLUMN IF NOT EXISTS invoice_state          text,
  ADD COLUMN IF NOT EXISTS due_date               date,
  ADD COLUMN IF NOT EXISTS invoice_terms_snapshot text,
  ADD COLUMN IF NOT EXISTS invoice_sent_at        timestamptz,
  ADD COLUMN IF NOT EXISTS voided_at              timestamptz,
  ADD COLUMN IF NOT EXISTS written_off_at         timestamptz,
  ADD COLUMN IF NOT EXISTS posted                 boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_legacy_import       boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.orders.invoice_number IS 'STRATA sequential invoice number (allocated on finalize; unique per company). For QB-imported history the original QB Num is kept as reference, not a STRATA number.';
COMMENT ON COLUMN public.orders.invoice_state IS 'A/R lifecycle (draft/open/partial/paid/overdue/void/written_off) — SEPARATE from order_status (fulfillment).';
COMMENT ON COLUMN public.orders.posted IS 'Post-and-lock: once true, the invoice document is immutable (edits go via void-and-reissue or credit memo).';
COMMENT ON COLUMN public.orders.is_legacy_import IS 'True for QB-imported historical orders — reported/reprintable but NOT assigned a real STRATA invoice number.';

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_invoice_state_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_invoice_state_check
  CHECK (invoice_state IS NULL OR invoice_state IN
    ('draft','open','partial','paid','overdue','void','written_off'));

-- Invoice number unique PER COMPANY when assigned (gap-free counter in billing_settings).
CREATE UNIQUE INDEX IF NOT EXISTS orders_company_invoice_number_uidx
  ON public.orders (company_id, invoice_number)
  WHERE invoice_number IS NOT NULL;

-- "Who owes you" / aging lookups (later phases).
CREATE INDEX IF NOT EXISTS orders_ar_open_idx
  ON public.orders (company_id, invoice_state, due_date)
  WHERE invoice_state IS NOT NULL;

-- ── billing_settings: per-company invoice-of-record config + gap-free counters ─
CREATE TABLE IF NOT EXISTS public.billing_settings (
  company_id           text PRIMARY KEY REFERENCES public.companies(company_id) ON DELETE CASCADE,
  -- The single flag every billing surface gates on. Default 'quickbooks' (Mode B)
  -- so existing tenants get NO new billing behavior until they opt into 'strata'.
  invoice_of_record    text NOT NULL DEFAULT 'quickbooks'
                         CHECK (invoice_of_record IN ('strata','quickbooks')),
  invoice_prefix       text,                        -- e.g. 'INV-'
  invoice_next_seq     bigint  NOT NULL DEFAULT 1,  -- allocate_invoice_number() bumps this (later phase)
  invoice_pad_width    integer NOT NULL DEFAULT 6,  -- zero-pad -> INV-000123
  credit_memo_prefix   text,                        -- e.g. 'CM-'
  credit_memo_next_seq bigint  NOT NULL DEFAULT 1,  -- SEPARATE sequence (jurisdiction-compliant)
  cutover_date         date,                        -- Mode A cutover (set in the cutover phase)
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.billing_settings IS 'Per-company invoice-of-record settings + gap-free invoice/credit-memo counters. No row => Mode B (keep QuickBooks).';

ALTER TABLE public.billing_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.billing_settings;
CREATE POLICY tenant_company_access ON public.billing_settings
  FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids()))
  WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- ── qb_import_batches: reversible import runs (models data_imports) ────────────
CREATE TABLE IF NOT EXISTS public.qb_import_batches (
  batch_id         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id       text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  facility_id      text REFERENCES public.facilities(facility_id) ON DELETE SET NULL,
  mode             text NOT NULL CHECK (mode IN ('strata','quickbooks')),  -- Mode A (full) / Mode B (light)
  source           text,          -- 'qb_desktop_csv' | 'qb_online_csv'
  scope            jsonb,         -- {customers:true, products:true, orders:true, ar:false}
  date_from        date,          -- historical sales cutoff (user-chosen)
  date_to          date,
  cutover_date     date,          -- Mode A A/R cutover
  status           text NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','previewed','committed','reverted','failed')),
  counts           jsonb,         -- {customers_created, products_linked, orders_created, lines, skipped, ...}
  errors           jsonb,
  created_log_ids  text[],        -- ids created this batch (one-click Undo)
  created_by       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  committed_at     timestamptz,
  reverted_at      timestamptz
);
COMMENT ON TABLE public.qb_import_batches IS 'One row per QB import run — reversible (created_log_ids / created_by tag) + resumable. Replaces the hardcoded mcr-qb-import tag.';

CREATE INDEX IF NOT EXISTS qb_import_batches_company_idx
  ON public.qb_import_batches (company_id, created_at DESC);

ALTER TABLE public.qb_import_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.qb_import_batches;
CREATE POLICY tenant_company_access ON public.qb_import_batches
  FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids()))
  WITH CHECK (company_id IN (SELECT auth_company_ids()));

NOTIFY pgrst, 'reload schema';
