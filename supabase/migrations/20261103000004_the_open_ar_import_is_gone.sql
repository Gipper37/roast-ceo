-- The Open A/R import is gone, and so is the function behind it.
--
-- WHY THE FEATURE WENT. It carried a roaster's live receivables over from a
-- QuickBooks A/R aging report and reconciled them against the invoices STRATA
-- had already imported. It could not be made fool-proof, and the failure mode
-- was a roaster chasing real people for money they did not owe:
--
--   * The orders import is INSERT-ONLY. An invoice already here is skipped, so
--     nothing could ever correct a total, a line or a tax amount that had
--     changed in QuickBooks since.
--   * This function deliberately left an already-live invoice alone, because
--     re-touching one would double-count its adjustment payment. So an invoice
--     PAID since the last run kept its old balance, and a fully paid one was
--     never on the aging report to begin with.
--   * Its reconciliation could not fail. Every row that cleared the entry gate
--     landed in one of five buckets, all five of which were inside the
--     subtracted sum, so `unaccounted_open_cents` was identically zero and the
--     UI showed "Matches QuickBooks exactly" over a skipped balance.
--
-- STRATA works out what it is owed from the invoices it holds. History comes
-- from QuickBooks; the balance does not.
--
-- WHY IT IS DROPPED AND NOT JUST ORPHANED. `authenticated` holds EXECUTE on it
-- and it is not SECURITY DEFINER, so RLS bounds it to the caller's own company
-- but nothing else does. The `billing.configure` check lived in the server
-- action that has just been deleted, never in the function. Left in place it is
-- a REST-reachable way for any signed-in user to post an order live as an
-- invoice and insert payments against it.
--
-- WHAT THIS DOES NOT TOUCH. Nothing is reversed. The 201 legacy invoices this
-- function already promoted on production stay exactly as they are: live, open,
-- and payable through the ordinary A/R ledger (lib/ar/arActions.ts). Their
-- balances are settled by recording a payment, which is the only way they ever
-- could have been.

begin;

drop function if exists public.apply_open_ar(text, jsonb, boolean, boolean);

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_open_ar'
  ) then
    raise exception 'apply_open_ar still exists under another signature';
  end if;
end $$;

commit;
