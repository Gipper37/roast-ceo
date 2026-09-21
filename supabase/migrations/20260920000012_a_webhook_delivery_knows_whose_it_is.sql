-- Add company_id to payment_webhook_events, so a delivery can be attributed to the roaster whose signing secret verified it, or whose endpoint it arrived on.
--
-- ORDER: 3 of 3. HARD BLOCKER: must land before the frontend deploys. The receiver writes company_id on every insert. Without the column PostgREST rejects with PGRST204, isUniqueViolation is false, and every delivery is answered 500 'log-failed'. Activity Pay retries for 24 hours and then auto-disables the webhook, so an approved charge is never settled and a void never clears its invoice. Confirmed absent on prod today.

begin;

-- The webhook log can say whose delivery it was now that it knows. Every
-- roaster has their own Activity Pay merchant account, so a delivery arrives
-- on that roaster's own endpoint and the secret that verified it names them.
--
-- Nullable on purpose: a delivery verified by the deployment's own
-- ACTIVITYPAY_WEBHOOK_SECRET names nobody, and a bad-signature row on the
-- shared endpoint has no tenant to attribute to. The receiver writes the
-- endpoint's tenant even when verification fails, because a failed delivery
-- on a roaster's own URL is still their problem to read about.
--
-- ON DELETE SET NULL, not RESTRICT: this is a log, and a deleted company must
-- not be held open by one. payment_transactions uses RESTRICT because it is
-- money.
alter table public.payment_webhook_events
  add column if not exists company_id text
    references public.companies(company_id) on delete set null;

comment on column public.payment_webhook_events.company_id is
  'The roaster whose Activity Pay signing secret verified this delivery, or whose endpoint it arrived on. Null for the shared endpoint verified by the deployment secret.';

-- The dev webhooks page lists deliveries newest first; per tenant is the read
-- that did not exist before.
create index if not exists idx_payment_webhook_events_company
  on public.payment_webhook_events (company_id, received_at desc)
  where company_id is not null;

commit;
