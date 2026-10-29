-- Issuing an invoice is one act, so every gate on it must admit the same key.
--
-- ── What the roaster saw ─────────────────────────────────────────────────
--
-- "permissions for whitney still didn't work."
--
-- 20261028000009 taught the NUMBER ALLOCATOR that invoice.print may issue.
-- The click then moved from "You may not allocate an invoice or credit-memo
-- number" to "You may not issue or post an invoice." -- a DIFFERENT guard, in
-- a trigger on orders, with the same omission.
--
-- 🔴 I SHIPPED A FIX FOR THE FIRST GATE I FOUND AND CALLED IT DONE. Issuing an
-- invoice passes three of them:
--
--   allocate_invoice_number    guard_counter_caller(...)        fixed in ...0009
--   guard_order_invoice_columns  v_issue                        THIS
--   guard_order_invoice_columns  the terms / due-date block     THIS
--
-- finalize_invoice writes invoice_number, invoice_sequence, invoice_state,
-- posted AND due_date in ONE statement, so the trigger tests the caller three
-- separate ways. Fixing one moves the error rather than clearing it. When a
-- single user action crosses several guards, enumerate them all before
-- shipping -- grep the raise text, not just the first function in the chain.
--
-- ── What changes ─────────────────────────────────────────────────────────
--
-- v_issue gains invoice.print, which covers the number/sequence/posted block
-- and the invoice_state in ('draft','open') block.
--
-- The due-date block gains a NARROW exception: only while the number is being
-- minted in the same statement (v_minting). The date finalize_invoice derives
-- at the moment of issue is part of issuing; changing a due date on an invoice
-- that already has a number is a money decision and still needs its own key.
--
-- Nothing else moves. Sending is still invoice.send, voiding invoice.void,
-- write-off invoice.write_off, payments their own keys -- each verified below.
--
-- Body taken from pg_get_functiondef on production and patched.

begin;

CREATE OR REPLACE FUNCTION public.guard_order_invoice_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_co       text := new.company_id;
  v_ins      boolean := (tg_op = 'INSERT');
  -- 🔴 The STORED flag on an update, never the incoming one. Reading NEW meant a
  -- caller could set is_legacy_import true and grant themselves the carve-out in
  -- the same statement.
  v_legacy   boolean := coalesce(case when v_ins then new.is_legacy_import else old.is_legacy_import end, false);
  v_send     boolean;
  v_void     boolean;
  v_writeoff boolean;
  v_billing  boolean;
  v_terms    boolean;
  v_import   boolean;
  v_print    boolean;
  v_minting  boolean;
  v_money    boolean;
  v_issue    boolean;
  v_state    text := new.invoice_state;
