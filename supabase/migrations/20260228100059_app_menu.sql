-- Migration 00059: app_menu table for AppSheet navigation menus
--
-- AppSheet doesn't have a native menu view type. This table holds menu items
-- for gallery-based navigation launchers. One table covers all sections;
-- AppSheet slices filter by section to produce separate gallery views.
--
-- Sections created: 'inventory', 'sales'
-- AppSheet setup:
--   1. Import app_menu table; set menu_item_id as Key, hide target_view column
--   2. Create slices: "Inventory Menu" (section="inventory"), "Sales Menu" (section="sales")
--   3. Action: App: go to another view → LINKTOVIEW([target_view])
--   4. Two Gallery views, one per slice, Row Selected → the action
--   5. Update target_view values to match exact AppSheet view names

CREATE TABLE public.app_menu (
    menu_item_id  text    NOT NULL,
    section       text    NOT NULL,
    sort_order    integer NOT NULL DEFAULT 0,
    label         text    NOT NULL,
    icon          text,
    target_view   text    NOT NULL,
    CONSTRAINT app_menu_pkey PRIMARY KEY (menu_item_id)
);

-- ── Inventory section ──────────────────────────────────────────
INSERT INTO public.app_menu (menu_item_id, section, sort_order, label, target_view) VALUES
    ('inventory-coffee',      'inventory', 1, 'Coffee Inventory',     'Coffee Inventory'),
    ('inventory-consumable',  'inventory', 2, 'Consumable Inventory', 'Consumable Inventory'),
    ('inventory-purchasing',  'inventory', 3, 'Coffee Purchasing',    'Coffee Purchasing'),
    ('inventory-order-guide', 'inventory', 4, 'Shipment Order Guide', 'Shipment Order Guide');

-- ── Sales / CRM section ────────────────────────────────────────
INSERT INTO public.app_menu (menu_item_id, section, sort_order, label, target_view) VALUES
    ('sales-customers', 'sales', 1, 'Customers',      'Customers'),
    ('sales-tracking',  'sales', 2, 'Sales Tracking', 'Sales Tracking'),
    ('sales-notes',     'sales', 3, 'Sales Notes',    'Sales Notes'),
    ('sales-tasks',     'sales', 4, 'Sales Tasks',    'Sales Tasks');
