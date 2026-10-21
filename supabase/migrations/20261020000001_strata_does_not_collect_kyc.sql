-- STRATA does not collect KYC, so stop holding the schema for it.
--
-- Activity Pay is the payment facilitator and they underwrite every roaster on
-- a hosted pre-application of their own
-- (https://www.activitypaypartner.co/?apply=…, now wired up as
-- ACTIVITYPAY_KYC_URL). Read that form 2026-10-20: it collects the legal name,
-- the EIN, the business and location addresses, every owner at 20% or more with
-- their date of birth and home address, AND the bank name, routing number and
-- account type. None of it passes through STRATA. The roaster types it on
-- Activity Pay's domain.
--
-- So the three surfaces below are not "not built yet". They are a different
-- company's job, and holding empty tables shaped like a dossier is an invitation
-- for someone to wire a form to them later.
--
--   company_kyc.ein_encrypted        a federal tax id, sealed with
--                                    KYC_ENCRYPTION_KEY
--   company_kyc_beneficial_owners    name, DOB, home address, ownership %
--   company_kyc_documents            uploaded identity documents
--
-- ── WHY NOT KEEP THEM TO HEDGE A FUTURE PAYFAC MOVE ──────────────────────────
--
-- Because a stored dossier is not usable when you would want it. KYC is a
-- point-in-time attestation with a signature attached: ownership splits, home
-- addresses, bank accounts and volume estimates all move, and any new facilitator
-- or gateway requires current data and a fresh signature whatever we hold. The
-- hedge does not save the step it exists for, and the cost is paid immediately by
-- every roaster, because nothing flows through us now -- to store it we would
-- have to stand up a second KYC form and make them fill in two.
--
-- What IS worth keeping is the record of the DECISION, and it stays, untouched:
-- who applied and when (handoff_at), the outcome and when (reviewed_at,
-- rejection_reason), the merchant id (provider_submerchant_id), the business
-- identity signup already gives us (legal_name, dba, business_type, the address
-- columns, ein_last4 for matching) and the economics we quoted
-- (expected_monthly_volume_cents, rolling_reserve_*). That is what a migration to
-- another processor actually needs: who to re-onboard, and enough to pre-fill the
-- dull half of somebody else's form.
--
-- ── PROVED DEAD BEFORE DROPPING ─────────────────────────────────────────────
--
-- On prod 2026-10-20: company_kyc_beneficial_owners 0 rows,
-- company_kyc_documents 0 rows, company_kyc rows with a non-empty ein_encrypted
-- 0. In the frontend: zero references to any of the three outside generated
-- database types, and the form that fed them (KycOnboardingForm) is already gone,
-- replaced by SetupJourney, which only hands off to Activity Pay's link. No view
-- depends on them and no foreign key points at them; their own RLS policies drop
-- with the tables.
--
-- The guard below is NOT a tautology: it refuses if any of the three holds data
-- by the time this applies, because that would mean somebody started collecting
-- after it was written and dropping it would destroy their rows. It cannot fire
-- on anything that exists today.
--
-- Leaves lib/payments/kyc-encryption.ts and the 'kyc' purpose in
-- lib/crypto/envelope.ts in place: both already have zero callers
-- (envelope.ts:165 says so of decryptKycField), and retiring them plus the
-- KYC_ENCRYPTION_KEY row on the gateway readiness page is a frontend-only change
-- that does not belong in the same batch as a schema drop.

begin;

do $$
declare
  owner_rows int;
  doc_rows   int;
  ein_rows   int;
begin
  select count(*) into owner_rows from public.company_kyc_beneficial_owners;
  select count(*) into doc_rows   from public.company_kyc_documents;
  select count(*) into ein_rows
    from public.company_kyc
   where ein_encrypted is not null and ein_encrypted <> '';

  if owner_rows > 0 or doc_rows > 0 or ein_rows > 0 then
    raise exception
      'Refusing to drop KYC storage that holds data: % beneficial owner row(s), % document row(s), % stored EIN(s). '
      'Something started collecting KYC after this migration was written. Decide what to do with those rows '
      '(they are personal data, so deleting them is likely correct) and then re-run this with the guard removed.',
      owner_rows, doc_rows, ein_rows;
  end if;
end $$;

drop table if exists public.company_kyc_documents;
drop table if exists public.company_kyc_beneficial_owners;

alter table public.company_kyc drop column if exists ein_encrypted;

commit;
