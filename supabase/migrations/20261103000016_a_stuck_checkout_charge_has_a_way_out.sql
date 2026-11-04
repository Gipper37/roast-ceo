-- A storefront checkout whose card charge never got an answer can be settled by a person.
--
-- 🔴 THE HOLE. A checkout the gateway never answered leaves the sale pending, the order
-- reading payment_status 'pending', and no hold. Every way of paying a storefront order asks
-- that column and refuses on 'pending', because money may be moving, and the guard below let
-- only the payment provider write it. So if no answer ever came, the order could not be paid,
-- could not be sent an invoice, read pending to the buyer for good, and the row on the stuck
-- list could only say so. The way out was a person with the database open.
--
-- 🔴 A PERSON MAY NOW SAY WHAT THE GATEWAY DID NOT, AND THE GATEWAY STILL HAS THE LAST WORD.
-- Two answers, the same two the webhook gives, ending in the same rows:
--
--   landed       the sale reads approved, the order reads captured with its paid date, and
--                a parked order goes Open. onApproved's writes, and settleCardCharge's.
--   did not land the sale reads failed and the order reads failed, so payableFromOrderPage
--                and reserve_order_charge let it take a payment. onDeclined's writes.
--
-- Whichever comes first, the two agree, because of how the webhook filters:
--
--   landed, then approved    onApproved moves pending and failed only, so it finds nothing to
--                            do on a captured order: no second paid date, nothing booked.
--   landed, then declined    onDeclined moved pending only, which left an order reading paid
--                            on a card that was refused, so the coffee ships unpaid. The sale
--                            now carries landed_by_hand_at, and the frontend's onDeclined
--                            moves such an order to failed and takes its paid date away.
--   did not land, approved   onApproved moves failed to captured, or says the buyer may have
--                            paid twice if the order has been numbered since.
--   did not land, declined   already failed, and the second write finds nothing.
--   approved or declined, then a click   the sale is no longer pending, so this refuses.
--
-- landed_by_hand_at is the one difference between an order captured on the gateway's word and
-- one captured on a person's. A real approval clears it. A decline does not touch an order
-- the gateway itself approved, which is what the test 'never un-pays an order that has since
-- been captured' goes on holding it to.
--
-- 🔴 NO LEDGER. A checkout's money is not on an invoice, and this writes no invoice_payments
-- row and mints no number. Apply to invoice is the other path, and it is the one that does.
-- There is exactly one state to book into, so a second booking has nowhere to land: both the
-- sale and the order are locked and both must read pending, in the order the webhook writes
-- them, so it cannot deadlock against one and exactly one of them finds the row still pending.
--
-- 🔴 paid_at IS THE DAY OF THE CHARGE, NOT THE DAY OF THE CLICK. A clean checkout stamps it as
-- the charge answers. Cash basis books revenue on it, and a charge settled by hand a week
-- later took the money a week ago: the same reason applyStuckCharge dates a payment by
-- created_at. NOT now().
--
-- 🔴 THE GUARD. guard_order_invoice_columns refuses a payment_status write from anything with
-- a JWT, and a security definer function still has its caller's JWT. So this function names
-- the order in a transaction-local setting and the guard admits that one order, and only the
-- two moves this function makes. Same door as app.late_fee_append (20260904000003). A raw
-- PostgREST update has no way to set it and dies in the guard as before. Guard text taken
-- from pg_get_functiondef on prod, identical to staging; only the last test changed.
--
-- Only payment.record, the key that says whether money arrived. Not payment.charge_card,
-- which a roastmaster at the terminal holds, and not invoice.send: nothing is issued.
--
-- No email. onApproved has no mail path and neither does this, and the buyer's order page
-- reads the new status on its own.
--
-- FRONTEND ORDER: this applies before the frontend. The webhook selects landed_by_hand_at,
-- and a select of a column that is not there fails. Against the old frontend it changes
-- nothing: no button calls the function and the guard refuses every other write as before.

alter table public.payment_transactions
  add column if not exists landed_by_hand_at timestamptz;

