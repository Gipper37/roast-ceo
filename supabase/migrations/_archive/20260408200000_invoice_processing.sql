-- Invoice AI Processing: tables for staging AI-extracted shipment data
-- and a private storage bucket for invoice files.

-- ── 1. invoice_documents ────────────────────────────────────────────

CREATE TABLE public.invoice_documents (
    invoice_document_id text NOT NULL PRIMARY KEY DEFAULT gen_random_uuid()::text,
    staged_shipment_id  text,
    file_path           text NOT NULL,
    file_name           text,
    file_type           text,
    source              text NOT NULL DEFAULT 'upload',
    email_from          text,
    email_subject       text,
    company_id          text NOT NULL REFERENCES public.companies(company_id),
    facility_id         text NOT NULL REFERENCES public.facilities(facility_id),
    created_at          timestamptz DEFAULT now(),
    updated_at          timestamptz DEFAULT now(),
    created_by          text,
    updated_by          text
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.invoice_documents
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.invoice_documents
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- ── 2. staged_shipments ─────────────────────────────────────────────

CREATE TABLE public.staged_shipments (
    staged_shipment_id  text NOT NULL PRIMARY KEY DEFAULT gen_random_uuid()::text,
    status              text NOT NULL DEFAULT 'processing',
    supplier_name_raw   text,
    supplier_id         text,
    supplier_confidence numeric,
    order_date          date,
    shipping_cost       numeric,
    currency            text DEFAULT 'USD',
    invoice_number      text,
    ai_raw_response     jsonb,
    confirmed_shipment_id text,
    processing_error    text,
    company_id          text NOT NULL REFERENCES public.companies(company_id),
    facility_id         text NOT NULL REFERENCES public.facilities(facility_id),
    created_at          timestamptz DEFAULT now(),
    updated_at          timestamptz DEFAULT now(),
    created_by          text,
    updated_by          text
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.staged_shipments
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.staged_shipments
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- FK from invoice_documents → staged_shipments (deferred to allow insert order flexibility)
ALTER TABLE public.invoice_documents
    ADD CONSTRAINT invoice_documents_staged_shipment_fkey
    FOREIGN KEY (staged_shipment_id) REFERENCES public.staged_shipments(staged_shipment_id)
    ON DELETE SET NULL;

-- ── 3. staged_line_items ────────────────────────────────────────────

CREATE TABLE public.staged_line_items (
    staged_line_item_id text NOT NULL PRIMARY KEY DEFAULT gen_random_uuid()::text,
    staged_shipment_id  text NOT NULL REFERENCES public.staged_shipments(staged_shipment_id) ON DELETE CASCADE,
    line_type           text NOT NULL DEFAULT 'coffee',
    item_name_raw       text,

    -- Coffee fields
    coffee_source_id    text,
    coffee_source_confidence numeric,
    origin_id           text,
    bags_ordered        numeric,
    cost_per_unit       numeric,
    cost_unit           text DEFAULT 'lb',
    bag_size            numeric,
    lot_number          text,
    harvest_year        text,

    -- Consumable fields
    consumable_id       text,
    consumable_confidence numeric,
    units_ordered       numeric,
    cost_per_consumable numeric,

    line_total          numeric,
    sort_order          integer DEFAULT 0,
    company_id          text NOT NULL REFERENCES public.companies(company_id),
    facility_id         text NOT NULL REFERENCES public.facilities(facility_id),
    created_at          timestamptz DEFAULT now(),
    updated_at          timestamptz DEFAULT now(),
    created_by          text,
    updated_by          text
);

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.staged_line_items
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();
CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.staged_line_items
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();

-- ── 4. Indexes ──────────────────────────────────────────────────────

CREATE INDEX idx_staged_shipments_company_facility
    ON public.staged_shipments(company_id, facility_id);
CREATE INDEX idx_staged_shipments_status
    ON public.staged_shipments(status);
CREATE INDEX idx_staged_line_items_shipment
    ON public.staged_line_items(staged_shipment_id);
CREATE INDEX idx_invoice_documents_staged
    ON public.invoice_documents(staged_shipment_id);

-- ── 5. Storage bucket (private — signed URLs for preview) ──────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'invoices',
    'invoices',
    false,
    20971520,  -- 20 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf']
);

-- Authenticated users can upload invoices
CREATE POLICY "Authenticated users can upload invoices"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'invoices');

-- Authenticated users can read their own invoices
CREATE POLICY "Authenticated users can read invoices"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'invoices');

-- Authenticated users can update their own invoices
CREATE POLICY "Authenticated users can update invoices"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'invoices');
