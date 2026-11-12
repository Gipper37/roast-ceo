-- An invoice closes when it reaches the customer, not when it is printed.
--
-- Owner: "allow edits until delivered or sent to customer", and asked whether
-- printing should close it: "only emailing it."
--
-- 🔴 THERE WAS NEVER A PACKED-BASED EDIT GUARD. Every guard keys on invoice
-- ISSUANCE (orders.posted). Since 1a2536c2 (2026-10-27) the bench prints the
-- invoice while packing, and finalize_invoice sets posted = true, so the lines
-- went immutable at the packing table -- long before delivery and before
-- anything was emailed. That is what staff were working around by cancelling
-- the order and re-keying it, which is the behaviour the owner is describing.
--
-- So the document closes on exactly two things:
--   invoice_sent_at IS NOT NULL   the invoice was emailed to the customer
--   order_status = 'Delivered'    the goods are with them
-- Printing stamps neither, by instruction. A numbered invoice printed at the
-- bench stays editable, and the number is reused when it is finally sent, so
-- the paper and the email agree.
--
-- 7 posted orders on prod are unsent and undelivered and become editable here.
-- 2 of them are Packed. That is the point.

begin;

-- ── 1. One definition of a closed document ─────────────────────────────
-- Both guards and the app read the same rule, so they cannot drift. STABLE,
-- not VOLATILE: it is read many times per statement inside the row guards.
create or replace function public.order_document_is_closed(p_order_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select o.invoice_sent_at is not null or o.order_status = 'Delivered'
       from public.orders o
      where o.order_id = p_order_id),
    false)
$fn$;

comment on function public.order_document_is_closed(text) is
  'True once the invoice has been emailed to the customer or the goods are delivered. Printing does not close it: the bench prints while packing, and locking there is what drove staff to cancel and re-key orders.';

revoke all on function public.order_document_is_closed(text) from public, anon;
grant execute on function public.order_document_is_closed(text) to authenticated;

-- ── 2. The two guards, predicate swapped and nothing else retyped ──────
-- Bodies below are pg_get_functiondef() of the live prod functions. The diff
-- against live is 9 lines and 6 lines: the predicate, plus messages that would
-- otherwise still say "posted invoice" for a document nobody has seen.
CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  v_posted := public.order_document_is_closed(COALESCE(NEW.order_id, OLD.order_id));

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- The one sanctioned append: a late-fee line, inserted by apply_late_fee
    -- in THIS transaction (the sentinel names the order). Product type alone
    -- was spoofable over PostgREST — RLS is tenancy-only (review P1).
    SELECT p.product_type INTO v_type FROM public.products p WHERE p.product_id = NEW.product_id;
    IF v_type = 'ptype_late_fee'
       AND current_setting('app.late_fee_append', true) = NEW.order_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', NEW.order_id;
  END IF;
  -- Every number the invoice shows, not just the net. A discount that can move
  -- while total_price stands still is a silently restated invoice.
  IF (NEW.quantity         IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id       IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price      IS DISTINCT FROM OLD.total_price)
  OR (NEW.list_price_total IS DISTINCT FROM OLD.list_price_total)
  OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
  OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
  OR (NEW.discount_amount  IS DISTINCT FROM OLD.discount_amount)
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override) THEN
    RAISE EXCEPTION 'invoice % has gone to the customer, so its lines are locked — void it or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % carries an invoice number and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  IF public.order_document_is_closed(OLD.order_id) THEN
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
    OR (NEW.invoice_number   IS DISTINCT FROM OLD.invoice_number)
    OR (NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence)
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
      RAISE EXCEPTION 'invoice % has gone to the customer — its document fields are locked (void-and-reissue or issue a credit memo to change it)', OLD.order_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 3. An order that changed after it was first saved ──────────────────
-- Owner: "whenever an edit is made to an order after it is first saved, the
-- production related roles should have a status/warning section at the top of
-- orders that says an order has been revised ... and then that order in the
-- table should be highlighted until that warning is dismissed on the order
-- detail page."
--
-- Opening the edit window above makes this necessary rather than merely nice:
-- a Packed order can now change under the person packing it.

alter table public.orders
  add column if not exists revised_at            timestamptz,
  add column if not exists revision_dismissed_at timestamptz;

-- Partial on OUTSTANDING, not on revised: the banner's whole question is
-- "anything unacknowledged?", and once production clears a revision the row
-- leaves the index for good. That keeps it the size of the open queue rather
-- than of the order history.
create index if not exists orders_revised_idx
  on public.orders (company_id, revised_at)
  where revised_at is not null and revision_dismissed_at is null;

comment on column public.orders.revised_at is
  'Last time this order changed after its first save. Null means it has not been revised.';
comment on column public.orders.revision_dismissed_at is
  'When production acknowledged the revision. Cleared whenever a new revision is stamped, so outstanding is exactly revised_at not null and this null.';

-- 🔴 WHAT COUNTS AS "AFTER IT IS FIRST SAVED".
-- Creating an order writes every line in ONE insert, so inside that
-- transaction no line is older than the transaction. now() is the transaction
-- start, so "another line of this order already existed before now()" is
-- exactly "this order had been saved before this edit" -- with no clock
-- arithmetic and no grace period to tune.
create or replace function public.stamp_order_revision()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_order_id text := coalesce(NEW.order_id, OLD.order_id);
  v_first    boolean;
