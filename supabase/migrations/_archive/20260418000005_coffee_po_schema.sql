-- Coffee PO feature
--
-- Extends shipment_received, supplier, coffee_source, and
-- coffee_inventory_purchased so a "Coffee Purchase Order" lives entirely
-- inside the existing receiving model. A row in shipment_received starts
-- life as a draft PO (status='po_draft'), gets emailed to the supplier
-- (status='po_sent'), and finally becomes a received shipment when the
-- coffee arrives (status='received'). Voided POs continue to use the
-- existing voided BOOLEAN flag — no separate "canceled" status.
--
-- PO numbers reset every calendar year per facility: PO-YYYY-NNN, where
-- NNN is a zero-padded sequential integer scoped to (facility_id, year).
-- Concurrency is handled by the UNIQUE index on (facility_id, po_number)
-- — if two clients race, the loser hits the unique-violation and can
-- retry with the next number.

-- ---------------------------------------------------------------------------
-- shipment_received: PO lifecycle columns
-- ---------------------------------------------------------------------------

ALTER TABLE shipment_received
  ADD COLUMN IF NOT EXISTS po_number       text,
  ADD COLUMN IF NOT EXISTS status          text NOT NULL DEFAULT 'received',
  ADD COLUMN IF NOT EXISTS email_sent_at   timestamptz,
  ADD COLUMN IF NOT EXISTS email_sent_to   text,
  ADD COLUMN IF NOT EXISTS email_subject   text,
  ADD COLUMN IF NOT EXISTS notes           text,
  ADD COLUMN IF NOT EXISTS ai_generation_log jsonb,
  ADD COLUMN IF NOT EXISTS estimated_total numeric;

-- Status enum: po_draft → po_sent → received. Voided shipments use the
-- existing `voided` boolean instead of a "canceled" status, so the
-- lifecycle stays linear.
ALTER TABLE shipment_received
  DROP CONSTRAINT IF EXISTS shipment_received_status_check;

ALTER TABLE shipment_received
  ADD CONSTRAINT shipment_received_status_check
  CHECK (status IN ('po_draft', 'po_sent', 'received'));

-- Race-safe per-facility PO numbering. Two clients can't grab the same
-- number; the loser retries.
CREATE UNIQUE INDEX IF NOT EXISTS shipment_received_facility_po_uniq
  ON shipment_received (facility_id, po_number)
  WHERE po_number IS NOT NULL;

-- ---------------------------------------------------------------------------
-- supplier: contact + sourcing URLs for AI lookup + PO email
-- ---------------------------------------------------------------------------

ALTER TABLE supplier
  ADD COLUMN IF NOT EXISTS website       text,
  ADD COLUMN IF NOT EXISTS catalog_url   text,
  ADD COLUMN IF NOT EXISTS contact_name  text,
  ADD COLUMN IF NOT EXISTS contact_email text,
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS notes         text;

-- ---------------------------------------------------------------------------
-- coffee_source: tasting/marketing detail + supplier deep-link
-- ---------------------------------------------------------------------------

ALTER TABLE coffee_source
  ADD COLUMN IF NOT EXISTS flavor_notes      text,
  ADD COLUMN IF NOT EXISTS supplier_lot_url  text,
  ADD COLUMN IF NOT EXISTS cupping_score     numeric;

-- ---------------------------------------------------------------------------
-- coffee_inventory_purchased: per-line AI match audit trail
-- ---------------------------------------------------------------------------
--
-- These columns capture *why* an AI-suggested lot was matched to a
-- coffee_source row. Manual POs leave them NULL. We do NOT add a
-- per-line status — the parent shipment's `status` already tells us
-- whether the line is on a draft, sent, or received PO.

ALTER TABLE coffee_inventory_purchased
  ADD COLUMN IF NOT EXISTS ai_match_reason         text,
  ADD COLUMN IF NOT EXISTS ai_confidence           numeric,
  ADD COLUMN IF NOT EXISTS proposed_lot_url        text,
  ADD COLUMN IF NOT EXISTS supplier_response_notes text;

-- ---------------------------------------------------------------------------
-- next_po_number(facility_id) — yearly-reset sequential PO number
-- ---------------------------------------------------------------------------
--
-- Returns the next PO number string for a facility, formatted
-- 'PO-YYYY-NNN'. Counts only POs from the current calendar year so
-- numbering resets every Jan 1.
--
-- Implementation note: we parse the trailing integer with a regex
-- because po_number is free text — historical rows (none today) might
-- not match the format, in which case they're ignored.

CREATE OR REPLACE FUNCTION next_po_number(p_facility_id text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  current_year text := to_char(now(), 'YYYY');
  next_num     integer;
BEGIN
  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(split_part(po_number, '-', 3), '\D', '', 'g'), '')::integer
  ), 0) + 1
    INTO next_num
    FROM shipment_received
   WHERE facility_id = p_facility_id
     AND po_number LIKE 'PO-' || current_year || '-%';

  RETURN 'PO-' || current_year || '-' || lpad(next_num::text, 3, '0');
END;
$$;

COMMENT ON FUNCTION next_po_number(text) IS
  'Returns the next available PO number for a facility, formatted PO-YYYY-NNN. Resets to 001 each calendar year. Caller is responsible for retrying on UNIQUE violation if two clients race.';
