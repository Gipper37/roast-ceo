-- ============================================================
-- Equipment + maintenance — core schema (Phase 1 of the equipment project)
-- ============================================================
-- Tables this introduces:
--   equipment_brand           global + per-tenant catalog of manufacturers
--   equipment_model           global + per-tenant catalog of models
--   maintenance_template      global catalog of standard maintenance tasks
--   equipment                 instance — placed at a customer OR in-house
--   equipment_schedule        per-equipment scheduled task with next_due_at
--   maintenance_log           history of completed maintenance
--   maintenance_part_used     line items per log entry
--   equipment_document        manuals, warranties, photos, invoices
--   equipment_tech_contact    manufacturer + 3rd-party tech support directory
--
-- Pattern reused from coffee_source / consumable_type:
--   - Catalog tables use the global+tenant pattern: company_id NULL = global,
--     company_id set = tenant-owned override
--   - Maintenance templates have an "applies_to_brand" / "applies_to_model"
--     pair for granular overrides (e.g. La Marzocco PB needs special boiler
--     descale, otherwise the generic espresso_machine descale template applies)
--
-- Predictive maintenance hooks (Phase ..009 will compute these):
--   - equipment.cumulative_lbs_processed  (auto-updated from roast_log for
--                                          roaster equipment, from order_details
--                                          for grinder equipment via trigger)
--   - equipment.cumulative_hours          (manual entry today; sensor-fed later)
--   - maintenance_template.typical_lifespan_lbs / _hours — when cumulative
--     gets close to lifespan, equipment_due_status view flags as predicted_due
-- ============================================================

-- ------------------------------------------------------------
-- Brands (global + per-tenant)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment_brand (
  equipment_brand_id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  category           text NOT NULL CHECK (category IN (
    'espresso_machine','grinder','brewer','roaster','packaging',
    'water_treatment','scale','other'
  )),
  name               text NOT NULL,
  country            text,
  support_url        text,
  support_phone      text,
  support_email      text,
  company_id         text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text,
  updated_by         text
);
-- Unique (category, name) within the same scope (global OR per-company).
-- A tenant can shadow a global brand with their own override.
CREATE UNIQUE INDEX equipment_brand_scope_name_uq
  ON public.equipment_brand (category, COALESCE(company_id, ''), lower(name));

CREATE INDEX equipment_brand_company_idx ON public.equipment_brand (company_id);
CREATE INDEX equipment_brand_category_idx ON public.equipment_brand (category);

ALTER TABLE public.equipment_brand ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.equipment_brand
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.equipment_brand
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Models (global + per-tenant). brand_id can reference a global OR a
-- tenant-owned brand, but tenant models can only reference brands the
-- tenant can see — enforced at insert-time by the RLS read on brand.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment_model (
  equipment_model_id     text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  brand_id               text NOT NULL REFERENCES public.equipment_brand(equipment_brand_id) ON DELETE RESTRICT,
  category               text NOT NULL,  -- denormalized for filter queries
  model_name             text NOT NULL,
  generation             text,           -- e.g. "PB" vs "GB5", "v3"
  -- Predictive-maintenance hints (nullable — set when we know the spec)
  typical_lifespan_lbs   numeric,        -- e.g. burrs typically last 600-800 lbs
  typical_lifespan_hours numeric,        -- e.g. pump lasts 8000 hrs
  notes                  text,
  company_id             text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active              boolean NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  created_by             text,
  updated_by             text
);
CREATE UNIQUE INDEX equipment_model_scope_uq
  ON public.equipment_model (brand_id, COALESCE(company_id, ''), lower(model_name), COALESCE(generation, ''));
CREATE INDEX equipment_model_brand_idx ON public.equipment_model (brand_id);
CREATE INDEX equipment_model_company_idx ON public.equipment_model (company_id);
CREATE INDEX equipment_model_category_idx ON public.equipment_model (category);

