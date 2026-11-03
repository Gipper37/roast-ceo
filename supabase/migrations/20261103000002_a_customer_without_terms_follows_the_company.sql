-- A customer with no terms of their own follows the roaster's default.
--
-- Owner, 2026-11-03, on order #4443 at Maui Coffee Roasters, whose terms panel
-- read "Use customer default (Card on file)": "why is customer default card on
-- file ... it should be COD". Then, having set Settings -> Billing -> Payment
-- terms -> New customers get: COD: "it was never set before and apparently
-- that defaulted everyone to card unless theirs was filled. that needs to
-- change."
--
-- 🔴 WHAT WAS WRONG. customers.payment_terms has been `text NOT NULL DEFAULT
-- 'card'` since the baseline. So "nobody chose" was stored as "Card on file",
-- indistinguishable from a choice, and companies.default_payment_terms (added
-- 20261002000004, documented there as "a new one gets NULL and inherits nothing
-- at all" -- false, the column default fired) was only ever COPIED at
-- creation, by one app path of seven. Changing it moved nobody. Measured on
-- prod before this migration: 1,887 customers on 'card' -- every customer of
-- every tenant except MCR, plus 125 of MCR's 372 -- and in MCR's case only ONE
-- of those 125 has ever paid by card.
--
-- 🔴 AND "CARD" WAS NEVER AN INVOICE ANSWER ANYWAY. The owner again: "shop
-- checkout and invoice are separate. just because a customer checks out on the
-- shop doesn't mean their terms are card." Checkout has been decided by
-- customers.shop_pay_at_checkout since 20260801000007; nothing in SQL or the
-- storefront reads payment_terms to route a payment. These are INVOICE terms.
--
-- So, from here:
--   customers.payment_terms NULL  = follows companies.default_payment_terms,
--                                   live -- change the setting and they move.
--   companies.default_payment_terms NULL = no terms: Due on receipt, which is
--                                   what finalize_invoice has always
--                                   snapshotted for a NULL ('receipt') and what
--                                   termsLabel(null) already prints.
--
-- 🔴 THE BACKFILL. Every 'card' row becomes NULL. There is no audit trail of
-- customer edits (config_audit_log has no customers rows), so a deliberate
-- card choice cannot be told from the default -- and the population says
-- default: 100% of four tenants, and at MCR 124 of 125 never paid by card. The
-- owner approved MCR's 125 explicitly. Rows holding any other term keep it:
-- those were chosen, by a person or by a QuickBooks terms column.
--
-- What it moves, said out loud:
--   * MCR's former card customers now resolve to COD. Due dates do not move
--     (card and COD are both 0 days); the Terms line on a NOT-yet-issued
--     document, and on the 3,759 QuickBooks-imported invoices that carry no
--     terms snapshot, now reads COD instead of Card on file.
--   * The other tenants have no default, so their customers resolve to Due on
--     receipt. Due dates do not move (0 days either way). None has issued a
--     STRATA invoice (all 74 snapshots on prod are MCR's).
--   * The 74 issued invoices are untouched: invoice_terms_snapshot is frozen at
--     issue and nothing here rewrites it.
--
-- finalize_invoice gains the third coalesce level. Its body below is
-- pg_get_functiondef() off prod (identical on staging) with ONLY the terms
-- select changed -- it is never retyped.
--
-- The backfill runs with app.skip_audit so 1,887 customers do not acquire an
-- updated_at that reads like a person edited them. The other BEFORE UPDATE
-- triggers on customers were read first: guard_demo_readonly returns early with
-- no JWT, and the sales-status and interval triggers act only when their own
-- columns change. customers_payment_terms_available is WHEN NOT NULL, so it
-- never sees the NULLs.

alter table public.customers alter column payment_terms drop default;
alter table public.customers alter column payment_terms drop not null;

select set_config('app.skip_audit', 'true', true);
update public.customers set payment_terms = null where payment_terms = 'card';
select set_config('app.skip_audit', 'false', true);

comment on column public.customers.payment_terms is
  'This customer''s own INVOICE terms (a payment_terms.terms_id). NULL = follows companies.default_payment_terms, live. Not a checkout setting: the storefront routes on shop_pay_at_checkout.';

comment on column public.companies.default_payment_terms is
  'Invoice terms for every customer of this company with none of their own (customers.payment_terms NULL), resolved at read and at finalize_invoice. NULL = no terms: Due on receipt.';

CREATE OR REPLACE FUNCTION public.finalize_invoice(p_order_id text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  v_company_id  text;
  v_customer    text;
  v_order_date  date;
  v_existing    text;
  v_legacy      boolean;
  v_status      text;
  v_total       numeric;
  v_opening     boolean;
  v_facility_id text;
  v_facility_tz text;
  v_today       date;
  v_cutover     date;
  v_terms       text;
  v_days        integer;
  v_num         text;
  v_seq         bigint;
begin
  select company_id, customer_id, order_date, invoice_number, is_legacy_import,
         order_status, order_total, is_opening_balance, facility_id
    into v_company_id, v_customer, v_order_date, v_existing, v_legacy,
         v_status, v_total, v_opening, v_facility_id
    from public.orders
   where order_id = p_order_id
   for update;

  if not found then
    raise exception 'order % not found (or not accessible)', p_order_id;
  end if;
  if v_existing is not null then
    return v_existing;                 -- already finalized — idempotent
  end if;
  if coalesce(v_legacy, false) then
    raise exception 'order % is a legacy import — it keeps its original QB number', p_order_id;
  end if;
  if coalesce(v_opening, false) then
    raise exception 'order % is an opening-balance stub — already an invoice', p_order_id;
  end if;
  if v_status = 'Canceled' then
    raise exception 'order % is canceled — cannot invoice it', p_order_id;
  end if;
  if coalesce(v_total, 0) <= 0 then
    raise exception 'order % has no billable total — cannot issue a zero-dollar invoice', p_order_id;
  end if;

  -- Clean-start: pre-cutover orders stay in QuickBooks, never finalized in STRATA.
  -- Timezone-aware so an order dated the facility's own local "today" (or later) is
  -- never blocked by a UTC-skewed cutover_date.
  select cutover_date into v_cutover from public.billing_settings where company_id = v_company_id;
  select time_zone   into v_facility_tz from public.facilities   where facility_id = v_facility_id;
  v_today := (now() at time zone coalesce(nullif(v_facility_tz, ''), 'UTC'))::date;
  if v_cutover is not null and v_order_date is not null
     and v_order_date < v_cutover
     and v_order_date < v_today then
    raise exception 'order % predates the STRATA cutover (%) — pre-cutover invoices stay in QuickBooks', p_order_id, v_cutover;
  end if;

  -- Terms: the per-order override wins, else the customer's own, else the
  -- company default. A customer with no terms of their own (NULL) follows the
  -- roaster's "New customers get" setting, live (20261103000002).
  select coalesce(
           (select payment_terms from public.orders    where order_id    = p_order_id),
           (select payment_terms from public.customers where customer_id = v_customer),
           (select default_payment_terms from public.companies where company_id = v_company_id)
         ) into v_terms;
  -- Was: CASE v_terms WHEN 'net_15' THEN 15 ... ELSE 0 END — one of five copies.
  v_days := coalesce(public.terms_net_days(v_terms), 0);

  -- TAX, BEFORE THE DOOR SHUTS.
  --
  -- finalize_invoice never mentioned tax. An order that had never had tax
  -- resolved -- a line added by a path that does not call recompute_order_tax,
  -- or an order created before a rate existed -- was posted with no tax on it,
  -- and posting is irreversible: recompute_order_tax refuses a posted order,
  -- and reviseAndReissueInvoice clones into a fresh draft that was equally
  -- untaxed. The roaster owed the GET and had no way to put it on the
  -- document.
  --
  -- Resolved here, at the last moment it still can be. Deliberately not fatal:
  -- a tenant with tax switched off resolves nothing, which is correct and must
  -- not block an invoice.
  begin
    perform public.recompute_order_tax(p_order_id);
  exception when others then
    -- Never let a tax recompute be the reason an invoice cannot be issued.
    raise notice 'tax could not be recomputed for % at finalize: %', p_order_id, sqlerrm;
  end;

  select a.invoice_sequence, a.invoice_number into v_seq, v_num
    from public.allocate_invoice_number(v_company_id) a;

  update public.orders
     set invoice_number         = v_num,
         invoice_sequence       = v_seq,
         invoice_state          = 'open',
         -- A due date set manually before posting survives; else derive from terms.
         due_date               = coalesce(due_date, coalesce(v_order_date, current_date) + v_days),
         invoice_terms_snapshot = coalesce(v_terms, 'receipt'),
         posted                 = true,
         pay_token              = coalesce(pay_token, gen_random_uuid()::text)
   where order_id = p_order_id;

  return v_num;
end;
$function$;

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'customers'
       and column_name = 'payment_terms'
       and (is_nullable <> 'YES' or column_default is not null)
  ) then
    raise exception 'customers.payment_terms is still NOT NULL or still has a default';
  end if;
  if position('default_payment_terms' in pg_get_functiondef('public.finalize_invoice(text)'::regprocedure)) = 0 then
    raise exception 'finalize_invoice does not fall through to the company default';
  end if;
end $$;
