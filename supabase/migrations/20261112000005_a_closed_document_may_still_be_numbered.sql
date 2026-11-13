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
    NEW.document_closed_at     := OLD.document_closed_at;
    NEW.document_closed_reason := OLD.document_closed_reason;
    return NEW;
  end if;

  if NEW.document_closed_at is not null then
    return NEW;
  end if;

  v_reason := case
    when NEW.voided_at      is not null then 'voided'
    when NEW.written_off_at is not null then 'written_off'
    when coalesce(NEW.invoice_state, '') = 'void' then 'voided'
    when NEW.invoice_sent_at is not null then 'emailed'
    when NEW.order_status = 'Delivered'  then 'delivered'
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
  update public.orders
     set document_closed_at     = now(),
         document_closed_reason = 'paid'
   where order_id = NEW.order_id
     and document_closed_at is null;
  return null;
end
$fn$;

drop trigger if exists trg_stamp_document_closed_alloc on public.invoice_payment_allocations;
create trigger trg_stamp_document_closed_alloc
  after insert on public.invoice_payment_allocations
  for each row execute function public.stamp_document_closed_on_allocation();

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
         else 'paid'
       end
 where o.document_closed_at is null
   and (o.invoice_sent_at is not null
     or o.order_status = 'Delivered'
     or o.voided_at is not null
     or o.written_off_at is not null
     or o.paid_at is not null
     or coalesce(o.invoice_state, '') in ('paid', 'partial', 'void')
     or exists (select 1 from public.invoice_payment_allocations a
                 where a.order_id = o.order_id));

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
DECLARE v_why text;
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
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (NEW.tax_amount       IS DISTINCT FROM OLD.tax_amount)
    OR (NEW.tax_rate         IS DISTINCT FROM OLD.tax_rate)
    OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
    OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
    OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
    OR (NEW.tax_passed_through IS DISTINCT FROM OLD.tax_passed_through)
    OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
    OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
    OR (NEW.discount_total   IS DISTINCT FROM OLD.discount_total)
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

commit;