ALTER TABLE public.equipment_model ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.equipment_model
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.equipment_model
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Maintenance templates (global + per-tenant overrides)
--
-- Tasks scope to a category; optionally constrained to a brand and/or
-- model. Resolution order at runtime: most specific match wins.
--   (category, brand, model) → use this
--   (category, brand)        → use this if no model-specific match
--   (category)               → fallback
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.maintenance_template (
  template_id        text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  category           text NOT NULL,
  applies_to_brand_id text REFERENCES public.equipment_brand(equipment_brand_id) ON DELETE CASCADE,
  applies_to_model_id text REFERENCES public.equipment_model(equipment_model_id) ON DELETE CASCADE,
  task_name          text NOT NULL,
  description        text,
  -- Frequency: time-based (daily..biennial) OR usage-based (hours / lbs / shots)
  frequency_type     text NOT NULL CHECK (frequency_type IN (
    'daily','weekly','monthly','quarterly','semi_annual',
    'annual','biennial','hours_used','lbs_processed','shots_pulled'
  )),
  frequency_interval numeric NOT NULL,  -- 1 = "every 1 day", "every 1 month", etc.
  -- Audience: client-recommended (not tracked, shown as suggestion) vs operator-tracked
  is_recommended_only boolean NOT NULL DEFAULT false,
  is_critical        boolean NOT NULL DEFAULT false,  -- safety / warranty-required
  estimated_minutes  int,
  parts_typically_needed jsonb,  -- [{name, part_number?}]
  tools_needed       jsonb,
  notes              text,
  company_id         text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active          boolean NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text,
  updated_by         text
);
CREATE INDEX maintenance_template_category_idx ON public.maintenance_template (category);
CREATE INDEX maintenance_template_brand_idx ON public.maintenance_template (applies_to_brand_id);
CREATE INDEX maintenance_template_model_idx ON public.maintenance_template (applies_to_model_id);
CREATE INDEX maintenance_template_company_idx ON public.maintenance_template (company_id);

ALTER TABLE public.maintenance_template ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.maintenance_template
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.maintenance_template
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Equipment instance — placed at a customer OR in-house at a facility
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment (
  equipment_id            text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id              text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  -- Exactly one of (facility_id, customer_id) must be set. facility_id = in-house,
  -- customer_id = at a customer's location.
  facility_id             text REFERENCES public.facilities(facility_id),
  customer_id             text REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  CONSTRAINT equipment_placement_xor CHECK (
    (facility_id IS NOT NULL AND customer_id IS NULL) OR
    (facility_id IS NULL     AND customer_id IS NOT NULL)
  ),
  -- Optional 1:1 link to an existing roaster_units row, so in-house roasters
  -- defined there flow through the equipment system without duplicate data.
  linked_roaster_unit_id  uuid REFERENCES public.roaster_units(roaster_unit_id) ON DELETE SET NULL,
  brand_id                text REFERENCES public.equipment_brand(equipment_brand_id) ON DELETE SET NULL,
  model_id                text REFERENCES public.equipment_model(equipment_model_id) ON DELETE SET NULL,
  category                text NOT NULL,  -- denormalized so the equipment list filters fast
  serial_number           text,
  asset_tag               text,           -- internal sticker label
  installed_at            date,
  acquired_at             date,
  status                  text NOT NULL DEFAULT 'active' CHECK (status IN (
    'active','inactive','needs_service','broken','decommissioned'
  )),
  location_notes          text,           -- "front bar", "grinder station 2"
  -- Cumulative usage counters (drive predictive maintenance)
  cumulative_hours        numeric NOT NULL DEFAULT 0,
  cumulative_lbs_processed numeric NOT NULL DEFAULT 0,
  photo_url               text,
  notes                   text,
  is_active               boolean NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              text,
  updated_by              text
);
CREATE INDEX equipment_company_idx          ON public.equipment (company_id);
CREATE INDEX equipment_customer_idx         ON public.equipment (customer_id);
CREATE INDEX equipment_facility_idx         ON public.equipment (facility_id);
CREATE INDEX equipment_category_idx         ON public.equipment (category);
CREATE INDEX equipment_status_idx           ON public.equipment (status);
CREATE INDEX equipment_roaster_unit_idx     ON public.equipment (linked_roaster_unit_id);

