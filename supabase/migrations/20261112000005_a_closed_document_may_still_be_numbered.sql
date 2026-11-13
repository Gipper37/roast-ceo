-- A document closes once and stays closed -- and a closed document may still be
-- numbered.
--
-- 20261112000003 got the RULE right and the consequences wrong. Two faults, both
-- proved by running them against staging, which has that migration applied:
--
-- 1. 🔴 IT PUT invoice_number AND invoice_sequence IN THE CLOSED BLOCK.
--    finalize_invoice mints the number and the sequence in ONE update, and
--    zzz_guard_posted_order is BEFORE UPDATE with no WHEN clause, so once an
--    order reached Delivered it could NEVER be invoiced:
--        delivered order        -> REFUSED  P0001 "has gone to the customer"
--        control, not delivered -> NUMBERED OK  (INV-000049)
--    No invoice for the driver to get signed, no cheque recordable, no card
--    chargeable -- each of those mints the number as its first act. And
--    friendlyFinalizeError has no mapping for the refusal, so a PERMANENT
--    refusal reads as "please try again": the 441-order shape a second time.
--
--    Owner, on the real workflow: "we print the invoice in the warehouse PRIOR
--    to delivery ... I mean you should still be able to print the invoice after
--    delivery too. accounting prints them after."
--
--    So the ordinary road was never broken -- the bench numbers it before the
--    van loads, and re-printing is a read. What broke is the EXCEPTION: MCR
--    leaks 1.9% of delivered orders out of the building unbilled (2 of 103
--    since its cutover). Today every one of those is still recoverable. That
--    migration is what would have made the leak permanent.
--
--    A number is therefore WRITE-ONCE, not closed-locked: blank becomes a
--    number at any time, a number never becomes a different number. Unlike the
--    old rule this holds whether the document is open or closed.
--
-- 2. 🔴 IT ASKED A LIVE QUESTION INSTEAD OF READING A FACT. "Closed" was
--    recomputed on every call, so one click on "Revert to Packed" re-opened a
--    document the customer was already holding -- and order_status has no check
--    constraint and no RLS policy anywhere in the schema (0 and 0, measured).
--    A stamp cannot be un-evaluated.
--
-- The stamp also carries the two terms the live expression could not reach:
--   MONEY     an invoice printed at the bench, not emailed, not delivered, and
--             paid over the phone was still line-editable. The money is the
--             evidence the customer has seen the document, same as the email.
--   RETIRED   void or written off. 2 void invoices on prod would otherwise have
--             become editable.
--
-- Owner's rule, unchanged and now literally true: editable until delivered or
-- the invoice is sent.

begin;

-- ── 1. The fact, stamped ───────────────────────────────────────────────
alter table public.orders
  add column if not exists document_closed_at     timestamptz,
  add column if not exists document_closed_reason text;

comment on column public.orders.document_closed_at is
  'When this document reached the customer and its lines and amounts locked. Stamped once by zy_stamp_document_closed and never cleared or moved -- a live expression let "Revert to Packed" re-open an invoice the customer was holding. Null means still editable.';
comment on column public.orders.document_closed_reason is
  'Which term closed it: emailed, delivered, paid, voided, written_off. For the screen, so a refusal can say why rather than "locked".';

