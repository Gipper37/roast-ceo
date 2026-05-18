-- ============================================================
-- Equipment Phase 9.2: per-tenant override of global parts
-- ============================================================
-- Mirrors the maintenance_template + equipment_schedule pattern.
-- The global parts_catalog row is never mutated; tenants store
-- their custom pricing/supplier/notes in this table. Reads
-- coalesce override → global so unchanged fields fall through.
--
-- Only "soft" fields are overrideable. Identity (name, number,
-- category, brand) stays locked to the global — if a tenant
-- needs to fork those they create a new tenant-scoped part via
-- the existing "+ Add part" flow.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.parts_catalog_override (
  company_id          text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  part_id             text NOT NULL REFERENCES public.parts_catalog(part_id) ON DELETE CASCADE,
  default_unit_cost   numeric,
  default_markup_pct  numeric,
  supplier            text,
  notes               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          text,
  PRIMARY KEY (company_id, part_id)
);

CREATE INDEX parts_catalog_override_part_idx
  ON public.parts_catalog_override (part_id);

ALTER TABLE public.parts_catalog_override ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.parts_catalog_override
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));

COMMENT ON TABLE public.parts_catalog_override IS
  'Per-tenant overrides of global parts_catalog rows. Only present when a tenant has actively customized a global. Read path coalesces override → global; missing override fields fall through to the global value. Same mental model as equipment_schedule overriding maintenance_template cadences.';
