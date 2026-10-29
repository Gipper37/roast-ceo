-- The button that mints an invoice number may actually mint one.
--
-- ── What the roaster saw ─────────────────────────────────────────────────
--
-- "whitney still cant print/mint invoices... the print button says issue
-- number and print, she clicks it, it does nothing and a warning pops up says
-- the invoice was not issued."
--
-- ── Why ──────────────────────────────────────────────────────────────────
--
-- The order screen decides whether to OFFER "Issue number and print" with
-- invoice.print (printInvoiceActions.ts, 2026-10-27: a packer at the bench
-- hands a customer a numbered document, and that mints the number). The thing
-- that actually mints it, allocate_invoice_number, opens with
--
--     guard_counter_caller(p_company_id, array['invoice.send', 'billing.configure'])
--
-- and knew nothing about that decision. So the button rendered on one key and
-- the click was refused on another: "You may not allocate an invoice or
-- credit-memo number."
--
-- 🔴 A KEY AND THE POLICY BEHIND IT MUST ADMIT THE SAME ROLES. This is that
-- rule failing in the loud direction; the quiet direction is worse and the
-- same mistake.
--
-- ── Why it hit a roastmaster at a terminal hardest ───────────────────────
--
-- Measured on production, for MCR's "Wholesale Orders" terminal with Whitney
-- PIN'd in:
--
--   invoice.print       login roastery_manager ✓   PIN'd-in roastmaster ✓  -> ALLOWED
--   invoice.send        login roastery_manager ✓   PIN'd-in roastmaster ✗  -> denied
--   billing.configure   login ✗                    PIN'd-in ✗              -> denied
--
-- auth_has_permission narrows a terminal to the INTERSECTION of the login's
-- role and the PIN'd-in person's. So the screen worked for whoever configured
-- it and failed for the person standing at the machine -- which is exactly the
-- shape that makes it read as "the PIN is broken" rather than as a permission.
--
-- ── Scope ────────────────────────────────────────────────────────────────
--
-- One key added to ALLOCATING an invoice number. Emailing an invoice is still
-- invoice.send, untouched. allocate_credit_memo_number is deliberately NOT
-- changed: a credit memo gives money back and is not a bench job.
--
-- Body taken from pg_get_functiondef on production and patched; the loop, the
-- collision retry and the QuickBooks refusal are untouched.

begin;

CREATE OR REPLACE FUNCTION public.allocate_invoice_number(p_company_id text)
 RETURNS TABLE(invoice_sequence bigint, invoice_number text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_seq       bigint;
  v_prefix    text;
  v_pad       integer;
  v_mode      text;
  v_candidate text;
  v_jumped    boolean := false;
  v_guard     integer := 0;
begin
  -- Issuing an invoice, or configuring the billing that provisions numbering.
  -- 🔴 invoice.PRINT ADMITTED, and it is the whole point of this change.
  --
  -- The order screen offers "Issue number and print" to anyone holding
  -- invoice.print, because the roaster's rule is that handing a customer a
  -- numbered document is a bench job: "a packer at the bench needs to hand a
  -- customer a numbered document, and that mints the number, but emailing an
  -- invoice in the roastery's name is a different act and staff do not get
  -- it." This guard never heard about that and still demanded invoice.send,
  -- so the button appeared and the click raised "You may not allocate an
  -- invoice or credit-memo number."
  --
  -- It bit a roastmaster at a shared terminal, where it is sharpest: the
  -- terminal LOGIN holds invoice.send, but auth_has_permission narrows a
  -- terminal to the intersection with the PIN'd-in person's role, and
  -- roastmaster does not. So the same screen worked for whoever set it up and
  -- failed for the person actually standing there.
  --
  -- 🔴 SENDING IS STILL invoice.send. This admits one more key to ALLOCATING a
  -- number, nothing else: emailing the invoice is gated where it always was.
  -- And allocate_credit_memo_number is deliberately NOT changed -- a credit
  -- memo gives money back and is not a bench job.
  perform public.guard_counter_caller(
    p_company_id, array['invoice.print', 'invoice.send', 'billing.configure']);

  insert into public.billing_settings
    (company_id, invoice_of_record, invoice_next_seq, invoice_prefix, invoice_pad_width, credit_memo_prefix)
  select p_company_id, 'strata',
         greatest(1, public.max_numeric_invoice_number(p_company_id) + 1),
         '', 6, 'CM-'
   where not exists (select 1 from public.billing_settings where company_id = p_company_id)
  on conflict (company_id) do nothing;

  loop
    v_guard := v_guard + 1;
    if v_guard > 1000 then
      raise exception 'no free invoice number for company % after 1000 attempts (last tried %)',
        p_company_id, v_candidate;
    end if;

    update public.billing_settings
       set invoice_next_seq = invoice_next_seq + 1,
           updated_at       = now()
     where company_id = p_company_id
    returning invoice_next_seq - 1, invoice_prefix, invoice_pad_width, invoice_of_record
         into v_seq, v_prefix, v_pad, v_mode;

    if not found then
      raise exception 'no billing settings for company % and none could be created — check your access', p_company_id;
    end if;
    if v_mode = 'quickbooks' then
      raise exception 'company % has QuickBooks set as its invoice of record — turn that off in Settings to invoice from STRATA', p_company_id;
    end if;

    v_candidate := coalesce(v_prefix, '') || lpad(v_seq::text, coalesce(v_pad, 6), '0');

    -- 🔴 `o.` is load-bearing (20260910000015).
    exit when not exists (
      select 1 from public.orders o
       where o.company_id = p_company_id
         and o.invoice_number = v_candidate
    );

    if not v_jumped then
      v_jumped := true;
      update public.billing_settings
         set invoice_next_seq = greatest(
               invoice_next_seq,
               public.max_numeric_invoice_number(p_company_id) + 1
             )
       where company_id = p_company_id;
    end if;
  end loop;

  invoice_sequence := v_seq;
  invoice_number   := v_candidate;
  return next;
end;
$function$;

do $$
declare v_src text; n_cm int;
begin
  select prosrc into v_src from pg_proc
   where proname = 'allocate_invoice_number' and pronamespace = 'public'::regnamespace;

  if v_src not like '%invoice.print%' then
    raise exception 'allocate_invoice_number still does not admit invoice.print';
  end if;
  -- The other two must survive: this widens, it does not replace.
  if v_src not like '%invoice.send%' or v_src not like '%billing.configure%' then
    raise exception 'allocate_invoice_number lost one of the keys it already admitted';
  end if;
  -- And the retry loop that keeps numbers unique must still be there.
  if v_src not like '%after 1000 attempts%' then
    raise exception 'allocate_invoice_number lost its collision retry';
  end if;

  -- 🔴 A credit memo is NOT a bench job and must not have been widened.
  select count(*) into n_cm from pg_proc
   where proname = 'allocate_credit_memo_number' and pronamespace = 'public'::regnamespace
     and prosrc like '%invoice.print%';
  if n_cm <> 0 then
    raise exception 'allocate_credit_memo_number was widened and should not have been';
  end if;

  raise notice 'issuing an invoice number now admits invoice.print; sending and credit memos unchanged';
end $$;

commit;
