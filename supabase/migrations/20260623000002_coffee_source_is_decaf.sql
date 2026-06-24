-- coffee_source.is_decaf — whether a source is decaffeinated.
--
-- Feeds the composed display title (a "Decaf" marker) so a decaf coffee never
-- composes to its caffeinated name. The column was first added directly during
-- the MCR composed-title backfill (scripts/mcr_composed_title_backfill_v3.sql);
-- this migration records it in the tracked history so staging + future envs and
-- the migration ledger stay in sync. Idempotent (IF NOT EXISTS) — a no-op where
-- it already exists.
ALTER TABLE coffee_source
  ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN coffee_source.is_decaf IS
  'Decaffeinated source. Adds a "Decaf" marker to the composed display title.';
