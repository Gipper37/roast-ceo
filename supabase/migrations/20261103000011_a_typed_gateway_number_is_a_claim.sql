-- A gateway number a person typed is a claim, and a refund does not go out on a claim.
--
-- 🔴 A REFUND GOES TO WHOEVER'S CARD THAT NUMBER BELONGS TO. A card charge whose response
-- was lost has no gateway number, and Apply to invoice asks for one off the payment
-- provider's dashboard so that a refund can find the charge later. Copying the row above
-- it is an easy slip: a real transaction of this merchant, a virtual-terminal sale say,
-- that has no row in STRATA. Nothing can catch it. The duplicate check passes, because
-- nothing here carries that number, the gateway has no lookup we can call, and onApproved
-- only writes a number where there is none. A company admin then refunds from the invoice
-- and the money goes to somebody else's card, for good. So the row says the number was
-- typed, refunds refuse on it and send the operator to the dashboard, and it clears when
-- the gateway names this charge by our own idempotency key.
--
-- Not "the gateway mentioned that number". A later event for the wrong row's transaction
-- names the number too, often with the same amount, and that would clear the flag on the
-- day the mistake mattered.
--
-- unplaced_gateway_approvals is the other half: what the gateway told us it approved that
-- belongs to no row of ours. onApproved retries such a delivery for half an hour and then
-- acknowledges it, so it is never delivered again, and the row it would have resolved
-- reads pending for good. Two questions read it. Does a number being typed disagree with
-- what the gateway said about it, and is there an approval that may be this charge, before
-- somebody says it did not land. A virtual-terminal sale reads exactly the same, which is
-- why it can only ever be a warning.
--
-- 🔴 A FUNCTION, BECAUSE THE TABLE IS SHUT. payment_webhook_events has RLS on and no policy,
-- on purpose: a payload is full of cardholder detail. Only the four figures below leave, and
-- only for a member holding ar.view or payment.record, the two keys that can see the list.
-- A delivery signed by the shared deployment secret has company_id null and names nobody,
-- so it is never returned: a roaster still on that secret simply gets no warning.
--
-- FRONTEND ORDER: this applies before the frontend that names either of them. The webhook
-- and the refund path both select the column, and a select of a column that is not there
-- fails.

alter table public.payment_transactions
  add column if not exists provider_id_unconfirmed boolean not null default false;

comment on column public.payment_transactions.provider_id_unconfirmed is
  'provider_transaction_id was typed by a person and the gateway has not named this charge by our idempotency key since. Refunds refuse while true.';

create or replace function public.unplaced_gateway_approvals(p_company_id text, p_since timestamptz default null)
returns table (
  provider_transaction_id text,
  received_at timestamptz,
  amount_cents bigint,
  authorized_cents bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select distinct on (e.provider_transaction_id)
         e.provider_transaction_id,
         e.received_at,
         case when d.body->>'amount' ~ '^[0-9]+$' then (d.body->>'amount')::bigint end,
         case when coalesce(d.body->>'amount_authorized', d.body->>'amount_captured') ~ '^[0-9]+$'
              then coalesce(d.body->>'amount_authorized', d.body->>'amount_captured')::bigint end
    from public.payment_webhook_events e
   cross join lateral (select coalesce(e.payload->'data', e.payload) as body) d
   where e.company_id = p_company_id
     and p_company_id in (select public.auth_company_ids())
     and (select public.auth_has_permission('ar.view', p_company_id)
              or public.auth_has_permission('payment.record', p_company_id))
     and e.signature_valid
     and e.provider_transaction_id is not null
     and (p_since is null or e.received_at >= p_since)
     and lower(d.body->>'response') = 'approved'
     and lower(coalesce(d.body->>'type', 'sale')) <> 'refund'
     and not exists (
       select 1 from public.payment_transactions t
        where t.company_id = e.company_id
          and t.provider_transaction_id = e.provider_transaction_id
     )
   order by e.provider_transaction_id, e.received_at;
$function$;

revoke all on function public.unplaced_gateway_approvals(text, timestamptz) from public, anon;
grant execute on function public.unplaced_gateway_approvals(text, timestamptz) to authenticated, service_role;
