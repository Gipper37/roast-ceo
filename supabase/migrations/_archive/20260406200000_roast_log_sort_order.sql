-- Add sort_order to roast_log for drag-to-reorder of uncharged rows
ALTER TABLE public.roast_log
  ADD COLUMN IF NOT EXISTS sort_order integer;