ALTER TABLE public.equipment ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Schedule — per-equipment instance of a template, with next_due_at.
-- An equipment can have many schedule rows (e.g. one for each periodic
-- task that applies to its category/brand/model). Default schedule is
-- materialized via a function in migration ..009.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment_schedule (
  schedule_id           text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id            text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  equipment_id          text NOT NULL REFERENCES public.equipment(equipment_id) ON DELETE CASCADE,
  template_id           text NOT NULL REFERENCES public.maintenance_template(template_id) ON DELETE RESTRICT,
  -- Denormalized + per-equipment overrideable
  frequency_type        text NOT NULL,
  frequency_interval    numeric NOT NULL,
  last_completed_at     timestamptz,
  next_due_at           timestamptz,  -- computed by trigger on update of last_completed_at
  assigned_team_member  text REFERENCES public.team(team_member_id) ON DELETE SET NULL,
  external_tech_company text,
  paused                boolean NOT NULL DEFAULT false,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            text,
  updated_by            text,
  UNIQUE (equipment_id, template_id)
);
CREATE INDEX equipment_schedule_equipment_idx ON public.equipment_schedule (equipment_id);
CREATE INDEX equipment_schedule_company_idx   ON public.equipment_schedule (company_id);
CREATE INDEX equipment_schedule_next_due_idx  ON public.equipment_schedule (next_due_at) WHERE paused = false;

ALTER TABLE public.equipment_schedule ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_schedule
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Maintenance log — history of completed maintenance
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.maintenance_log (
  log_id                text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id            text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  equipment_id          text NOT NULL REFERENCES public.equipment(equipment_id) ON DELETE CASCADE,
  schedule_id           text REFERENCES public.equipment_schedule(schedule_id) ON DELETE SET NULL,
  task_name             text NOT NULL,
  description           text,
  completed_at          timestamptz NOT NULL DEFAULT now(),
  completed_by_team_member text REFERENCES public.team(team_member_id) ON DELETE SET NULL,
  external_tech_company text,
  external_tech_name    text,
  notes                 text,
  total_cost            numeric,
  -- Snapshot counters at the moment of completion — used to compute
  -- "lbs / hours since last service" for predictive maintenance.
  hours_at_completion   numeric,
  lbs_at_completion     numeric,
  photo_urls            text[],
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            text,
  updated_by            text
);
CREATE INDEX maintenance_log_equipment_idx ON public.maintenance_log (equipment_id);
CREATE INDEX maintenance_log_schedule_idx  ON public.maintenance_log (schedule_id);
CREATE INDEX maintenance_log_company_idx   ON public.maintenance_log (company_id);
CREATE INDEX maintenance_log_completed_idx ON public.maintenance_log (completed_at DESC);

