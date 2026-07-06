-- Merchant-onboarding (KYC) beneficial-owner fixes. The onboarding form collects
-- each owner's email, phone, and control-person status, but
-- company_kyc_beneficial_owners had no columns for them — so the form's save
-- failed (schema drift between the onboarding action and the table). Add them.
-- (The action's other column names are corrected in the same release; they map to
-- the existing full_name / date_of_birth / role / address_* columns.)
ALTER TABLE public.company_kyc_beneficial_owners
  ADD COLUMN IF NOT EXISTS email             text,
  ADD COLUMN IF NOT EXISTS phone             text,
  ADD COLUMN IF NOT EXISTS is_control_person boolean NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
