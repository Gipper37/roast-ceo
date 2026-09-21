-- Add the payments.credentials_manage permission key with its role_permissions and plan_permissions rows.
--
-- ORDER: 2 of 3. HARD BLOCKER: must land before the frontend deploys. An unknown key is undefined in the grant snapshot, which denies every role in silence, and the only audience /app/company/payments/onboarding allows is company_admin, so the roastery owner would open the page and be told they cannot use it with no way forward. Checked against prod: sort_order 16 is free between merchant_onboard (15) and payments.charge (20), and default_deny_message is NOT NULL on this table, which one of the two proposed versions omitted and would have failed on.

begin;

-- Connecting a roaster's own Activity Pay account is not the same power as
-- filling in the verification form, so it is not payments.merchant_onboard.
-- The day a facility admin is allowed to finish onboarding, that grant must
-- not also hand over the credential that moves money.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'payments.credentials_manage',
  'Payments',
  'Connect the payment gateway',
  'Enter, replace or re-check this roastery''s own Activity Pay keys. The private key is encrypted and can never be read back, only replaced. Separate from payments.merchant_onboard on purpose: being verified by Activity Pay and holding the key that moves money are different powers.',
  'Only a company admin can connect the payment gateway.',
  false,
  16
)
on conflict (permission_id) do update set
  category             = excluded.category,
  label                = excluded.label,
  description          = excluded.description,
  default_deny_message = excluded.default_deny_message,
  is_plan_gated        = excluded.is_plan_gated,
  sort_order           = excluded.sort_order,
  updated_at           = now();

-- company_admin only. No row for any other role: absence is denial.
insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin', 'payments.credentials_manage', true)
on conflict (role_id, permission_id) do update set
  granted    = excluded.granted,
  updated_at = now();

-- Every plan. Connecting your own processor account is not something to sell
-- back to a roaster: the plan gates whether they can TAKE cards
-- (subscription_plans.can_accept_payments, payment.charge_card), not whether
-- they may own their own gateway identity. Mirrors payments.merchant_onboard,
-- which is is_plan_gated=false and granted on all four plans.
insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, 'payments.credentials_manage', true
from public.subscription_plans p
on conflict (plan_id, permission_id) do update set
  granted    = excluded.granted,
  updated_at = now();

commit;
