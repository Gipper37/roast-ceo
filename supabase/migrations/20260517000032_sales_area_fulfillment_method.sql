-- ============================================================
-- sales_area.fulfillment_method — delivery vs shipping
-- ============================================================
-- Same physical table powers two operational concepts: sales
-- territories (where do we sell?) and delivery routes (where do
-- we drive our truck?). They overlap heavily but aren't identical
-- — some sales territories ship via carrier instead of local
-- truck. This column lets the system tell them apart so the
-- delivery routing UI / order flow / day-views can exclude
-- shipping zones cleanly.
--
-- Two values:
--   'delivery' — local truck route (default; backward compatible)
--   'shipping' — fulfilled via carrier (UPS/FedEx/etc.) — excluded
--                from delivery day-views
--
-- Existing rows default to 'delivery' so this is non-breaking.
-- Operator changes per-zone via a small dropdown in the Zones admin.
-- ============================================================

ALTER TABLE public.sales_area
  ADD COLUMN IF NOT EXISTS fulfillment_method text NOT NULL DEFAULT 'delivery'
    CHECK (fulfillment_method IN ('delivery', 'shipping'));

CREATE INDEX IF NOT EXISTS sales_area_fulfillment_method_idx
  ON public.sales_area (fulfillment_method);

COMMENT ON COLUMN public.sales_area.fulfillment_method IS
  'How orders in this zone are fulfilled. delivery → local truck route, surfaces in /app/delivery; shipping → carrier (UPS/FedEx), excluded from delivery day-views.';
