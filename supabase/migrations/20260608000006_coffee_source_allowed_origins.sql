-- ============================================================
-- coffee_source.allowed_origin_ids — multi-group source usability
-- ============================================================
-- A coffee_source has a PRIMARY origin_id (where it primarily lives —
-- "Brazil Mogiana" belongs under "Brazil"). Some sources are useful
-- across multiple coffee groups too (a flavor base, an organic
-- single-origin that pairs into blends, etc.). The picker has been
-- filtering by primary origin only, which hides legitimate options.
--
-- allowed_origin_ids: text[] of ADDITIONAL coffee_inventory.origin_id
-- values this source is usable in. When empty, source only appears in
-- pickers matching its primary origin. When populated, source ALSO
-- appears for any matching origin in the list.
--
-- Default empty array — existing sources continue to show only under
-- their primary origin until an operator explicitly tags them.
-- ============================================================

ALTER TABLE public.coffee_source
  ADD COLUMN IF NOT EXISTS allowed_origin_ids text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.coffee_source.allowed_origin_ids IS
  'Extra coffee_inventory.origin_id values this source can be picked for, '
  'beyond its primary origin_id. Empty = primary-only (default). The roast '
  'logger picker shows a source when the recipe origin matches primary OR is '
  'in this array.';

CREATE INDEX IF NOT EXISTS coffee_source_allowed_origin_ids_gin
  ON public.coffee_source USING gin (allowed_origin_ids);

NOTIFY pgrst, 'reload schema';
