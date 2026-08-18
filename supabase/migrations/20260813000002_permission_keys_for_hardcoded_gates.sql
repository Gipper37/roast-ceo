-- ============================================================================
-- Ships ALONE, BEFORE any frontend change that references these keys.
-- ============================================================================
--
-- Six keys so the dev portal can actually decide six things it currently cannot.
--
-- WHY THESE SIX AND NOT AN EXISTING KEY. The conversion sweep found ~100 sites
-- where a hardcoded role array stands where a permission key belongs. For the
-- overwhelming majority a key already exists and the fix is pure code. These six
-- are the residue: places where I checked every candidate in the catalog and none
-- fits without changing who gets in, or where the catalog's data model literally
-- cannot express the rule. Each is justified individually below, because a key
-- nobody can explain is a dev-portal checkbox nobody dares touch.
--
-- SCOPE. role_permissions has no company_id and there is no per-tenant override
-- table, so these grants are GLOBAL by construction — every roastery on STRATA,
-- now and in future. Same as every other row in this table. That is the intent.
--
-- INERT ON ITS OWN. Nothing in the frontend references these keys yet. This
-- migration changes no behaviour until the matching code ships. That ordering is
-- mandatory, not stylistic: buildPermissionSnapshot returns Record<string,true>
-- holding only GRANTED keys, so a key the DB does not have resolves to undefined
-- — denied for EVERY role including company_admin, with no error anywhere.
-- Frontend-before-migration silently blacks out whatever it gates.
--
-- IMPLICIT DENY. Only 33 of 450 existing role_permissions rows are granted=false;
-- absence of a row IS the deny, and the resolver reads it that way
-- (`if (r?.granted && planOk)`). So each key below gets grant rows only.
--
-- PLAN ROWS ON NON-GATED KEYS ARE COSMETIC. The resolver short-circuits with
-- `planOk = !p.is_plan_gated || planMap[id] === true`, so plan_permissions is
-- ignored entirely when is_plan_gated=false (accounting.view has zero plan rows
-- and works fine). They are seeded anyway, matching the majority of non-gated
-- keys, so the row is future-proof if someone ever flips is_plan_gated.

begin;

-- ─── 1. company.view ─────────────────────────────────────────────────────────
-- /app/company is an umbrella: team, facilities, products, recipes, inventory,
-- suppliers, roaster units. It hosts actions spanning team.*, company.*,
-- product.*, recipe.*, inventory.*, supplier.* and config.roaster_unit. Every
-- near-miss candidate fails: company.edit / company.facilities /
-- company.subscription are all company_admin-only, so reusing one would lock
-- facility_admin and manager out of a page they use daily. The team.* keys hold
-- exactly the right 3 roles today, but gating a workspace tab on "can invite a
-- teammate" is semantically wrong and breaks the moment someone edits team.invite
-- in the portal. Grants reproduce nav-items.ts:226 minRoles and company/page.tsx:24
-- COMPANY_PAGE_ROLES bit for bit — the conversion is a true no-op.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'company.view',
  'Company',
  'Open the Company workspace',
  'Reach the Company tab — team roster, facilities, and the product / recipe / inventory / supplier catalogs. What you can DO once inside is still gated per-action (team.*, product.*, recipe.*, inventory.*, supplier.*).',
  'You do not have access to the Company workspace.',
  false,
  5                       -- ahead of company.edit (10)
)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'company.view', true),
  ('facility_admin', 'company.view', true),
  ('manager',        'company.view', true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

-- ─── 2. config.view ──────────────────────────────────────────────────────────
-- The one tab a single EXISTING key cannot express. Configuration fronts five
-- independently-keyed surfaces whose grant sets do not nest:
--   config.parameters   CA,FA,MG
--   config.roaster_unit CA,FA,MG,RM
--   config.connections  CA,FA,MG,RM   (pro+)
--   config.import_data  CA,FA,MG,RM   (ent+)
--   billing.configure   AA,CA,FA      (ent+)
-- Gating the tab on config.parameters would strip it from roastmaster, who
-- demonstrably needs it — roastmaster holds config.roaster_unit AND
-- config.connections. And NavItem.permission is single-key by construction
-- (Sidebar.tsx:194 is a ternary against one grants[key] lookup), so an any-of list
-- is not expressible without rebuilding the nav machinery. An umbrella key is the
-- smaller change. It also gives /app/configuration its FIRST route-level gate —
-- the page has none today; nav-items.ts:233 hideForRoles is the whole enforcement
-- and a URL walks straight past it.
-- Grants = the exact complement of that hideForRoles list, so nobody gains or
-- loses the tab on conversion day.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'config.view',
  'Configuration',
  'Open the Configuration workspace',
  'Reach the Configuration tab. Each sub-tab is still gated on its own key — parameters, roaster units, connected devices, data import, billing settings.',
  'You do not have access to Configuration.',
  false,
  5                       -- ahead of config.parameters (10)
)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'config.view', true),
  ('facility_admin',    'config.view', true),
  ('manager',           'config.view', true),
  ('roastmaster',       'config.view', true),
  ('assistant_roaster', 'config.view', true),
  ('equipment_tech',    'config.view', true),
  ('sales_person',      'config.view', true),
  ('staff',             'config.view', true)
  -- accounting_admin + accounting_view deliberately absent = denied,
  -- matching nav-items.ts:233 hideForRoles exactly.
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