-- ── 2. What closes a document ──────────────────────────────────────────
-- BEFORE, so the stamp is on NEW by the time the row guard reads it, and so
-- the statement that CLOSES a document is itself allowed through. Named to
-- sort before zzz_guard_posted_order, which depends on that ordering.
create or replace function public.stamp_document_closed()
returns trigger
language plpgsql
as $fn$
declare v_reason text;
begin
  -- Closed once, closed forever. Not an error to try: ordinary updates carry
  -- the whole row, so refusing here would refuse every later edit to a closed
  -- order, including the ones that are still allowed.
  if TG_OP = 'UPDATE' and OLD.document_closed_at is not null then
    -- 🔴 ONE TERM IS REVERSIBLE AND MUST HAVE A RELEASE. A cheque keyed
    -- against the wrong order stamps 'paid'; voidPayment is the documented
    -- repair and it restores invoice_state, paid_at and the whole balance.
    -- Without a way back the order stays locked forever, reading "This
    -- invoice has been paid -- refund the payment" on an invoice with no
    -- payment. Money that was taken back is not money recorded. Only the
    -- release trigger may do it, and only for 'paid': nobody un-emails an
    -- invoice, so emailed, delivered, shipped, voided and written_off latch.
    if NEW.document_closed_at is null
       and OLD.document_closed_reason = 'paid'
       and current_setting('app.releasing_document', true) = OLD.order_id then
      NEW.document_closed_reason := null;
      return NEW;
    end if;

    -- The TIME never moves -- the document closed when it closed -- but the
    -- REASON may be superseded by a stronger one. An invoice that was emailed
    -- and is then voided IS voided, and the screen has to say so: otherwise
    -- it offers a credit memo and a refund on a dead document. 3 of prod's 5
    -- voided orders were emailed, delivered or paid first.
    NEW.document_closed_at := OLD.document_closed_at;
    NEW.document_closed_reason := case
      when NEW.voided_at is not null
        or coalesce(NEW.invoice_state, '') = 'void' then 'voided'
      when NEW.written_off_at is not null           then 'written_off'
      else OLD.document_closed_reason
    end;
    return NEW;
  end if;

  -- 🔴 ONLY THE STAMP MAY STAMP. `authenticated` holds column-level UPDATE on
  -- orders.document_closed_at, orders_tenant_update is tenancy-only, and
  -- guard_order_invoice_columns never names this column -- so without this
  -- branch one PATCH {"document_closed_at": "2001-01-01"} freezes any order
  -- in the tenant forever, with no permission key in the way and no way back.
  -- It would also produce the half-stamp (time set, reason null) that this
  -- migration's own verify block asserts cannot exist. The allocation trigger
  -- is the one legitimate caller and names its order in a session setting it
  -- sets itself -- the same sentinel shape the late-fee append already uses.
  if NEW.document_closed_at is not null then
    if current_setting('app.closing_document', true) = NEW.order_id then
      NEW.document_closed_reason := coalesce(NEW.document_closed_reason, 'paid');
      return NEW;
    end if;
    NEW.document_closed_at     := null;
    NEW.document_closed_reason := null;
  end if;

  v_reason := case
    when NEW.voided_at      is not null then 'voided'
    when NEW.written_off_at is not null then 'written_off'
    when coalesce(NEW.invoice_state, '') = 'void' then 'voided'
    when NEW.invoice_sent_at is not null then 'emailed'
    when NEW.order_status = 'Delivered'  then 'delivered'
    -- 'Shipped' is live code, not a dead value: delivery/actions.ts writes it
    -- and baggedStock.ts allocates stock on it. Nothing on either database
    -- carries it today, so this decides a flow nobody has used yet rather
    -- than changing one: goods with a carrier are as gone as goods delivered,
    -- and leaving it open would make a shipped order freely editable --
    -- looser than the delivered order beside it. Its own reason, because the
    -- screen must not tell a roaster something was delivered when it is on a
    -- van.
    when NEW.order_status = 'Shipped'    then 'shipped'
    when NEW.paid_at is not null         then 'paid'
    when coalesce(NEW.invoice_state, '') in ('paid', 'partial') then 'paid'
    else null
  end;

  if v_reason is not null then
    NEW.document_closed_at     := now();
    NEW.document_closed_reason := v_reason;
  end if;

  return NEW;
end
$fn$;

drop trigger if exists zy_stamp_document_closed on public.orders;
create trigger zy_stamp_document_closed
  before insert or update on public.orders
  for each row execute function public.stamp_document_closed();

-- Money lives in its own table, so it stamps from there. The UPDATE below
-- fires the row guard, which passes: no locked column moves.
create or replace function public.stamp_document_closed_on_allocation()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- Names itself to the stamp trigger, which refuses a caller-supplied stamp
  -- from anyone else. Scoped to this transaction.
  perform set_config('app.closing_document', NEW.order_id, true);
  update public.orders
     set document_closed_at     = now(),
         document_closed_reason = 'paid'
   where order_id = NEW.order_id
     and document_closed_at is null;
  perform set_config('app.closing_document', '', true);
  return null;
end
$fn$;

drop trigger if exists trg_stamp_document_closed_alloc on public.invoice_payment_allocations;
create trigger trg_stamp_document_closed_alloc
  after insert on public.invoice_payment_allocations
  for each row execute function public.stamp_document_closed_on_allocation();

