BEGIN;
-- Get rid of the leftover/trash 'Maui' coffee group (split into Maui Red/
-- Yellow/Mokka/H3/Peaberry/Decaf). Soft-archive the group + its sources.
UPDATE coffee_inventory SET is_active = false, updated_at = now()
  WHERE company_id = '9ShiyDAXhV' AND origin_id = 'orig_142ffc976e750f22';
UPDATE coffee_source SET is_active = false, updated_at = now()
  WHERE company_id = '9ShiyDAXhV' AND origin_id = 'orig_142ffc976e750f22' AND is_active;

-- Peaberry should appear in the composed/label name. The v3 backfill left
-- grade_label NULL for peaberry-only sources, so the '·' label (which reads
-- grade_label) dropped it. Carry 'Peaberry' in grade_label (matches what
-- composeGradeLabel produces on edit).
UPDATE coffee_source
  SET grade_label = NULLIF(TRIM(COALESCE(grade_label, '') || ' Peaberry'), ''),
      updated_at = now()
  WHERE company_id = '9ShiyDAXhV' AND is_active AND is_peaberry
    AND (grade_label IS NULL OR grade_label NOT ILIKE '%peaberry%');
COMMIT;
