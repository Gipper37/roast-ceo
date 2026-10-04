-- Payments is a module a roastery turns on.
--
-- The rule for this corner of the app is that every invoice, payment and A/R
-- feature is gated three ways: plan, permission, feature flag. Two of the
-- three already ship. Fourteen permission keys exist and are granted to
-- roles, and twelve of them are plan gated. The flag did not exist:
-- feature_catalog held exactly one row, 'haccp'.
--
-- This migration adds the catalog row, PARKED (is_active = false), and records
-- the choice for the tenants who are already taking money. It deliberately
-- does NOT attach the flag to the fourteen permissions, and the rest of this
-- comment is why, because "finish the attachment later" is only defensible if
-- the reason is written down where the next person will find it.
--
-- ── Why the row lands parked ───────────────────────────────────────────────
--
-- The first draft of this insert omitted is_active, which takes the table
-- default of true (20260907000014:44), and that one omission shipped a control
-- that lied. feature_catalog.is_active is what decides whether a module is
-- OFFERED: Configuration > General selects the catalog with
-- `.eq('is_active', true)` (app/app/(app)/configuration/page.tsx:282) and
-- hands every row it gets to ModulesCard as a live switch. An active row with
-- no permission attached to it therefore put a "Customer payments" switch in
-- front of every company_admin, and turning it off changed nothing at all:
-- staff kept seeing and using Charge card, the shop kept rendering Pay
-- buttons, saved methods kept charging, and the roaster who switched it off
-- believed payments were off. A switch that lies about what it does is worse
-- than no switch at all.
--
-- With is_active = false both readers skip the row (page.tsx:282 by the
-- filter, lib/permissions/server.ts:230 by `if (cat.is_active === false)
-- continue`), so the catalog row and the backfill below can land now with
-- nothing visible anywhere, and the follow-up that attaches the gateway-only
-- keys flips is_active to true in the same transaction as the attachment.
--
-- ── How the gate actually behaves ──────────────────────────────────────────
--
-- permissions.feature_key (20260907000014) tags a key as belonging to a
-- module. Two resolvers read that tag, and they do not read the same columns:
--
--   SERVER. auth_has_permission() ands in
--
--       exists (select 1 from public.company_feature cf
--                where cf.company_id = t.company_id
--                  and cf.feature_key = p.feature_key
--                  and cf.enabled)
--
--   inlined by 20260925000003, which is the migration that made the switch
--   switch anything off at all server side. It reads company_feature.enabled
--   and nothing else: not feature_catalog.is_active, not
--   feature_catalog.plans, and no subscription row. company_has_feature()
--   still exists from 20260907000014 and still answers all three of those
--   questions, but nothing calls it any more and 20260910000012 revoked
--   EXECUTE on it from authenticated.
--
--   CLIENT. enabledFeaturesFor() (lib/permissions/server.ts:203-235) reads
--   company_feature.enabled AND feature_catalog.is_active AND
--   feature_catalog.plans, with one exception: line 231 skips the plans
--   comparison when the tenant's plan is null. buildPermissionSnapshot applies
--   the result at line 445, `featureOk = !p.feature_key ||
--   enabledFeatures.has(p.feature_key)`.
--
-- Both agree on the part that decides this file: company_feature defaults to
-- false and a MISSING row reads as off. So the instant a key carries a
-- feature_key, every tenant without an enabled row loses that key, silently,
-- which is the failure mode the triple-gate rule exists to prevent rather
-- than to cause.
--
-- The asymmetry is the trap for whoever lands the attachment: is_active =
-- false denies on the client and allows on the server. While no key carries
-- feature_key = 'payments' that costs nothing, which is exactly what lets the
-- row park here. Attaching keys without flipping is_active in the same
-- transaction would leave the UI and the RPCs disagreeing about who can charge
-- a card, and that disagreement is the shape of every permission bug this app
-- has had.
--
-- ── Why the attachment is deferred ─────────────────────────────────────────
--
-- 1. Most of these keys do not need a gateway at all. invoice.send,
--    invoice.void, invoice.write_off and payment.record ("Record payments",
--    which is a roaster typing in a cheque or a bank transfer) work perfectly
--    for a roastery that has never seen a card. Gating them on a payments
--    module would switch off working A/R for anyone invoicing without a
--    gateway. On prod today that is a named, live tenant: 752af3ed-4 holds 8
--    invoice_documents, zero provider_credentials and zero payment_
--    transactions, so the "enable everyone who already takes payments"
--    backfill below does not reach it, and cannot be made to without turning
--    the module on for people who never asked for it.
--
-- 2. invoice.process is not a payments key at all. Its label is "Process
--    supplier invoices (AI extraction)": a bill arriving from a green coffee
--    supplier, read by the AP extractor. It is on the list by the word
--    "invoice" and nothing else. Attaching it would gate the inbound supplier
--    reader behind the customer card gateway.
--
-- 3. The two onboarding keys are the on-ramp to the switch itself.
--    payments.merchant_onboard and payments.credentials_manage are the only
--    two of the fourteen that are deliberately NOT plan gated, because
--    connecting a gateway is how a roastery begins, and they are granted on
--    all four plans. Gate them on a module that defaults to off and a new
--    merchant cannot onboard until somebody has already turned on the module
--    that onboarding is supposed to deliver. That is a deadlock, and it lands
--    squarely on the work in flight: adding merchants and taking payments is
--    the thing being built right now.
--
-- NOT a reason, and written down because the first draft of this file listed
-- it as one and the next reader would have designed around it: a tenant with
-- no subscription is not blocked. The superseded company_has_feature()
-- required `s.plan_id = any (f.plans)` across a left join, so a plan-less
-- tenant answered null and no value of `plans` could rescue it. Neither
-- resolver asks that question today. The server module clause reads no
-- subscription row at all, and the client skips the plans comparison outright
-- when plan is null (lib/permissions/server.ts:231). shopify-test-company-001,
-- the tenant the first draft named, has zero subscriptions rows, so
-- company_subscription_status (a view over companies left join subscriptions)
-- hands it plan_id null, and it would keep both onboarding keys. The deferral
-- stands on reasons 1 to 3, which are about what the keys mean.
--
-- When the attachment does land it wants to be narrower than the list above:
-- the keys that genuinely require a live gateway (payment.charge_card,
-- payment.saved_methods, payments.charge, payments.refund, payment.refund,
-- payments.onboard, payments.terms_edit), never the invoice and record keys
-- from reason 1, never invoice.process, and never the on-ramp from reason 3.
-- Its precondition is that provisioning a merchant writes company_feature
-- enabled = true as part of the onboarding path, so that a tenant who has a
-- gateway always has the module. A parked flag costs nothing today. Taking
-- invoicing away from a roastery mid-week costs a great deal.
--
-- ── Why plans is all four ──────────────────────────────────────────────────
--
-- feature_catalog.plans is one array for a whole module, but the plan policy
-- here is already per key and differs per key:
--
--     payments.charge, payments.onboard, payments.refund,
--     payments.credentials_manage, payments.merchant_onboard   all four plans
--     payment.saved_methods                        pro, enterprise, ent_plus
--     payment.charge_card, payment.record, payment.refund,
--     invoice.send, invoice.void, invoice.write_off,
--     payments.terms_edit                          enterprise, ent_plus
--     invoice.process                              enterprise_plus
--
-- A single array cannot express that. And note which side would enforce it:
-- only the CLIENT resolver reads feature_catalog.plans
-- (lib/permissions/server.ts:231), the server module clause never does. So
-- anything narrower than every plan would not be a second plan gate
-- everywhere, it would be a second plan gate on ONE side, dropping a key in
-- the UI that plan_permissions grants and that auth_has_permission still
-- answers yes to, with no row anywhere saying why. So plans lists all four and
-- plan_permissions stays the only authority on the plan question.
--
-- The consequence, stated here rather than discovered later: all four plans
-- means that once is_active flips true, every tenant sees this switch with no
-- Lock beside it, starter included. That is right for payments, because the
-- two onboarding keys are granted on all four plans, so every plan really can
-- connect a gateway and take money.
--
-- The module row then contributes exactly one thing, which is the only thing a
-- module is for: the tenant's own answer to "do you want it".