-- ── 2b. And the way back ───────────────────────────────────────────────
-- The owner's rule is "if a payment has been recorded it shouldn't be
-- editable". A voided payment is not a recorded one. voidPayment and
-- reverseWriteOff both exist to undo a mistake, and both would otherwise
-- leave the order permanently locked with a reason that is no longer true.
-- Releases ONLY when every other closing term is also absent, so this can
-- never re-open a document that was emailed, delivered, shipped or voided.
create or replace function public.release_document_closed_on_reversal()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_order text;
begin
  for v_order in
    select distinct a.order_id
      from public.invoice_payment_allocations a
     where a.payment_id = coalesce(NEW.payment_id, OLD.payment_id)
  loop
    perform set_config('app.releasing_document', v_order, true);
    update public.orders o
       set document_closed_at = null, document_closed_reason = null
     where o.order_id = v_order
       and o.document_closed_reason = 'paid'
       and o.invoice_sent_at is null
       and o.order_status not in ('Delivered', 'Shipped')
       and o.voided_at is null
       and o.written_off_at is null
       and o.paid_at is null
       and coalesce(o.invoice_state, '') not in ('paid', 'partial', 'void')
       and not exists (
             select 1 from public.invoice_payment_allocations a2
               join public.invoice_payments p2 on p2.payment_id = a2.payment_id
              where a2.order_id = o.order_id and p2.voided_at is null);
    perform set_config('app.releasing_document', '', true);
  end loop;
  return null;
end
$fn$;

comment on function public.release_document_closed_on_reversal() is
  'Un-stamps a document that was closed only because a payment was recorded, once that payment is voided and no live allocation remains. Money taken back is not money recorded: without this, voidPayment -- the documented repair for a cheque keyed against the wrong order -- left the order locked forever reading "this invoice has been paid".';

drop trigger if exists trg_release_document_closed on public.invoice_payments;
create trigger trg_release_document_closed
  after update of voided_at on public.invoice_payments
  for each row when (NEW.voided_at is not null and OLD.voided_at is null)
  execute function public.release_document_closed_on_reversal();

-- ── 3. Backfill, newest honest timestamp first ─────────────────────────
-- Every term, not just the two the old expression had: the orders this adds
-- are exactly the ones 20261112000003 would have left editable.
update public.orders o
   set document_closed_at = coalesce(
         o.invoice_sent_at, o.voided_at, o.written_off_at, o.paid_at,
         o.delivered_on::timestamptz, o.order_date::timestamptz, now()),
       document_closed_reason = case
         when o.voided_at      is not null then 'voided'
         when o.written_off_at is not null then 'written_off'
         when coalesce(o.invoice_state, '') = 'void' then 'voided'
         when o.invoice_sent_at is not null then 'emailed'
         when o.order_status = 'Delivered'  then 'delivered'
         when o.order_status = 'Shipped'    then 'shipped'
         else 'paid'
       end
 where o.document_closed_at is null
   and (o.invoice_sent_at is not null
     or o.order_status in ('Delivered', 'Shipped')
     or o.voided_at is not null
     or o.written_off_at is not null
     or o.paid_at is not null
     or coalesce(o.invoice_state, '') in ('paid', 'partial', 'void')
     -- A VOIDED payment is not a recorded one, here as in the release above.
     -- Without the join this would close orders whose only payment was
     -- already taken back, and nothing could re-open them.
     or exists (select 1 from public.invoice_payment_allocations a
                  join public.invoice_payments p on p.payment_id = a.payment_id
                 where a.order_id = o.order_id and p.voided_at is null));

-- ── 4. The helper reads the stamp ──────────────────────────────────────
-- guard_posted_order_detail_immutable calls this and is NOT retyped: routing
-- both guards through one helper is what makes re-meaning the lock a
-- one-statement change.
create or replace function public.order_document_is_closed(p_order_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select o.document_closed_at is not null
       from public.orders o
      where o.order_id = p_order_id),
    false)
$fn$;

comment on function public.order_document_is_closed(text) is
  'True once orders.document_closed_at is stamped -- emailed, delivered, paid, voided or written off. Reads a fact rather than re-deciding one, so nothing can re-open a document the customer already holds. Printing does not close it: the bench prints while packing.';

revoke all on function public.order_document_is_closed(text) from public, anon;
grant execute on function public.order_document_is_closed(text) to authenticated;