comment on column public.payment_transactions.landed_by_hand_at is
  'A person said this checkout charge landed and the gateway has not confirmed it since. A decline moves the order to failed only while this is set. onApproved clears it.';

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
    -- The one way past it: resolve_stuck_checkout_charge, having passed every check of its
    -- own, for this order, in this transaction, moving a pending card to one of two answers.
    if v_ins
       or old.payment_status is distinct from 'pending'
       or coalesce(new.payment_status, '') not in ('captured', 'failed')
       or coalesce(current_setting('app.resolve_checkout_charge', true), '') <> new.order_id then
      raise exception 'Payment status is set by the payment provider, not from the app.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.resolve_stuck_checkout_charge(
  p_transaction_id uuid,
  p_landed         boolean,
  p_gateway_ref    text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_t      record;
  v_o      record;
  v_ref    text := nullif(btrim(coalesce(p_gateway_ref, '')), '');
  v_status text;
begin
  if p_landed is null then
    raise exception 'Say whether this charge landed.';
  end if;

  -- The company filter comes first, so another roaster's charge reads as one that is not
  -- there. It has to be here at all because a definer function runs past row level security.
  select t.payment_transaction_id, t.company_id, t.order_id, t.type, t.status, t.created_at,
         t.settled, t.provider_transaction_id, t.response_text
    into v_t
    from public.payment_transactions t
   where t.payment_transaction_id = p_transaction_id
     and t.company_id in (select public.auth_company_ids())
     for update;
  if not found then
    raise exception 'That charge could not be found, so nothing was changed.';
  end if;

  if not public.auth_has_permission('payment.record', v_t.company_id) then
    raise exception 'You may not settle a card charge.' using errcode = 'insufficient_privilege';
  end if;

  -- A second click, a stale tab, or the webhook getting here first.
  if v_t.type <> 'sale' or v_t.status <> 'pending' then
    raise exception 'This charge is no longer waiting on an answer, so nothing was changed. Refresh the page.';
  end if;
  -- The line stuck_card_charges draws. Inside the first day the gateway may still answer.
  if v_t.created_at >= now() - interval '1 day' then
    raise exception 'The payment provider may still answer this charge, so nothing was changed. It can be settled here once it is a day old.';
  end if;
  -- A hold means it went through the ledger, from an order page or the terminal, and
  -- releasing or applying that hold is what settles it.
  if exists (select 1 from public.terminal_charge_holds h
              where h.payment_transaction_id = v_t.payment_transaction_id) then
    raise exception 'This charge is holding an invoice, so use It did not land or Apply to invoice. Nothing was changed.';
  end if;
  if v_t.order_id is null then
    raise exception 'This charge is not attached to an order, so nothing was changed.';
  end if;

  select o.order_id, o.shop_order_ref, o.invoice_number, o.posted, o.payment_status, o.order_status
    into v_o
    from public.orders o
   where o.order_id = v_t.order_id
     and o.company_id = v_t.company_id
     for update;
  if not found then
    raise exception 'The order this charge is on could not be found, so nothing was changed.';
  end if;

  if v_o.shop_order_ref is null then
    raise exception 'This charge did not come from the shop checkout, so nothing was changed.';
  end if;
  -- Numbered, its money is the ledger's to say. onApproved and onDeclined skip these too.
  if v_o.invoice_number is not null or coalesce(v_o.posted, false) then
    raise exception 'This order has an invoice now, so its money is on the invoice. Nothing was changed.';
  end if;
  if v_o.payment_status is distinct from 'pending' then
    raise exception 'This order no longer reads as waiting on its card, so nothing was changed. Refresh the page.';
  end if;
  if exists (select 1 from public.invoice_payments p
              where p.payment_transaction_id = v_t.payment_transaction_id
                and p.voided_at is null) then
    raise exception 'This charge is already recorded as a payment, so nothing was changed.';
  end if;
  -- One sale per checkout, by construction. Failing one here would free the order for another
  -- card while the second may be landing, and capturing one would hide the second.
  if exists (select 1 from public.payment_transactions x
              where x.order_id = v_t.order_id
                and x.company_id = v_t.company_id
                and x.type = 'sale'
                and x.status = 'pending'
                and x.payment_transaction_id <> v_t.payment_transaction_id) then
    raise exception 'This order has another card charge still waiting, so nothing was changed. Send us the order number.';
  end if;
  -- Captured says all of it was kept and failed says none of it moved, and a refund says
  -- neither. The two statuses the charge panel counts as money gone back.
  if exists (select 1 from public.payment_transactions r
              where r.order_id = v_t.order_id
                and r.company_id = v_t.company_id
                and r.type = 'refund'
                and r.status in ('approved', 'pending')) then
    raise exception 'A refund has been recorded against this order, so nothing was changed. Send us the order number.';
  end if;

  if p_landed then
    -- The number a refund goes back through. Same rule as Apply to invoice: a number someone
    -- typed goes on the row as a claim, and refunds refuse on it until the gateway confirms.
    if v_t.provider_transaction_id is null then
      if v_ref is null then
        raise exception 'Enter the transaction number from the payment provider''s dashboard. Nothing was changed.';
      end if;
      if v_ref !~ '^\S{4,100}$' then
        raise exception 'That does not look like a transaction number. Copy it from the dashboard. Nothing was changed.';
      end if;
      if exists (select 1 from public.payment_transactions x
                  where x.company_id = v_t.company_id
                    and x.provider_transaction_id = v_ref) then
        raise exception 'That transaction number is already on another charge. Check you have the right one. Nothing was changed.';
      end if;
    end if;

    update public.payment_transactions t
       set status = 'approved',
           response_text = left('Confirmed by hand as landed.'
                                || coalesce(' The gateway had said: ' || v_t.response_text, ''), 500),
           provider_transaction_id = coalesce(t.provider_transaction_id, v_ref),
           provider_id_unconfirmed = t.provider_id_unconfirmed or t.provider_transaction_id is null,
           landed_by_hand_at = now(),
           updated_by = auth.uid()::text
     where t.payment_transaction_id = v_t.payment_transaction_id;

    perform set_config('app.resolve_checkout_charge', v_o.order_id, true);
    update public.orders o
       set payment_status = 'captured',
           -- The gateway's own number or none. One someone typed is a claim, not a match.
           payment_transaction_id = coalesce(v_t.provider_transaction_id, o.payment_transaction_id),
           paid_at = v_t.created_at,
           payment_failed_at = null,
           payment_failure_reason = null
     where o.order_id = v_o.order_id;
    perform set_config('app.resolve_checkout_charge', '', true);

    -- A shop card order is inserted Canceled, and that is the status every roaster screen
    -- leaves out, so a captured one left there is money taken for coffee nobody will roast.
    -- Its own statement and only while Canceled, as onApproved does it, because
    -- trg_order_status_consumable_sync fires on any update of the column, changed or not.
    update public.orders o
       set order_status = 'Open'
     where o.order_id = v_o.order_id
       and o.order_status = 'Canceled';

    v_status := 'captured';
  else
    -- A settlement on the row is the gateway saying it took the money.
    if v_t.settled then
      raise exception 'The payment provider has settled this charge, so it did land. Nothing was changed.';
    end if;

    update public.payment_transactions t
       set status = 'failed',
           response_text = left('Marked as not landed by hand.'
                                || coalesce(' The gateway had said: ' || v_t.response_text, ''), 500),
           updated_by = auth.uid()::text
     where t.payment_transaction_id = v_t.payment_transaction_id;

    -- No failure reason: the order page prints that as what the payment provider said, and
    -- it said nothing. order_status stays, as onDeclined leaves it: someone may have started.
    perform set_config('app.resolve_checkout_charge', v_o.order_id, true);
    update public.orders o
       set payment_status = 'failed',
           payment_failed_at = now(),
           payment_failure_reason = null,
           paid_at = null
     where o.order_id = v_o.order_id;
    perform set_config('app.resolve_checkout_charge', '', true);

    v_status := 'failed';
  end if;

  return jsonb_build_object(
    'order_id', v_o.order_id,
    'payment_status', v_status,
    'reopened', p_landed and v_o.order_status = 'Canceled'
  );
end;
$function$;

comment on function public.resolve_stuck_checkout_charge(uuid, boolean, text) is
  'A person settles a storefront checkout charge the gateway never answered: landed reads captured, not landed reads failed. Refuses anything not actually pending. payment.record. See 20261103000016.';

revoke all on function public.resolve_stuck_checkout_charge(uuid, boolean, text) from public, anon, service_role;
grant execute on function public.resolve_stuck_checkout_charge(uuid, boolean, text) to authenticated;

do $$
declare
  v_fn regprocedure := 'public.resolve_stuck_checkout_charge(uuid, boolean, text)'::regprocedure;
begin
  if not (select p.prosecdef from pg_proc p where p.oid = v_fn) then
    raise exception 'resolve_stuck_checkout_charge has to run as its owner: it writes past row level security';
  end if;
  if has_function_privilege('anon', v_fn, 'execute') then
    raise exception 'anon may call resolve_stuck_checkout_charge';
  end if;
  if not has_function_privilege('authenticated', v_fn, 'execute') then
    raise exception 'authenticated may not call resolve_stuck_checkout_charge';
  end if;
end $$;
