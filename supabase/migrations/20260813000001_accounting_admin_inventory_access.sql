-- Accounting Admin can see what arrived.
--
-- WHY. An accounting admin holds the whole A/R side — ar.view, ar.export,
-- invoice.send, invoice.void, payment.record — and order.view/create/edit/cancel.
-- What they could not do is open Inventory at all: the role held ZERO inventory
-- keys, not even inventory.view. So the person reconciling a supplier invoice
-- could not look at the shipment it bills for. That is the job, and it was
-- unreachable.
--
-- WHAT THEY GET. Three keys, the minimum for working orders and shipments:
--   inventory.view      — open the page (and Cost Center, which gates on the
--                         same key; COGS is accounting's business anyway)
--   inventory.receive   — mark a shipment arrived, record what landed
--   inventory.purchase  — the purchase lifecycle: send a request to a supplier,
--                         promote a draft to a real order, enter shipping cost
--
-- WHAT THEY DELIBERATELY DO NOT GET. inventory.edit, .count, .archive and .void
-- stay with the floor and management. Those are operational — correcting lot
-- lines, running a stock take, archiving an origin, voiding a receipt — and an
-- accountant reconciling paperwork has no business silently changing the count
-- the roasters just took. .void in particular is destructive.
--
-- SCOPE: role_permissions has no company_id and there is no per-tenant override
-- table, so this is GLOBAL by construction — every roastery on STRATA, now and
-- in future. That is the owner's explicit intent: this is what the Accounting
-- Admin role IS, not a setting for one tenant.
--
-- PLAN GATE UNCHANGED. All three keys are already is_plan_gated=true and granted
-- on pro/enterprise/enterprise_plus, denied on starter. A starter tenant's
-- accounting admin still cannot open Inventory, exactly as before — this only
-- moves the ROLE leg of the gate.
--
-- 🔴 THIS MIGRATION IS HALF THE FIX. app/app/(app)/inventory/page.tsx guarded the
-- route with a hardcoded ALLOWED_ROLES array while rendering
-- <PermissionDenied permission="inventory.view">, i.e. it claimed to enforce the
-- key and actually enforced a role list. Granting the key alone changes nothing
-- until that page asks currentUserCan('inventory.view'). The frontend change
-- ships with this.
--
-- Upsert rather than do-nothing: a granted=false row may exist in some
-- environment, and the intent here is to grant, not to defer to whatever is
-- already recorded.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('accounting_admin', 'inventory.view',     true),
  ('accounting_admin', 'inventory.receive',  true),
  ('accounting_admin', 'inventory.purchase', true)
on conflict (role_id, permission_id) do update
  set granted    = true,
      updated_at = now();

commit;
