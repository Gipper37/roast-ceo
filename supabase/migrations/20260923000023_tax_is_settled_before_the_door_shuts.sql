-- An invoice must not be posted untaxed, and switching tax off must clear it.
--
-- Two holes on either side of the same gap: nothing resolved tax at the moment
-- it stopped being changeable, and nothing cleared it when a tenant stopped
-- charging it.
--
-- 1. finalize_invoice never mentioned tax. An order that had never had it
--    resolved was posted without any, and posting is irreversible --
--    recompute_order_tax refuses a posted order, and the documented escape,
--    reviseAndReissueInvoice, clones into a fresh draft that is equally
--    untaxed. The roaster owes Hawaii the GET with no way to put it on the
--    document. Order 4029 ($493.50, tax null, resolvable at 0.502513%) would
--    have gone out at $493.50 instead of $495.98.
--
--    Now resolved inside finalize_invoice, at the last moment it still can be,
--    and deliberately non-fatal: a tenant with tax off resolves nothing, and
--    that must never block an invoice.
--
-- 2. recompute_order_tax could not tell "tax is switched off" from "no rule
--    matched", because resolve_tax_rate answers null to both. Its null branch
--    preserves history on purpose -- that was fixed once, so an unresolvable
--    rate would stop deleting invoices from the filing report -- but it meant
--    switching tax OFF left every open order carrying its stamped tax, and the
--    next line edit did not clear it. The order kept charging a tax the
--    roaster had stopped collecting.
--
--    Off now clears, on-with-no-rule still preserves. That is the distinction
--    that was missing.

begin;

create or replace function public.recompute_order_tax(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_o         record;
  v_pass      boolean;
  v_tax       numeric := 0;
  v_dominant  text;
  v_line      record;
  v_rate_id   text;
  v_charge    numeric;
  v_statutory numeric;
  v_line_tax  numeric;
begin
  select o.order_id, o.company_id, o.facility_id, o.customer_id, o.order_date,
         o.order_total, coalesce(o.posted,false) as posted,
         coalesce(o.is_legacy_import,false) as legacy
    into v_o from public.orders o where o.order_id = p_order_id;
  if not found then return null; end if;
  if v_o.posted or v_o.legacy then
    raise exception 'order % is posted or imported history — its tax is locked', p_order_id;
  end if;

  -- IS TAX ON AT ALL? resolve_tax_rate returns null both when a tenant has tax
  -- switched off and when no rule happens to match, and the caller could not
  -- tell them apart -- so switching tax OFF left every open order carrying the
  -- tax it had already been stamped with, and the next line edit did not clear
  -- it. The order went on charging a tax the roaster had stopped collecting.
  --
  -- Off means clear it. No rule while tax is ON still means leave history
  -- alone, which is the distinction that was missing.
  if not exists (
    select 1 from public.billing_settings b
     where b.company_id = v_o.company_id and b.tax_enabled
  ) then
    update public.order_details
       set tax_rate_id = null, tax_amount = null
     where order_id = p_order_id and (tax_rate_id is not null or tax_amount is not null);
    update public.orders
       set tax_rate_id = null, tax_rate = null, tax_amount = 0
     where order_id = p_order_id
       and (tax_rate_id is not null or coalesce(tax_amount, 0) <> 0);
    return 0;
  end if;

  select coalesce(c.tax_passed_through, true) into v_pass
    from public.customers c where c.customer_id = v_o.customer_id;
  v_pass := coalesce(v_pass, true);

  -- LINE BY LINE. Each resolves against its OWN channel and product type,
  -- which is what a tax rule keys on.
  for v_line in
    select od.order_detail_id, od.total_price, p.channel, p.product_type
    from public.order_details od
    left join public.products p on p.product_id = od.product_id
    where od.order_id = p_order_id
  loop
    v_rate_id := public.resolve_tax_rate(
      v_o.company_id, v_o.facility_id, v_line.channel, v_line.product_type,
      v_o.customer_id, v_o.order_date);

    if v_rate_id is null then
      -- No rate for this line. It contributes nothing, and its own stamp is
      -- left alone for the same reason the order-level one always was.
      continue;
    end if;

    select t.charge_rate into v_charge
      from public.tax_rate t where t.tax_rate_id = v_rate_id;

    v_line_tax := case when v_pass
                       then round(coalesce(v_line.total_price,0) * coalesce(v_charge,0), 2)
                       else 0 end;

    update public.order_details
       set tax_rate_id = v_rate_id,
           tax_amount  = v_line_tax
     where order_detail_id = v_line.order_detail_id;

    v_tax := v_tax + v_line_tax;
  end loop;

  -- The dominant rate, for display and for anything still reading the order's
  -- single tax_rate_id. The MONEY no longer comes from it.
  select od.tax_rate_id into v_dominant
  from public.order_details od
  where od.order_id = p_order_id and od.tax_rate_id is not null
  group by od.tax_rate_id
  order by sum(coalesce(od.total_price,0)) desc nulls last
  limit 1;

  if v_dominant is null then
    -- Nothing resolved at all: leave the order's existing stamp as history.
    return null;
  end if;

  select t.charge_rate, t.statutory_rate into v_charge, v_statutory
    from public.tax_rate t where t.tax_rate_id = v_dominant;

  update public.orders
     set tax_rate_id = v_dominant,
         tax_rate = case when v_pass then v_charge else v_statutory end,
         tax_amount = v_tax,
         tax_passed_through = v_pass
   where order_id = p_order_id;
  return v_tax;
end;
$function$;;

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

  -- Terms: the per-order override wins, else the customer default.
  select coalesce(
           (select payment_terms from public.orders    where order_id    = p_order_id),
           (select payment_terms from public.customers where customer_id = v_customer)
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
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.finalize_invoice(text)'::regprocedure;
  if position('recompute_order_tax' in v_src) = 0 then
    raise exception 'finalize_invoice still posts without resolving tax';
  end if;

  select prosrc into v_src from pg_proc
  where oid = 'public.recompute_order_tax(text)'::regprocedure;
  if position('b.tax_enabled' in v_src) = 0 then
    raise exception 'recompute_order_tax still cannot tell tax-off from no-rule';
  end if;
  -- And 000021's per-line walk must have survived being re-emitted here.
  if position('for v_line in' in v_src) = 0 then
    raise exception 'the per-line tax walk from 000021 was lost';
  end if;
end $$;

commit;
