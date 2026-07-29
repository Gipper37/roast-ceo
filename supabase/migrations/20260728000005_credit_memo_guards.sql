-- Credit memos: make the table safe to expose to an operator (plan Phase 1.4).
--
-- credit_memos has existed since P4 with a working RPC and guard, but ZERO rows in
-- production — nothing has ever exercised it. Putting a button on it surfaces four
-- gaps that do not matter while the only caller is a test, and matter a great deal
-- the first time a bookkeeper fat-fingers an amount.
--
-- 🔴 THE ONE THAT MATTERS MOST: over-crediting is currently silent AND irreversible.
-- invoice_ar_balances clamps `GREATEST(total − payments − credits, 0)` and
-- recompute_invoice_ar_state flips an invoice to 'paid' as soon as credits ≥ total.
-- So a $10,000 credit memo against a $100 invoice posts cleanly, reads as a normal
-- paid invoice, and destroys $9,900 of receivable with no trace — and `voided_at` is
-- READ by the view and the recompute but WRITTEN by nothing anywhere in either repo,
-- so it cannot be undone from the app at all. The ceiling and the void path below are
-- prerequisites for the UI, not follow-ups to it.

begin;

-- ── 1. credit_date ─────────────────────────────────────────────────────────
-- When a credit was ISSUED is a different fact from when the row was INSERTed, and
-- period close (companies.books_closed_through) and as-of reporting both key on the
-- former. Retrofitting a date onto already-issued documents is impossible, so it goes
-- in before the first one exists. Zero rows today, so the DEFAULT backfills nothing.
alter table public.credit_memos
  add column if not exists credit_date date not null default current_date;

comment on column public.credit_memos.credit_date is
  'Date the credit was issued (an accounting fact). Distinct from created_at, which is when the row was written. Period close and as-of reporting key on this.';

-- ── 2. The guard ───────────────────────────────────────────────────────────
create or replace function public.guard_credit_memo_valid()
returns trigger
language plpgsql
as $$
DECLARE
  v_ord_cust text; v_posted boolean; v_state text; v_mode text;
  v_ord_total_cents bigint; v_other_credits bigint; v_payments bigint;
  v_closed date;
BEGIN
  -- ── UPDATE: the ONLY legal update is a void ──────────────────────────────
  -- A posted negative document is corrected by void-and-reissue, never edited: the
  -- number is gap-free and already on a customer's statement. Returning early also
  -- fixes a real deadlock in the old guard, which re-ran the full validity check on
  -- UPDATE — so voiding a credit memo whose invoice had since been voided would
  -- RAISE, making the bad memo permanently unremovable.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.voided_at IS NULL AND NEW.voided_at IS NOT NULL
       AND NEW.credit_memo_id     IS NOT DISTINCT FROM OLD.credit_memo_id
       AND NEW.company_id         IS NOT DISTINCT FROM OLD.company_id
       AND NEW.customer_id        IS NOT DISTINCT FROM OLD.customer_id
       AND NEW.credit_memo_number IS NOT DISTINCT FROM OLD.credit_memo_number
       AND NEW.amount_cents       IS NOT DISTINCT FROM OLD.amount_cents
       AND NEW.applied_to_order_id IS NOT DISTINCT FROM OLD.applied_to_order_id
       AND NEW.credit_date        IS NOT DISTINCT FROM OLD.credit_date
    THEN
      RETURN NEW;   -- a void, and nothing else
    END IF;
    RAISE EXCEPTION 'a credit memo cannot be edited once issued — void it and issue a new one';
  END IF;

  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode', NEW.company_id;
  END IF;

  -- ── Must be applied to an invoice ────────────────────────────────────────
  -- An unapplied credit memo is storable but invisible: invoice_ar_balances only
  -- joins credits WHERE applied_to_order_id IS NOT NULL, nothing else reads the
  -- table, and there is no customer credit balance anywhere. It would burn a
  -- gap-free number and vanish. Lift this when credit_memo_applications + a customer
  -- credit balance land (plan 1.4b) — not before.
  IF NEW.applied_to_order_id IS NULL THEN
    RAISE EXCEPTION 'a credit memo must be applied to an invoice';
  END IF;

  SELECT o.customer_id, o.posted, o.invoice_state,
         round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint
    INTO v_ord_cust, v_posted, v_state, v_ord_total_cents
    FROM public.orders o WHERE o.order_id = NEW.applied_to_order_id
    FOR UPDATE;   -- serialize concurrent credits against the same invoice

  -- 'written_off' added: crediting an invoice already written off to bad debt
  -- double-counts the loss. guard_allocation_not_overapplied already refuses it for
  -- payments; the credit guard did not.
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL OR v_state IN ('void','draft','written_off') THEN
    RAISE EXCEPTION 'credit memo target order % is not a posted STRATA invoice', NEW.applied_to_order_id;
  END IF;
  IF NEW.customer_id IS NOT NULL AND v_ord_cust IS DISTINCT FROM NEW.customer_id THEN
    RAISE EXCEPTION 'credit memo customer mismatch on order %', NEW.applied_to_order_id;
  END IF;

  -- ── Period close ─────────────────────────────────────────────────────────
  SELECT books_closed_through INTO v_closed FROM public.companies WHERE company_id = NEW.company_id;
  IF v_closed IS NOT NULL AND NEW.credit_date <= v_closed THEN
    RAISE EXCEPTION 'the books are closed through % — a credit dated % cannot be posted', v_closed, NEW.credit_date;
  END IF;

  -- ── THE CEILING ──────────────────────────────────────────────────────────
  -- Payments + other live credits + this one may not exceed the invoice total. Uses
  -- the TAX-AWARE total, matching invoice_ar_balances and recompute_invoice_ar_state
  -- (both made tax-aware in 20260706000004); a ceiling on order_total alone would
  -- under-cap by exactly the tax and reject legitimate full credits.
  SELECT COALESCE(SUM(a.amount_cents),0) INTO v_payments
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id = a.payment_id AND p.voided_at IS NULL
   WHERE a.order_id = NEW.applied_to_order_id;

  SELECT COALESCE(SUM(cm.amount_cents),0) INTO v_other_credits
    FROM public.credit_memos cm
   WHERE cm.applied_to_order_id = NEW.applied_to_order_id
     AND cm.voided_at IS NULL
     AND cm.credit_memo_id <> NEW.credit_memo_id;

  IF v_payments + v_other_credits + NEW.amount_cents > v_ord_total_cents THEN
    RAISE EXCEPTION 'credit of % would exceed what is still owed on this invoice (total %, already settled %)',
      (NEW.amount_cents/100.0)::numeric(12,2),
      (v_ord_total_cents/100.0)::numeric(12,2),
      ((v_payments + v_other_credits)/100.0)::numeric(12,2);
  END IF;

  RETURN NEW;
