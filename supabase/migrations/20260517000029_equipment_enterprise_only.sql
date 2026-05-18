-- ============================================================
-- Equipment: tighten plan gating from Pro+ to Enterprise+
-- ============================================================
-- Equipment maintenance + parts catalog is positioned as an
-- Enterprise feature. Pro tier loses access; existing Pro tenants
-- with equipment data keep the rows in the DB but lose UI access
-- until they upgrade.
--
-- Permissions in the equipment.* family covered:
--   equipment.view, equipment.create, equipment.edit,
--   equipment.archive, equipment.log_maintenance, equipment.admin
--   equipment.view_cost, equipment.edit_cost, equipment.manage_pricing
--
-- Role grants are unchanged — gating is purely at the plan layer.
-- ============================================================

DELETE FROM public.plan_permissions
WHERE plan_id = 'pro'
  AND permission_id IN (
    'equipment.view',
    'equipment.create',
    'equipment.edit',
    'equipment.archive',
    'equipment.log_maintenance',
    'equipment.admin',
    'equipment.view_cost',
    'equipment.edit_cost',
    'equipment.manage_pricing'
  );
