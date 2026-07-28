-- Make the QB import's stamp MOVE reversible.
--
-- products.qb_item_id is the durable bookmark tying a QuickBooks item name to the
-- STRATA product it means, so a later import resolves it by id instead of re-matching
-- by name (and survives a rename). A QB item has exactly ONE home: when the operator
-- corrects an item to a different product, the import must RELEASE the bookmark from
-- the old holder before claiming it on the new one — otherwise two products wear the
-- same name, and the next import can silently pick the one just corrected away from.
--
-- That release is the only write the importer makes to a row it does NOT own.
-- revertQbImport deletes rows tagged created_by = batch_id, so without a record of
-- what was released, Undo would leave the tenant WORSE than before the import: the
-- corrected product gets deleted and the original bookmark is gone for good. For MCR
-- that would quietly destroy hand-backfilled bookmarks on a rolled-back import.
--
-- So: record every released (product_id, qb_item_id) pair on the batch, and let the
-- revert put them back after the created products are deleted.
--
--   [{"product_id": "...", "qb_item_id": "12oz Kona"}, ...]

alter table public.qb_import_batches
  add column if not exists released_stamps jsonb not null default '[]'::jsonb;

comment on column public.qb_import_batches.released_stamps is
  'Bookmarks (products.qb_item_id) this import took off a product it did not create, so revertQbImport can restore them. Append-only within a batch.';

notify pgrst, 'reload schema';
