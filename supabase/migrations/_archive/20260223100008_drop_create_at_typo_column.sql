-- Migration: Drop create_at typo column from sales_notes
--
-- Issue 16: sales_notes (schema.sql line 6539) has two nearly identical columns:
--
--   create_at  timestamp with time zone          -- line 6547, NO DEFAULT, always NULL
--   created_at timestamp with time zone DEFAULT now()  -- line 6548, correct
--
-- create_at is a typo from initial table creation. It has no DEFAULT and is never
-- written by any trigger — trg_audit_insert -> handle_new_record() writes only
-- to created_at and updated_at. The column is always NULL.
--
-- DROP COLUMN IF EXISTS is idempotent — safe to re-run.

ALTER TABLE public.sales_notes DROP COLUMN IF EXISTS create_at;
