-- Migration: Drop duplicate tr_calculate_* triggers on 3 tables
--
-- Issue 6: Three tables each have TWO triggers wired to the same function,
-- causing every INSERT or UPDATE to run that function twice per row:
--
--   roast_detail_by_blend:
--     tr_calculate_roast_blend  (schema.sql line 8526) -> calculate_roast_by_blend()      [DROP]
--     trg_calculate_roast_blend (schema.sql line 9261) -> calculate_roast_by_blend()      [KEEP]
--
--   roast_detail:
--     tr_calculate_roast_detail (schema.sql line 8533) -> calculate_roast_detail_origin() [DROP]
--     trg_calculate_roast_origin(schema.sql line 9268) -> calculate_roast_detail_origin() [KEEP]
--
--   totals:
--     tr_calculate_totals       (schema.sql line 8540) -> calculate_totals_columns()      [DROP]
--     trg_calculate_totals      (schema.sql line 9275) -> calculate_totals_columns()      [KEEP]
--
-- The tr_* names follow an older naming convention. The trg_* names are the
-- standardized replacements already present in the schema. These functions each
-- run 5-6 subqueries and sit at the end of multiple cascade chains, so the
-- double-execution compounds significantly.
--
-- DROP TRIGGER IF EXISTS is idempotent — safe to run repeatedly.

DROP TRIGGER IF EXISTS tr_calculate_roast_blend ON public.roast_detail_by_blend;

DROP TRIGGER IF EXISTS tr_calculate_roast_detail ON public.roast_detail;

DROP TRIGGER IF EXISTS tr_calculate_totals ON public.totals;
