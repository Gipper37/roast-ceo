-- ============================================================
-- Equipment Phase 9.1: tenant pricing + parts catalog primitives
-- ============================================================
-- Stops treating prices as free-text inputs at log time. Manager+
-- maintains the catalog once; techs pick from dropdowns at work time.
--
-- Tables added in this migration:
--   company_labor_rate        — N labor rates per tenant
--                                (Standard, Emergency, After-Hours,
--                                 Weekend, Travel)
--   company_pricing_default   — single row per company with default
--                                rate/trip-fee/tax/markup
--   parts_catalog             — global + tenant catalog of parts with
--                                pricing
--   maintenance_template_part — which parts a template typically uses
--                                (quantity, required flag)
--
-- Already-existing template column `estimated_minutes` is now the
-- "standard labor minutes" — no new column needed.
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- company_labor_rate
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.company_labor_rate (
  labor_rate_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id    text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  rate_name     text NOT NULL,                     -- "Standard", "Emergency", "After Hours", "Weekend", "Travel"
  hourly_rate   numeric NOT NULL,                   -- $/hr (for Travel: rate per hour drive time)
  is_default    boolean NOT NULL DEFAULT false,
  sort_order    int     NOT NULL DEFAULT 0,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  updated_by    text,
  UNIQUE (company_id, lower(rate_name))
);
CREATE INDEX company_labor_rate_company_idx ON public.company_labor_rate (company_id, sort_order);

ALTER TABLE public.company_labor_rate ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.company_labor_rate
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- company_pricing_default — one row per company
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.company_pricing_default (
  company_id              text PRIMARY KEY REFERENCES public.companies(company_id) ON DELETE CASCADE,
  default_labor_rate_id   text REFERENCES public.company_labor_rate(labor_rate_id) ON DELETE SET NULL,
  default_trip_fee        numeric NOT NULL DEFAULT 0,
  default_tax_rate        numeric NOT NULL DEFAULT 0,  -- percent
  default_parts_markup_pct numeric NOT NULL DEFAULT 0,
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              text
);

ALTER TABLE public.company_pricing_default ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.company_pricing_default
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- parts_catalog — global + tenant
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.parts_catalog (
  part_id              text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  part_name            text NOT NULL,
  part_number          text,
  category             text NOT NULL,  -- matches equipment category
  applies_to_brand_id  text REFERENCES public.equipment_brand(equipment_brand_id) ON DELETE CASCADE,
  applies_to_model_id  text REFERENCES public.equipment_model(equipment_model_id) ON DELETE CASCADE,
  default_unit_cost    numeric,
  default_markup_pct   numeric NOT NULL DEFAULT 0,
  supplier             text,
  notes                text,
  company_id           text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           text,
  updated_by           text
);
CREATE INDEX parts_catalog_category_idx ON public.parts_catalog (category);
CREATE INDEX parts_catalog_brand_idx    ON public.parts_catalog (applies_to_brand_id);
CREATE INDEX parts_catalog_model_idx    ON public.parts_catalog (applies_to_model_id);
CREATE INDEX parts_catalog_company_idx  ON public.parts_catalog (company_id);

ALTER TABLE public.parts_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.parts_catalog
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.parts_catalog
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- maintenance_template_part — link parts to templates
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.maintenance_template_part (
  template_id text NOT NULL REFERENCES public.maintenance_template(template_id) ON DELETE CASCADE,
  part_id     text NOT NULL REFERENCES public.parts_catalog(part_id) ON DELETE CASCADE,
  quantity    numeric NOT NULL DEFAULT 1,           -- "1 per group" → use 1, then multiply at log time
  per_group   boolean NOT NULL DEFAULT false,        -- when true, multiply by equipment group_count (future)
  is_required boolean NOT NULL DEFAULT true,         -- vs "may need" suggestion
  notes       text,
  PRIMARY KEY (template_id, part_id)
);

ALTER TABLE public.maintenance_template_part ENABLE ROW LEVEL SECURITY;
-- Inherits visibility from parent template (global vs tenant)
CREATE POLICY catalog_read_global ON public.maintenance_template_part
  FOR SELECT TO authenticated USING (
    template_id IN (SELECT template_id FROM public.maintenance_template WHERE company_id IS NULL)
  );
CREATE POLICY tenant_company_access ON public.maintenance_template_part
  FOR ALL TO authenticated USING (
    template_id IN (
      SELECT template_id FROM public.maintenance_template
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );


-- ────────────────────────────────────────────────────────────────
-- Helper: get_or_create_pricing_defaults(company_id) — guarantees a
-- company has a pricing_default row, returns it. Called by the UI
-- on first load.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_company_pricing_default(p_company_id text)
RETURNS public.company_pricing_default
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r public.company_pricing_default;
BEGIN
  INSERT INTO public.company_pricing_default (company_id)
  VALUES (p_company_id)
  ON CONFLICT (company_id) DO NOTHING;
  SELECT * INTO r FROM public.company_pricing_default WHERE company_id = p_company_id;
  RETURN r;
END
$$;

GRANT EXECUTE ON FUNCTION public.ensure_company_pricing_default(text) TO authenticated;