-- CLOSED is not the same question as FINAL, and conflating them is exactly
-- what broke finalize_invoice. A document CLOSES when the operator is done
-- with it -- delivered, shipped, emailed, paid, voided. Its FIGURES are FINAL
-- only once the customer has actually been shown them: a number was issued,
-- it was emailed, it came from the storefront, or it was imported from the
-- system that billed it. Between the two sits the order this whole batch
-- exists for -- delivered, never billed -- whose arithmetic may still be
-- resolved, and must be, because that is what finalize_invoice does at the
-- moment of numbering.
create or replace function public.order_figures_are_final(p_order_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select o.document_closed_at is not null
        and (o.invoice_number  is not null
          or o.invoice_sent_at is not null
          or o.shop_order_ref  is not null
          or coalesce(o.is_legacy_import, false)
          or coalesce(o.document_closed_reason, '') not in ('delivered', 'shipped'))
       from public.orders o
      where o.order_id = p_order_id),
    false)
$fn$;

comment on function public.order_figures_are_final(text) is
  'True once the customer has been shown this order''''s figures -- a closed document that carries a number, was emailed, came from the storefront, or was imported. Deliberately narrower than order_document_is_closed: a delivered order nobody has billed is closed to editing, but its tax and discounts may still be resolved.';

revoke all on function public.order_figures_are_final(text) from public, anon;
grant execute on function public.order_figures_are_final(text) to authenticated;

-- ── 5. The header guard: write-once number, OLD-or-NEW closed ──────────
-- Body is 20261112000003's, with three changes and nothing else retyped:
--   a. the invoice number gets its own unconditional write-once rule and
--      leaves the closed block, so a delivered order can still be invoiced;
--   b. closed is read off the stamp, and off OLD *or* NEW, so one statement
--      cannot carry a locked edit in alongside the delivery that closes it;
--   c. the refusal names the reason, which the stamp now knows.
CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_why text; v_billed boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % carries an invoice number and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  -- A NUMBER IS WRITE-ONCE, NOT CLOSED-LOCKED. Blank becomes a number at any
  -- time -- that is how a delivered order still gets an invoice for the driver
  -- to get signed, a cheque recorded, or a card charged. A number never becomes
  -- a different number, open or closed, which is the thing that actually
  -- matters: an invoice number the customer has quoted cannot be restated.
  IF (OLD.invoice_number IS NOT NULL AND NEW.invoice_number IS DISTINCT FROM OLD.invoice_number)
  OR (OLD.invoice_sequence IS NOT NULL AND NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence) THEN
    RAISE EXCEPTION 'invoice % already carries number % — a number cannot be changed or cleared (void and reissue instead)', OLD.order_id, OLD.invoice_number;
  END IF;

  IF COALESCE(OLD.document_closed_at, NEW.document_closed_at) IS NOT NULL THEN
    v_why := COALESCE(OLD.document_closed_reason, NEW.document_closed_reason, 'emailed');
    -- 🔴 TAX IS DERIVED, AND finalize_invoice RESOLVES IT AT THE MOMENT OF
    -- NUMBERING. Its last act before minting is recompute_order_tax, whose
    -- final statement writes these columns -- so locking them on a closed
    -- document breaks the exact flow this migration exists to enable:
    -- accounting invoices a delivered order, the guard raises, and finalize's
    -- own `exception when others` swallows it to a NOTICE nobody sees over
    -- PostgREST. The invoice is issued with no tax at all. Measured on prod:
    -- 30 delivered, never-billed orders would have lost $69.03 of tax the
    -- roaster owes, silently, growing with every delivered-and-unbilled order.
    --
    -- So the rule here is the one 20261112000007 states for lines: A FIGURE
    -- THE CUSTOMER HAS SEEN NEVER MOVES. Never numbered and never sent means
    -- nobody has seen it, and a derived figure may still be resolved. The
    -- discount INPUTS stay locked either way -- those are a decision, not an
    -- arithmetic, and the owner's rule is that a delivered order is not
    -- editable.
    --
    -- Written to be the SAME test 20261112000007 uses on the lines, so the
    -- header and the lines cannot disagree about which orders a correction
    -- may still reach: if the lines moved, the arithmetic over them has to be
    -- allowed to follow, or the invoice contradicts itself.
    v_billed := (OLD.invoice_number IS NOT NULL
              OR OLD.invoice_sent_at IS NOT NULL
              OR OLD.shop_order_ref  IS NOT NULL
              OR COALESCE(OLD.is_legacy_import, false)
              OR COALESCE(OLD.document_closed_reason, '') NOT IN ('delivered', 'shipped'));
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (v_billed AND (
           (NEW.tax_amount         IS DISTINCT FROM OLD.tax_amount)
        OR (NEW.tax_rate           IS DISTINCT FROM OLD.tax_rate)
        OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
        OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
        OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
        OR (NEW.tax_passed_through IS DISTINCT FROM OLD.tax_passed_through)
        OR (NEW.discount_total     IS DISTINCT FROM OLD.discount_total)))
    OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
    OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
    OR (
      (   (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
       OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
       OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
       OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
       OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
       OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
       OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
       OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
       OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
      )
      -- The one way in: no JWT, an order holding no address, a whole address
      -- arriving, and any contact the order already holds left as it is. Once
      -- this has fired the order holds an address, so it can only fire once.
      AND NOT (
            auth.uid() IS NULL
        AND nullif(btrim(OLD.bill_to_address), '')   IS NULL
        AND nullif(btrim(OLD.bill_to_address_2), '') IS NULL
        AND nullif(btrim(OLD.bill_to_city), '')      IS NULL
        AND nullif(btrim(OLD.bill_to_state), '')     IS NULL
        AND nullif(btrim(OLD.bill_to_zip), '')       IS NULL
        AND nullif(btrim(NEW.bill_to_address), '')   IS NOT NULL
        AND nullif(btrim(NEW.bill_to_city), '')      IS NOT NULL
        AND nullif(btrim(NEW.bill_to_state), '')     IS NOT NULL
        AND nullif(btrim(NEW.bill_to_zip), '')       IS NOT NULL
        AND (nullif(btrim(OLD.bill_to_name), '')  IS NULL OR NEW.bill_to_name  IS NOT DISTINCT FROM OLD.bill_to_name)
        AND (nullif(btrim(OLD.bill_to_email), '') IS NULL OR NEW.bill_to_email IS NOT DISTINCT FROM OLD.bill_to_email)
        AND (nullif(btrim(OLD.bill_to_phone), '') IS NULL OR NEW.bill_to_phone IS NOT DISTINCT FROM OLD.bill_to_phone)
      )
    )
    THEN
      RAISE EXCEPTION 'this invoice is closed (%) — its document fields are locked. Void and reissue it, or issue a credit memo.', v_why;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 5b. A half-stamp is not a stamp ────────────────────────────────────
-- The verify block below asserts these two things hold at migration time.
-- Constraints are what keep them true afterwards: without them the first
-- caller-supplied stamp that slips through writes a time with no reason, and
-- the guard then reports the reason as 'emailed' for a document that reached
-- nobody.
alter table public.orders drop constraint if exists orders_document_closed_whole;
alter table public.orders add constraint orders_document_closed_whole
  check ((document_closed_at is null) = (document_closed_reason is null));

alter table public.orders drop constraint if exists orders_document_closed_reason_known;
alter table public.orders add constraint orders_document_closed_reason_known
  check (document_closed_reason is null
      or document_closed_reason in ('emailed','delivered','shipped','paid','voided','written_off'));

-- ── 6. Prove it ────────────────────────────────────────────────────────
-- Each of these can fail. Asserting that the helper returns true for a stamped
-- order would be a tautology -- the helper IS that expression -- so none of
-- them does that.
do $$
declare v_n integer;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'orders'
                    and column_name = 'document_closed_at') then
    raise exception 'orders.document_closed_at was not added';
  end if;

  -- The backfill covered every term, so nothing that is closed lacks a stamp.
  select count(*) into v_n from public.orders o
   where o.document_closed_at is null
     and (o.invoice_sent_at is not null
       or o.order_status = 'Delivered'
       or o.voided_at is not null
       or o.written_off_at is not null
       or o.paid_at is not null
       or coalesce(o.invoice_state, '') in ('paid', 'partial', 'void'));
  if v_n > 0 then
    raise exception 'backfill left % closed order(s) unstamped', v_n;
  end if;

  -- A stamp that is not a stamp: a reason with no time, or the reverse.
  select count(*) into v_n from public.orders
   where (document_closed_at is null) <> (document_closed_reason is null);
  if v_n > 0 then
    raise exception '% order(s) carry half a stamp', v_n;
  end if;

  -- The header guard must no longer decide closed by asking, and must no
  -- longer lock the number. Checked on the parse tree's own text, which is
  -- why the comments above deliberately do not contain these strings.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_immutable'
                    and p.prosrc like '%OLD.document_closed_at%') then
    raise exception 'guard_posted_order_immutable does not read the stamp';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'guard_posted_order_immutable'
                and p.prosrc like '%order_document_is_closed(OLD.order_id)%') then
    raise exception 'guard_posted_order_immutable still re-decides closed on every call';
  end if;

  -- The detail guard was deliberately NOT retyped and must still route
  -- through the helper, or the two guards have drifted apart again.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                    and p.prosrc like '%order_document_is_closed%') then
    raise exception 'guard_posted_order_detail_immutable no longer calls the helper';
  end if;

  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'orders' and t.tgname = 'zy_stamp_document_closed') then
    raise exception 'the stamp trigger is not on orders';
  end if;
  -- It has to sort before the guard it feeds, or the guard reads a NEW row
  -- that has not been stamped yet.
  if 'zy_stamp_document_closed' >= 'zzz_guard_posted_order' then
    raise exception 'the stamp trigger no longer fires before the row guard';
  end if;
end $$;

-- ── 7. Probes that RUN, each rolling itself back ───────────────────────
-- 🔴 A prosrc grep proves the text is there, not that the behaviour is. Every
-- block below performs the real write in a subtransaction and then raises to
-- undo it, so a failure is the database refusing, not a fixture problem. Each
-- pairs the case that must PASS with the control that must FAIL.
do $$
declare v_open text; v_free text; v_billed text; v_ok boolean;
begin
  -- (a) THE REGRESSION THIS MIGRATION WAS RE-WRITTEN FOR. A delivered order
  -- that nobody has billed must still accept its tax, or finalize_invoice
  -- mints the number and silently issues the invoice untaxed.
  select order_id into v_free from public.orders
   where document_closed_at is not null
     and invoice_number is null and invoice_sent_at is null
     and not coalesce(is_legacy_import, false)
   limit 1;
  if v_free is null then
    raise warning 'NO CLOSED, NEVER-BILLED ORDER ON THIS DATABASE — the tax carve-out is UNPROVEN here, not proven';
  else
    begin
      update public.orders set tax_amount = coalesce(tax_amount, 0) where order_id = v_free;
      raise exception 'PROBE_ROLLBACK';
    exception when others then
      if SQLERRM <> 'PROBE_ROLLBACK' then
        raise exception 'a closed, never-billed order still cannot have its tax resolved, so finalize_invoice would issue it untaxed: %', SQLERRM;
      end if;
    end;
  end if;

  -- (a-control) ...and a BILLED closed invoice must still refuse it, or the
  -- carve-out is not a carve-out, it is the lock gone.
  select order_id into v_billed from public.orders
   where document_closed_at is not null and invoice_number is not null
   limit 1;
  if v_billed is not null then
    v_ok := false;
    begin
      update public.orders set tax_amount = coalesce(tax_amount, 0) + 1 where order_id = v_billed;
    exception when others then
      v_ok := true;
    end;
    if not v_ok then
      raise exception 'tax moved on an invoice that already carries a number — the closed lock is gone';
    end if;
  end if;

  -- (b) ONLY THE STAMP MAY STAMP. An ordinary write that names the column on
  -- an open order must leave it open, not freeze it forever.
  select order_id into v_open from public.orders where document_closed_at is null limit 1;
  if v_open is not null then
    begin
      update public.orders
         set document_closed_at = now(), document_closed_reason = 'emailed'
       where order_id = v_open;
      if exists (select 1 from public.orders
                  where order_id = v_open and document_closed_at is not null) then
        raise exception 'PROBE_FROZE';
      end if;
      raise exception 'PROBE_ROLLBACK';
    exception when others then
      if SQLERRM = 'PROBE_FROZE' then
        raise exception 'any tenant user can permanently freeze an order by naming document_closed_at';
      elsif SQLERRM <> 'PROBE_ROLLBACK' then
        raise exception 'the stamp probe failed for an unexpected reason: %', SQLERRM;
      end if;
    end;
  end if;
end $$;

commit;
