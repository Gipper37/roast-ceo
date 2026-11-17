-- The buyer hears about packed, delivered and canceled only if the roaster
-- says so.
--
-- Owner, 2026-11-16: "packed, delivered, canceled should not send
-- notifications. that would need a toggle in settings by the roaster." Asked
-- which sender he meant: "should not send is just the orderstatusemail".
--
-- So this is one switch for one sender, off for everybody, and the roaster
-- turns it on.
--
-- WHAT EXISTS TODAY, AND WHY A PER-SEND TICK IS NOT THE SAME THING.
-- `lib/shop/orderStatusDispatch.ts` is the one door to that email and it sends
-- only on a literal `true` from the person moving the order. There are eleven
-- controls on screen that can send it, every one of them PRE-TICKED
-- (`useState(true)` in OrdersTable, PackingLabelButton, DeliveryCapture,
-- DeliveredOnField, both tools filters, and `initialNotify = true` in
-- ConfirmEmail). That is the Shopify model and it was the owner's own choice
-- for the control. It is not a tenant decision: a roaster who does not want
-- their buyers emailed at all has to untick a box on eleven screens, for ever,
-- and one packer forgetting sends the email. This column is where that
-- decision lives instead, once, for the tenant.
--
-- 🔴 WHY shop_config AND NOT company_parameters.
-- `company_parameters` is keyed (company_id, parameter_id, facility_id) and is
-- resolved by `lib/parameters/userParameters.ts`, which checks
-- `user_parameters` FIRST. A per-user override of a tenant-wide email decision
-- means one packer could silence every buyer notification for the whole
-- roastery, and a multi-facility roaster would need one row per facility while
-- the dispatcher holds only `orders.company_id`. `shop_config` is one row per
-- company, is already the home of the shop's email behaviour
-- (`reply_to_email`, `shop_name`), and is ALREADY READ by the dispatcher at
-- `orderStatusDispatch.ts:55` for slug, shop_name, accent_color, reply_to and
-- logo -- so the gate costs no extra round trip and adds no new failure mode.
--
-- 🔴 NO NEW PERMISSION KEY, AND THE REACH IS WHY.
-- It rides `shop.configure`, which is already granted on all four plans
-- (starter, pro, enterprise, enterprise_plus) and to company_admin,
-- facility_admin and manager, is already enforced by `patchShopConfig`
-- (app/app/(app)/shop/actions.ts:362) and by the shop_config RLS write
-- policies in both directions. Putting it under `billing.configure` instead
-- would have made it Enterprise-only, which is exactly the wrong tenants: the
-- roasters running a storefront are on starter and pro. The verify block below
-- asserts those grants still exist, because a key with no plan row is a silent
-- denial.
--
-- DEFAULT false, DELIBERATELY, and it is not a behaviour change in practice.
-- These three emails write no `email_log` row, stamp no column and are read by
-- no report, so there is no record of them on our side at all. The bound is
-- storefront orders: prod has 3 of 16,354 (two Maui Coffee Roasters orders
-- packed on 2026-10-29 and 2026-11-04, one Social Hour order canceled on
-- 2026-06-11), and no storefront order has ever reached Delivered. So at most
-- three orders' worth have ever been sent, across two tenants. Defaulting to
-- true would instead have carried the current behaviour into a setting nobody
-- chose, which is the opposite of what he asked for.
--
-- This migration is independent of 20261116000001 and of the recall change in
-- 20261116000003. It touches no function, no trigger and no other table.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

alter table public.shop_config
  add column if not exists order_status_emails_enabled boolean not null default false;

comment on column public.shop_config.order_status_emails_enabled is
  'Whether this roaster emails a buyer when their order is packed, delivered or canceled. OFF unless the roaster turns it on in Shop settings, Branding. The per-send tick on each control decides whether THIS move emails; this column decides whether the control is offered at all. Read by lib/shop/orderStatusDispatch.ts, which refuses the send when it is false, and by the four server pages that compute who could be emailed so no tick is offered. It gates only that one sender: invoices, receipts, payment confirmations, order confirmations, reorder reminders, recall notices, maintenance reminders and resale certificate requests are unaffected.';

do $$
declare
  v_default text;
  v_notnull boolean;
  v_type    text;
  v_comment text;
  v_plans   int;
  v_roles   int;
begin
  -- 1. The column is there, boolean, not null, and defaults to OFF. A default
  --    of true would have turned every tenant's buyer emails on without
  --    anybody choosing it, which is the whole point of the change.
  select c.column_default, c.is_nullable = 'NO', c.data_type
    into v_default, v_notnull, v_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name   = 'shop_config'
    and c.column_name  = 'order_status_emails_enabled';

  if v_type is null then
    raise exception 'shop_config.order_status_emails_enabled was not created, so the dispatcher gate has nothing to read and the whole select would fail with 42703';
  end if;
  if v_type <> 'boolean' then
    raise exception 'shop_config.order_status_emails_enabled is % and not boolean', v_type;
  end if;
  if not v_notnull then
    raise exception 'shop_config.order_status_emails_enabled is nullable, so an existing row could read null and a null is neither on nor off';
  end if;
  if v_default is null or position('false' in v_default) = 0 then
    raise exception 'shop_config.order_status_emails_enabled does not default to false (default is %); every existing tenant would start emailing buyers with nobody having chosen it', coalesce(v_default, '<none>');
  end if;

  -- 2. Every existing tenant actually reads OFF. The default only covers rows
  --    written from now on; `add column ... not null default false` backfills,
  --    and this is the assertion that it did.
  if exists (select 1 from public.shop_config where order_status_emails_enabled is distinct from false) then
    raise exception 'a shop_config row already has order_status_emails_enabled set to something other than false';
  end if;

  -- 3. The comment is the only place the one-sender scope is written down next
  --    to the column itself.
  select col_description('public.shop_config'::regclass, c.ordinal_position::int)
    into v_comment
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name   = 'shop_config'
    and c.column_name  = 'order_status_emails_enabled';

  if v_comment is null or position('packed' in v_comment) = 0 then
    raise exception 'the column comment is missing or no longer says which email this gates';
  end if;

  -- 4. The permission it rides still reaches every plan and the three roles
  --    that can configure a shop. A missing plan row is a silent denial, so a
  --    toggle nobody can reach would look exactly like a toggle that is off.
  select count(*) into v_plans
  from public.plan_permissions
  where permission_id = 'shop.configure' and granted;

  select count(*) into v_roles
  from public.role_permissions
  where permission_id = 'shop.configure' and granted;

  if v_plans < 4 then
    raise exception 'shop.configure is granted on only % plans; the roaster on a plan without it could never turn buyer status emails on', v_plans;
  end if;
  if v_roles < 1 then
    raise exception 'shop.configure is granted to no role, so nobody can reach the toggle';
  end if;
end $$;

commit;