begin;

insert into public.feature_catalog (feature_key, label, description, plans, sort_order, is_active)
values (
  'payments',
  'Customer payments',
  'Take card and bank payments from your wholesale customers, save a payment method on file for repeat orders, and let customers pay an invoice themselves. Turn this on once your payment gateway is connected.',
  array['starter', 'pro', 'enterprise', 'enterprise_plus'],
  20,
  -- Parked, deliberately. See the header: an active row with no permission
  -- carrying its flag is a switch in Configuration > General that controls
  -- nothing, and the first draft of this file shipped exactly that by letting
  -- is_active take its default of true. The migration that attaches the
  -- gateway-only keys flips this to true in the same transaction.
  false
)
on conflict (feature_key) do update
  set label = excluded.label,
      description = excluded.description,
      plans = excluded.plans,
      sort_order = excluded.sort_order;
-- is_active is deliberately absent from that conflict branch: re-running this
-- file after the attachment migration has published the switch must not
-- un-publish it.

-- Anyone already taking money has plainly answered "yes, I want this", so the
-- row is written for them now rather than waiting for them to find a switch
-- they never saw. This is also what makes the eventual attachment safe for
-- them: the enabled row is in place before any key depends on it. Set-based
-- rather than by id, because staging and prod hold different tenants and a
-- hardcoded list would be right in exactly one database.
insert into public.company_feature (company_id, feature_key, enabled, updated_by)
select c.company_id, 'payments', true, 'migration 20261003000012'
  from public.companies c
 where exists (select 1 from public.provider_credentials pc
                where pc.company_id = c.company_id)
    or exists (select 1 from public.payment_transactions pt
                where pt.company_id = c.company_id)
