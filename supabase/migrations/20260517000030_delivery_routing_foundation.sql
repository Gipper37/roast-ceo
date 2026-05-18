-- ============================================================
-- Delivery routing — foundation
-- ============================================================
-- Adds the day-of-week layer on top of existing sales_area zones,
-- the customer ↔ day assignment table, and a delivery_date column
-- on orders. Plus a delivery.* permission family gated to Pro+.
--
-- Data model:
--   sales_area              (existing) — zone identity
--   sales_area_day          (new)      — which days a zone has trucks
--   customer_delivery_day   (new)      — which day(s) a customer is on
--                                         within a zone (multi-day
--                                         allowed for twice-weekly)
--   orders.delivery_date    (new col)  — scheduled delivery date.
--                                         NULL → derive from customer
--                                         day at view time. Stored
--                                         value wins (holiday shift,
--                                         skip-week, same-day, etc).
--
-- Day-of-week values are lowercase 3-letter ISO codes:
--   mon, tue, wed, thu, fri, sat, sun
-- Matches what shows in the UI; CHECK constraint enforces.
-- ============================================================


-- ────────────────────────────────────────────────────────────────
-- sales_area_day — which weekdays a zone runs trucks
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sales_area_day (
  sales_area_id text NOT NULL REFERENCES public.sales_area(id) ON DELETE CASCADE,
  day_of_week   text NOT NULL CHECK (day_of_week IN ('mon','tue','wed','thu','fri','sat','sun')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  PRIMARY KEY (sales_area_id, day_of_week)
);
CREATE INDEX sales_area_day_zone_idx ON public.sales_area_day (sales_area_id);
CREATE INDEX sales_area_day_dow_idx  ON public.sales_area_day (day_of_week);

ALTER TABLE public.sales_area_day ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.sales_area_day
  FOR ALL TO authenticated USING (
    sales_area_id IN (
      SELECT id FROM public.sales_area
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );


-- ────────────────────────────────────────────────────────────────
-- customer_delivery_day — which day(s) a customer is on for a zone
-- ────────────────────────────────────────────────────────────────
-- Single-day zones: row optional (implied from zone's only day).
-- Multi-day zones: row required for the customer to appear in any
-- day-view; the picker in the zone admin UI manages this.
-- Twice-weekly customers: two rows with same (customer_id, zone),
-- different day_of_week.
CREATE TABLE IF NOT EXISTS public.customer_delivery_day (
  customer_id   text NOT NULL REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  sales_area_id text NOT NULL REFERENCES public.sales_area(id) ON DELETE CASCADE,
  day_of_week   text NOT NULL CHECK (day_of_week IN ('mon','tue','wed','thu','fri','sat','sun')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  updated_by    text,
  PRIMARY KEY (customer_id, sales_area_id, day_of_week)
);
CREATE INDEX customer_delivery_day_customer_idx ON public.customer_delivery_day (customer_id);
CREATE INDEX customer_delivery_day_zone_dow_idx ON public.customer_delivery_day (sales_area_id, day_of_week);

ALTER TABLE public.customer_delivery_day ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_company_access ON public.customer_delivery_day
  FOR ALL TO authenticated USING (
    customer_id IN (
      SELECT customer_id FROM public.customers
      WHERE company_id IN (SELECT auth_company_ids())
    )
  );


-- ────────────────────────────────────────────────────────────────
-- orders.delivery_date — scheduled delivery date (nullable override)
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_date date;
CREATE INDEX IF NOT EXISTS orders_delivery_date_idx
  ON public.orders (delivery_date) WHERE delivery_date IS NOT NULL;

COMMENT ON COLUMN public.orders.delivery_date IS
  'Scheduled delivery date. NULL → derive on read from customer''s assigned day for orders.area zone. Stored value wins (holiday shift, skip-week, same-day delivery). Stamped at delivery completion at the latest so reporting queries always have a date.';


-- ────────────────────────────────────────────────────────────────
-- Helpers — day-of-week conversion
-- ────────────────────────────────────────────────────────────────
-- Convert text dow code → ISO weekday number (1=Mon..7=Sun) for date math.
CREATE OR REPLACE FUNCTION public.dow_text_to_iso(p_dow text)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_dow
    WHEN 'mon' THEN 1 WHEN 'tue' THEN 2 WHEN 'wed' THEN 3
    WHEN 'thu' THEN 4 WHEN 'fri' THEN 5 WHEN 'sat' THEN 6
    WHEN 'sun' THEN 7 END
$$;

-- Convert ISO weekday number → text code.
CREATE OR REPLACE FUNCTION public.dow_iso_to_text(p_iso int)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_iso
    WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
    WHEN 7 THEN 'sun' END
$$;

-- Compute the next occurrence of a given text dow ON OR AFTER a date.
-- Used by the order create flow to fill delivery_date and by the
-- day-view to derive when delivery_date is NULL.
CREATE OR REPLACE FUNCTION public.next_dow_on_or_after(p_from date, p_dow text)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from + (((public.dow_text_to_iso(p_dow) - EXTRACT(ISODOW FROM p_from)::int + 7) % 7))::int
$$;


-- ────────────────────────────────────────────────────────────────
-- Permissions — delivery.* family, Pro+ only
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.permissions (permission_id, category, label, description, error_message, plan_gated, sort_order) VALUES
  ('delivery.view',              'delivery', 'View delivery routes',
    'See the day-by-day delivery view and zone schedules.',
    'You do not have permission to view delivery routes.', true, 200),
  ('delivery.manage_zones',      'delivery', 'Manage delivery zones',
    'Add/remove zones, set which days each zone runs trucks, and move customers between days.',
    'You do not have permission to manage delivery zones.', true, 210),
  ('delivery.assign_customer_day','delivery', 'Assign customer delivery days',
    'Set or change the delivery day for individual customers within their zone.',
    'You do not have permission to assign customer delivery days.', true, 220),
  ('delivery.mark_delivered',    'delivery', 'Mark stops delivered',
    'Confirm stop completion on the day-view (driver action).',
    'You do not have permission to mark deliveries complete.', true, 230)
ON CONFLICT (permission_id) DO UPDATE SET
  category = EXCLUDED.category, label = EXCLUDED.label,
  description = EXCLUDED.description, error_message = EXCLUDED.error_message,
  plan_gated = EXCLUDED.plan_gated, sort_order = EXCLUDED.sort_order;


-- Plan grants — Pro and up
INSERT INTO public.plan_permissions (plan_id, permission_id, granted)
SELECT p.plan_id, perm.permission_id, true
FROM public.subscription_plans p
CROSS JOIN (VALUES
  ('delivery.view'),
  ('delivery.manage_zones'),
  ('delivery.assign_customer_day'),
  ('delivery.mark_delivered')
) perm(permission_id)
WHERE p.plan_id IN ('pro','enterprise','enterprise_plus')
ON CONFLICT (plan_id, permission_id) DO UPDATE SET granted = true;


-- Role grants:
--   company_admin / manager / facility_admin — all four
--   sales_person                              — view + assign (manages relationships)
--   staff                                     — view + mark_delivered (driver)
--   roastmaster / assistant_roaster / equipment_tech — none by default
INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES
  ('delivery.view'),
  ('delivery.manage_zones'),
  ('delivery.assign_customer_day'),
  ('delivery.mark_delivered')
) perm(permission_id)
WHERE r.role_id IN ('company_admin','manager','facility_admin')
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('delivery.view'), ('delivery.assign_customer_day')) perm(permission_id)
WHERE r.role_id = 'sales_person'
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;

INSERT INTO public.role_permissions (role_id, permission_id, granted)
SELECT r.role_id, perm.permission_id, true
FROM public.user_roles r
CROSS JOIN (VALUES ('delivery.view'), ('delivery.mark_delivered')) perm(permission_id)
WHERE r.role_id = 'staff'
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true;
