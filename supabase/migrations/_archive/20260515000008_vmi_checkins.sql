-- VMI check-in flow (Phase 2 #3)
--
-- Vendor-Managed Inventory: the operator visits the customer, counts
-- what's on the shelf, and places an order based on observed stock.
-- The 'Vendor-Managed Inventory' management_type has existed for a
-- while but had no dedicated workflow — operators just placed
-- orders manually with no record of the visit itself.
--
-- This adds:
--   1. vmi_checkins        — one row per visit (header: when, who, notes)
--   2. vmi_checkin_items   — one row per product observed at the visit
--                            (observed_qty + suggested_qty + actual_qty)
--   3. Optional FK from orders.created_from_checkin_id back to the
--      check-in that generated the order, so the customer's history
--      page can show "Order #123 was generated from a check-in on Mar 5"
--
-- Tenant scoped + RLS standard pattern.

-- 1) Header table.
CREATE TABLE IF NOT EXISTS public.vmi_checkins (
  vmi_checkin_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  facility_id      text REFERENCES public.facilities(facility_id) ON DELETE SET NULL,
  customer_id      text NOT NULL REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  -- When the operator visited the customer.
  visited_at       timestamptz NOT NULL DEFAULT NOW(),
  visited_by       text REFERENCES public.team(team_member_id) ON DELETE SET NULL,
  notes            text,
  -- Set when "Create order from this check-in" produces an order.
  -- NULL means the check-in is captured but no order was generated
  -- (e.g. the customer had enough stock).
  generated_order_id text REFERENCES public.orders(order_id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT NOW(),
  updated_at       timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vmi_checkins_customer_idx
  ON public.vmi_checkins (customer_id, visited_at DESC);
CREATE INDEX IF NOT EXISTS vmi_checkins_company_idx
  ON public.vmi_checkins (company_id, visited_at DESC);

ALTER TABLE public.vmi_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_company_access ON public.vmi_checkins;
CREATE POLICY tenant_company_access ON public.vmi_checkins
  FOR ALL
  USING (company_id IN (SELECT auth_company_ids()))
  WITH CHECK (company_id IN (SELECT auth_company_ids()));

-- 2) Line items table — one per product observed.
CREATE TABLE IF NOT EXISTS public.vmi_checkin_items (
  vmi_checkin_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vmi_checkin_id   uuid NOT NULL REFERENCES public.vmi_checkins(vmi_checkin_id) ON DELETE CASCADE,
  product_id       text NOT NULL REFERENCES public.products(product_id) ON DELETE CASCADE,
  -- What the operator counted on the shelf.
  observed_qty     numeric NOT NULL DEFAULT 0,
  -- System suggestion (operator-overridable) — e.g. par_level - observed.
  -- Not enforced here; the UI computes + the operator confirms.
  suggested_qty    numeric,
  -- What the operator ultimately decided to order. NULL until the
  -- operator chooses to "create order from check-in" or saves a
  -- value here.
  ordered_qty      numeric,
  coffee_prep      text NOT NULL DEFAULT 'Whole Bean',
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (vmi_checkin_id, product_id, coffee_prep)
);

CREATE INDEX IF NOT EXISTS vmi_checkin_items_checkin_idx
  ON public.vmi_checkin_items (vmi_checkin_id);

ALTER TABLE public.vmi_checkin_items ENABLE ROW LEVEL SECURITY;

-- Items inherit visibility from the parent check-in (which is
-- tenant-scoped). Policy reads through the join.
DROP POLICY IF EXISTS tenant_via_checkin ON public.vmi_checkin_items;
CREATE POLICY tenant_via_checkin ON public.vmi_checkin_items
  FOR ALL
  USING (
    vmi_checkin_id IN (
      SELECT vmi_checkin_id FROM public.vmi_checkins
      WHERE company_id IN (SELECT auth_company_ids())
    )
  )
  WITH CHECK (
    vmi_checkin_id IN (
      SELECT vmi_checkin_id FROM public.vmi_checkins
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );

-- 3) Back-reference on orders so the order detail page can link
-- "generated from VMI check-in on <date>".
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS created_from_vmi_checkin_id uuid
    REFERENCES public.vmi_checkins(vmi_checkin_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS orders_vmi_checkin_idx
  ON public.orders (created_from_vmi_checkin_id)
  WHERE created_from_vmi_checkin_id IS NOT NULL;

-- 4) Touch updated_at on the parent when an item changes — keeps
-- the "last edited" feel correct.
CREATE OR REPLACE FUNCTION public.touch_vmi_checkin_on_item_change()
RETURNS trigger AS $$
BEGIN
  UPDATE public.vmi_checkins
     SET updated_at = NOW()
   WHERE vmi_checkin_id = COALESCE(NEW.vmi_checkin_id, OLD.vmi_checkin_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_touch_vmi_checkin_on_item_change ON public.vmi_checkin_items;
CREATE TRIGGER trg_touch_vmi_checkin_on_item_change
  AFTER INSERT OR UPDATE OR DELETE ON public.vmi_checkin_items
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_vmi_checkin_on_item_change();

-- Verification (post-push):
--   \d vmi_checkins
--   \d vmi_checkin_items
--   SELECT policyname FROM pg_policies WHERE tablename IN ('vmi_checkins','vmi_checkin_items');
