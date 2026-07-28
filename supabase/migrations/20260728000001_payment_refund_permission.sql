-- `payment.refund` — its own permission, because a refund SENDS MONEY OUT.
--
-- The refund button could have borrowed `payment.record`, but those are opposite
-- risks: recording a payment says money arrived (a bookkeeping claim, correctable),
-- while refunding tells the gateway to move real funds from the roaster's account to
-- a customer's card (irreversible via the app). Anyone who can do the first should
-- not automatically be able to do the second.
--
-- Gating mirrors the rest of the invoice-of-record family, per the owner's standing
-- rule that EVERY invoice/payment feature is gated three ways:
--   1. plan       — is_plan_gated=true + plan_permissions (Enterprise/Enterprise+ only)
--   2. permission — this row + role_permissions
--   3. feature    — every callsite ALSO requires billing_settings.invoice_of_record
--                   = 'strata' AND shop_config.payments_enabled (checked server-side)
--
-- Roles: company_admin + facility_admin only. Deliberately NOT `manager`, which DOES
-- hold payment.record — a manager can reconcile the books, but sending money back out
-- is an owner-level act. Grant it to manager later if the owner wants that.

insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'payment.refund',
  'Payments',
  'Refund payments',
  'Refund a card payment taken through STRATA back to the customer. Reverses the invoice to open. Enterprise plans, invoice-of-record mode only.',
  'You do not have permission to refund payments.',
  true,
  71                      -- directly after payment.record (70)
)
on conflict (permission_id) do nothing;

-- Plan gate: same tiers that get the rest of invoice-of-record.
insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, 'payment.refund', p.plan_id in ('enterprise', 'enterprise_plus')
from (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as p(plan_id)
on conflict (plan_id, permission_id) do nothing;

-- Role grant: admins only (see note above re: manager).
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'payment.refund', true),
  ('facility_admin', 'payment.refund', true)
on conflict (role_id, permission_id) do nothing;

notify pgrst, 'reload schema';