-- ─── 3. cost_center.view ─────────────────────────────────────────────────────
-- Cost Center is the last live instance of the bug that started this project: the
-- nav (nav-items.ts:189) shows the link to manager+ only, while the page
-- (cost-center/page.tsx:38) gates on inventory.view — held by accounting_admin,
-- assistant_roaster, roastmaster and staff as well. So four roles can open
-- /app/cost-center by URL today and see landed cost and margin, with no link in
-- their sidebar. Nav stricter than page.
--
-- Reusing inventory.view to match the page is the only zero-new-key option and it
-- WIDENS the sidebar by those four roles — almost certainly not wanted for a
-- costing page. So: a dedicated key granted to the three the nav shows today,
-- which preserves the visible contract and closes the URL hole in one move.
-- (The alternative — grant all seven — is a one-line change to this file if the
-- owner prefers preserving URL access. It is a judgement call, not a fact.)
--
-- PLAN-GATED to mirror inventory.view exactly (pro/ent/ent+). The page's own plan
-- branch at cost-center/page.tsx:51 must keep running FIRST so starter sees the
-- TierLocked upsell rather than a permission denial — a plan-gated key can only
-- ever hide, never upsell. Same for nav minPlan: keep it.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'cost_center.view',
  'Inventory',
  'View the Cost Center',
  'Open the Cost Center — landed cost, COGS, margin by product, and period book-closing. Editing is still gated on inventory.edit; closing a book on company.edit.',
  'You do not have permission to view the Cost Center.',
  true,
  15                      -- directly after inventory.view (10)
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, 'cost_center.view', p.plan_id in ('pro', 'enterprise', 'enterprise_plus')
from (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as p(plan_id)
on conflict (plan_id, permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'cost_center.view', true),
  ('facility_admin', 'cost_center.view', true),
  ('manager',        'cost_center.view', true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

-- ─── 4. payments.merchant_onboard ────────────────────────────────────────────
-- 🔴 DO NOT REUSE payments.onboard. Read its own catalog row: label ends
-- "(deprecated)" and the description says "DEPRECATED — no callsites …
-- payments.charge and payments.onboard were never wired. Do not grant." It is also
-- already granted to company_admin AND facility_admin on all four plans, so wiring
-- it would silently widen KYC submission to facility_admin as a side effect of a
-- mechanical conversion. That is a policy change smuggled in as a refactor.
--
-- This key reproduces the three live hardcoded sites exactly — onboarding/page.tsx:31,
-- onboarding/actions.ts:81 (which writes company_kyc plus encrypted EIN/SSN and moves
-- status to 'submitted'), and payments/bank/page.tsx:22 — all company_admin only.
-- Widening to facility_admin is a deliberate decision to make separately, in the
-- portal, which is the entire point of moving it here.
--
-- NOT plan-gated: there is no plan gate on these pages today. onboarding/page.tsx:58-64
-- reads subscription_plans.can_accept_payments only to render an informational
-- notice. Adding a plan leg here would be a NEW restriction, not a conversion.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'payments.merchant_onboard',
  'Payments',
  'Complete merchant onboarding (KYC)',
  'Submit and lock the merchant KYC application — legal entity, beneficial owners, tax IDs — and link the payout bank account. Replaces the never-wired payments.onboard.',
  'Only a company admin can complete merchant onboarding.',
  false,
  15
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, 'payments.merchant_onboard', true
from (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as p(plan_id)
on conflict (plan_id, permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin', 'payments.merchant_onboard', true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

-- ─── 5. customer.invoice_pay_link.disable ────────────────────────────────────
-- ─── 6. shop.pay_at_checkout.disable ─────────────────────────────────────────
-- These two exist because plan_permissions CANNOT express the rule as written.
--
-- customers/actions.ts:359  →  if (!enabled && identity.plan !== 'enterprise_plus')
-- shop/actions.ts:665       →  if (!args.payAtCheckout && identity.plan !== 'enterprise_plus')
--
-- Both gate ONE DIRECTION of a boolean toggle. Turning the Pay button ON, or
-- turning pay-at-checkout back ON, is always allowed — nobody needs permission to
-- send us more processing volume. Turning it OFF is the Enterprise+ privilege.
-- plan_permissions is a flat (plan, permission, granted) grant with no notion of
-- the VALUE being written, so the rule cannot ride on customer.edit or
-- shop.customer_invite. A direction-specific key is the only expressible form.
--
-- Worth minting rather than leaving alone: this is deliberate revenue policy
-- (processing volume is the revenue behind the lower subscription prices) and it
-- is currently duplicated as a bare 'enterprise_plus' string literal across four
-- files — the two server rules above plus their display halves at
-- customers/[id]/page.tsx:25 → CustomerDetail.tsx:984 → InvoicePayLinkRow.tsx:65,71
-- and shop/page.tsx:195 → ShopSetupClient.tsx:1521-1539. Policy that earns money
-- should be visible in the catalog, not buried in four inequality checks.
--
-- ROLE SETS MATCH THE BASE KEY ON PURPOSE. customers/actions.ts:351 already
-- requires customer.edit and shop/actions.ts:658 already requires
-- shop.customer_invite, so matching those role sets means each new key adds
-- EXACTLY the plan restriction and nothing else. A precise no-op.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  (
    'customer.invoice_pay_link.disable',
    'Customers',
    'Turn OFF a customer''s invoice Pay button',
    'Remove the online Pay button from a customer''s invoices so they pay you outside STRATA. Turning it back on is always allowed and needs no permission.',
    'Removing the Pay button from invoices is an Enterprise+ feature.',
    true,
    45                    -- after customer.archive (40)
  ),
  (
    'shop.pay_at_checkout.disable',
    'Wholesale',
    'Bill a shop customer later instead of at checkout',
    'Let a wholesale customer place shop orders on invoice terms instead of paying by card at checkout. Switching them back to pay-at-checkout is always allowed and needs no permission.',
    'Billing a shop customer later is an Enterprise+ feature — shop orders are paid at checkout on your plan.',
    true,
    27                    -- after shop.customer_invite (25)
  )
on conflict (permission_id) do nothing;

-- Enterprise+ ONLY for both. Explicit false rows on the lower tiers so the
-- intent is legible in the table rather than inferred from absence.
insert into public.plan_permissions (plan_id, permission_id, granted)
select p.plan_id, k.permission_id, p.plan_id = 'enterprise_plus'
from (values ('starter'), ('pro'), ('enterprise'), ('enterprise_plus')) as p(plan_id)
cross join (values ('customer.invoice_pay_link.disable'), ('shop.pay_at_checkout.disable')) as k(permission_id)
on conflict (plan_id, permission_id) do nothing;

-- Role leg mirrors customer.edit (7 roles) and shop.customer_invite (3 roles).
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('accounting_admin',  'customer.invoice_pay_link.disable', true),
  ('assistant_roaster', 'customer.invoice_pay_link.disable', true),
  ('company_admin',     'customer.invoice_pay_link.disable', true),
  ('facility_admin',    'customer.invoice_pay_link.disable', true),
  ('manager',           'customer.invoice_pay_link.disable', true),
  ('roastmaster',       'customer.invoice_pay_link.disable', true),
  ('sales_person',      'customer.invoice_pay_link.disable', true),
  ('company_admin',     'shop.pay_at_checkout.disable',      true),
  ('facility_admin',    'shop.pay_at_checkout.disable',      true),
  ('manager',           'shop.pay_at_checkout.disable',      true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

commit;

notify pgrst, 'reload schema';
