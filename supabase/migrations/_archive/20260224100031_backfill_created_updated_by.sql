-- Migration 00031: Backfill created_by / updated_by
-- Replaces the legacy email address with the correct team_member_id across
-- every base table in the public schema that has these columns.
-- Views are excluded automatically via table_type = 'BASE TABLE'.
-- Rows that are NULL or already a team_member_id are untouched.

DO $$
DECLARE
  old_val TEXT := 'ryan@brmg.co';
  new_val TEXT := '15e4644e';
  r       RECORD;
BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name
    FROM   information_schema.columns c
    JOIN   information_schema.tables  t
           ON  t.table_schema = c.table_schema
           AND t.table_name   = c.table_name
    WHERE  c.table_schema = 'public'
      AND  c.column_name  IN ('created_by', 'updated_by')
      AND  t.table_type   = 'BASE TABLE'
    ORDER  BY c.table_name, c.column_name
  LOOP
    EXECUTE format(
      'UPDATE public.%I SET %I = $1 WHERE %I = $2',
      r.table_name, r.column_name, r.column_name
    ) USING new_val, old_val;
  END LOOP;
END $$;
