-- What the payment provider reported and STRATA would not act on is kept, so the order can say
-- so and staff are told once.
--
-- THE HOLE. A refund, void, return, dispute or decline can name a charge only by a gateway number
-- somebody typed. The webhook changes nothing on it, which is right: the number may be another
-- customer's, and acting on it reopened a paid invoice. But the only trace was the reason on the
-- delivery, on a developer page no roaster can open. The money may really have gone back and
-- nobody at the roastery could know.
--
-- WHY THIS IS A TABLE AND NOT A COLUMN ON payment_webhook_events, which is the first place to
-- look because it already holds the delivery:
--
--   * That table has RLS on and no policy, on purpose: a payload is full of cardholder detail. An
--     order page could only read it through a new definer function.
--   * It has no order on it. A refund event's own id is the refund's, so the link from a delivery
--     to a charge is in the payload, or in prose on processing_error. Reading money off prose is
--     how a reworded sentence loses a notice, and a retry overwrites that column anyway.
--   * It is one row per delivery. Activity Pay sends more than one event about one refund, as
--     transaction_create and transaction_update, and those are different rows. One refund has to
--     send one email.
--
-- THE UNIQUE CONSTRAINT IS THE WHOLE DEDUPE. The webhook inserts with ON CONFLICT DO NOTHING and
-- sends the email only if a row came back. Two deliveries at once get exactly one row back between
-- them, and a redelivery a day later gets none. Nothing else decides who sends.
--
-- event_number is not null, with '' for an event that carried no id, because a null in a unique
-- key is distinct from every other null and would let each delivery through.
--
-- order_ids is an array because one charge can pay several invoices. It is what the charge was
-- behind when the report came in: the row's own order, any order it holds, and any invoice it was
-- applied to.
--
-- card_declined rows are here for the same claim and no order page reads them: a declined checkout
-- already has its own warning on the order, and this is only what makes its email go once.
--
-- approved_after_failed is the same again: the gateway approved or settled a charge we had as
-- failed or declined, so the customer may have paid twice. The email says so, and its row is what
-- makes one charge send one email, whichever way the gateway says it. event_number is the charge's
-- own number, not the event's, so that an approval and a settlement are one fact.
--
-- READ BY the two keys that can see the stuck card charge list on the same page, ar.view and
-- payment.record, the same pair unplaced_gateway_approvals asks for. No new key. Nobody but the
-- webhook writes here, so authenticated gets select and nothing else. A buyer holds neither key
-- and is told nothing new by this.
--
-- FRONTEND ORDER: this applies before the frontend. The webhook writes this table on every report
-- of a typed number and answers 500 if it cannot, and the order page reads it for anyone holding
-- either key.

begin;

create table public.payment_staff_alerts (
  alert_id               uuid primary key default gen_random_uuid(),
  company_id             text not null references public.companies(company_id) on delete cascade,
  payment_transaction_id uuid not null references public.payment_transactions(payment_transaction_id) on delete cascade,
  kind                   text not null,
  event_number           text not null default '',
  named_number           text,
  amount_cents           bigint,
  order_ids              text[] not null default '{}',
  created_at             timestamptz not null default now(),
  constraint payment_staff_alerts_kind_chk
    check (kind in ('card_declined', 'approved_after_failed', 'refund', 'void', 'return', 'dispute', 'decline')),
  constraint payment_staff_alerts_once
    unique (payment_transaction_id, kind, event_number)
);

comment on table public.payment_staff_alerts is
  'What the payment provider reported that staff were told about. A row is the claim that its email has been sent, and for a report on a typed gateway number it is also the notice on the order.';
comment on column public.payment_staff_alerts.event_number is
  'The payment provider''s own number for what it reported, or an empty string when the event carried none.';
comment on column public.payment_staff_alerts.named_number is
  'The gateway number on our charge when the report came in. It can change later if the gateway names the charge by our key, and the notice has to go on saying what was reported.';
comment on column public.payment_staff_alerts.order_ids is
  'The orders this charge was behind when the report came in: its own, any it holds, any invoice it was applied to.';

create index idx_payment_staff_alerts_company
  on public.payment_staff_alerts (company_id, created_at desc);

alter table public.payment_staff_alerts enable row level security;

revoke all on public.payment_staff_alerts from public, anon, authenticated;
grant select on public.payment_staff_alerts to authenticated;
grant select, insert on public.payment_staff_alerts to service_role;

create policy payment_staff_alerts_read on public.payment_staff_alerts
  for select to authenticated
  using (
    company_id in (select public.auth_company_ids())
    and (public.auth_has_permission('ar.view', company_id)
         or public.auth_has_permission('payment.record', company_id))
  );

commit;