END;
$$;

-- The guard must see UPDATEs to enforce void-only. (It already fires on both, but
-- re-declared here so the contract is visible next to the function.)
drop trigger if exists trg_guard_credit_memo on public.credit_memos;
create trigger trg_guard_credit_memo
  before insert or update on public.credit_memos
  for each row execute function public.guard_credit_memo_valid();

-- ── 3. RPC gains p_credit_date ─────────────────────────────────────────────
-- Signature change, so the old one is dropped: leaving both would make the call
-- ambiguous from PostgREST.
drop function if exists public.create_credit_memo(text, text, bigint, text, text, text);

create or replace function public.create_credit_memo(
  p_company_id          text,
  p_customer_id         text,
  p_amount_cents        bigint,
  p_applied_to_order_id text,
  p_reason              text,
  p_created_by          text,
  p_credit_date         date default current_date
) returns jsonb
language plpgsql
as $$
DECLARE v_seq bigint; v_num text; v_cm_id text;
BEGIN
  IF p_company_id NOT IN (SELECT auth_company_ids()) THEN
    RAISE EXCEPTION 'not authorized for company %', p_company_id;
  END IF;
  IF COALESCE(p_amount_cents,0) <= 0 THEN RAISE EXCEPTION 'amount must be positive'; END IF;

  -- Allocated INSIDE this transaction so a guard rejection rolls the sequence bump
  -- back and numbering stays gap-free. Never call this to "preview" a number.
  SELECT a.credit_memo_sequence, a.credit_memo_number INTO v_seq, v_num
    FROM public.allocate_credit_memo_number(p_company_id) a;

  v_cm_id := gen_random_uuid()::text;
  INSERT INTO public.credit_memos
    (credit_memo_id, company_id, customer_id, credit_memo_number, credit_memo_sequence,
     amount_cents, applied_to_order_id, reason, created_by, credit_date)
  VALUES
    (v_cm_id, p_company_id, p_customer_id, v_num, v_seq,
     p_amount_cents, NULLIF(p_applied_to_order_id,''), p_reason, p_created_by,
     COALESCE(p_credit_date, current_date));

  RETURN jsonb_build_object('ok', true, 'credit_memo_number', v_num, 'credit_memo_id', v_cm_id);
END;
$$;

-- SECURITY INVOKER (the default) is deliberate: RLS on credit_memos and orders is
-- what stops a credit being applied to another tenant's invoice, and the guard's
-- order lookup returns nothing under RLS for a foreign order.
revoke all on function public.create_credit_memo(text, text, bigint, text, text, text, date) from public, anon;
grant execute on function public.create_credit_memo(text, text, bigint, text, text, text, date) to authenticated;

-- ── 4. The grant my own migration promised and did not deliver ─────────────
-- 20260728000004 documented accounting_admin as the CONTROL bundle — "OPERATE +
-- invoice.void, invoice.write_off, payment.refund, ar.close_period,
-- ar.dunning_manage, billing.configure" — but its values list only inserted the keys
-- that migration created. The outsourced bookkeeper ended up able to write an
-- invoice off to bad debt while unable to record a payment, send an invoice, or void
-- one. Credit memos ride invoice.void (same verb risk class: cancel a receivable we
-- issued, no money moves), so the gap would have locked the primary user out of the
-- feature being built.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('accounting_admin', 'invoice.void',      true),
  ('accounting_admin', 'invoice.send',      true),
  ('accounting_admin', 'payment.record',    true),
  ('accounting_admin', 'billing.configure', true)
  -- Deliberately NOT payment.refund: sending money back out is a different act from
  -- reconciling books, and the owner should decide that one explicitly.
  --
  -- manager is untouched: it already holds invoice.void from an earlier migration,
  -- so credit memos reach it automatically — consistent, since a role that can void
  -- a whole invoice can obviously cancel part of one.
on conflict (role_id, permission_id) do update set granted = excluded.granted;

commit;

notify pgrst, 'reload schema';
