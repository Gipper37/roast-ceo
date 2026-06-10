-- Grant managers shop.configure so they can fully manage the wholesale shop.
-- Managers already had shop.view (tab access); without shop.configure they
-- could open the shop page but every save action (requirePermission
-- 'shop.configure') would fail. This makes manager shop access functional
-- end-to-end. Still editable per-role in the dev portal.
INSERT INTO public.role_permissions (role_id, permission_id, granted)
VALUES ('manager', 'shop.configure', true)
ON CONFLICT (role_id, permission_id) DO UPDATE SET granted = true, updated_at = now();
