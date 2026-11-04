-- A recorded payment is voided, never deleted, and an allocation is never rewritten.
--
-- 🔴 NOT UNTIL THE FRONTEND THAT CALLS remove_unapplied_payment IS LIVE ON PROD. This is
-- the third step of the order in 20261103000014. Before that, the frontend still rolls a
-- refused allocation back with .delete(), and with these policies gone that touches no
-- rows and reports no error: an allocation row left behind on the first invoice, its
-- invoice_state stale, a full-amount payment standing, and an operator told only of the
-- refusal who enters it again.
--
-- 🔴 THE HOLE. 20260910000014 gave payment.record the DELETE on invoice_payments,
-- because recordPayment's rollback deleted through the caller's own client, and the
-- UPDATE and DELETE on invoice_payment_allocations alongside it. So anyone holding the
-- key could do over raw REST what no screen offers: hard-delete a payment, cascading
-- its allocations, or shrink an allocation, or delete one. Nothing recorded it,
-- voided_at never got a value, and invoice_state was not recomputed, so an invoice
-- could read Paid with nothing behind it and a customer's "I paid that" could lose its
-- only proof. voidPayment exists so that a payment leaves the balance and stays in the
-- history, and it asks invoice.void. payment.record says only that money arrived, and
-- 20261103000006 has just handed it to roastery_manager, who does not hold invoice.void.
--
-- Nothing else needs these policies, read rather than assumed:
--   recordPayment's rollback    remove_unapplied_payment, since 20261103000014
--   voidPayment                 UPDATE of voided_at on invoice_payments, under invoice.void
--   chargeAndRecord             INSERT only
--   the pay page, the webhook   the admin client, which holds BYPASSRLS, so a refund
--     and the refund fan-out    still voids, shrinks and deletes what it must
--   refundActions, write-off    write neither table
--   SQL functions               six name these tables, and all six only read them
--
-- 🔴 WITH NO POLICY A DELETE IS NOT AN ERROR. RLS filters the target rows to none, so
-- PostgREST answers 204 and supabase-js hands back no error, which is why the rollback
-- had to move to a function that raises when it refuses, and why this waits for it.

drop policy invoice_payments_delete on public.invoice_payments;
drop policy invoice_payment_allocations_update on public.invoice_payment_allocations;
drop policy invoice_payment_allocations_delete on public.invoice_payment_allocations;
