-- Per-component planned lots for roast planning.
--
-- Lets the operator pre-pick which coffee_source (lot) each recipe component
-- will use at Add-Roast time (and adjust mid-plan). The profiler seeds its
-- active-source pointers from this map, so the FIFO auto-resolve
-- (resolveActiveSourceId) never overrides a lot the planner deliberately chose.
--
-- Shape: { "<origin_id>": "<coffee_source_id>", ... }. Empty {} = no plan
-- (profiler falls back to FIFO as before). Single-origin roasts can also use it,
-- though roast_log.coffee_source_id still carries the single-origin pick.
ALTER TABLE roast_log
  ADD COLUMN IF NOT EXISTS planned_lots jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN roast_log.planned_lots IS
  'Per-component planned lots {origin_id: coffee_source_id}. Seeds the profiler active-source pointers and overrides FIFO auto-resolve. Empty {} = no plan.';
