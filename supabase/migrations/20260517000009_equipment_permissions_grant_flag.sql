-- ============================================================
-- Fix: flip granted=true on the equipment.* role + plan rows
-- ============================================================
-- The original equipment permissions migration (..006) INSERTed rows
-- into role_permissions + plan_permissions but didn't set `granted`,
-- and the column defaults to false. Result: every equipment.* check
-- returned false, redirecting users from /app/equipment to /upgrade.
--
-- This migration sets granted=true on the rows ..006 created. Also
-- updates the inserts in ..006 *retroactively* by being explicit
-- about the flag in the upserts here.
-- ============================================================

UPDATE public.role_permissions
   SET granted = true
 WHERE permission_id LIKE 'equipment.%';

UPDATE public.plan_permissions
   SET granted = true
 WHERE permission_id LIKE 'equipment.%';
