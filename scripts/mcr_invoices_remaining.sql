-- ============================================================================
-- MCR: import the remaining 9 consumable invoices (image PDFs + parser gaps).
-- Data hand-extracted (4 were image-only PDFs with no text layer).
-- Shipments + suppliers already exist from the first import run; here we fix
-- the shipment metadata and add the consumable_inventory_purchased line items.
-- Advanced Labels - Sales Quote is intentionally skipped: it's the quote for
-- the same 8oz Dawn Patrol labels already imported via their actual invoice.
-- ============================================================================
BEGIN;
SET LOCAL app.skip_audit = 'true';

-- ── 1. New consumable item: Rimfire produce shipper box (no prior match) ────
INSERT INTO public.consumable_inventory
  (consumable_inventory_id, consumable_inventory_item, in_stock, consumable_type,
   company_id, facility_id, created_at, updated_at, created_by)
VALUES
  ('cons-mcr-vegie-shipper-box', 'Produce Shipper Box - Vegie V1.7 (20ct/bundle)', 0,
   'global_consumable_type_operational', '9ShiyDAXhV',
   '5cc581b9-2803-42c2-98de-0ba16ae42f8e', now(), now(), '9ShiyDAXhV')
ON CONFLICT (consumable_inventory_id) DO NOTHING;

-- ── 2. Fix shipment metadata (order_date + po_number) ───────────────────────
UPDATE public.shipment_received SET order_date='2026-05-28', po_number='32438'
  WHERE shipment_id='mcr-ship-dana-labels---oval-labels';
UPDATE public.shipment_received SET order_date='2026-03-09', po_number='29894'
  WHERE shipment_id='mcr-ship-santa-rosa---inv-29894';
UPDATE public.shipment_received SET order_date='2026-01-13', po_number='SO126396'
  WHERE shipment_id='mcr-ship-guittard---so126396';
UPDATE public.shipment_received SET order_date='2026-01-21', po_number='0258745-IN'
  WHERE shipment_id='mcr-ship-john-d-walsh-co--flavor';
UPDATE public.shipment_received SET po_number='9146998'
  WHERE shipment_id='mcr-ship-online-label---4x6';
UPDATE public.shipment_received SET order_date='2026-05-12', po_number='120-9202'
  WHERE shipment_id='mcr-ship-savor-brands---so-120-9202';
UPDATE public.shipment_received SET order_date='2025-08-06', po_number='162490'
  WHERE shipment_id='mcr-ship-two-leaves---a-bud---matcha';

-- Shipping costs where the invoice itemised freight
UPDATE public.shipment_received SET shipping_cost=14.13
  WHERE shipment_id='mcr-ship-dana-labels---oval-labels';
UPDATE public.shipment_received SET shipping_cost=147.98
  WHERE shipment_id='mcr-ship-online-label---4x6';

-- ── 3. Purchase line items ──────────────────────────────────────────────────
-- helper note: amount is bigint (units), cost_unit numeric (per-unit cost)

INSERT INTO public.consumable_inventory_purchased
  (consumable_purchase_id, shipment_id, consumable_inventory_item, amount, cost_unit,
   company_id, facility_id, created_at, updated_at, created_by)
VALUES
  -- Dana Labels — Oval, 1000/roll @ $93.14/M = $0.09314/label (10M Ground, 2M Whole Bean)
  ('mcr-consp-dana-ground',   'mcr-ship-dana-labels---oval-labels', 'cons_1a6445659d8f95d0', 10000, 0.09314, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),
  ('mcr-consp-dana-wholebean','mcr-ship-dana-labels---oval-labels', 'cons_329ce5daab57abed',  2000, 0.09314, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Santa Rosa — labels, 500/roll → per-label cost
  ('mcr-consp-sr-nicky',  'mcr-ship-santa-rosa---inv-29894', 'cons_2b92f978d1c27951',  500, 0.167, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),
  ('mcr-consp-sr-hula8',  'mcr-ship-santa-rosa---inv-29894', 'cons_575f4da4af9a323d',  500, 0.163, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),
  ('mcr-consp-sr-hula16', 'mcr-ship-santa-rosa---inv-29894', 'cons_5cb34cb3fe1307c0', 1500, 0.163, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),
  ('mcr-consp-sr-mama',   'mcr-ship-santa-rosa---inv-29894', 'cons_eea73a07a7b570e0',  500, 0.163, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Guittard — by case (Distribution)
  ('mcr-consp-guit-white', 'mcr-ship-guittard---so126396', 'cons_8e79a53420c0b0fd', 24, 216.5625, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),
  ('mcr-consp-guit-choc',  'mcr-ship-guittard---so126396', 'cons_a73a40ba58aaffbf', 12, 139.375,  '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- John D Walsh — Highland Grogg, 25 lbs @ $23.35/lb
  ('mcr-consp-walsh-grogg', 'mcr-ship-john-d-walsh-co--flavor', 'cons_dd19948cd00e3319', 25, 23.35, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Online Label 4x6 — thermal label rolls, per roll
  ('mcr-consp-online-4x6', 'mcr-ship-online-label---4x6', 'cons_dbc6cf6d6146f383', 16, 8.59188, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Savor Brands — 8oz QSBB Blue V2.2 = Maui Blend *Blue* Bags 8oz Hula, per bag
  ('mcr-consp-savor-blue', 'mcr-ship-savor-brands---so-120-9202', 'cons_b04b08246488e971', 10000, 0.539, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Two Leaves — Nice Matcha 500g, per unit (Distribution)
  ('mcr-consp-twoleaves-matcha', 'mcr-ship-two-leaves---a-bud---matcha', 'cons_d7e66f0707955110', 132, 27.00, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV'),

  -- Rimfire — produce shipper box, per case
  ('mcr-consp-rimfire-box', 'mcr-ship-rimfire-imports---produce-boxes', 'cons-mcr-vegie-shipper-box', 1, 95.00, '9ShiyDAXhV','5cc581b9-2803-42c2-98de-0ba16ae42f8e',now(),now(),'9ShiyDAXhV')
ON CONFLICT (consumable_purchase_id) DO NOTHING;

COMMIT;
