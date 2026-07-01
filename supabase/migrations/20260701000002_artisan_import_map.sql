-- Artisan importer: per-tenant learned mapping of Artisan blend titles /
-- origin names to STRATA recipes / coffee groups. Populated when the user
-- resolves an unmatched blend or origin in the .alog history-import step, and
-- reused to pre-fill matches on subsequent uploads — the "learned matching"
-- that replaces any hardcoded, customer-specific alias table.
--
-- NOTE: this is an IMPORT-TOOL-SCOPED lookup, deliberately NOT an
-- external_id/artisan_id column on the catalog tables (coffee_inventory /
-- roast_recipes) — those were kept free of importer identifiers by design.

CREATE TABLE IF NOT EXISTS public.artisan_import_map (
  map_id              text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id          text NOT NULL REFERENCES public.companies(company_id)   ON DELETE CASCADE,
  facility_id         text NOT NULL REFERENCES public.facilities(facility_id) ON DELETE CASCADE,
  kind                text NOT NULL CHECK (kind IN ('blend','origin')),
  source_name_norm    text NOT NULL,   -- normalized Artisan title / origin name (the match key)
  source_name_display text,            -- last-seen raw name, for the UI
  target_kind         text NOT NULL CHECK (target_kind IN ('recipe','group','ignore')),
  target_id           text,            -- recipe_id (kind=blend) / origin_id (kind=origin); NULL for 'ignore'
                                        -- polymorphic, so no FK; the resolver drops stale targets at read time.
  created_by          text,
  updated_by          text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (facility_id, kind, source_name_norm)
);
COMMENT ON TABLE public.artisan_import_map IS
  'Per-tenant learned mapping: Artisan blend title / origin name -> STRATA recipe / coffee group (or ignore). Pre-fills the .alog history-import matching step on re-upload.';

CREATE INDEX IF NOT EXISTS artisan_import_map_lookup_idx
  ON public.artisan_import_map (facility_id, kind, source_name_norm);

ALTER TABLE public.artisan_import_map ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_company_access ON public.artisan_import_map;
CREATE POLICY tenant_company_access ON public.artisan_import_map
  FOR ALL TO authenticated
  USING (company_id IN (SELECT auth_company_ids()))
  WITH CHECK (company_id IN (SELECT auth_company_ids()));
