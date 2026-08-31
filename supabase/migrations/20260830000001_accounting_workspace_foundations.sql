-- Foundations for the accounting workspace: the phone-payment permission and
-- the manipulable margin report.
--
-- 1. payment.charge_card — keying a customer's card into the hosted tokenizer
--    is a materially different act from recording a check that already
--    arrived, so it gets its own key (dev-portal controllable) rather than
--    riding on payment.record. Grants mirror payment.record: the accounting
--    operators and admins, on the card-capable plans.
--
-- 2. gross_margin_report(from, to, interval, group, exclude_imported) — the
--    QuickBooks-style report the owner asked for instead of a P&L: revenue,
--    COGS and gross margin over any date range, bucketed by
--    day/week/month/quarter/year, grouped by nothing / product type /
--    customer / channel. Excludes cancelled orders and void/written-off
--    invoices (a margin report that counts voided documents is fiction), and
--    by default excludes imported QB history, whose lines carry no COGS and
--    would dilute every margin. Tenancy via auth_company_ids() — the caller
--    sees their company, or nothing.

begin;

-- ── 1. The permission ────────────────────────────────────────────────────────
insert into public.permissions (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'payment.charge_card',
  'Payments',
  'Take card payments by phone',
  'Charge a customer''s card against an open invoice using the hosted card terminal. Card data goes straight to the payment processor and is never stored by STRATA.',
  'You don''t have permission to take card payments. Contact your administrator if you need access.',
  true,
  83
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select sp.plan_id, 'payment.charge_card',
       sp.plan_id in ('enterprise', 'enterprise_plus'),
       'phone terminal launch — mirrors payment.record'
from public.subscription_plans sp
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

insert into public.role_permissions (role_id, permission_id, granted)
values ('accounting_admin', 'payment.charge_card', true),
       ('company_admin',    'payment.charge_card', true),
       ('facility_admin',   'payment.charge_card', true),
       ('manager',          'payment.charge_card', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ── 2. The report ────────────────────────────────────────────────────────────
create or replace function public.gross_margin_report(
  p_from             date,
  p_to               date,
  p_interval         text    default 'month',
  p_group            text    default 'total',
  p_exclude_imported boolean default true
)
returns table (period date, group_label text, revenue numeric, cogs numeric, orders bigint)
language sql
stable
as $function$
  select date_trunc(
           case when p_interval in ('day','week','month','quarter','year')
                then p_interval else 'month' end,
           o.order_date::timestamp)::date as period,
         case p_group
           when 'product_type' then coalesce(pt.product_type, 'Untyped')
           when 'customer'     then coalesce(c.name_company, 'Unknown')
           when 'channel'      then coalesce(ch.channel, 'No channel')
           else 'Total'
         end as group_label,
         coalesce(sum(od.total_price), 0)       as revenue,
         coalesce(sum(od.unit_cost_at_sale), 0) as cogs,
         count(distinct o.order_id)             as orders
  from public.order_details od
  join public.orders o on o.order_id = od.order_id
  left join public.products p       on p.product_id = od.product_id
  left join public.product_type pt  on pt.product_type_id = p.product_type
  left join public.channel ch       on ch.channel_id = p.channel
  left join public.customers c      on c.customer_id = o.customer_id
  where o.company_id in (select public.auth_company_ids())
    and o.order_status <> 'Canceled'
    and coalesce(o.invoice_state, '') not in ('void', 'written_off')
    and o.order_date >= p_from
    and o.order_date <= p_to
    and (not p_exclude_imported or not coalesce(o.is_legacy_import, false))
  group by 1, 2
  order by 1, 2;
$function$;

commit;

notify pgrst, 'reload schema';