ALTER TABLE public.maintenance_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.maintenance_log
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Parts used — line items per maintenance log
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.maintenance_part_used (
  id          bigserial PRIMARY KEY,
  log_id      text NOT NULL REFERENCES public.maintenance_log(log_id) ON DELETE CASCADE,
  company_id  text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  part_name   text NOT NULL,
  part_number text,
  quantity    numeric NOT NULL DEFAULT 1,
  unit_cost   numeric,
  supplier    text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maintenance_part_used_log_idx ON public.maintenance_part_used (log_id);

ALTER TABLE public.maintenance_part_used ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.maintenance_part_used
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Documents (manuals, warranties, invoices, photos)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment_document (
  id            bigserial PRIMARY KEY,
  equipment_id  text NOT NULL REFERENCES public.equipment(equipment_id) ON DELETE CASCADE,
  company_id    text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  doc_type      text NOT NULL CHECK (doc_type IN (
    'manual','warranty','invoice','service_history','photo','spec_sheet','other'
  )),
  file_name     text NOT NULL,
  storage_path  text NOT NULL,
  uploaded_at   timestamptz NOT NULL DEFAULT now(),
  uploaded_by   text,
  notes         text
);
CREATE INDEX equipment_document_equipment_idx ON public.equipment_document (equipment_id);

ALTER TABLE public.equipment_document ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.equipment_document
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Tech contacts — manufacturer support + third-party service techs
-- Global rows = manufacturer support (any tenant can read).
-- Per-tenant rows = local technician contacts (only that tenant sees).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.equipment_tech_contact (
  contact_id    text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  brand_id      text REFERENCES public.equipment_brand(equipment_brand_id) ON DELETE CASCADE,
  category      text,  -- when brand_id is null, this contact services a whole category
  contact_name  text,  -- e.g. "Alex Rivera"
  company_name  text NOT NULL,  -- e.g. "La Marzocco USA Service"
  phone         text,
  email         text,
  website       text,
  notes         text,
  company_id    text REFERENCES public.companies(company_id) ON DELETE CASCADE,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  updated_by    text
);
CREATE INDEX equipment_tech_contact_brand_idx ON public.equipment_tech_contact (brand_id);
CREATE INDEX equipment_tech_contact_company_idx ON public.equipment_tech_contact (company_id);

ALTER TABLE public.equipment_tech_contact ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read_global ON public.equipment_tech_contact
  FOR SELECT TO authenticated USING (company_id IS NULL);
CREATE POLICY tenant_company_access ON public.equipment_tech_contact
  FOR ALL TO authenticated USING (company_id IN (SELECT auth_company_ids()));


-- ------------------------------------------------------------
-- Trigger: recompute equipment_schedule.next_due_at when
-- last_completed_at or frequency changes.
-- Time-based: next_due = last_completed + interval.
-- Usage-based: next_due is computed lazily by the equipment_due_status
-- view in migration ..009 (depends on cumulative_lbs / cumulative_hours).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_equipment_schedule_due()
RETURNS trigger AS $$
BEGIN
  IF NEW.last_completed_at IS NULL THEN
    -- Brand new schedule with no history — due now (or installed_at, if known)
    NEW.next_due_at := COALESCE(NEW.next_due_at, now());
  ELSE
    NEW.next_due_at := CASE NEW.frequency_type
      WHEN 'daily'        THEN NEW.last_completed_at + (NEW.frequency_interval || ' days')::interval
      WHEN 'weekly'       THEN NEW.last_completed_at + (NEW.frequency_interval * 7 || ' days')::interval
      WHEN 'monthly'      THEN NEW.last_completed_at + (NEW.frequency_interval || ' months')::interval
      WHEN 'quarterly'    THEN NEW.last_completed_at + (NEW.frequency_interval * 3 || ' months')::interval
      WHEN 'semi_annual'  THEN NEW.last_completed_at + (NEW.frequency_interval * 6 || ' months')::interval
      WHEN 'annual'       THEN NEW.last_completed_at + (NEW.frequency_interval || ' years')::interval
      WHEN 'biennial'     THEN NEW.last_completed_at + (NEW.frequency_interval * 2 || ' years')::interval
      ELSE NEW.next_due_at  -- usage-based: leave as-is, computed by view
    END;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recompute_schedule_due
  BEFORE INSERT OR UPDATE OF last_completed_at, frequency_type, frequency_interval
  ON public.equipment_schedule
  FOR EACH ROW EXECUTE FUNCTION public.recompute_equipment_schedule_due();

-- ------------------------------------------------------------
-- Trigger: when a maintenance_log is inserted, update the linked
-- schedule's last_completed_at (which cascades into next_due_at via
-- the trigger above).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.maintenance_log_update_schedule()
RETURNS trigger AS $$
BEGIN
  IF NEW.schedule_id IS NOT NULL THEN
    UPDATE public.equipment_schedule
       SET last_completed_at = NEW.completed_at
     WHERE schedule_id = NEW.schedule_id;
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_maintenance_log_update_schedule
  AFTER INSERT ON public.maintenance_log
  FOR EACH ROW EXECUTE FUNCTION public.maintenance_log_update_schedule();
