-- Everyone who may charge a card can get that charge into the ledger, and a roastery
-- manager may record a payment.
--
-- 🔴 THE HOLE. 20261030000002 gave roastery_manager and roastmaster
-- payment.charge_card so the roast floor can take a card, and did not touch the
-- ledger. chargeCardOverPhone approves at the gateway FIRST, then inserts
-- invoice_payments and invoice_payment_allocations through the caller's own client,
-- and both tables' RLS asks payment.record, which neither role holds. Measured on
-- staging as each role: 42501 on the insert. So the card was taken and the screen
-- said "The card WAS charged", with nothing on the invoice.
--
-- Prod, 2026-11-03: nobody has fallen in. 3 approved sales since the grant: 2 have
-- ledger rows and the third is SH-000001, a shop checkout, which never writes this
-- ledger.
--
-- 🔴 NOT BY GRANTING THE ROASTMASTER payment.record. That key opens the record form
-- and its receipts, and the owner's line for those is "roastery manager and up,
-- including accounting admin". The roastmaster may charge a card at the terminal,
-- so they get exactly the ledger row a real charge needs: method card, pointing at
-- an approved sale of their own company.
--
-- The carve-out fits a real charge and little else: the row must point at an approved
-- sale of this company, for that sale's exact amount, for the customer of the order it
-- was charged on. And one charge can only ever be one live payment, for everybody: a
-- unique index, because a policy cannot ask this about its own table ("infinite
-- recursion detected in policy"). Prod has no duplicates today.
--
-- What that does NOT stop, stated: payment_transactions_insert/update also ask only
-- payment.charge_card, so a holder of that key working over raw REST could write
-- themselves an approved row and then a payment against it, and so mark an invoice of
-- their own company paid with no money behind it. Reachable only by a signed-in member
-- of the tenant holding the key. Closing it means taking those two policies away from
-- the charge path, which is a change of its own.
--
-- roastery_manager gains payment.record outright (owner, 2026-11-03: "gated to
-- roastery manager and up, including accounting admin"). The key stays plan-gated to
-- enterprise and up. Every role holding it still holds invoice.send, which is what
-- emailPaidReceipts relies on.

-- 🔴 AND THE POLICIES ALONE DO NOT FIX IT. guard_allocation_not_overapplied locks the
-- payment with SELECT ... FOR UPDATE and raises "payment missing or voided" when it
-- finds nothing. It runs as the caller, and FOR UPDATE applies the table's UPDATE
-- policy as well as its SELECT one: invoice_payments_update asks invoice.void. So
-- anyone without invoice.void could write the payment row and then be told it did
-- not exist. A guard must not depend on the caller's right to edit the row it is
-- checking, so it runs as its owner.
--
-- 🔴 RUNNING AS ITS OWNER REMOVES THE RLS IT WAS LEANING ON. Those reads had no company
-- filter of their own: RLS was the whole of it. Without one, a member of company A could
-- insert a payment with no customer and allocate it to company B's posted order, and
-- every admin-client reader would see B's balance reduced. So the payment and the order
-- must now belong to the company the allocation row claims. Both filters are the only
-- change to this body.

insert into public.role_permissions (role_id, permission_id, granted, updated_by)
values ('roastery_manager', 'payment.record', true, 'migration:20261103000006')
on conflict (role_id, permission_id) do update
  set granted      = true,
      deny_message = null,
      updated_at   = now(),
      updated_by   = 'migration:20261103000006';

CREATE OR REPLACE FUNCTION public.guard_allocation_not_overapplied()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pay bigint; v_alloc bigint; v_pay_cust text;
  v_ord_cust text; v_posted boolean; v_state text; v_mode text;
  v_ord_total_cents bigint; v_ord_alloc bigint;
BEGIN
  -- Lock the payment row so concurrent allocations to it serialize.
  SELECT amount_cents, customer_id INTO v_pay, v_pay_cust
    FROM public.invoice_payments
   WHERE payment_id = NEW.payment_id AND company_id = NEW.company_id AND voided_at IS NULL
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment % missing or voided', NEW.payment_id; END IF;

  SELECT o.customer_id, o.posted, o.invoice_state,
         round((COALESCE(o.order_total,0) + COALESCE(o.tax_amount,0)) * 100)::bigint
    INTO v_ord_cust, v_posted, v_state, v_ord_total_cents
    FROM public.orders o WHERE o.order_id = NEW.order_id AND o.company_id = NEW.company_id;
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL OR v_state IN ('void','draft','written_off') THEN
    RAISE EXCEPTION 'order % is not a collectable STRATA invoice', NEW.order_id;
  END IF;
  IF v_pay_cust IS NOT NULL AND v_ord_cust IS DISTINCT FROM v_pay_cust THEN
    RAISE EXCEPTION 'allocation customer mismatch (order % belongs to a different customer)', NEW.order_id;
  END IF;

  SELECT invoice_of_record INTO v_mode FROM public.billing_settings WHERE company_id = NEW.company_id;
  IF COALESCE(v_mode,'quickbooks') <> 'strata' THEN
    RAISE EXCEPTION 'company % is not in STRATA billing mode', NEW.company_id;
  END IF;

  -- Ceiling 1: allocations for THIS payment can't exceed the payment.
  SELECT COALESCE(SUM(amount_cents),0) INTO v_alloc FROM public.invoice_payment_allocations
   WHERE payment_id = NEW.payment_id AND allocation_id IS DISTINCT FROM NEW.allocation_id;
  IF v_alloc + NEW.amount_cents > v_pay THEN
    RAISE EXCEPTION 'allocations (%) exceed payment (%)', v_alloc + NEW.amount_cents, v_pay;
  END IF;

  -- Ceiling 2: allocations to THIS invoice (from all live payments) can't exceed
  -- its balance. Prevents silently over-paying one invoice.
  SELECT COALESCE(SUM(a.amount_cents),0) INTO v_ord_alloc
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id = a.payment_id AND p.voided_at IS NULL
   WHERE a.order_id = NEW.order_id AND a.allocation_id IS DISTINCT FROM NEW.allocation_id;
  v_ord_alloc := v_ord_alloc + COALESCE((SELECT SUM(amount_cents) FROM public.credit_memos
                                          WHERE applied_to_order_id = NEW.order_id AND voided_at IS NULL), 0);
  IF v_ord_alloc + NEW.amount_cents > v_ord_total_cents THEN
    RAISE EXCEPTION 'allocation would over-apply invoice % (balance %, attempted %)',
      NEW.order_id, v_ord_total_cents - v_ord_alloc, NEW.amount_cents;
  END IF;

  RETURN NEW;
END; $function$;

create unique index invoice_payments_one_live_per_charge
  on public.invoice_payments (payment_transaction_id)
  where payment_transaction_id is not null and voided_at is null;

drop policy invoice_payments_insert on public.invoice_payments;
create policy invoice_payments_insert on public.invoice_payments
  for insert to authenticated
  with check (
    company_id in (select public.auth_company_ids())
    and (
      public.auth_has_permission('payment.record', company_id)
      or (
        method = 'card'
        and public.auth_has_permission('payment.charge_card', company_id)
        and exists (
          select 1 from public.payment_transactions t
            join public.orders o on o.order_id = t.order_id
           where t.payment_transaction_id = invoice_payments.payment_transaction_id
             and t.company_id = invoice_payments.company_id
             and t.type = 'sale'
             and t.status = 'approved'
             and t.gross_amount_cents = invoice_payments.amount_cents
             and o.customer_id = invoice_payments.customer_id
        )
      )
    )
  );

drop policy invoice_payment_allocations_insert on public.invoice_payment_allocations;
create policy invoice_payment_allocations_insert on public.invoice_payment_allocations
  for insert to authenticated
  with check (
    company_id in (select public.auth_company_ids())
    and (
      public.auth_has_permission('payment.record', company_id)
      or (
        public.auth_has_permission('payment.charge_card', company_id)
        and exists (
          select 1 from public.invoice_payments p
           where p.payment_id = invoice_payment_allocations.payment_id
             and p.company_id = invoice_payment_allocations.company_id
             and p.method = 'card'
             and p.payment_transaction_id is not null
        )
      )
    )
  );
