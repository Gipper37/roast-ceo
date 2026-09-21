-- company_kyc learns the handoff, the promise and the send-once stamp, and stops being writable by the tenant. Folds the email cluster's column into the journey cluster's migration; they are additive either way and shipping one migration is one fewer thing to get out of order.
--
-- ORDER: 2 of 4. The frontend deploy. Reads are isolated per surface so a missing column costs a date rather than a page, but beginGatewaySetup and applyKycDecision both degrade with a loud log until this lands, and the ready email cannot send at all. Must come AFTER the saveKycApplication service-role change in this working tree, which is why they ship as one release.

begin;

-- Six columns the whole journey reads and no database has. Verified against
-- prod: company_kyc has 29 columns and not one of these is among them.
--
-- handoff_at and the existing submitted_at split 'submitted' into the two
-- states the journey needs. Activity Pay publish seven webhook events and
-- every one is about a transaction, a settlement or the account updater;
-- there is no onboarding event, so "at the form" and "waiting on a decision"
-- cannot be told apart any other way.
alter table public.company_kyc
  add column if not exists handoff_at                     timestamptz,
  add column if not exists auto_enable_on_ready           boolean not null default false,
  add column if not exists connection_owner               text,
  add column if not exists connection_claimed_at          timestamptz,
  add column if not exists connection_due_at              timestamptz,
  add column if not exists connection_ready_email_sent_at timestamptz;

comment on column public.company_kyc.handoff_at is
  'When STRATA sent this roaster to Activity Pay''s hosted verification form. Nothing in the app set any status when they clicked through, so a roaster who started and stalled was indistinguishable from one who never began, and no operator could see either.';
comment on column public.company_kyc.submitted_at is
  'When the roaster told us they had finished Activity Pay''s hosted form. There is no KYC webhook, so this is the only signal that the form was completed and the only thing separating "at the form" from "waiting on a decision".';
comment on column public.company_kyc.auto_enable_on_ready is
  'The roaster asked, at handoff, for card checkout to be switched on the moment the gateway is connected. Default false: publishing a public card form is a decision a business makes. Honoured only through lib/payments/autoEnableOnConnect.ts, which runs the same plan, subscription, underwriting and gateway gates the switch itself runs.';
comment on column public.company_kyc.connection_owner is
  'The STRATA operator who has taken on minting this roaster''s Activity Pay keys. Stops two operators creating two pairs on one merchant account, which leaves one pair silently dead. The queue sorts on it and never filters on it: a claim may delay someone, it may never hide them.';
comment on column public.company_kyc.connection_claimed_at is
  'When that claim was taken. A claim older than 24 hours with nothing stored is shown as stale and treated as no claim at all.';
comment on column public.company_kyc.connection_due_at is
  'When we told the roaster their card payments would be ready, stamped at approval by applyKycDecision. Stored rather than computed so the roaster''s page, the shop card and the operator queue cannot show three different dates, and so a promise made on Friday does not move when the policy changes. Written once: a re-approval must not push a date somebody is already late for into the future.';
comment on column public.company_kyc.connection_ready_email_sent_at is
  'When STRATA emailed this roaster''s company_admins to say their Activity Pay account is connected. Claimed with a conditional UPDATE before the mail is handed to Resend, so two operators acting at once cannot both send; cleared again only when the send itself failed, which is the one case where nobody was actually told and a retry is correct.';

-- LIVE HOLE ON PROD, verified this session by reading the catalog:
-- role_table_grants gives `authenticated` table-level INSERT, UPDATE and
-- DELETE on company_kyc, and pg_policy shows exactly one policy,
-- tenant_company_access, with polcmd '*' -- FOR ALL, same USING and WITH
-- CHECK. So any signed-in team member can PATCH their own company's
-- company_kyc.status straight to 'approved' through PostgREST, which is the
-- last gate in merchantChargeRefusal, without ever loading a form.
--
-- Every writer now uses the service role behind a permission check:
-- saveKycApplication (moved this session -- it was the one tenant-side
-- writer and this revoke would otherwise have broken the entire KYC
-- application form), setupActions.ts, applyKycDecision, the dev gateway
-- claim/release actions, notifyGatewayConnected and the Activity Pay
-- webhook. Reads are unchanged.
revoke insert, update, delete on public.company_kyc from authenticated;

drop policy if exists tenant_company_access on public.company_kyc;
create policy tenant_company_read on public.company_kyc
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- No per-column grants. The builders proposed some; they are unnecessary
-- and misleading. `authenticated` holds a TABLE-level SELECT here, which
-- covers columns added later, and adding column grants beside a table grant
-- suggests a restriction that is not being applied.

commit;
