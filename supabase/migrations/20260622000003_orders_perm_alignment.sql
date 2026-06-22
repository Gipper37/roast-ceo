-- ============================================================================
-- Orders / delivery permission alignment (2026-06-22)
-- ----------------------------------------------------------------------------
-- orders/actions.ts was historically UNGATED (no requirePermission on any of its
-- ~15 mutations — a privilege hole within a tenant). We added server gates:
--   order status / line edits / updateOrder / sendOrderInvoice -> order.edit
--   createOrder / duplicateOrder / bulkDuplicateOrders          -> order.create
--   toggleLineItemPacked / bulkMarkItemsPacked                  -> order.pack
--   saveDeliveryProof                                           -> delivery.mark_delivered
--   createSalesArea (sales_area is used ONLY as the delivery zone today)
--                                                              -> delivery.manage_zones
--   fetchOrderSortData (read)                                   -> order.view
--
-- One role grant is added so the new gates don't strip an ability from a role
-- that legitimately uses it (the chosen keys already cover the other roles):
--   roastmaster -> delivery.mark_delivered
--     Per product owner: "if staff have it, of course roastmasters do."
--     Roastmasters mark deliveries; staff (drivers) already had this key.
--
-- DELIBERATELY NOT granting sales_person anything: the sales/delivery split +
-- sales_person capabilities are deferred to the future CRM build. createSalesArea
-- stays manager+ (delivery.manage_zones = company_admin / facility_admin / manager).
-- sales_person also keeps no order.* access (per product owner) — gates enforce
-- the existing dev-portal model, which is the source of truth.
--
-- Idempotent + FK-safe. (Validated against prod in a rollback txn before commit.)
-- ============================================================================

BEGIN;

INSERT INTO public.role_permissions (role_id, permission_id, granted, updated_by)
SELECT v.role_id, v.permission_id, true, 'migration:20260622000003'
FROM (VALUES
  ('roastmaster', 'delivery.mark_delivered')
) AS v(role_id, permission_id)
WHERE EXISTS (SELECT 1 FROM public.user_roles  ur WHERE ur.role_id      = v.role_id)
  AND EXISTS (SELECT 1 FROM public.permissions p  WHERE p.permission_id = v.permission_id)
ON CONFLICT (role_id, permission_id) DO UPDATE
  SET granted = true,
      updated_by = EXCLUDED.updated_by,
      updated_at = now();

COMMIT;