begin
  if auth.uid() is null then return new; end if;

  v_send     := public.auth_has_permission('invoice.send', v_co);
  v_void     := public.auth_has_permission('invoice.void', v_co);
  v_writeoff := public.auth_has_permission('invoice.write_off', v_co);
  v_billing  := public.auth_has_permission('billing.configure', v_co);
  v_terms    := public.auth_has_permission('payments.terms_edit', v_co);
  v_import   := public.auth_has_permission('config.import_data', v_co);
  -- 🔴 invoice.print ISSUES. The order screen offers "Issue number and print"
  -- on this key, because handing a customer a numbered document is a bench
  -- job; emailing one in the roastery's name is not. 20261028000009 taught the
  -- number allocator that and this trigger still refused the write, so the
  -- same click moved from "may not allocate a number" to "may not issue or
  -- post an invoice". A key and every policy behind it must admit the same
  -- roles -- ALL of them, not the first one found.
  v_print    := public.auth_has_permission('invoice.print', v_co);

  -- Is this statement minting the number? Used below so that the due date
  -- finalize_invoice derives AT THE MOMENT OF ISSUE is part of issuing, while
  -- changing a due date later still needs the terms key.
  v_minting  := (v_ins and new.invoice_number is not null)
             or (not v_ins and new.invoice_number is distinct from old.invoice_number
                 and new.invoice_number is not null);

  -- Marking a row as imported history is an import decision, and only ever as
  -- the row is written for the first time.
  if not v_ins and (new.is_legacy_import is distinct from old.is_legacy_import) then
    raise exception 'Whether an order is imported history is fixed when it is created.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_ins and coalesce(new.is_legacy_import, false) and not v_import then
    raise exception 'You may not import invoice history.' using errcode = 'insufficient_privilege';
  end if;

  v_issue := v_send or v_billing or v_print or (v_import and v_legacy);
  v_money := public.auth_has_permission('payment.record', v_co)
          or public.auth_has_permission('payment.charge_card', v_co)
          or public.auth_has_permission('ar.late_fee_apply', v_co)
          or v_void or v_writeoff or v_billing;

  if ((v_ins and new.invoice_number is not null)     or (not v_ins and new.invoice_number     is distinct from old.invoice_number))
  or ((v_ins and new.invoice_sequence is not null)   or (not v_ins and new.invoice_sequence   is distinct from old.invoice_sequence))
  or ((v_ins and coalesce(new.posted, false))        or (not v_ins and new.posted             is distinct from old.posted)) then
    if not v_issue then
      raise exception 'You may not issue or post an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.invoice_sent_at is not null) or (not v_ins and new.invoice_sent_at is distinct from old.invoice_sent_at) then
    if not v_send then
      raise exception 'You may not send an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if ((v_ins and new.voided_at is not null)                 or (not v_ins and new.voided_at                 is distinct from old.voided_at))
  or ((v_ins and new.supersedes_invoice_number is not null) or (not v_ins and new.supersedes_invoice_number is distinct from old.supersedes_invoice_number))
  or ((v_ins and new.superseded_by_order_id is not null)    or (not v_ins and new.superseded_by_order_id    is distinct from old.superseded_by_order_id)) then
    if not v_void then
      raise exception 'You may not void an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.written_off_at is not null) or (not v_ins and new.written_off_at is distinct from old.written_off_at) then
    if not v_writeoff then
      raise exception 'You may not write off an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and new.paid_at is not null) or (not v_ins and new.paid_at is distinct from old.paid_at) then
    if not v_money then
      raise exception 'You may not record payment against an invoice.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if ((v_ins and new.due_date is not null)      or (not v_ins and new.due_date      is distinct from old.due_date))
  or ((v_ins and new.payment_terms is not null) or (not v_ins and new.payment_terms is distinct from old.payment_terms)) then
    -- 🔴 ...or the due date is being derived as the invoice is minted.
    -- finalize_invoice sets invoice_number, posted AND due_date in one
    -- statement, so without this an issuer who is not also a terms-editor gets
    -- past the number and dies on the due date. Deliberately narrow: only
    -- while v_minting. Changing a due date on an invoice that already has a
    -- number is a money decision and still needs its own key.
    if not (v_terms or v_send or v_billing or (v_minting and v_issue)) then
      raise exception 'You may not change an invoice''s terms or due date.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and coalesce(new.aging_excluded, false)) or (not v_ins and new.aging_excluded is distinct from old.aging_excluded) then
    if not (v_billing or (v_import and v_legacy)) then
      raise exception 'You may not exclude an invoice from ageing.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  if (v_ins and v_state is not null) or (not v_ins and new.invoice_state is distinct from old.invoice_state) then
    if v_state = 'void' then
      if not v_void then
        raise exception 'You may not void an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state = 'written_off' then
      if not v_writeoff then
        raise exception 'You may not write off an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state in ('draft', 'open') then
      if not v_issue then
        raise exception 'You may not issue an invoice.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state in ('paid', 'partial', 'overdue') then
      if not v_money then
        raise exception 'You may not re-state an invoice''s balance.' using errcode = 'insufficient_privilege';
      end if;
    elsif v_state is null then
      if not v_void then
        raise exception 'You may not clear an invoice''s state.' using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  if (v_ins and new.payment_status is not null) or (not v_ins and new.payment_status is distinct from old.payment_status) then
    raise exception 'Payment status is set by the payment provider, not from the app.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$function$;

do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc
   where proname = 'guard_order_invoice_columns' and pronamespace = 'public'::regnamespace;

  if v_src not like '%v_print%' then
    raise exception 'the orders guard still does not know about invoice.print';
  end if;
  if v_src not like '%v_minting and v_issue%' then
    raise exception 'the due date derived at issue is still refused';
  end if;

  -- 🔴 The keys that must NOT have been widened. Each of these raises has to
  -- still be reached by its own permission and nothing else.
  if v_src not like '%if not v_send then%' then
    raise exception 'sending an invoice no longer requires invoice.send';
  end if;
  if v_src not like '%if not v_void then%' then
    raise exception 'voiding an invoice no longer requires invoice.void';
  end if;
  if v_src not like '%if not v_writeoff then%' then
    raise exception 'writing off an invoice no longer requires invoice.write_off';
  end if;
  if v_src not like '%if not v_money then%' then
    raise exception 'recording payment no longer requires a payment key';
  end if;

  raise notice 'issuing admits invoice.print across every gate; sending, voiding, write-off and payment unchanged';
end $$;

commit;
