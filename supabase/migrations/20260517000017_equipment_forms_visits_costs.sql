-- ============================================================
-- Equipment Phase 8.3-4: forms, visits, granular pricing
-- ============================================================
-- This is the "standalone-app" part: real form-based maintenance with
-- per-step checklists, per-task labor cost, per-part markup, and
-- visit-level invoicing.
--
-- Adds:
--   A) maintenance_template_step + maintenance_log_step
--      → Every template can have an ordered list of checklist items
--        (with optional measurement label/unit). When the task is
--        logged, each step records pass/fail + the measurement value.
--
--   B) labor_hours + labor_rate + labor_cost on maintenance_log
--      markup_pct on maintenance_part_used + computed line_total
--      → Per-task labor and per-part markup. Total cost stays as
--        the source of truth (user can override with a flat fee
--        for ad-hoc visits) but the per-component breakdown is now
--        captured.
--
--   C) equipment_visit + equipment_visit_line_item
--      → One service trip = one visit. A visit groups N maintenance
--        log entries (each can be a scheduled task) PLUS arbitrary
--        custom line items (e.g. "Replace fuse" that doesn't map to
--        any template). Visit has trip fee, tax, discount, and a
--        computed grand total — invoice-shaped.
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- A) Checklist sub-items per template
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.maintenance_template_step (
  step_id          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  template_id      text NOT NULL REFERENCES public.maintenance_template(template_id) ON DELETE CASCADE,
  sort_order       int  NOT NULL,
  description      text NOT NULL,
  -- Optional measurement capture: a label + unit + acceptable range
  measurement_label text,    -- e.g. "Brew pressure"
  measurement_unit  text,    -- e.g. "bar"
  measurement_min   numeric, -- alert if reading is below
  measurement_max   numeric, -- alert if reading is above
  is_required      boolean NOT NULL DEFAULT true,
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maintenance_template_step_template_idx
  ON public.maintenance_template_step (template_id, sort_order);

ALTER TABLE public.maintenance_template_step ENABLE ROW LEVEL SECURITY;
-- Steps inherit visibility from the parent template: global templates
-- are globally readable; tenant templates only to that tenant.
CREATE POLICY catalog_read_global ON public.maintenance_template_step
  FOR SELECT TO authenticated USING (
    template_id IN (SELECT template_id FROM public.maintenance_template WHERE company_id IS NULL)
  );
CREATE POLICY tenant_company_access ON public.maintenance_template_step
  FOR ALL TO authenticated USING (
    template_id IN (
      SELECT template_id FROM public.maintenance_template
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );


-- Per-log step completions
CREATE TABLE IF NOT EXISTS public.maintenance_log_step (
  id                bigserial PRIMARY KEY,
  log_id            text NOT NULL REFERENCES public.maintenance_log(log_id) ON DELETE CASCADE,
  step_id           text NOT NULL REFERENCES public.maintenance_template_step(step_id) ON DELETE RESTRICT,
  company_id        text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  completed         boolean NOT NULL DEFAULT false,
  outcome           text CHECK (outcome IN ('pass','fail','n/a','flag')),
  measurement_value numeric,
  notes             text,
  recorded_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maintenance_log_step_log_idx ON public.maintenance_log_step (log_id);
CREATE UNIQUE INDEX maintenance_log_step_uniq ON public.maintenance_log_step (log_id, step_id);

ALTER TABLE public.maintenance_log_step ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.maintenance_log_step
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- B) Granular pricing on log + parts
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.maintenance_log
  ADD COLUMN IF NOT EXISTS labor_hours numeric,
  ADD COLUMN IF NOT EXISTS labor_rate  numeric,  -- $/hr at time of logging
  ADD COLUMN IF NOT EXISTS labor_cost  numeric GENERATED ALWAYS AS (
    COALESCE(labor_hours, 0) * COALESCE(labor_rate, 0)
  ) STORED,
  -- Visit grouping: NULL = standalone log entry; set = part of a visit
  ADD COLUMN IF NOT EXISTS visit_id    text;  -- FK added after equipment_visit exists

ALTER TABLE public.maintenance_part_used
  ADD COLUMN IF NOT EXISTS markup_pct numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS line_total numeric GENERATED ALWAYS AS (
    COALESCE(quantity, 0) * COALESCE(unit_cost, 0) * (1 + COALESCE(markup_pct, 0) / 100)
  ) STORED;

COMMENT ON COLUMN public.maintenance_log.labor_cost IS
  'Computed labor_hours × labor_rate. Read-only — set the components.';
COMMENT ON COLUMN public.maintenance_part_used.line_total IS
  'Computed quantity × unit_cost × (1 + markup_pct/100). Read-only — set the components.';


-- ────────────────────────────────────────────────────────────────
-- C) Visit grouping (multi-task service trip)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.equipment_visit (
  visit_id          text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id        text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  equipment_id      text NOT NULL REFERENCES public.equipment(equipment_id) ON DELETE CASCADE,
  visited_at        timestamptz NOT NULL DEFAULT now(),
  technician_team_member text REFERENCES public.team(team_member_id) ON DELETE SET NULL,
  technician_company text,  -- when external
  technician_name    text,  -- when external
  summary_notes     text,
  -- Default labor rate for line items in this visit (line items can override)
  default_labor_rate numeric,
  -- Visit-level extras
  trip_fee          numeric NOT NULL DEFAULT 0,
  tax_rate          numeric NOT NULL DEFAULT 0,  -- percent
  discount_amount   numeric NOT NULL DEFAULT 0,
  -- Aggregated cost columns (recomputed by trigger when line items change)
  labor_subtotal    numeric NOT NULL DEFAULT 0,
  parts_subtotal    numeric NOT NULL DEFAULT 0,
  -- grand_total computed: labor + parts + trip_fee + tax - discount
  grand_total       numeric GENERATED ALWAYS AS (
    COALESCE(labor_subtotal, 0)
    + COALESCE(parts_subtotal, 0)
    + COALESCE(trip_fee, 0)
    + (COALESCE(labor_subtotal, 0) + COALESCE(parts_subtotal, 0) + COALESCE(trip_fee, 0))
      * COALESCE(tax_rate, 0) / 100
    - COALESCE(discount_amount, 0)
  ) STORED,
  status            text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed','invoiced')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text,
  updated_by        text
);
CREATE INDEX equipment_visit_equipment_idx ON public.equipment_visit (equipment_id);
CREATE INDEX equipment_visit_company_idx   ON public.equipment_visit (company_id);
CREATE INDEX equipment_visit_visited_idx   ON public.equipment_visit (visited_at DESC);

ALTER TABLE public.equipment_visit ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_visit
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- Now wire the maintenance_log.visit_id FK
ALTER TABLE public.maintenance_log
  ADD CONSTRAINT maintenance_log_visit_fk
  FOREIGN KEY (visit_id) REFERENCES public.equipment_visit(visit_id) ON DELETE SET NULL;
CREATE INDEX maintenance_log_visit_idx ON public.maintenance_log (visit_id) WHERE visit_id IS NOT NULL;


-- ────────────────────────────────────────────────────────────────
-- Custom line items — for things that aren't tied to a template
-- (e.g. "Replace fuse", "Diagnostic time", "Pickup + return") which
-- show up alongside maintenance_log entries on the visit invoice.
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.equipment_visit_line_item (
  id           bigserial PRIMARY KEY,
  visit_id     text NOT NULL REFERENCES public.equipment_visit(visit_id) ON DELETE CASCADE,
  company_id   text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('labor','part','fee','other')),
  description  text NOT NULL,
  quantity     numeric NOT NULL DEFAULT 1,
  unit_cost    numeric NOT NULL DEFAULT 0,
  markup_pct   numeric NOT NULL DEFAULT 0,
  line_total   numeric GENERATED ALWAYS AS (
    COALESCE(quantity, 0) * COALESCE(unit_cost, 0) * (1 + COALESCE(markup_pct, 0) / 100)
  ) STORED,
  notes        text,
  sort_order   int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX equipment_visit_line_item_visit_idx ON public.equipment_visit_line_item (visit_id, sort_order);

ALTER TABLE public.equipment_visit_line_item ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_visit_line_item
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ────────────────────────────────────────────────────────────────
-- Trigger: keep equipment_visit.{labor_subtotal,parts_subtotal} in
-- sync as logs / parts / line items change.
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recompute_visit_totals(p_visit_id text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_labor numeric;
  v_parts numeric;
BEGIN
  IF p_visit_id IS NULL THEN RETURN; END IF;

  -- Labor = sum(maintenance_log.labor_cost) + sum(visit_line_item where kind='labor')
  SELECT
    COALESCE((SELECT SUM(labor_cost) FROM public.maintenance_log WHERE visit_id = p_visit_id), 0)
    + COALESCE((SELECT SUM(line_total) FROM public.equipment_visit_line_item
                 WHERE visit_id = p_visit_id AND kind = 'labor'), 0)
    INTO v_labor;

  -- Parts = sum(maintenance_part_used.line_total via logs in this visit)
  --       + sum(visit_line_item where kind='part')
  SELECT
    COALESCE((SELECT SUM(p.line_total) FROM public.maintenance_part_used p
              JOIN public.maintenance_log l ON l.log_id = p.log_id
              WHERE l.visit_id = p_visit_id), 0)
    + COALESCE((SELECT SUM(line_total) FROM public.equipment_visit_line_item
                 WHERE visit_id = p_visit_id AND kind = 'part'), 0)
    INTO v_parts;

  UPDATE public.equipment_visit
     SET labor_subtotal = v_labor,
         parts_subtotal = v_parts,
         updated_at     = now()
   WHERE visit_id = p_visit_id;
END
$$;

-- Trigger functions that call recompute on any cost-affecting change
CREATE OR REPLACE FUNCTION public.tg_visit_recompute_from_log()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.visit_id IS NOT NULL THEN PERFORM public.recompute_visit_totals(OLD.visit_id); END IF;
  ELSE
    IF NEW.visit_id IS NOT NULL THEN PERFORM public.recompute_visit_totals(NEW.visit_id); END IF;
    IF TG_OP = 'UPDATE' AND OLD.visit_id IS DISTINCT FROM NEW.visit_id AND OLD.visit_id IS NOT NULL THEN
      PERFORM public.recompute_visit_totals(OLD.visit_id);
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END
$$;

CREATE TRIGGER trg_visit_recompute_log
  AFTER INSERT OR UPDATE OR DELETE ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.tg_visit_recompute_from_log();

CREATE OR REPLACE FUNCTION public.tg_visit_recompute_from_part()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_visit text;
BEGIN
  SELECT visit_id INTO v_visit FROM public.maintenance_log
    WHERE log_id = COALESCE(NEW.log_id, OLD.log_id);
  IF v_visit IS NOT NULL THEN PERFORM public.recompute_visit_totals(v_visit); END IF;
  RETURN COALESCE(NEW, OLD);
END
$$;

CREATE TRIGGER trg_visit_recompute_part
  AFTER INSERT OR UPDATE OR DELETE ON public.maintenance_part_used
  FOR EACH ROW EXECUTE FUNCTION public.tg_visit_recompute_from_part();

CREATE OR REPLACE FUNCTION public.tg_visit_recompute_from_line()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.recompute_visit_totals(COALESCE(NEW.visit_id, OLD.visit_id));
  RETURN COALESCE(NEW, OLD);
END
$$;

CREATE TRIGGER trg_visit_recompute_line
  AFTER INSERT OR UPDATE OR DELETE ON public.equipment_visit_line_item
  FOR EACH ROW EXECUTE FUNCTION public.tg_visit_recompute_from_line();
