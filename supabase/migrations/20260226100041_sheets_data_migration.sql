-- =============================================================
-- Google Sheets -> Supabase Migration
-- Generated: 2026-02-26T14:56:38.755272
-- Company:   R7CbqHmA1j
-- Facility:  cc844abb-db0b-48db-9aeb-abd8df9117de
-- Cutoff:    rows after 2026-01-15
-- =============================================================

BEGIN;

-- ── _fk_sales_area (1 rows) ────────────────────────────────────────
INSERT INTO public.sales_area (id, area_name, company_id, created_at, updated_at)
VALUES ('b2faac39', 'Shipped', 'R7CbqHmA1j', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── customers (16 rows) ────────────────────────────────────────
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ad7c8903', 'Online', 'Todd Boyd', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-19', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bc25f496', 'Online', 'Lhar Marquez', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-19', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e6e6a1ec', 'Online', 'Lezlee McQueen', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-26', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a401f50', 'Online', 'Susan Kirsch', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-26', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cfc0041a', 'Online', 'Kimberly Kahn', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-30', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7adba5c8', 'Online', 'Amy Worley', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-30', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fc4b8a72', 'Online', 'Keanu Catugal', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-30', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('866c0d02', 'Online', 'Mike LeClair', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-02', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3daf3337', 'Online', 'Ray Woodruff', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-02', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('db367dce', 'Online', 'Jason Handman', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-06', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ec73f6c3', 'Online', 'Hunter Milligan', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-06', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3c60981f', 'Online', 'Grace C Twelmeyer', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-09', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('207e1eda', 'Online', 'Lisa Marrero', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-09', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('438241a6', 'VIP', 'Cory Martin', NULL, NULL, NULL, NULL, FALSE, 'b2faac39', NULL, NULL, NULL, '16632 Algonquin St', 'Huntington Beach', 'CA', '92649', NULL, '2026-02-13', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bc9bf4b3', 'Online', 'Heidi Swigart', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-23', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;
INSERT INTO public.customers (customer_id, customer_category, name_company, contact, acct_management_interval_wks, management_type, order_reminders_unsubscribed, deal_open_closed, sales_area, sales_person, email, phone, street, city, state, zip, tags, customer_since, flag, created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5432f414', 'Online', 'Jonah Dayan', NULL, NULL, NULL, NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-23', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (customer_id) DO NOTHING;

-- ── products (143 rows) ────────────────────────────────────────
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('V12WBWSDTC', 'Vinyl 12oz - DTC', '4a184796', 'Retail DTC', 'ybrgh19d', 'Products_Images/V12WBWSDTC.Image.230111.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('V12WBWS', 'Vinyl 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/V12WBWS.Image.230205.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f7f0965e', 'Vinyl 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', 'Products_Images/f7f0965e.Image.225844.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('V5WBWS', 'Vinyl 5lb', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('CSO12WBWSDTC', 'Nova 12oz - DTC', 'e8e9bdf2', 'Retail DTC', 'ybrgh19d', 'Products_Images/CSO12WBWSDTC.Image.230211.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('CSO12WBWS', 'Nova 12oz - WS', 'e8e9bdf2', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/CSO12WBWS.Image.230224.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('195fd9b7', 'Nova 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', 'Products_Images/195fd9b7.Image.225905.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('CSO5WBWS', 'Nova 5lb', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/CSO12WBWSDTC.Image.233003.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7641ec65DTC', 'Dawn Patrol 8oz - DTC', 'f4d30d4f', 'Retail DTC', '40edp3ll', 'Products_Images/7641ec65DTC.Image.230410.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7641ec65', 'Dawn Patrol 8oz - WS', 'f4d30d4f', 'Wholesale Retail', '40edp3ll', 'Products_Images/7641ec65.Image.230423.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b4babd6b', 'Dawn Patrol 4.5lbs', 'f4d30d4f', 'Wholesale Bulk', '6b3c354a', 'Products_Images/b4babd6b.Image.225918.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('H12WBWSDTC', 'Hendrix 12oz - DTC', 'c5bac29f', 'Retail DTC', 'ybrgh19d', 'Products_Images/H12WBWSDTC.Image.230438.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('H12WBWS', 'Hendrix 12oz - WS', 'c5bac29f', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/H12WBWS.Image.230450.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9a46a019', 'Hendrix 4.5lbs', 'c5bac29f', 'Wholesale Bulk', '6b3c354a', 'Products_Images/9a46a019.Image.225933.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('H5WBWS', 'Hendrix 5lb', 'c5bac29f', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/H12WBWSDTC.Image.233720.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('HS12WBWSDTC', 'Hon Solo 12oz - DTC', '635ee2cf', 'Retail DTC', 'ybrgh19d', 'Products_Images/HS12WBWSDTC.Image.230544.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('HS12WBWS', 'Hon Solo 12oz - WS', '635ee2cf', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/HS12WBWS.Image.230550.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('64caec66', 'Hon Solo 8oz - DTC', '635ee2cf', 'Retail DTC', '40edp3ll', 'Products_Images/64caec66.Image.230557.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('211d879f', 'Hon Solo 8oz - WS', '635ee2cf', 'Wholesale Bulk', '40edp3ll', 'Products_Images/211d879f.Image.225954.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d2dc6b6c', 'Hon Solo 4.5lb', '635ee2cf', 'Wholesale Bulk', '6b3c354a', 'Products_Images/d2dc6b6c.Image.230009.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('HS5WBWS', 'Hon Solo 5lb', '635ee2cf', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/HS12WBWSDTC.Image.233736.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3d12aa60DTC', 'Rubix 8oz - DTC', '9ccea659', 'Retail DTC', '40edp3ll', 'Products_Images/3d12aa60DTC.Image.230616.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3d12aa60', 'Rubix 8oz - WS', '9ccea659', 'Wholesale Retail', '40edp3ll', 'Products_Images/3d12aa60.Image.030412.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('R12WBWS', 'Rubix 12oz', '9ccea659', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/R12WBWS.Image.230030.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('89484f1e', 'Rubix 4.5lb', '9ccea659', 'Wholesale Bulk', '6b3c354a', 'Products_Images/89484f1e.Image.230044.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('R5WBWS', 'Rubix 5lb', '9ccea659', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/3d12aa60DTC.Image.233811.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a5e741eeDTC', 'Maui Sunrise 8oz - DTC', '0414e3e6', 'Retail DTC', '40edp3ll', 'Products_Images/a5e741eeDTC.Image.230709.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a5e741ee', 'Maui Sunrise 8oz - WS', '0414e3e6', 'Wholesale Retail', '40edp3ll', 'Products_Images/a5e741ee.Image.230722.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5c604e90', 'Maui Sunrise 4.5lb', '0414e3e6', 'Wholesale Bulk', '6b3c354a', 'Products_Images/5c604e90.Image.230730.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1ae5dfa5', 'Maui Sunrise 5lb', '0414e3e6', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/a5e741eeDTC.Image.233845.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('RO8WBWSDTC', 'Red Origin 8oz - DTC', '16f8550f', 'Retail DTC', '40edp3ll', 'Products_Images/RO8WBWSDTC.Image.230741.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('RO8WBWS', 'Red Origin 8oz - WS', '16f8550f', 'Wholesale Retail', '40edp3ll', 'Products_Images/RO8WBWS.Image.230751.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b3e0fcdb', 'Red Origin 4.5lb', '16f8550f', 'Wholesale Bulk', '6b3c354a', 'Products_Images/b3e0fcdb.Image.230831.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('RO5WBWS', 'Red Origin 5lb', '16f8550f', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/RO8WBWSDTC.Image.233916.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MR8WBWSDTC', 'Mokka Reserve 8oz - DTC', 'e67acae4', 'Retail DTC', '40edp3ll', 'Products_Images/MR8WBWSDTC.Image.230848.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MR8WBWS', 'Mokka Reserve 8oz  - WS', 'e67acae4', 'Wholesale Retail', '40edp3ll', 'Products_Images/MR8WBWS.Image.230858.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('87d63ca5', 'Mokka Reserve 4.5lb', 'e67acae4', 'Wholesale Bulk', '6b3c354a', 'Products_Images/87d63ca5.Image.230909.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MR5WBWS', 'Mokka Reserve 5lb', 'e67acae4', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/MR8WBWSDTC.Image.233930.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MP8WBWSDTC', 'Mokka Peaberry 8oz - DTC', '74c94f04', 'Retail DTC', '40edp3ll', 'Products_Images/MP8WBWSDTC.Image.230932.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MP8WBWS', 'Mokka Peaberry 8oz', '74c94f04', 'Wholesale Retail', '40edp3ll', 'Products_Images/MP8WBWS.Image.230940.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e0fdd121', 'Mokka Peaberry 4.5lb', '74c94f04', 'Wholesale Bulk', '6b3c354a', 'Products_Images/e0fdd121.Image.230950.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('MP5WBWS', 'Mokka Peaberry 5lb', '74c94f04', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/MR8WBWSDTC.Image.233930.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('VD12WBWSDTC', 'Sunset Decaf 12oz - DTC', '75b3b0f7', 'Retail DTC', 'ybrgh19d', 'Products_Images/VD12WBWSDTC.Image.231029.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('VD12WBWS', 'Sunset Decaf 12oz - WS', '75b3b0f7', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/VD12WBWS.Image.231109.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ad4071b4', 'Sunset Decaf 4.5lb', '75b3b0f7', 'Wholesale Bulk', '6b3c354a', 'Products_Images/ad4071b4.Image.231130.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('VD5WBWS', 'Decaf 5lb', '75b3b0f7', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9cfc5c96DTC', 'Golden Hour 8oz - DTC', '95288025', 'Retail DTC', '40edp3ll', 'Products_Images/9cfc5c96DTC.Image.231207.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9cfc5c96', 'Golden Hour 8oz - WS', '95288025', 'Wholesale Retail', '40edp3ll', 'Products_Images/9cfc5c96.Image.231212.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d90b89f4', 'Golden Hour 4.5lb', '95288025', 'Wholesale Bulk', '6b3c354a', 'Products_Images/d90b89f4.Image.231222.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('be678eca', 'Golden Hour 5lb', '95288025', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ef22c82c', 'Sol Do Brasil 4.5lbs', '96345ed6', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1d6700ae', 'Sol Do Brasil 5lbs', '96345ed6', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f4443031', 'Fruit 4.5lbs', 'd208cfd2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ac41e90f', 'Fruit 5lbs', 'd208cfd2', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('58cf42d7', 'NOLA', '5be9a88f', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1c98a15f', 'Vigilatte 12oz - WS', '3d6066dc', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('01bab83e', 'Vigilatte 4.5lbs', '3d6066dc', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c435528a', 'Vigilatte 5lbs', '3d6066dc', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8b00add9', 'Beardy Brew 8oz - WS', '9ccea659', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('905fa1f9', 'Beardy Brew 12oz - WS', '9ccea659', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d43edb6c', 'Crema Blend 12oz - WS', 'c5bac29f', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a72807f3', 'Crema Blend 4.5lb', 'c5bac29f', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('efa274e1', 'Crema Blend 5lb', 'c5bac29f', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e8b47e54', 'Kea Lani 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2f2b79ff', 'Kea Lani House 5lbs', '9ccea659', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('54f0f73d', 'Kea Lani House 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('26ad7b5b', 'Kea Lani Espresso 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7a1a9a71', 'Kea Lani Espresso 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('58e8b865', 'B-Side Espresso 5lb', '3d6066dc', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('82bf6128', 'B-Side Espresso 4.5lbs', '3d6066dc', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7f15e40d', 'B-Side House 5lb', 'f4d30d4f', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('24fc4197', 'B-Side House 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('44bfa758', 'Piko House 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1bbb9dfb', 'Piko House 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4a763766', 'Piko Espresso 5lbs', '9ccea659', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4717422b', 'Piko Espresso 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('882b8b9b', 'Olili House 5lbs', 'b01ccacd', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a06b4dae', 'Olili House 4.5lbs', 'b01ccacd', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b4a06dfe', 'Olili Espresso 5lbs', '43c3cbc7', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('868a2ee1', 'Olili Espresso 4.5lbs', '47bc5ac1', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6a383b94', 'Vida Roast 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('59fd2fff', 'Vida Roast 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3362fa39', 'Vida Roast 5lbs', '4a184796', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e32bce9a', 'Better Things 12 oz', 'e8e9bdf2', 'Wholesale Retail', 'ybrgh19d', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2ac5df4c', 'Better Things 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a5265d3', 'Better Things 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d668ad4c', 'Drew Method Mindful 12oz', '4a184796', 'Wholesale Retail', 'ybrgh19d', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c08346f7', 'Drew Method Honduras 12oz', '635ee2cf', 'Wholesale Retail', 'ybrgh19d', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d8e8b187', 'Olinda Blend 12oz', '9ccea659', 'Wholesale Retail', 'ybrgh19d', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2f3735a', 'Casa Nova 5lbs', '47bc5ac1', 'Wholesale Bulk', 'gvqguxsf', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3dde8d36', 'Casa Nova 4.5lbs', '47bc5ac1', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('28767a32', 'Christmas Spirit 8oz - WS', 'c76f71ab', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f4d2e883', 'Redfish House 4.5lbs', '3d6066dc', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1d6b3246', 'Redfish Espresso 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2f407b45', 'Nova Sample', 'e8e9bdf2', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('800be196', 'Vinyl Sample', '4a184796', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cf078713', 'Dawn Patrol Sample', 'f4d30d4f', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2b91698b', 'Hendrix Sample', 'c5bac29f', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0713a786', 'Rubix Sample', '9ccea659', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e3026e07', 'Super Nova Sample', '3d6066dc', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f9784517', 'Kea Lani 8oz - WS', '9ccea659', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('382f6811', 'COLD BREW', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bb7b2772', 'Mokka Peaberry 2lbs', '74d114d3', 'Wholesale Bulk', '25dbab14', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f4008a6c', 'Beardy Brew 8oz (Vinyl) - WS', '4a184796', 'Wholesale Bulk', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d28a6d3f', 'B-Side Espresso 8oz - WS', '3d6066dc', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('50dbea5d', 'B-Side House 8oz - WS', 'e8e9bdf2', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('230c5c06', 'Ax Ranch 12oz - WS', '47bc5ac1', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f8321ab2', 'Ax Ranch 4.5lbs', '47bc5ac1', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f56fb020', 'Bottom of the Barrel 12oz - WS', '0de3187e', 'Wholesale Bulk', '6b3c354a', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4ed64dc0', 'Crema Blend 4.5lbs', 'c5bac29f', 'Wholesale Bulk', '6b3c354a', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4c091d56', 'Kona Extra Fancy 100G - WS', '2bf0491b', 'Wholesale Retail', '58691df6', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fe4e2354', 'Kona Melody 100G - WS', 'ac0889fc', 'Wholesale Retail', '58691df6', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c698fb0c', 'Kona Blend 8oz - WS', '49b9bc58', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8ddefb00', 'Papi''s Ohana 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('32fc41f6', 'Java Cafe 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/V12WBWS.Image.230205.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('898aa877', 'Java Cafe 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', 'Products_Images/f7f0965e.Image.225844.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2e71bfa7', 'Papi''s Ohana 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', 'Products_Images/f7f0965e.Image.225844.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4dfcdec1', 'Momona Bakery 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', 'Products_Images/195fd9b7.Image.225905.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2586f56b', 'Momona Bakery 12oz - WS', 'e8e9bdf2', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/CSO12WBWS.Image.230224.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('be6f3459', 'Hotel Wailea 4.5lbs', 'e8e9bdf2', 'Wholesale Bulk', '6b3c354a', 'Products_Images/195fd9b7.Image.225905.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4bd4f73b', 'Trotters Koffie 4.5lbs', '4a184796', 'Wholesale Bulk', '6b3c354a', 'Products_Images/f7f0965e.Image.225844.png', TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('89e19cad', 'Trotter Koffie 12oz - WS', '4a184796', 'Wholesale Retail', 'ybrgh19d', 'Products_Images/V12WBWS.Image.230205.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0c8d7035', 'Mahi Pono 8oz - WS', '0414e3e6', 'Wholesale Retail', '40edp3ll', 'Products_Images/a5e741ee.Image.230722.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('803aa45c', 'Kona Extra Fancy 100G - DTC', '2bf0491b', 'Retail DTC', '58691df6', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('23b13937', 'Kona Melody 100G - DTC', 'ac0889fc', 'Retail DTC', '58691df6', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cd0719e0', 'Kona Blend 8oz - DTC', '49b9bc58', 'Retail DTC', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0064b790', 'Sol Do Brasil 8oz WS', '96345ed6', 'Wholesale Retail', 'ybrgh19d', NULL, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d17c6886', 'Java Bulk 5lb', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c759e1ba', 'Papi''s Ohana Bulk 5lb', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1f5f0ed4', 'Kealani House Bulk 5lbs', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d83e44fc', 'Trotter''s Bulk 5lbs', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ef84c708', 'Piko Espresso Bulk 5lbs', '4a184796', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/V12WBWSDTC.Image.232840.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2824b0bc', 'Momona Bulk 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/CSO12WBWSDTC.Image.233003.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d2dd846b', 'Hotel Wailea Bulk 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/CSO12WBWSDTC.Image.233003.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('25510a47', 'B-Side House Bulk 5lbs', 'e8e9bdf2', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/CSO12WBWSDTC.Image.233003.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c50cd142', 'Dawn Patrol 5lbs - WS', 'f4d30d4f', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('37308503', 'Sunset Decaf 5lb', '75b3b0f7', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/ad4071b4.Image.231130.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('595a69fd', 'Kona Extra Fancy 5lbs', '2bf0491b', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c418753f', 'Sol Do Brasil 12oz - WS', '96345ed6', 'Wholesale Retail', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2036346d', 'Et Al 5lbs drip', '6883f887', 'Wholesale Bulk', 'gvqguxsf', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bbbe3e73', 'Super Nova 5lbs', '3d6066dc', 'Wholesale Bulk', 'gvqguxsf', 'Products_Images/CSO12WBWSDTC.Image.233003.png', FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6a6af31c', 'Sol Do Brasil 12oz - DTC', '96345ed6', 'Retail DTC', 'ybrgh19d', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;
INSERT INTO public.products (product_id, product_name, recipe_id, product_type, size, image, "archived?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4e6c17f1', 'Dear Wanderlust 8oz WS', 'e0c203d6', 'Wholesale Retail', '40edp3ll', NULL, FALSE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (product_id) DO NOTHING;

-- ── roast_recipes (1 rows) ────────────────────────────────────────
INSERT INTO public.roast_recipes (recipe_id, recipe_name, image, cost_lb_green, cost_lb_roasted, shipping_lb, created_at, created_by, updated_at, updated_by, company_id, roast_type, facility_id)
VALUES ('e0c203d6', 'Dear Wanderlust Retail Blend', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'Pre-Blend', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (recipe_id) DO NOTHING;

-- ── recipe_components (2 rows) ────────────────────────────────────────
INSERT INTO public.recipe_components (component_id, recipe_id, item_id, percentage, coffee_item, component_cost, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('7e707012-e33a-4ffa-9198-e61a46e8c602', 'e0c203d6', '8b8e83a2', 0.7, '8b8e83a2', NULL, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (component_id) DO NOTHING;
INSERT INTO public.recipe_components (component_id, recipe_id, item_id, percentage, coffee_item, component_cost, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('5c83ccf5-d759-4862-9724-432aa929c214', 'e0c203d6', '04e6c723', 0.3, '04e6c723', NULL, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (component_id) DO NOTHING;

-- ── roast_log (427 rows) ────────────────────────────────────────
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2a593a37', '2026-01-19', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6b45442b', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('37f93db3', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1d9142f8', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7568b59a', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b719b61', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ea03feba', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eaaf033d', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6a1308ee', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('766f2316', '2026-01-19', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1e423a82', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('aeb4bcc3', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b7f746b', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e9ea178b', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('41cb1c77', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('59a55f8e', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('de12e811', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('523ca693', '2026-01-19', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fe3a5b88', '2026-01-19', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b87b770a', '2026-01-19', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2e26177', '2026-01-19', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e6088be9', '2026-01-19', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0ff5aa88', '2026-01-19', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('567bd819', '2026-01-19', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ca1ca188', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3838c7e9', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3d01cd92', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('69d9d996', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cc50da70', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b1079489', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('75fafc53', '2026-01-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0f346bed', '2026-01-22', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('94a1110f', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6f8663a8', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('19d966dd', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('90c8ad76', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('df4de30d', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4697132e', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3dc5621f', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7423a771', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f53f3b4c', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8ec910d0', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fb8a9d84', '2026-01-22', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3c0c9e1a', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('642b85b7', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('25792363', '2026-01-22', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5a8f3cb7', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('314f2eac', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4c4a50bb', '2026-01-22', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7ed6c501', '2026-01-22', '6c752b40', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('81607548', '2026-01-22', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('020331d0', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4301896d', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ef90a580', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('51a605c5', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('979fe2d9', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0a6fb5d7', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5e1f28a5', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('60f3277d', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eba1d0c2', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5ec0e522', '2026-01-22', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7b541d73', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f0b8e2c2', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('403a013e', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('88af306c', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1dbfd241', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f7b10eeb', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('410d2487', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4a06fdc9', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('585d5a0d', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1ee2c235', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c9449bc4', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('440546a4', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7fb53a8d', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b091969', '2026-01-22', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a6f52dc9', '2026-01-22', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('26ee0899', '2026-01-26', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('786f5676', '2026-01-26', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('38cd6eb0', '2026-01-26', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6b9c70ab', '2026-01-26', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f8dd1726', '2026-01-26', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7ed9bd14', '2026-01-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('16762a9b', '2026-01-26', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a89403a7', '2026-01-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a90fa812', '2026-01-26', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('649ef7a4', '2026-01-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2bd7c61', '2026-01-26', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7b39098a', '2026-01-26', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ea1c8829', '2026-01-26', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b1018e5', '2026-01-26', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9d5596c9', '2026-01-26', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3b2bef6a', '2026-01-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bd35ffd5', '2026-01-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c63ea46a', '2026-01-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fb23c779', '2026-01-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b08a031d', '2026-01-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5b3dc7dd', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('90bae70c', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7160766c', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('848f48ee', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ac1edef0', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('385a0023', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fffa953e', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('72d3ded3', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('82b5be49', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1521af19', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a6ae55eb', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('babf950c', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f71834ff', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d3e260aa', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('912efd2a', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ecf35d84', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6229c2a8', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8e5317fc', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c06a3467', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('df8678a4', '2026-01-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9a28eb6f', '2026-01-29', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('da3ddfb9', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('85e644a1', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c15e7482', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b8b75200', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('14384351', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a9c3b58', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('53e329d1', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dc7a4d62', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('85c8444d', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fb02093d', '2026-01-29', '28c61c9d', '0414e3e6', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d77fe473', '2026-01-29', 'b65e3842', '16f8550f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('026e832c', '2026-01-29', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('083ab02e', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2259b47a', '2026-01-29', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('88b3575c', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c24cbbe4', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cf7f8227', '2026-01-29', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d0853f70', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9e4caf9e', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('da075c71', '2026-01-29', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2d6fda96', '2026-01-29', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('79dc6233', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5db70b18', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('25bf7282', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1ebab52b', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d877007b', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('287c33d6', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f28fb40b', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('19597732', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('72fe67d3', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('35301d76', '2026-01-29', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5c608f0e', '2026-01-29', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('81f704cc', '2026-01-29', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ef310ef2', '2026-01-29', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d2bb5eb0', '2026-01-29', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7aba5152', '2026-01-29', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('06d96fd3', '2026-02-02', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('06d7d974', '2026-02-02', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('538660ff', '2026-02-02', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ed2749b1', '2026-02-02', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1f95c2bf', '2026-02-02', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5e728d76', '2026-02-02', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9685056a', '2026-02-02', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2f0a45b', '2026-02-02', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5933c4af', '2026-02-02', '6c752b40', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('42e47b71', '2026-02-02', '6c752b40', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5bb5acb1', '2026-02-02', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1a20308a', '2026-02-02', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8a03bd8c', '2026-02-02', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7c00404e', '2026-02-02', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b4025da', '2026-02-02', '6c752b40', '0de3187e', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cd72c6e2', '2026-02-02', 'c9a002a8', '96345ed6', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('54ea27f6', '2026-02-02', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a8194226', '2026-02-02', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9ab26c46', '2026-02-02', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('51714ace', '2026-02-02', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('31c7086a', '2026-02-02', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a113b7a5', '2026-02-02', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0563Feb13', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7783d9b6', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ccd3f856', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9d808f93', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c17bf451', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c42baeed', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8836bb1f', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('95f4d90f', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ddb1a13c', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('48f5cd2a', '2026-02-02', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('22d08e01', '2026-02-05', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a35ccdcc', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('34002d15', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ca18aefd', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('68be06be', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b2473ce2', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eccc128f', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('05efd14b', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a8a38438', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9375ff3e', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0da9504d', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('836ffbde', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('32cadfff', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cecce7f1', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1f9f5a2c', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e55dac68', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bc0126d9', '2026-02-05', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a43fcf9e', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dd86c809', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b493ffed', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('00ea96b2', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d4f01350', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('680e0fd7', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fd5bffc2', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4ddfef8c', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('38430427', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9e8286a1', '2026-02-05', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('16b89c15', '2026-02-05', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e5dd12d5', '2026-02-05', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ac2a072e', '2026-02-05', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('60190d87', '2026-02-05', '6c752b40', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d6947780', '2026-02-09', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eaa1fa51', '2026-02-09', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('49fa8f98', '2026-02-09', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8983d168', '2026-02-09', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5feb332d', '2026-02-09', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a8b87be4', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2980d3b4', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e37f6e75', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4ec785e8', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('819ca34a', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('10b6aaf8', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8aa26b12', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('00a2b3dd', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7b622d39', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f0ee80ee', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('adcee0e3', '2026-02-09', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6e74f81b', '2026-02-09', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('032d443c', '2026-02-09', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('259c0a26', '2026-02-09', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('912da13c', '2026-02-09', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9bfcb843', '2026-02-09', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('940a71ec', '2026-02-09', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d14121e5', '2026-02-09', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5e963afd', '2026-02-09', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('25f72d42', '2026-02-09', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6ef03b5f', '2026-02-09', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('74830447', '2026-02-09', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4dcc44d5', '2026-02-09', '6c752b40', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6937aad2', '2026-02-09', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2dedf2e', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('58a806b2', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('76b1677e', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ddf92ede', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cd70e2a0', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('63be1deb', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e6a8e0e3', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b75ec33e', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9b6c1eb4', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('08c5682a', '2026-02-09', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('32561be4', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4c2f65d2', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7b4dd081', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f6c39ed7', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9d9a901e', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f077a5dd', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('22c0b990', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4523fb47', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('480a2e85', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f71fb999', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('39f7b117', '2026-02-12', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3697cb5c', '2026-02-12', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3fee536e', '2026-02-12', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('93a60845', '2026-02-12', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e27f5340', '2026-02-12', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('814e4b23', '2026-02-12', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f915a64a', '2026-02-12', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fa469726', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6589e44d', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('801b4ddf', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5d97e130', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c1a56e49', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d13bb650', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b9a7fb4f', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('489bae10', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c98e12ff', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('23ff7f26', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('63f0846b', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a7901e90', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f3f548bb', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c4939829', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6d4e451e', '2026-02-12', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('aaae26bc', '2026-02-16', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('16506fef', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6a9b6157', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('21c0062d', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bcf8cbfc', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2358f1c3', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ef097329', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c8151111', '2026-02-16', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('00c1aad5', '2026-02-16', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('68e07d81', '2026-02-16', '6c752b40', 'c5bac29f', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c86387a3', '2026-02-16', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d9baebbb', '2026-02-16', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('36f61611', '2026-02-16', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('54445a0a', '2026-02-16', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('da527acb', '2026-02-16', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('28388024', '2026-02-16', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b7fda143', '2026-02-16', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0fb51b54', '2026-02-16', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7ad828c1', '2026-02-16', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('36c1c404', '2026-02-16', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1fadbd9e', '2026-02-16', '6c752b40', '3d6066dc', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ad1d782c', '2026-02-16', '6c752b40', '3d6066dc', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d6c2faf5', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2febdb75', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8aaff165', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ce0eab21', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7a0d7d5e', '2026-02-16', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8b996ab7', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('170ecaeb', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('19f9402e', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1efa30c1', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d0c25a5e', '2026-02-16', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3ddd0a42', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3f2acdf8', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1829bb19', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3cba4f6a', '2026-02-16', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('206dd984', '2026-02-16', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('97574114', '2026-02-16', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a503242f', '2026-02-19', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('465a6fb3', '2026-02-19', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bbd99c82', '2026-02-19', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bff35a71', '2026-02-19', '6c752b40', '4a184796', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bd6a34f0', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('678591d7', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d5d85536', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f4f45723', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('69fd4854', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9093fdef', '2026-02-19', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a8f9f88a', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9c5967c0', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('69a1e3f8', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3b1ed36c', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1888c796', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('df4d7cc1', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('009f0b90', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('179d227a', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('83db24e7', '2026-02-19', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('449f6a6a', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('65ac2fb3', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6bf23ca7', '2026-02-19', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3eaaf3d4', '2026-02-19', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0867c403', '2026-02-19', '8b8e83a2', '635ee2cf', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('85997bcf', '2026-02-19', 'c9a002a8', '96345ed6', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9cc944e2', '2026-02-19', '28c61c9d', '0414e3e6', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5d35f8a9', '2026-02-23', 'b65e3842', '16f8550f', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1e5e173f', '2026-02-23', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c3be6908', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('08e3f346', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bbcf0d36', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5277999e', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bf4c56ce', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2f5f753e', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cb19d668', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2ba8f7d3', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ab85c511', '2026-02-23', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c235efff', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('02fcfacb', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('76218b12', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('58eba59c', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7804ea93', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('10186103', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('44897318', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0f450376', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2167a1df', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('00df42b4', '2026-02-23', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a8e27f4', '2026-02-23', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6cd6b572', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('24ac8f11', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d0cd25cc', '2026-02-23', 'b40bc5b0', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2486c7d8', '2026-02-23', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c2e40c69', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3333b33d', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('28b6264c', '2026-02-23', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c0e4f2a8', '2026-02-23', '6c752b40', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d2a915cb', '2026-02-23', '6c752b40', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f0d6afb9', '2026-02-23', '6c752b40', 'c5bac29f', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('de53cf47', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f2faff47', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c834454a', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b78a2e89', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fd058583', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ec13921c', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e58b9c3f', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ccf00354', '2026-02-23', '6c752b40', '3d6066dc', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e63b3a34', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('15c460b5', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9bb6e477', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('83351ad2', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dc92e05b', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('806c72ec', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2835a2d0', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a382ee5a', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8506ea10', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a8a54bb2', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f81a7889', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('84a6923a', '2026-02-26', '6c752b40', '3d6066dc', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7691020b', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bdf0ebc7', '2026-02-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f15caa3d', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2ea37dc4', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('50f20623', '2026-02-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e26deb30', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('113fc30c', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f4b6d687', '2026-02-26', 'b40bc5b0', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b8c2257', '2026-02-26', '6c752b40', '4a184796', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e1ca350f', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fa69f07e', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('cfc416ab', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5298a0dd', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e6af93ce', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('35c496ea', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, TRUE, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ffed510f', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a6703f3', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d6be2cd8', '2026-02-26', '6c752b40', 'e8e9bdf2', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d4e1bc49', '2026-02-26', '6c752b40', 'e8e9bdf2', 20, 16.4, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fb8a0f37', '2026-02-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3f6e8b24', '2026-02-26', '6c752b40', 'e8e9bdf2', 25.04, 20.53, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f9759b51', '2026-02-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('07d39f81', '2026-02-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;
INSERT INTO public.roast_log (roast_log_id, roast_date, origin_id, recipe_id, charge_weight, roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d9fc523e', '2026-02-26', '04a6d7fb', '75b3b0f7', 23, 18.86, TRUE, NULL, now(), NULL, now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (roast_log_id) DO NOTHING;

-- ── shipment_received (2 rows) ────────────────────────────────────────
INSERT INTO public.shipment_received (shipment_id, supplier_id, shipping_cost, date_received, order_date, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('9cf077a6', 'BiSv0a', 6140.54, '2026-02-13', '2026-02-13', now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (shipment_id) DO NOTHING;
INSERT INTO public.shipment_received (shipment_id, supplier_id, shipping_cost, date_received, order_date, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('21e4fb1a', 'BiSv0a', NULL, '2026-03-31', '2026-02-24', now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (shipment_id) DO NOTHING;

-- ── coffee_inventory_purchased (7 rows) ────────────────────────────────────────
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('5ad91cfe', '9cf077a6', '6c752b40', 'Peru Vida Alta SHB EP', '37779', 4.84, 11692, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('68a894fb', '9cf077a6', 'b40bc5b0', 'Papua New Guinea Siane Chimbu A/X', '35349', 4.67, 1323, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('4a758e8b', '9cf077a6', '04a6d7fb', 'Decaf Colombia EA Natural Process', '37866', 5.74, 461, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('ebd62256', '21e4fb1a', '6c752b40', 'HONDURAS FT-FLO ORGANIC COPAN CAFESCOR SHG EP', '37758', 4.26, 11550, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('2e2ccc7c', '21e4fb1a', 'b40bc5b0', 'Colombia Huila Asprotimana Women’s Coffee', '38836', 4.24, 1848, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('ff00fff4', '21e4fb1a', 'c9a002a8', 'Brazil SS FC 15/16', '35952', 3.99, 308, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;
INSERT INTO public.coffee_inventory_purchased (origin_purchase_id, shipment_id, origin, coffee_name, lot_id, cost_lb, amount, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('3d05ee3b', '21e4fb1a', '04a6d7fb', 'DECAF HONDURAS FT-USA ORGANIC COMSA ROYAL SELECT WATER PROCESS', '38018', NULL, 462, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (origin_purchase_id) DO NOTHING;

-- ── consumable_inventory (2 rows) ────────────────────────────────────────
INSERT INTO public.consumable_inventory (consumable_inventory_id, consumable_inventory_item, last_inventory_date, inventory_count, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('a97ab564', 'Plain Labels', '2026-01-19', 10000, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (consumable_inventory_id) DO UPDATE SET
  consumable_inventory_item = EXCLUDED.consumable_inventory_item,
  last_inventory_date = EXCLUDED.last_inventory_date,
  inventory_count = EXCLUDED.inventory_count,
  updated_at = now();
INSERT INTO public.consumable_inventory (consumable_inventory_id, consumable_inventory_item, last_inventory_date, inventory_count, created_at, updated_at, created_by, updated_by, company_id, facility_id)
VALUES ('991b79d6', 'Dear Wanderlust Label', '2026-02-02', 505, now(), now(), 'R7CbqHmA1j', NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (consumable_inventory_id) DO UPDATE SET
  consumable_inventory_item = EXCLUDED.consumable_inventory_item,
  last_inventory_date = EXCLUDED.last_inventory_date,
  inventory_count = EXCLUDED.inventory_count,
  updated_at = now();

-- ── orders (186 rows) ────────────────────────────────────────
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ed25070c', '6c179141', '2026-01-19', 'Delivered', NULL, 'a4781210', 'a0c5c8ab', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('38ed70ed', '8545e6b2', '2026-01-19', 'Delivered', NULL, 'f069167e', 'e263b9b4', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5e76aa64', '93d82ce0', '2026-01-19', 'Delivered', NULL, 'ae07783a', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e19dba1b', 'c3crgsfb', '2026-01-19', 'Delivered', NULL, '211dce7a', '8bcb9318', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b5f84b00', '552a2263', '2026-01-19', 'Delivered', NULL, 'e4c1f2ff', 'ccdef0e9', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('941f3ba2', 'ad7c8903', '2026-01-19', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4d4c8190', '02dc4297', '2026-01-19', 'Delivered', NULL, '4aae84a0', '1176c236', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dda898bc', '1a0a3e30', '2026-01-19', 'Delivered', NULL, '5fa0c88d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2a00e6d2', '6bc9adea', '2026-01-19', 'Delivered', NULL, '50b762cc', '9d2f17c3', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('414a02cc', 'c9b920db', '2026-01-19', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('81044b35', '081657fa', '2026-01-19', 'Delivered', NULL, 'fe7bedb2', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('267434d6', '29b6dd55', '2026-01-19', 'Delivered', NULL, '38cdb537', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('29635a9c', 'bc25f496', '2026-01-19', 'Delivered', NULL, NULL, '2c84ffb0', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('db00e7bf', '0baf6cd0', '2026-01-19', 'Delivered', NULL, '6537b715', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('91e15c18', '6a380c32', '2026-01-19', 'Delivered', NULL, 'c1f11b87', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ad4074e7', '647d5345', '2026-01-19', 'Delivered', NULL, 'bd41fe45', '691031b2', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a574de6b', 'eaa092a1', '2026-01-19', 'Delivered', NULL, 'bbc28e53', 'd2a44242', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a4052f7d', '0d70f923', '2026-01-19', 'Delivered', NULL, 'e1c80ee8', '24e6e835', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5d954e35', '87dbf284', '2026-01-19', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ea0dd0b4', 'inrj8aqd', '2026-01-19', 'Delivered', NULL, 'dc57dd4c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('382a15ad', 'a60df569', '2026-01-19', 'Delivered', NULL, '02a0e084', '317fc103', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d4530f25', 'f7cc406e', '2026-01-19', 'Delivered', NULL, '80626cf2', 'de27e085', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('69582c55', 'fe31a8bd', '2026-01-20', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5968f335', '6cfcd982', '2026-01-20', 'Delivered', NULL, '32719ee1', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1275a45a', '04929c93', '2026-01-20', 'Delivered', NULL, NULL, '2c6ba799', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ac24c22d', 'ccc86aa2', '2026-01-20', 'Delivered', NULL, NULL, '7c2758c9', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3e5acac8', '8320be67', '2026-01-26', 'Delivered', NULL, '74e7e604', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('740029d0', 'c3crgsfb', '2026-01-26', 'Delivered', NULL, '96051c47', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ccdef0e9', '552a2263', '2026-01-26', 'Delivered', NULL, 'b5f84b00', '6088f6f8', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e263b9b4', '8545e6b2', '2026-01-26', 'Delivered', NULL, '38ed70ed', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c870cca8', 'e6e6a1ec', '2026-01-26', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d6160793', '4f09f73f', '2026-01-26', 'Delivered', NULL, 'e0d6d011', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d9f607fc', '02dc4297', '2026-01-26', 'Delivered', NULL, 'b8dec3d5', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ecad2fa9', '2e2d4e03', '2026-01-26', 'Delivered', NULL, 'bf506075', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('892213eb', '04929c93', '2026-01-26', 'Delivered', NULL, '80a091e4', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9d2f17c3', '6bc9adea', '2026-01-26', 'Delivered', NULL, '2a00e6d2', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a055a854', '3a401f50', '2026-01-26', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d2a44242', 'eaa092a1', '2026-01-26', 'Delivered', NULL, 'a574de6b', '8db64016', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('691031b2', '647d5345', '2026-01-26', 'Delivered', NULL, 'ad4074e7', '357df8b8', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dbafd8ed', '0d70f923', '2026-01-26', 'Delivered', NULL, 'e25d0b65', '70ee0178', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('97fe3e72', '081657fa', '2026-01-26', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('87b7f19b', '87dbf284', '2026-01-26', 'Delivered', NULL, NULL, '5dcc1397', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4c83dda8', 'c9b920db', '2026-01-26', 'Delivered', NULL, '2e68ceec', '3f2e769d', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e52e94e3', '1a0a3e30', '2026-01-26', 'Delivered', NULL, NULL, 'd482dc3a', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('60c1f58f', '184caf13', '2026-01-26', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7d95108f', '04929c93', '2026-01-26', 'Delivered', NULL, NULL, 'bd226d65', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('aecbd1aa', 'f7cc406e', '2026-01-26', 'Delivered', NULL, NULL, 'c75ad3b7', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f3fcbf97', 'inrj8aqd', '2026-01-26', 'Delivered', NULL, 'da0f7099', '418a1f6c', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('95c3f4a1', '057a9a0d', '2026-01-26', 'Delivered', 'Order: 160335325', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a88dde5a', '14694048', '2026-01-26', 'Delivered', 'Order: 160334578', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d0120326', '55de29ff', '2026-01-26', 'Delivered', 'Order: 160067192', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dd40efde', '14694048', '2026-01-26', 'Delivered', 'Order: 160040227', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('41947df8', '057a9a0d', '2026-01-26', 'Delivered', 'Order: 159905102', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8453b7be', 'b830db03', '2026-01-27', 'Delivered', NULL, 'd53b4934', '011367f6', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4c0cc1da', '6cfcd982', '2026-01-27', 'Delivered', NULL, '32719ee1', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b271e265', 'e1c68221', '2026-01-29', 'Delivered', NULL, '7d0492e3', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fc44f1d7', 'cfc0041a', '2026-01-30', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8d958b0d', '38408416', '2026-01-30', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('99822ecb', 'a240ff32', '2026-01-30', 'Delivered', NULL, '15d4e068', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3c40fffc', '962ce684', '2026-01-30', 'Delivered', NULL, '361a5a2d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eb27e241', 'd9b30ef2', '2026-01-30', 'Delivered', NULL, '1f4579e4', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fdde38d7', '63a8b929', '2026-01-30', 'Delivered', NULL, 'a879948f', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('20f14401', '7adba5c8', '2026-01-30', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('19a862ff', 'fc4b8a72', '2026-01-30', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a0c5c8ab', '6c179141', '2026-01-30', 'Delivered', NULL, 'ed25070c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fbf57933', '22c135b1', '2026-01-30', 'Delivered', NULL, '4f80d4ac', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a53315dd', 'e036259c', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0a0a0a4b', '52512ea4', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('90849497', '6bc9adea', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8d0c24c0', '552a2263', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d14aacc3', '8545e6b2', '2026-02-02', 'Delivered', NULL, NULL, '65093cf1', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('120c4ea7', '866c0d02', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('10823d9b', '1a0a3e30', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0535adf9', '02dc4297', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8ca112cc', '081657fa', '2026-02-02', 'Delivered', NULL, NULL, '393c26af', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('70ee0178', '0d70f923', '2026-02-02', 'Delivered', NULL, 'dbafd8ed', '8f88f9cc', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0d5c56ff', 'eaa092a1', '2026-02-02', 'Delivered', NULL, 'd2a44242', '63b24063', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('357df8b8', '647d5345', '2026-02-02', 'Delivered', NULL, '691031b2', '199e67a2', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6bab3e30', '87dbf284', '2026-02-02', 'Delivered', NULL, '9f504c9b', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f19d0593', '3daf3337', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8f4db644', 'f7cc406e', '2026-02-02', 'Delivered', NULL, '014b4e80', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e66f7470', 'c9b920db', '2026-02-02', 'Delivered', NULL, 'aa501156', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bb07511d', '04929c93', '2026-02-02', 'Delivered', NULL, NULL, '2e1777a1', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8bcb9318', 'c3crgsfb', '2026-02-02', 'Delivered', NULL, 'e19dba1b', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('55c17a06', '4945630b', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5bf605c0', 'inrj8aqd', '2026-02-02', 'Delivered', NULL, 'f8c4e37c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('55ce8bd3', '04929c93', '2026-02-02', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('237899a3', '867715c2', '2026-02-03', 'Delivered', NULL, 'fade8591', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d3a2677c', '99508f63', '2026-02-03', 'Delivered', NULL, '8d9cb931', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('da42c0b2', '6cfcd982', '2026-02-03', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ceb9b842', '6604928f', '2026-02-06', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d5246a81', 'fc4b8a72', '2026-02-06', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('17a989c8', 'db367dce', '2026-02-06', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('86dac6de', 'ebf8818f', '2026-02-06', 'Delivered', NULL, '2de6d2ba', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('26c6eba6', 'ec73f6c3', '2026-02-06', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('7c2758c9', 'ccc86aa2', '2026-02-06', 'Delivered', NULL, 'ac24c22d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0524f4fb', '88c2bd00', '2026-02-09', 'Delivered', NULL, '74280b92', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('847dd4b9', 'ccd40604', '2026-02-09', 'Delivered', NULL, '8c35474d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('607dc662', '3c60981f', '2026-02-09', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6088f6f8', '552a2263', '2026-02-09', 'Delivered', NULL, 'ccdef0e9', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('65093cf1', '8545e6b2', '2026-02-09', 'Delivered', NULL, 'd14aacc3', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a936c3ae', '02dc4297', '2026-02-09', 'Delivered', NULL, 'b8dec3d5', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('31454f87', '207e1eda', '2026-02-09', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5dcc1397', '87dbf284', '2026-02-09', 'Delivered', NULL, '87b7f19b', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('113b350c', '1a0a3e30', '2026-02-09', 'Delivered', NULL, 'f803e991', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0e4b59ca', 'c9b920db', '2026-02-09', 'Delivered', NULL, '28824be8', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('393c26af', '081657fa', '2026-02-09', 'Delivered', NULL, '8ca112cc', '1967700b', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2d4bf725', '14694048', '2026-02-09', 'Delivered', '160767645', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ddcbd8fa', '55de29ff', '2026-02-09', 'Delivered', '160709693', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b84b2ee9', '14694048', '2026-02-09', 'Delivered', '160683562', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f9ad4340', 'd9b30ef2', '2026-02-09', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8db64016', 'eaa092a1', '2026-02-09', 'Delivered', NULL, 'd2a44242', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('199e67a2', '647d5345', '2026-02-09', 'Delivered', NULL, '357df8b8', 'e8ed1a84', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8f88f9cc', '0d70f923', '2026-02-09', 'Delivered', NULL, '70ee0178', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('26892a40', '6cfcd982', '2026-02-09', 'Delivered', NULL, '32719ee1', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f6ac2d88', 'f7cc406e', '2026-02-09', 'Delivered', NULL, '1f208e9f', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('bd226d65', '04929c93', '2026-02-09', 'Delivered', NULL, '7d95108f', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4f251bef', 'inrj8aqd', '2026-02-09', 'Delivered', NULL, 'd14b1eb6', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('48eced0a', '14694048', '2026-02-09', 'Delivered', '160806839', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2e1777a1', '04929c93', '2026-02-09', 'Delivered', NULL, 'bb07511d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fba4d652', '7444eeb3', '2026-02-10', 'Delivered', NULL, '54eb0751', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4846ff05', 'c3crgsfb', '2026-02-10', 'Delivered', NULL, NULL, '99723c97', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('73e333b8', '438241a6', '2026-02-13', 'Delivered', 'See customer for address info', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('c31232bd', '02dc4297', '2026-02-16', 'Delivered', NULL, 'c2e30e3d', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e9f4d5a1', '63a8b929', '2026-02-16', 'Delivered', NULL, 'b595c5d4', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5c182153', '2e5f3a06', '2026-02-16', 'Delivered', NULL, '6d02d83c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('66f3a985', '73b2fc23', '2026-02-16', 'Delivered', NULL, '6f8bea41', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f6297b19', 'a1277ca6', '2026-02-16', 'Delivered', NULL, 'ce33d780', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5a8b9975', '52512ea4', '2026-02-16', 'Delivered', NULL, '318457df', '3e1c282e', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('0c22a937', 'da2d82b0', '2026-02-16', 'Delivered', NULL, '8a5a2112', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8122919a', '8545e6b2', '2026-02-16', 'Delivered', NULL, '0a6e4697', '973f4dbc', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d0fb0ffb', '552a2263', '2026-02-16', 'Delivered', NULL, '6a224b5f', '971e8cc3', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('19db9f5c', '6bc9adea', '2026-02-16', 'Delivered', NULL, '33c8bc49', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('75c976ae', '87dbf284', '2026-02-16', 'Delivered', NULL, 'a7b92f8b', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4b627e54', '184caf13', '2026-02-16', 'Delivered', NULL, '7120441c', '439c473c', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3f2e769d', 'c9b920db', '2026-02-16', 'Delivered', NULL, '4c83dda8', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d482dc3a', '1a0a3e30', '2026-02-16', 'Delivered', NULL, 'e52e94e3', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1967700b', '081657fa', '2026-02-16', 'Delivered', NULL, '393c26af', '3f3ed96b', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('24e6e835', '0d70f923', '2026-02-16', 'Delivered', NULL, 'a4052f7d', 'a600e1e7', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('63b24063', 'eaa092a1', '2026-02-16', 'Delivered', NULL, '0d5c56ff', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e8ed1a84', '647d5345', '2026-02-16', 'Delivered', NULL, '199e67a2', '5ecbaeab', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('317fc103', 'a60df569', '2026-02-16', 'Delivered', NULL, '382a15ad', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3dec3a81', '898c1a57', '2026-02-16', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('418a1f6c', 'inrj8aqd', '2026-02-16', 'Delivered', NULL, 'f3fcbf97', 'a6628187', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('01dad77a', 'd9b30ef2', '2026-02-16', 'Delivered', NULL, NULL, '1d2d253b', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('88cfa142', 'f7cc406e', '2026-02-17', 'Delivered', NULL, 'aecbd1aa', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('6297493f', '04929c93', '2026-02-17', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3a81f7a6', 'fd5168bb', '2026-02-17', 'Delivered', NULL, 'cdf001ab', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('4093920b', 'cfac3670', '2026-02-17', 'Delivered', NULL, '59ab8e35', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('eaf1a022', '6cfcd982', '2026-02-19', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('12f11a77', 'd6f1b3e6', '2026-02-23', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('ad563677', 'c10264ad', '2026-02-23', 'Delivered', NULL, '9c7e5eb1', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('54ddbd19', 'a6eac0ca', '2026-02-23', 'Delivered', NULL, '05f76f6e', '07927fb0', NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('fd2bc040', 'b45ff5f9', '2026-02-23', 'Delivered', NULL, 'e3256102', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2c6ba799', '04929c93', '2026-02-23', 'Delivered', NULL, '1275a45a', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9e3fb81d', '950d6ccc', '2026-02-23', 'Delivered', NULL, '99267043', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2a9644a5', '967e328b', '2026-02-23', 'Delivered', NULL, '0740de72', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('2c84ffb0', 'bc25f496', '2026-02-23', 'Delivered', NULL, '29635a9c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('971e8cc3', '552a2263', '2026-02-23', 'Delivered', NULL, 'd0fb0ffb', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('8e83904d', '04929c93', '2026-02-23', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('83a94963', 'bc9bf4b3', '2026-02-23', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('973f4dbc', '8545e6b2', '2026-02-23', 'Delivered', NULL, '8122919a', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1176c236', '02dc4297', '2026-02-23', 'Delivered', NULL, '4d4c8190', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('48cf2463', '1a0a3e30', '2026-02-23', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('79a372e0', '5432f414', '2026-02-23', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('89a8786e', '93d82ce0', '2026-02-23', 'Delivered', NULL, '8ba839b3', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('b3fd7ed1', '6bc9adea', '2026-02-23', 'Delivered', NULL, 'a3a4f460', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d476fd48', 'b73540eb', '2026-02-23', 'Open', NULL, '4a4db650', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3f3ed96b', '081657fa', '2026-02-23', 'Delivered', NULL, '1967700b', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a600e1e7', '0d70f923', '2026-02-23', 'Delivered', NULL, '24e6e835', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('5ecbaeab', '647d5345', '2026-02-23', 'Delivered', NULL, 'e8ed1a84', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('e3eeb372', '4945630b', '2026-02-23', 'Delivered', NULL, '71de74a5', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('3e1c282e', '52512ea4', '2026-02-23', 'Delivered', NULL, '5a8b9975', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('dcf48fa4', 'c9b920db', '2026-02-23', 'Delivered', NULL, '884d70ff', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('08be72f8', '87dbf284', '2026-02-23', 'Delivered', NULL, '1619e1ea', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('a6628187', 'inrj8aqd', '2026-02-23', 'Delivered', NULL, '418a1f6c', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('34227b00', '6cfcd982', '2026-02-23', 'Delivered', NULL, 'ad24c5c4', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('99723c97', 'c3crgsfb', '2026-02-23', 'Delivered', NULL, '4846ff05', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('de27e085', 'f7cc406e', '2026-02-23', 'Delivered', NULL, 'd4530f25', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('1d2d253b', 'd9b30ef2', '2026-02-23', 'Delivered', NULL, '01dad77a', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('439c473c', '184caf13', '2026-02-23', 'Delivered', NULL, '4b627e54', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('9e3fa3ed', '14694048', '2026-02-23', 'Delivered', '161265039', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('69a0b024', '14694048', '2026-02-23', 'Delivered', '161233615', NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('f754a701', 'e1c68221', '2026-02-23', 'Open', NULL, '887b8446', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('d5ecf10e', '314b8bb1', '2026-02-24', 'Delivered', NULL, NULL, NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.orders (order_id, customer_id, order_date, order_status, order_notes, previous_order, next_order, delivery_photo, signature, "update column", created_at, created_by, updated_at, updated_by, company_id, facility_id)
VALUES ('011367f6', 'b830db03', '2026-02-26', 'Open', NULL, '8453b7be', NULL, NULL, NULL, NULL, now(), 'R7CbqHmA1j', now(), NULL, 'R7CbqHmA1j', 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_id) DO NOTHING;

-- ── order_details (374 rows) ────────────────────────────────────────
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e6f8d49d', 'ed25070c', '2586f56b', 'Whole Bean', 2, 'Open', '072e65fd', '631ab369', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ce6e1dc9', '38ed70ed', 'CSO5WBWS', 'Whole Bean', 6, 'Open', '1004faee', 'ecc9a7fc', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('54f8ac4b', '38ed70ed', 'bbbe3e73', 'Cold Brew Ground', 1, 'Open', '4949bab5', 'f2f56b3a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4ba58ee9', '5e76aa64', 'd83e44fc', 'Whole Bean', 6, 'Open', '7d091119', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('517ed4f0', '5e76aa64', '89e19cad', 'Whole Bean', 6, 'Open', '0a7a3d1d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f2d22ba9', 'e19dba1b', '2036346d', 'Whole Bean', 3, 'Open', 'eb4a1237', '5411ef9a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('322c9d64', 'e19dba1b', 'CSO5WBWS', 'Whole Bean', 2, 'Open', 'ed0b698a', '6f52fbce', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fabfd557', 'e19dba1b', '37308503', 'Other Ground', 2, 'Open', NULL, '70d0a4f0', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a0096e79', 'b5f84b00', 'bbbe3e73', 'Whole Bean', 13, 'Open', 'd50bdcc8', '9d9b3e13', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('67d8c37c', '941f3ba2', 'VD12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b6ba8921', '4d4c8190', '2824b0bc', 'Whole Bean', 18, 'Open', '2c19491c', 'ad332253', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('620a1f0c', '4d4c8190', '2586f56b', 'Whole Bean', 4, 'Open', 'f1e939b8', 'cb5880d4', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('107b233a', 'dda898bc', '3362fa39', 'Whole Bean', 6, 'Open', 'd784e4de', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8b3b1d28', 'dda898bc', 'bbbe3e73', 'Whole Bean', 2, 'Open', '21027b1a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('779dfbff', 'dda898bc', 'CSO5WBWS', 'Whole Bean', 3, 'Open', '62e6cf78', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('27025d2b', 'dda898bc', '7641ec65', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('33b41384', 'dda898bc', 'H12WBWS', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6bfed9f4', 'dda898bc', 'c418753f', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b346b0f1', 'dda898bc', '6a383b94', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('962f40c5', '2a00e6d2', '58e8b865', 'Whole Bean', 10, 'Open', '0a210566', 'c6630383', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('199f5876', '2a00e6d2', '25510a47', 'Whole Bean', 5, 'Open', '3dc75bb1', '4b7a7871', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7f13503a', '414a02cc', 'V5WBWS', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('275171ba', '414a02cc', 'V12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cb351fe8', '81044b35', 'd17c6886', 'Whole Bean', 8, 'Open', 'b712cdf4', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d3ad0477', '81044b35', '7641ec65', 'Whole Bean', 4, 'Open', '3ae93023', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('db8f5087', '81044b35', '32fc41f6', 'Whole Bean', 6, 'Open', 'defe82e2', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f3d8e7a7', '267434d6', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', '70de1aeb', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ee9b87e5', '29635a9c', '23b13937', 'Whole Bean', 1, 'Open', NULL, '3ea080d3', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('11123e0b', '29635a9c', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, 'b6487357', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('45ab306e', '29635a9c', '28767a32', 'Whole Bean', 1, 'Open', NULL, '2a5aba02', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('44c012c9', '29635a9c', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, 'e302ddad', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b188acb7', '29635a9c', 'V12WBWSDTC', 'Whole Bean', 2, 'Open', NULL, 'ce059a48', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ce74f042', 'db00e7bf', 'CSO5WBWS', 'Whole Bean', 1, 'Open', '829e9cff', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fde91a59', '91e15c18', 'c418753f', 'Whole Bean', 1, 'Open', '33f7d887', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cd399fd0', 'ad4074e7', 'CSO5WBWS', 'Whole Bean', 20, 'Open', '6849a08d', '949202cd', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('80ad5d2c', 'a574de6b', 'CSO5WBWS', 'Whole Bean', 15, 'Open', 'c6f86ab2', '0a8e5028', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7de35ad8', 'a4052f7d', 'd2dd846b', 'Whole Bean', 6, 'Open', '05e506df', '83db33c6', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9ae1e30d', '5d954e35', 'H5WBWS', 'Whole Bean', 7, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4b99d155', '5d954e35', 'R5WBWS', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0750d209', 'ea0dd0b4', 'CSO5WBWS', 'Whole Bean', 40, 'Open', '94695642', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('44d08885', 'ea0dd0b4', '37308503', 'Whole Bean', 16, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7a0e181a', '382a15ad', 'f4008a6c', 'Whole Bean', 70, 'Open', 'a25ff8d9', '1c0b9a8d', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8b7015a1', 'd4530f25', 'efa274e1', 'Whole Bean', 6, 'Open', '760ca113', 'eba2d23d', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('32fdefad', '69582c55', 'V12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('676ff4e4', '69582c55', '3d12aa60', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('404b6c7c', '69582c55', 'a5e741ee', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('89fd76ce', '5968f335', 'CSO5WBWS', 'Whole Bean', 6, 'Open', '6b5df8d9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('201d03be', '1275a45a', '26ad7b5b', 'Whole Bean', 10, 'Open', NULL, 'c0a51ebd', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d2673135', 'ac24c22d', 'CSO5WBWS', 'Drip Ground', 8, 'Open', NULL, 'dac3e15a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8299baa0', 'ac24c22d', '37308503', 'Drip Ground', 4, 'Open', NULL, '1087b814', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('33082118', '3e5acac8', 'V12WBWSDTC', 'Whole Bean', 1, 'Open', '474edf57', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('209d2668', '740029d0', '2036346d', 'Drip Ground', 2, 'Open', 'bf47bf01', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c6841e5a', '740029d0', 'CSO5WBWS', 'Whole Bean', 2, 'Open', 'b4873df7', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3ffdb1d0', '740029d0', 'VD12WBWS', 'Whole Bean', 2, 'Open', 'c202b59b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e7b7c323', '740029d0', 'CSO5WBWS', 'Cold Brew Ground', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9d9b3e13', 'ccdef0e9', 'bbbe3e73', 'Whole Bean', 13, 'Open', 'a0096e79', '1a1bdbe2', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ecc9a7fc', 'e263b9b4', 'CSO5WBWS', 'Whole Bean', 6, 'Open', 'ce6e1dc9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f2f56b3a', 'e263b9b4', 'bbbe3e73', 'Cold Brew Ground', 1, 'Open', '54f8ac4b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4f8da8a0', 'c870cca8', 'V12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4ba727c3', 'c870cca8', '7641ec65DTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c4b92eeb', 'c870cca8', '3d12aa60DTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3deda1b3', 'd6160793', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', '4ec48783', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5d638831', 'd9f607fc', '2824b0bc', 'Whole Bean', 22, 'Open', '88443a5a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d313700c', 'd9f607fc', '2586f56b', 'Whole Bean', 2, 'Open', '35745cfe', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d135d154', 'ecad2fa9', 'CSO5WBWS', 'Whole Bean', 5, 'Open', 'a2aa0570', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b9bc089a', 'ecad2fa9', '37308503', 'Whole Bean', 1, 'Open', '1799e1e3', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a0e5d3c8', '892213eb', '26ad7b5b', 'Whole Bean', 2, 'Open', '2bac1578', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0c546812', '892213eb', '1f5f0ed4', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9ede215a', '892213eb', '58cf42d7', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c6630383', '9d2f17c3', '58e8b865', 'Whole Bean', 10, 'Open', '962f40c5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4b7a7871', '9d2f17c3', '25510a47', 'Whole Bean', 5, 'Open', '199f5876', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('61720064', '9d2f17c3', '50dbea5d', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('21f02b90', '9d2f17c3', 'd28a6d3f', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0c88d0d7', 'a055a854', '3d12aa60DTC', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0a8e5028', 'd2a44242', 'CSO5WBWS', 'Whole Bean', 15, 'Open', '80ad5d2c', 'fe226c35', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('949202cd', '691031b2', 'CSO5WBWS', 'Whole Bean', 20, 'Open', 'cd399fd0', '557ade69', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1642c9b5', 'dbafd8ed', 'd2dd846b', 'Whole Bean', 8, 'Open', '801e4edb', '8a0739c5', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('528a6a9e', '97fe3e72', 'd17c6886', 'Whole Bean', 8, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0cdc6657', '97fe3e72', 'CSO5WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ead71f90', '97fe3e72', '32fc41f6', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ea61900f', '97fe3e72', '3d12aa60', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('2459e14e', '97fe3e72', '4c091d56', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('347a7fd5', '97fe3e72', 'CSO12WBWS', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('efdef794', '87b7f19b', 'H5WBWS', 'Whole Bean', 6, 'Open', NULL, '0d304d2c', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7c42f76b', '87b7f19b', 'R5WBWS', 'Whole Bean', 2, 'Open', NULL, '9e60efb7', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7bf6f934', '87b7f19b', '37308503', 'Whole Bean', 1, 'Open', NULL, 'e7982ca7', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6edc57ae', '87b7f19b', 'HS5WBWS', 'Whole Bean', 1, 'Open', NULL, '66a96171', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('03667be0', '4c83dda8', 'V5WBWS', 'Whole Bean', 7, 'Open', '8009240b', 'c3e7f472', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('83f82351', '4c83dda8', 'V12WBWS', 'Whole Bean', 5, 'Open', '7b367906', '72a1b74e', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('be0beada', 'e52e94e3', '3362fa39', 'Whole Bean', 7, 'Open', NULL, 'd9f3514b', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('41831dc4', 'e52e94e3', 'CSO5WBWS', 'Whole Bean', 5, 'Open', NULL, '2e81aead', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('442f2522', 'e52e94e3', 'bbbe3e73', 'Whole Bean', 2, 'Open', NULL, 'c3066ada', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f8fffa3e', 'e52e94e3', '6a383b94', 'Whole Bean', 4, 'Open', NULL, 'b0d8d09c', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d1460fea', 'e52e94e3', 'CSO12WBWS', 'Whole Bean', 3, 'Open', NULL, '0439cca3', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d860efd7', 'e52e94e3', '7641ec65', 'Whole Bean', 3, 'Open', NULL, '82a27148', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e99f226e', '60c1f58f', 'bbbe3e73', 'Whole Bean', 8, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('13b4a4db', '60c1f58f', '37308503', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d405b614', '7d95108f', '26ad7b5b', 'Whole Bean', 5, 'Open', NULL, 'd425bc87', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cd2c1a06', 'aecbd1aa', 'efa274e1', 'Whole Bean', 7, 'Open', NULL, 'e386de80', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c1c1e5d8', 'f3fcbf97', 'CSO5WBWS', 'Whole Bean', 48, 'Open', '94b95a78', '3bedae7b', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d4671e7d', 'f3fcbf97', '37308503', 'Whole Bean', 8, 'Open', '7de510e2', 'b3f6c9f1', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7e54cd5f', '95c3f4a1', 'V12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('809d536f', 'a88dde5a', 'V12WBWS', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5394b3ad', 'd0120326', 'V12WBWS', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('382ccc14', 'd0120326', 'H12WBWS', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e7c3e13b', 'dd40efde', 'V12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('15ceba2f', '41947df8', 'a5e741ee', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ccb85204', '8453b7be', 'CSO5WBWS', 'Drip Ground', 5, 'Open', '2e8f07aa', 'd25d3a86', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9e14b4ef', '4c0cc1da', 'CSO5WBWS', 'Whole Bean', 3, 'Open', '6b5df8d9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('949ad3fd', '4c0cc1da', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7aed9bd7', 'b271e265', 'c435528a', 'Whole Bean', 10, 'Open', 'c1f9dc16', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('540adb7e', 'fc44f1d7', '3d12aa60DTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cea9caf3', 'fc44f1d7', 'a5e741eeDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('06daa472', '8d958b0d', 'cd0719e0', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a8b7c0fd', '99822ecb', '7641ec65DTC', 'Whole Bean', 1, 'Open', 'c944bef5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('df766304', '3c40fffc', '211d879f', 'Whole Bean', 2, 'Open', '3b3e12b2', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a296e356', '3c40fffc', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', 'f8382eb6', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8070ed1c', 'eb27e241', '8ddefb00', 'Whole Bean', 24, 'Open', 'cc43062e', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bdb3f312', 'fdde38d7', 'V12WBWSDTC', 'Whole Bean', 2, 'Open', 'e04ef9fb', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cf0c1523', '20f14401', 'V12WBWSDTC', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7d6ac441', '19a862ff', '64caec66', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('631ab369', 'a0c5c8ab', '2586f56b', 'Whole Bean', 2, 'Open', 'e6f8d49d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c359a066', 'fbf57933', '3d12aa60DTC', 'Whole Bean', 1, 'Open', '906ecd9d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ccac7be5', 'fbf57933', '7641ec65DTC', 'Whole Bean', 1, 'Open', '890f0e62', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d6a859bf', 'fbf57933', '8ddefb00', 'Whole Bean', 1, 'Open', 'bcbe11b0', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6fa0f334', 'a53315dd', 'H12WBWS', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ffb253b8', 'a53315dd', '211d879f', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('2efd3c0c', 'a53315dd', 'CSO12WBWS', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bdf64d7a', 'a53315dd', 'a5e741ee', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5b58c384', 'a53315dd', 'V12WBWS', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5016f563', '0a0a0a4b', 'V5WBWS', 'Drip Ground', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bd980983', '90849497', '25510a47', 'Whole Bean', 9, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0107817a', '8d0c24c0', 'bbbe3e73', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e79e31f5', '8d0c24c0', '37308503', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4be079fb', 'd14aacc3', 'CSO5WBWS', 'Whole Bean', 7, 'Open', NULL, 'b28bc18e', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('89dd212f', 'd14aacc3', 'bbbe3e73', 'Whole Bean', 2, 'Open', NULL, 'd62132b4', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b612bfee', 'd14aacc3', '37308503', 'Whole Bean', 1, 'Open', NULL, 'e5e8ee76', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b68813e2', '120c4ea7', '3d12aa60DTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('424ad50d', '120c4ea7', 'a5e741eeDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1351433e', '120c4ea7', 'V12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6b5d3c6b', '120c4ea7', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0f5f7bf0', '10823d9b', '3362fa39', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f8f01a44', '10823d9b', 'CSO5WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f9c83b80', '10823d9b', 'bbbe3e73', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('abc1a5de', '10823d9b', '6a383b94', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4a6f894e', '0535adf9', 'CSO5WBWS', 'Whole Bean', 20, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('dbe53447', '0535adf9', '37308503', 'Other Ground', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9364bb9e', '0535adf9', '2586f56b', 'Whole Bean', 10, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('65ab7945', '8ca112cc', 'd17c6886', 'Whole Bean', 10, 'Open', NULL, '4914b403', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('11a19e63', '8ca112cc', 'CSO5WBWS', 'Whole Bean', 1, 'Open', NULL, 'deea94af', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9ef35fe9', '8ca112cc', '37308503', 'Whole Bean', 2, 'Open', NULL, 'f2e4bb4a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('67db2933', '8ca112cc', '32fc41f6', 'Whole Bean', 6, 'Open', NULL, '1c9fe961', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8a0739c5', '70ee0178', 'd2dd846b', 'Whole Bean', 8, 'Open', '1642c9b5', '3c7908dd', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bff94cf0', '0d5c56ff', 'CSO5WBWS', 'Whole Bean', 15, 'Open', '0a8e5028', '6b20e507', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('557ade69', '357df8b8', 'CSO5WBWS', 'Whole Bean', 20, 'Open', '949202cd', 'ad435f7f', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('80369ada', '6bab3e30', 'H5WBWS', 'Whole Bean', 8, 'Open', '2f30d36c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a3e54138', '6bab3e30', 'R5WBWS', 'Whole Bean', 1, 'Open', '72b1b2ba', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c60f4ff5', '0d5c56ff', 'CSO12WBWS', 'Whole Bean', 10, 'Open', NULL, '7bcbfd40', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f18cdf89', 'f19d0593', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4962c048', '8f4db644', 'efa274e1', 'Whole Bean', 8, 'Open', '5a1ae384', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5650ce33', 'e66f7470', 'V5WBWS', 'Whole Bean', 7, 'Open', '24cf39b2', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('40c20cad', 'e66f7470', 'V12WBWS', 'Whole Bean', 3, 'Open', '8d28eeba', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4f17523c', 'bb07511d', '26ad7b5b', 'Whole Bean', 8, 'Open', NULL, 'a0dba393', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4ef35805', 'bb07511d', '1f5f0ed4', 'Whole Bean', 8, 'Open', NULL, 'da0cb4c4', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c9e8f1df', 'bb07511d', '37308503', 'Whole Bean', 2, 'Open', NULL, '72878956', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7cd2861c', 'bb07511d', '58cf42d7', 'Whole Bean', 1, 'Open', NULL, 'd507f331', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5411ef9a', '8bcb9318', '2036346d', 'Whole Bean', 4, 'Open', 'f2d22ba9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6f52fbce', '8bcb9318', 'CSO5WBWS', 'Whole Bean', 3, 'Open', '322c9d64', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('70d0a4f0', '8bcb9318', 'VD12WBWS', 'Other Ground', 1, 'Open', 'fabfd557', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a0dec288', '55c17a06', 'HS5WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6970bc42', '55c17a06', '4e6c17f1', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9b98a2ce', '5bf605c0', 'CSO5WBWS', 'Whole Bean', 48, 'Open', 'c7ec8148', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('578f3b01', '55ce8bd3', 'e8b47e54', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('27ea1e51', '237899a3', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', 'daad9abf', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cfc8c4e2', 'd3a2677c', '3d12aa60DTC', 'Whole Bean', 4, 'Open', 'ef9f791d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('582ee1e3', 'da42c0b2', 'CSO5WBWS', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('185d1d3f', 'da42c0b2', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('baed27ef', 'ceb9b842', '1c98a15f', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b769f37c', 'd5246a81', 'V12WBWSDTC', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c5625a98', '17a989c8', 'VD12WBWSDTC', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ccdd7316', '86dac6de', 'c418753f', 'Whole Bean', 1, 'Open', '55f578c5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('14a5936e', '26c6eba6', '1c98a15f', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('dac3e15a', '7c2758c9', 'CSO5WBWS', 'Whole Bean', 2, 'Open', 'd2673135', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3e73eb3f', '0524f4fb', '905fa1f9', 'Whole Bean', 1, 'Open', '42fc71c8', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c3a609d5', '847dd4b9', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', 'f2efc709', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7f7f82c0', '607dc662', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1a1bdbe2', '6088f6f8', 'bbbe3e73', 'Whole Bean', 20, 'Open', '9d9b3e13', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b28bc18e', '65093cf1', 'CSO5WBWS', 'Whole Bean', 7, 'Open', '4be079fb', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5f84e11a', 'a936c3ae', '2824b0bc', 'Whole Bean', 17, 'Open', '88443a5a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fa308c39', 'a936c3ae', '2586f56b', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3639dc03', '31454f87', 'VD12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ffd58d5a', '31454f87', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a78f155e', '31454f87', 'cd0719e0', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0d1b9a10', '31454f87', '3d12aa60DTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0d304d2c', '5dcc1397', 'H5WBWS', 'Whole Bean', 6, 'Open', 'efdef794', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9e60efb7', '5dcc1397', 'R5WBWS', 'Whole Bean', 1, 'Open', '7c42f76b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('66a96171', '5dcc1397', 'HS5WBWS', 'Whole Bean', 1, 'Open', '6edc57ae', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9cc21fdd', '5dcc1397', '211d879f', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('545d04af', '5dcc1397', 'VD12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1589d825', '113b350c', '3362fa39', 'Whole Bean', 6, 'Open', '6509cc85', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('be68b245', '113b350c', 'CSO5WBWS', 'Whole Bean', 4, 'Open', '157720df', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('539de9c0', '113b350c', '37308503', 'Whole Bean', 1, 'Open', '32725452', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('acacc3bc', '113b350c', '211d879f', 'Whole Bean', 6, 'Open', 'a9dd6c0b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d11dc8d8', '0e4b59ca', 'V5WBWS', 'Whole Bean', 8, 'Open', 'e33de2b2', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3ed585e6', '0e4b59ca', 'V12WBWS', 'Whole Bean', 3, 'Open', '8cda944f', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4914b403', '393c26af', 'd17c6886', 'Whole Bean', 10, 'Open', '65ab7945', '1f333a3a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('deea94af', '393c26af', 'CSO5WBWS', 'Whole Bean', 2, 'Open', '11a19e63', '63485991', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1c9fe961', '393c26af', '32fc41f6', 'Whole Bean', 6, 'Open', '67db2933', '6b35f39d', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e0dfedaf', '393c26af', 'CSO12WBWS', 'Whole Bean', 3, 'Open', NULL, '08ce3fdc', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bb408a9b', '2d4bf725', 'H12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('464ed39f', 'ddcbd8fa', 'H12WBWS', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8b6a0217', 'ddcbd8fa', 'V12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('11c0a82c', 'b84b2ee9', 'H12WBWS', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e5e8ee76', '65093cf1', '37308503', 'Whole Bean', 1, 'Open', 'b612bfee', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('12e93bad', 'f9ad4340', 'bbbe3e73', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('eb11eaa8', 'f9ad4340', 'c759e1ba', 'Drip Ground', 7, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d62132b4', '65093cf1', 'bbbe3e73', 'Whole Bean', 2, 'Open', '89dd212f', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fe226c35', '8db64016', 'CSO5WBWS', 'Whole Bean', 15, 'Open', '0a8e5028', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ad435f7f', '199e67a2', 'CSO5WBWS', 'Whole Bean', 20, 'Open', '557ade69', '5884c865', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3c7908dd', '8f88f9cc', 'd2dd846b', 'Whole Bean', 8, 'Open', '8a0739c5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('294743f3', '26892a40', 'CSO5WBWS', 'Whole Bean', 3, 'Open', '6b5df8d9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('29f26de3', 'f6ac2d88', 'efa274e1', 'Whole Bean', 7, 'Open', '2a019849', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('940dcb6b', 'f6ac2d88', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d425bc87', 'bd226d65', '26ad7b5b', 'Whole Bean', 5, 'Open', 'd405b614', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('16df1769', '4f251bef', 'CSO5WBWS', 'Whole Bean', 32, 'Open', '5c6415b4', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('df4e0884', '48eced0a', 'H12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a0dba393', '2e1777a1', '26ad7b5b', 'Whole Bean', 8, 'Open', '4f17523c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('da0cb4c4', '2e1777a1', '1f5f0ed4', 'Whole Bean', 8, 'Open', '4ef35805', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('72878956', '2e1777a1', '37308503', 'Whole Bean', 2, 'Open', 'c9e8f1df', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d507f331', '2e1777a1', '58cf42d7', 'Whole Bean', 1, 'Open', '7cd2861c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('133874d4', 'fba4d652', 'H12WBWSDTC', 'Whole Bean', 2, 'Open', '4d26b5da', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fe10f462', '4846ff05', '2036346d', 'Whole Bean', 3, 'Open', NULL, '48c6189b', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3b6a252c', '4846ff05', 'CSO5WBWS', 'Whole Bean', 2, 'Open', NULL, 'fb03006c', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('2b2886d1', '4846ff05', 'VD12WBWS', 'Whole Bean', 1, 'Open', NULL, '0d997592', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5d729f25', '73e333b8', 'bbbe3e73', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('251a7575', 'c31232bd', '2824b0bc', 'Whole Bean', 20, 'Open', '382ce5dc', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d1fa50d2', 'c31232bd', '2586f56b', 'Whole Bean', 10, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1a37215e', 'c31232bd', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('52f5033f', 'e9f4d5a1', '64caec66', 'Whole Bean', 2, 'Open', '6d114e1a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f84f5849', '5c182153', 'R5WBWS', 'Whole Bean', 5, 'Open', 'febf6fbd', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a52c57ee', '66f3a985', 'V5WBWS', 'Whole Bean', 2, 'Open', 'b319804d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('dcc6ac58', 'f6297b19', 'V12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e2afade4', 'f6297b19', 'H12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f58dbf07', 'f6297b19', 'c418753f', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5481b0e2', 'f6297b19', '211d879f', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('78c9bf8e', 'f6297b19', 'c698fb0c', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('821e4ecb', 'f6297b19', '3d12aa60', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b53b3b8c', '5a8b9975', 'V5WBWS', 'Drip Ground', 4, 'Open', 'fb8c01cc', '421650be', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('20dd5e92', '0c22a937', 'V12WBWSDTC', 'Whole Bean', 1, 'Open', '3cfb1150', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5d577096', '0c22a937', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', 'e43ae827', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1a0194af', '0c22a937', '6a6af31c', 'Whole Bean', 1, 'Open', 'e18bb610', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c2808272', '8122919a', 'CSO5WBWS', 'Whole Bean', 10, 'Open', '87588110', '064cd69f', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d6b3b913', 'd0fb0ffb', 'bbbe3e73', 'Whole Bean', 10, 'Open', '096e585c', 'aec89fca', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c0ddd75e', '19db9f5c', '58e8b865', 'Whole Bean', 11, 'Open', '0ab14e8f', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e8489bbd', '19db9f5c', '25510a47', 'Whole Bean', 7, 'Open', 'da41839e', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0db1bce1', '75c976ae', 'H5WBWS', 'Whole Bean', 4, 'Open', '0d05f8bc', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('93939c18', '75c976ae', 'HS5WBWS', 'Whole Bean', 1, 'Open', 'f67c0f44', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('737872b5', '75c976ae', 'R5WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('26700a4e', '75c976ae', 'VD12WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0a5e2de3', '75c976ae', 'CSO12WBWS', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('41dd1d26', '75c976ae', '211d879f', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e3e0a69b', '4b627e54', 'bbbe3e73', 'Whole Bean', 10, 'Open', 'e3f90aae', 'acd3a5bd', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('49688558', '4b627e54', '37308503', 'Whole Bean', 1, 'Open', 'edb34211', 'e4f0e3d8', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c3e7f472', '3f2e769d', 'V5WBWS', 'Whole Bean', 3, 'Open', '03667be0', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('72a1b74e', '3f2e769d', 'V12WBWS', 'Whole Bean', 5, 'Open', '83f82351', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d9f3514b', 'd482dc3a', '3362fa39', 'Whole Bean', 7, 'Open', 'be0beada', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c3066ada', 'd482dc3a', 'bbbe3e73', 'Whole Bean', 4, 'Open', '442f2522', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b0d8d09c', 'd482dc3a', '6a383b94', 'Whole Bean', 3, 'Open', 'f8fffa3e', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0439cca3', 'd482dc3a', 'CSO12WBWS', 'Whole Bean', 2, 'Open', 'd1460fea', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1e6d26af', 'd482dc3a', 'H12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7922ada6', 'd482dc3a', 'VD12WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1f333a3a', '1967700b', 'd17c6886', 'Whole Bean', 12, 'Open', '4914b403', '3bb3937d', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('63485991', '1967700b', 'CSO5WBWS', 'Whole Bean', 2, 'Open', 'deea94af', 'ad88158b', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6b35f39d', '1967700b', '32fc41f6', 'Whole Bean', 4, 'Open', '1c9fe961', '08f68257', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e2ff5264', '1967700b', '37308503', 'Whole Bean', 1, 'Open', NULL, '8627a4cb', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cc85108c', '1967700b', '3d12aa60', 'Whole Bean', 3, 'Open', NULL, 'cd2cc945', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('83db33c6', '24e6e835', 'd2dd846b', 'Whole Bean', 6, 'Open', '7de35ad8', '8ff27a5a', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6b20e507', '63b24063', 'CSO5WBWS', 'Whole Bean', 15, 'Open', 'bff94cf0', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7bcbfd40', '63b24063', 'CSO12WBWS', 'Whole Bean', 10, 'Open', 'c60f4ff5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5884c865', 'e8ed1a84', 'CSO5WBWS', 'Whole Bean', 20, 'Open', 'ad435f7f', '9c5397bf', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('1c0b9a8d', '317fc103', 'f4008a6c', 'Whole Bean', 70, 'Open', '7a0e181a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('81ef2da2', '3dec3a81', 'V5WBWS', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ed00a78f', '3dec3a81', 'CSO5WBWS', 'Whole Bean', 24, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3bedae7b', '418a1f6c', 'CSO5WBWS', 'Whole Bean', 48, 'Open', 'c1c1e5d8', '59c1f8ee', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b3f6c9f1', '418a1f6c', '37308503', 'Whole Bean', 8, 'Open', 'd4671e7d', 'c077a432', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('450205a5', '01dad77a', '8ddefb00', 'Whole Bean', 28, 'Open', NULL, '581e3cfb', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('32504cd7', '88cfa142', 'efa274e1', 'Whole Bean', 7, 'Open', 'cd2c1a06', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('67d6ff34', '6297493f', '26ad7b5b', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('56042f11', '6297493f', '58cf42d7', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c6e321d6', '6297493f', '37308503', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d0e00b88', '3a81f7a6', 'V12WBWS', 'Whole Bean', 8, 'Open', '159a80a6', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bad3feab', '3a81f7a6', 'CSO12WBWS', 'Whole Bean', 8, 'Open', '3b7bcfce', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('a851b0bd', '3a81f7a6', 'H12WBWS', 'Whole Bean', 8, 'Open', '8b535df9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('351740cc', '3a81f7a6', 'a5e741ee', 'Whole Bean', 8, 'Open', '55930e0b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7c163739', '3a81f7a6', 'c698fb0c', 'Whole Bean', 8, 'Open', 'bc7c90ac', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bd8abb19', '3a81f7a6', '3d12aa60', 'Whole Bean', 8, 'Open', 'ab280b65', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8e683e5f', '4093920b', '7641ec65', 'Whole Bean', 16, 'Open', '28cfe430', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('36dcd43a', '4093920b', 'H12WBWS', 'Whole Bean', 8, 'Open', 'd9ed7409', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('72ceae24', '4093920b', 'CSO12WBWS', 'Whole Bean', 8, 'Open', 'b8d21e27', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0e985f19', 'eaf1a022', 'CSO5WBWS', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('21c609ad', 'eaf1a022', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('484a8cfc', '12f11a77', 'CSO5WBWS', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7792da50', '12f11a77', 'V5WBWS', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9f068d80', '12f11a77', 'V12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('abbd95bd', '12f11a77', 'CSO12WBWS', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('b67e4912', 'ad563677', 'bbbe3e73', 'Whole Bean', 6, 'Open', 'd5a3110d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6215c973', 'ad563677', '37308503', 'Whole Bean', 1, 'Open', '6c6dc792', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0c2ca3fb', '54ddbd19', 'CSO5WBWS', 'Whole Bean', 1, 'Open', '21e3c602', '2ab48b25', 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3d1a2252', 'fd2bc040', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', '87207ee2', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c0a51ebd', '2c6ba799', '26ad7b5b', 'Whole Bean', 12, 'Open', '201d03be', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4a35044a', '9e3fb81d', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', '3fd6b639', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f2ed49cd', '2a9644a5', 'V5WBWS', 'Whole Bean', 1, 'Open', 'a38704a1', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('2a5aba02', '2c84ffb0', '2586f56b', 'Whole Bean', 1, 'Open', '45ab306e', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e302ddad', '2c84ffb0', 'CSO12WBWSDTC', 'Whole Bean', 2, 'Open', '44c012c9', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ce059a48', '2c84ffb0', 'c418753f', 'Whole Bean', 1, 'Open', 'b188acb7', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('aec89fca', '971e8cc3', 'bbbe3e73', 'Whole Bean', 10, 'Open', 'd6b3b913', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('804d1017', '8e83904d', '26ad7b5b', 'Whole Bean', 16, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('efa28e77', '8e83904d', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('74863231', '8e83904d', '58cf42d7', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('dc8160ad', '83a94963', 'CSO12WBWSDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('064cd69f', '973f4dbc', 'CSO5WBWS', 'Whole Bean', 10, 'Open', 'c2808272', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('32704557', '973f4dbc', 'bbbe3e73', 'Cold Brew Ground', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ad332253', '1176c236', '2824b0bc', 'Whole Bean', 18, 'Open', 'b6ba8921', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cb5880d4', '1176c236', '2586f56b', 'Whole Bean', 4, 'Open', '620a1f0c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e4b2e41f', '48cf2463', '3362fa39', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('4c928b95', '48cf2463', 'CSO5WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7f974e88', '48cf2463', 'bbbe3e73', 'Whole Bean', 2, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f0ee632b', '48cf2463', '6a383b94', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9b141bfe', '48cf2463', 'CSO12WBWS', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('899155b8', '48cf2463', '211d879f', 'Whole Bean', 3, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('cc20df40', '48cf2463', '7641ec65', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('18678134', '79a372e0', 'a5e741eeDTC', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('bfd9732a', '89a8786e', 'd83e44fc', 'Whole Bean', 6, 'Open', 'a5388c05', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3031a7ae', 'b3fd7ed1', '25510a47', 'Whole Bean', 5, 'Open', 'b598783a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f288725f', 'b3fd7ed1', '58e8b865', 'Whole Bean', 7, 'Open', 'c20e158d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('22a6d026', 'b3fd7ed1', 'd28a6d3f', 'Whole Bean', 10, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('f5a79ad1', 'b3fd7ed1', '50dbea5d', 'Whole Bean', 10, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8cf2884e', 'd476fd48', '7641ec65', 'Whole Bean', 1, 'Open', '1b5a006b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('7e6352f9', 'd476fd48', 'H12WBWSDTC', 'Whole Bean', 1, 'Open', 'c1b30fdc', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9716b182', 'd476fd48', '28767a32', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('3bb3937d', '3f3ed96b', 'd17c6886', 'Whole Bean', 12, 'Open', '1f333a3a', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('ad88158b', '3f3ed96b', 'CSO5WBWS', 'Whole Bean', 1, 'Open', '63485991', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('08f68257', '3f3ed96b', '32fc41f6', 'Whole Bean', 6, 'Open', '6b35f39d', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('99a8b829', '3f3ed96b', 'c698fb0c', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('8ff27a5a', 'a600e1e7', 'd2dd846b', 'Whole Bean', 6, 'Open', '83db33c6', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9c5397bf', '5ecbaeab', 'CSO5WBWS', 'Whole Bean', 20, 'Open', '5884c865', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('739d466a', 'e3eeb372', 'HS5WBWS', 'Whole Bean', 2, 'Open', 'b13aa642', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('2660800a', 'e3eeb372', '64caec66', 'Whole Bean', 5, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('421650be', '3e1c282e', 'V5WBWS', 'Drip Ground', 4, 'Open', 'b53b3b8c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('9baa7834', 'dcf48fa4', 'V5WBWS', 'Whole Bean', 6, 'Open', '71707182', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('dfa9c99e', 'dcf48fa4', 'V12WBWS', 'Whole Bean', 4, 'Open', 'bafcff31', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('320ec3cc', '08be72f8', 'H5WBWS', 'Whole Bean', 5, 'Open', '26cae1d5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d309b1f8', '08be72f8', 'HS5WBWS', 'Whole Bean', 1, 'Open', 'feba92e7', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e9f51eb7', '08be72f8', 'R5WBWS', 'Whole Bean', 2, 'Open', 'a79a20bd', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c1ef2385', '08be72f8', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('59c1f8ee', 'a6628187', 'CSO5WBWS', 'Whole Bean', 48, 'Open', '3bedae7b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('c077a432', 'a6628187', '37308503', 'Whole Bean', 8, 'Open', 'b3f6c9f1', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('6fb2bfd6', '34227b00', 'CSO5WBWS', 'Whole Bean', 4, 'Open', '395c0918', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('729a756c', '34227b00', '37308503', 'Whole Bean', 1, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('48c6189b', '99723c97', '2036346d', 'Whole Bean', 3, 'Open', 'fe10f462', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('fb03006c', '99723c97', 'CSO5WBWS', 'Whole Bean', 2, 'Open', '3b6a252c', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('0d997592', '99723c97', 'VD12WBWS', 'Whole Bean', 2, 'Open', '2b2886d1', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('eba2d23d', 'de27e085', 'efa274e1', 'Whole Bean', 6, 'Open', '8b7015a1', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('581e3cfb', '1d2d253b', '8ddefb00', 'Whole Bean', 28, 'Open', '450205a5', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('5ccafa87', '1d2d253b', 'c759e1ba', 'Whole Bean', 4, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('acd3a5bd', '439c473c', 'bbbe3e73', 'Whole Bean', 10, 'Open', 'e3e0a69b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('54fd46ac', '9e3fa3ed', 'V12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('50b66b47', '69a0b024', 'H12WBWS', 'Whole Bean', 6, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('750dfe24', 'f754a701', 'c435528a', 'Whole Bean', 20, 'Open', 'b147ba9b', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('aa3f4932', 'f754a701', '1c98a15f', 'Whole Bean', 20, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('35234929', 'd5ecf10e', '7641ec65', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('e63b9106', 'd5ecf10e', 'a5e741ee', 'Whole Bean', 8, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('87af048e', 'd5ecf10e', '3d12aa60', 'Whole Bean', 12, 'Open', NULL, NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;
INSERT INTO public.order_details (order_detail_id, order_id, product_id, coffee_prep, quantity, item_status, previous_order_details, next_order_details, company_id, created_at, created_by, updated_at, updated_by, facility_id)
VALUES ('d25d3a86', '011367f6', 'CSO5WBWS', 'Drip Ground', 10, 'Open', 'ccb85204', NULL, 'R7CbqHmA1j', now(), 'R7CbqHmA1j', now(), NULL, 'cc844abb-db0b-48db-9aeb-abd8df9117de')
ON CONFLICT (order_detail_id) DO NOTHING;

COMMIT;