begin
  -- A component line is written BY the bundle explosion, not by a person.
  -- Flagging it would report every mixed case as a revision of itself.
  if coalesce(NEW.parent_order_detail_id, OLD.parent_order_detail_id) is not null then
    return null;
  end if;

  -- Imported history is a record, not something production is working on.
  if exists (select 1 from public.orders o
              where o.order_id = v_order_id and coalesce(o.is_legacy_import, false)) then
    return null;
  end if;

  if TG_OP = 'INSERT' then
    select not exists (
      select 1 from public.order_details od
       where od.order_id = v_order_id
         and od.order_detail_id <> NEW.order_detail_id
         and od.created_at < now()
    ) into v_first;
    if v_first then return null; end if;
  end if;

  -- Clearing the dismissal is what makes "outstanding" a single indexable
  -- predicate -- revised_at not null and revision_dismissed_at null -- instead
  -- of a column-to-column comparison the orders page could not push into its
  -- query. A second revision after an acknowledgement is a NEW thing to see.
  update public.orders
     set revised_at = now(),
         revision_dismissed_at = null
   where order_id = v_order_id;

  return null;
end
$fn$;

drop trigger if exists trg_stamp_order_revision_ins on public.order_details;
create trigger trg_stamp_order_revision_ins
  after insert or delete on public.order_details
  for each row execute function public.stamp_order_revision();

-- Only the columns a person edits. Not item_status: packing an order is not a
-- revision of it, and the bundle explosion propagates status to its children.
drop trigger if exists trg_stamp_order_revision_upd on public.order_details;
create trigger trg_stamp_order_revision_upd
  after update of quantity, product_id, amount_override, discount_kind,
                  discount_value, coffee_prep on public.order_details
  for each row execute function public.stamp_order_revision();

-- The same for the order's own production-facing fields.
-- BEFORE, not AFTER. An AFTER trigger here would have to UPDATE the very row
-- it fired on: a second row version per edit, and a recursion question to
-- reason about every time somebody adds a trigger to orders. Writing NEW
-- directly has neither. (`update of` fires on the SET clause, not on a value
-- change, so an AFTER version would also need its own guard.)
create or replace function public.stamp_order_revision_header()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if coalesce(NEW.is_legacy_import, false) then return NEW; end if;
  NEW.revised_at := now();
  NEW.revision_dismissed_at := null;
  return NEW;
end
$fn$;

drop trigger if exists trg_stamp_order_revision_header on public.orders;
create trigger trg_stamp_order_revision_header
  before update of requested_delivery_date, customer_id, customer_po on public.orders
  for each row
  when (OLD.requested_delivery_date is distinct from NEW.requested_delivery_date
     or OLD.customer_id             is distinct from NEW.customer_id
     or OLD.customer_po             is distinct from NEW.customer_po)
  execute function public.stamp_order_revision_header();

-- ── 4. Who sees it and who may clear it ────────────────────────────────
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('order.revision_view', 'Orders', 'See revised-order warnings',
   'Show the banner and the highlight when an order changes after it was first saved.', false, 70),
  ('order.revision_acknowledge', 'Orders', 'Clear a revised-order warning',
   'Dismiss the revision warning on an order, for everybody.', false, 71)
on conflict (permission_id) do update
  set category = excluded.category, label = excluded.label,
      description = excluded.description, sort_order = excluded.sort_order;

-- Production first, because they are who the warning is for.
insert into public.role_permissions (role_id, permission_id, granted, updated_by)
select r.role_id, 'order.revision_view', true, 'migration:20261112000003'
  from (values ('roastmaster'),('assistant_roaster'),('staff'),('manager'),
               ('roastery_manager'),('facility_admin'),('company_admin')) as r(role_id)
on conflict (role_id, permission_id) do update
  set granted = true, deny_message = null,
      updated_at = now(), updated_by = 'migration:20261112000003';

-- Clearing it speaks for the whole floor, so it stops at the leads.
insert into public.role_permissions (role_id, permission_id, granted, updated_by)
select r.role_id, 'order.revision_acknowledge', true, 'migration:20261112000003'
  from (values ('roastmaster'),('manager'),('roastery_manager'),
               ('facility_admin'),('company_admin')) as r(role_id)
on conflict (role_id, permission_id) do update
  set granted = true, deny_message = null,
      updated_at = now(), updated_by = 'migration:20261112000003';

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, k.permission_id, true, 'Revised-order warnings: every plan'
  from public.subscription_plans p
  cross join (values ('order.revision_view'),('order.revision_acknowledge')) as k(permission_id)
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason, updated_at = now();

-- ── 5. Prove the substitution landed ───────────────────────────────────
-- Asserting that an unsent order reads as open would be a tautology: the
-- helper IS that expression, so such a check can only ever pass. These can
-- fail. If a guard body were replaced by something that still read posted,
-- the whole release stops here rather than shipping a lock nobody wanted.
do $$
declare v_n integer;
begin
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('guard_posted_order_detail_immutable','guard_posted_order_immutable')
     and p.prosrc like '%order_document_is_closed%';
  if v_n <> 2 then
    raise exception 'expected both order guards to call order_document_is_closed, found %', v_n;
  end if;

  -- The detail guard must no longer read orders.posted at all.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'guard_posted_order_detail_immutable'
                and p.prosrc ~ 'SELECT\s+posted\s+INTO') then
    raise exception 'guard_posted_order_detail_immutable still reads orders.posted';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'orders'
                    and column_name = 'revised_at') then
    raise exception 'orders.revised_at was not added';
  end if;

  select count(*) into v_n from public.role_permissions
   where permission_id = 'order.revision_view' and granted;
  if v_n < 7 then
    raise exception 'order.revision_view granted to only % role(s)', v_n;
  end if;
end $$;

commit;
