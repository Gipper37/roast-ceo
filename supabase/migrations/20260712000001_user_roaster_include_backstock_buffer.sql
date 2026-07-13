-- include_backstock_buffer — per-roaster toggle for whether the predictive
-- backstock buffer is included in the Orders-mode roast plan / LFP count.
--
-- The backstock buffer is backstock_buffer_pct% of the 6-week trailing ORDER
-- average, added on top of current demand in the roast_detail_by_blend view.
-- In Orders mode that projected buffer leaks in even for recipes with zero
-- current orders → "phantom" BS roasts (LFP shows N roasts with no orders).
-- This toggle lets the roaster exclude the buffer from the plan count.
--
-- DEFAULT FALSE: Orders mode = orders only by default; it never silently
-- recommends buffer roasts. When true, the buffer is included (its roasts still
-- render in a separate, labeled section — never mixed into the order count).
--
-- Mirrors user_roaster_settings.projected_source: per-user (email key), synced
-- across web + Mac app. Read on /app/roast, written by setBackstockBuffer.

ALTER TABLE public.user_roaster_settings
  ADD COLUMN IF NOT EXISTS include_backstock_buffer boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.user_roaster_settings.include_backstock_buffer IS
  'Per-roaster: include the predictive backstock buffer in the Orders-mode roast plan / LFP count. Default false (orders only). Buffer roasts always render in a separate labeled section regardless.';

NOTIFY pgrst, 'reload schema';