-- DO NOTHING, not `do update set enabled = true`, which is what the first
-- draft wrote. On a first apply that branch is unreachable: the catalog row is
-- created in this same transaction and company_feature.feature_key references
-- it, so no 'payments' row can pre-exist. It is reachable on every re-run, a
-- staging reset or a by-hand replay, and there it would have flipped the
-- module back on for a roaster who had deliberately switched it off, bumped
-- updated_at, and written a config_audit_log row crediting 'migration
-- 20261003000012' with reversing their decision. The toggle is theirs; the
-- file that says so must not then overwrite it.
on conflict (company_id, feature_key) do nothing;

do $verify$
declare
  v_bad       int;
  v_attached  int;
  v_plans     text[];
  v_allplans  text[];
begin
  -- The row exists.
  if not exists (select 1 from public.feature_catalog where feature_key = 'payments') then
    raise exception 'the payments module is not in the catalog';
  end if;

  -- The deferral is real: no payment key carries the flag yet, so this
  -- migration cannot have taken a working permission away from anybody. The
  -- follow-up that attaches them is the place to prove the other direction.
  select count(*) into v_attached
    from public.permissions
   where feature_key = 'payments';
  if v_attached > 0 then
    raise exception '% permission(s) were attached to the payments module; see this file''s header for why that is deferred', v_attached;
  end if;

  -- And because nothing carries the flag, the row must not be OFFERED yet.
  -- is_active true with zero permissions attached is a live switch that
  -- controls nothing, which is the defect this file was corrected for.
  if exists (select 1 from public.feature_catalog
              where feature_key = 'payments' and is_active) then
    raise exception 'the payments module is active in Configuration > General while no permission carries its flag, so the switch would control nothing';
  end if;

  -- Its plans cover every plan a tenant can actually be resolved on, so the
  -- module cannot deny on the client a key that plan_permissions grants.
  -- subscription_plans is filtered to active rows, because a retired or draft
  -- plan nobody is on cannot produce that denial and must not abort the apply;
  -- a plan_id still named by a company_subscription_status row is included
  -- even if the plan has been retired, because that tenant is on it today.
  select plans into v_plans from public.feature_catalog where feature_key = 'payments';
  select array_agg(distinct p order by p) into v_allplans
    from (
      select plan_id as p from public.subscription_plans where active
      union
      select plan_id from public.company_subscription_status where plan_id is not null
    ) s;
  if exists (select 1 from unnest(v_allplans) p where p <> all (v_plans)) then
    raise exception 'the payments module excludes plan(s) %, which the client resolver would read as a second plan gate on top of plan_permissions',
      (select string_agg(p, ', ') from unnest(v_allplans) p where p <> all (v_plans));
  end if;
  -- That is a snapshot, checked once. A DO block runs at apply time and cannot
  -- fire again, so nothing re-checks the relationship afterwards: a fifth plan
  -- sold next quarter is silently absent from the array, and
  -- lib/permissions/server.ts:231 will drop payments for every tenant on it.
  -- Adding a plan means adding it to every feature_catalog.plans array in the
  -- same migration. The first draft of this comment claimed the block "fails
  -- loudly" for a plan added later, which is not something a migration can do.

  -- Everyone who already transacts has a row. The check is for a MISSING row
  -- rather than for enabled = true, because the DO NOTHING above leaves an
  -- existing row alone: on a re-run, a roaster who had switched the module off
  -- would otherwise abort the apply over a decision this file promises to
  -- respect.
  select count(*) into v_bad
    from public.companies c
   where (exists (select 1 from public.provider_credentials pc where pc.company_id = c.company_id)
          or exists (select 1 from public.payment_transactions pt where pt.company_id = c.company_id))
     and not exists (select 1 from public.company_feature cf
                      where cf.company_id = c.company_id
                        and cf.feature_key = 'payments');
  if v_bad > 0 then
    raise exception '% company(ies) take payments today but have no payments module row', v_bad;
  end if;

  raise notice 'the payments module is in the catalog, parked (is_active false, nothing attached), and recorded as wanted by % tenant(s)',
    (select count(*) from public.company_feature where feature_key = 'payments' and enabled);
end
$verify$;

commit;
