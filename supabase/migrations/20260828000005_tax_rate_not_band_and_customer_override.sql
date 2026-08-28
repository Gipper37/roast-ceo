-- Three corrections to the tax setup, all from the owner reading it back.
--
-- 1. "BAND" IS NOT A WORD ANYONE USES. I invented it and then used it in the
--    schema. It just means a tax RATE — the row that says 0.5%, this is what we
--    charge and what we file. The owner said plainly "I don't know what a band
--    is", which is the end of the argument: if it means nothing to him it means
--    nothing to an operator. Renamed in the comments here; the tables were
--    already called tax_rate, so only the prose was wrong.
--
-- 2. A RESALE CERTIFICATE IS NOT AN EXEMPTION, and calling the column
--    requires_exemption_doc taught exactly the wrong idea — I made the mistake
--    myself while describing my own schema. In Hawaii the SELLER always owes
--    General Excise Tax on gross receipts. A resale certificate does not excuse
--    that; it qualifies the sale for the WHOLESALE RATE (0.5%) instead of the
--    retail rate (4%). MCR's own books prove it: 200 invoices to certificate
--    holders were taxed at 0.5%, not at zero, and all 18,629 documents — every
--    rate — post to the single account "GE Tax Payable". Renamed to
--    requires_resale_cert, which says what it is.
--
-- 3. THE CERTIFICATE MUST NOT GATE THE RATE. Previously the resolver checked for
--    a resale number and used it to decide. That is backwards for how this
--    actually works: an operator signs up a wholesale account and charges the
--    wholesale rate on day one, and the paperwork follows. Making the rate wait
--    for the document would overcharge every new wholesale customer until
--    someone filed a PDF.
--
--    So the certificate becomes a COMPLIANCE REMINDER, never a gate. The rate
--    comes from the rules and from the per-customer override below. A view lists
--    who is being charged a rate that wants a certificate and has not produced
--    one — which is both the on-screen warning and the mailing list for chasing
--    them. On MCR today that is 330 of 367 active customers, 251 with an email.

begin;

-- ── 1. Say what it is ────────────────────────────────────────────────────────
alter table public.tax_rate rename column requires_exemption_doc to requires_resale_cert;

comment on column public.tax_rate.requires_resale_cert is
  'This rate is only defensible if the customer has a resale certificate on file '
  '— Hawaii''s 0.5% wholesale rate, for instance. It does NOT gate the rate: the '
  'rate applies and the missing paperwork is surfaced as a warning, because a '
  'wholesale account is charged the wholesale rate from day one and the document '
  'follows. See customers_missing_resale_cert.';

comment on table public.tax_rate is
  'A tax rate this company can charge. Stores the STATUTORY rate it files at plus '
  'a gross_up flag, and derives the rate it actually charges — Hawaii GET is a tax '
  'on the seller''s receipts, so 4% filed is 4.1667% charged. Not a "band": that '
  'was my word and nobody uses it.';

-- ── 2. Certificate expiry, so a stale one can be chased ──────────────────────
alter table public.customers
  add column if not exists resale_cert_expires_on date;

comment on column public.customers.resale_cert_expires_on is
  'When the resale certificate lapses. NULL means no expiry recorded. Informational '
  'only — an expired certificate never changes what the customer is charged, it '
  'raises a flag to go and collect a new one.';

-- ── 3. The per-customer override the owner asked for ─────────────────────────
-- "We need to be able to exempt certain clients from rules regardless of certs."
-- One customer, one rate, overriding every rule. Points at a real tax_rate row —
-- including a 0% one — rather than carrying a loose boolean, so an exempt sale
-- still files under a named reason instead of vanishing from the return.
alter table public.customers
  add column if not exists tax_rate_id text references public.tax_rate(tax_rate_id),
  add column if not exists tax_rate_note text;

comment on column public.customers.tax_rate_id is
  'Always charge THIS customer this tax rate, whatever the rules say. Beats every '
  'tax_rule and is beaten only by an override typed on the order itself. Point it '
  'at a 0% rate to make a customer non-taxable — deliberately a rate and not a '
  'boolean, so an untaxed sale still files under a named reason rather than '
  'disappearing off the return.';

-- ── 4. The resolver: rules and overrides decide, paperwork does not ──────────
create or replace function public.resolve_tax_rate(
  p_company_id      text,
  p_facility_id     text default null,
  p_channel_id      text default null,
  p_product_type_id text default null,
  p_customer_id     text default null,
  p_on_date         date default null
)
returns text
language plpgsql
stable
as $$
declare
  v_on_date date := coalesce(p_on_date, current_date);
  v_rate_id text;
begin
  -- Gate 0: the feature flag, checked inside the resolver so no caller can
  -- forget it. Tax off means resolve nothing, compute nothing, print nothing.
  if not exists (
    select 1 from public.billing_settings b
     where b.company_id = p_company_id and b.tax_enabled
  ) then
    return null;
  end if;

  -- 1. THE CUSTOMER'S OWN OVERRIDE. Set by a human, and it wins over every rule.
  --    This is the "exempt this client regardless of certs" case: it applies
  --    whether or not any paperwork exists, because whether to charge someone is
  --    an operator's decision and the document is a filing-cabinet problem.
  if p_customer_id is not null then
    select c.tax_rate_id into v_rate_id
      from public.customers c
      join public.tax_rate t on t.tax_rate_id = c.tax_rate_id
     where c.customer_id = p_customer_id
       and t.is_active
       and t.effective_from <= v_on_date
       and (t.effective_to is null or t.effective_to >= v_on_date);
    if v_rate_id is not null then
      return v_rate_id;
    end if;
  end if;

  -- 2. THE MOST SPECIFIC RULE. facility x channel x product type, most specific
  --    first. "Charge the wholesale rate on the wholesale channel at this
  --    facility" is one row here.
  select r.tax_rate_id
    into v_rate_id
    from public.tax_rule r
    join public.tax_rate t on t.tax_rate_id = r.tax_rate_id
   where r.company_id = p_company_id
     and r.is_active
     and t.is_active
     and t.effective_from <= v_on_date
     and (t.effective_to is null or t.effective_to >= v_on_date)
     and (r.facility_id     is null or r.facility_id     = p_facility_id)
     and (r.channel_id      is null or r.channel_id      = p_channel_id)
     and (r.product_type_id is null or r.product_type_id = p_product_type_id)
   order by r.match_specificity desc, t.effective_from desc
   limit 1;

  -- 3. NULL means UNRESOLVED, not zero. A caller must surface it, never assume
  --    0%. Silently defaulting an unresolved line to no tax produces a system
  --    that looks like it works and quietly under-remits.
  return v_rate_id;
end;
$$;

comment on function public.resolve_tax_rate is
  'The tax rate for this sale. Customer override first, then the most specific '
  'active rule. A resale certificate is NOT consulted — it never gates the rate, '
  'it only raises a warning when missing. NULL means unresolved, never zero.';

-- ── 5. Who owes us a certificate ─────────────────────────────────────────────
-- Drives both the on-screen warning and the list to email. Only lists customers
-- actually being charged a rate that wants a certificate, so it is a finding
-- rather than a nag: a retail-rate customer never appears here.
create or replace view public.customers_missing_resale_cert as
-- Keyed on what a customer has actually BOUGHT, because nothing else links a
-- customer to a channel — there is no tier or channel column on customers and no
-- linking table. Checked, not assumed. Their orders carry it: 185 of MCR's
-- customers have bought on the wholesale channel.
--
-- That turns out to be the better definition anyway. "Marked wholesale" would be
-- a flag someone has to maintain; "has bought at a rate that wants a
-- certificate" maintains itself and cannot drift from the invoices.
with charged as (
  select distinct o.customer_id, o.company_id,
         public.resolve_tax_rate(o.company_id, o.facility_id, p.channel, p.product_type,
                                 o.customer_id, o.order_date) as tax_rate_id
    from public.orders o
    join public.order_details od on od.order_id = o.order_id
    join public.products p on p.product_id = od.product_id
   where o.order_status <> 'Canceled'
     and o.order_date >= current_date - 365
)
select c.customer_id,
       c.company_id,
       c.name_company,
       c.email,
       c.resale_number,
       c.resale_cert_expires_on,
       t.tax_rate_id,
       t.label as tax_rate_label,
       case
         when coalesce(btrim(c.resale_number), '') = ''    then 'never provided'
         when c.resale_cert_expires_on < current_date       then 'expired'
         else 'expiring soon'
       end as cert_status
  from public.customers c
  join charged ch on ch.customer_id = c.customer_id
  join public.tax_rate t on t.tax_rate_id = ch.tax_rate_id
 where c.is_active
   and t.requires_resale_cert
   and (
        coalesce(btrim(c.resale_number), '') = ''
     or c.resale_cert_expires_on is null
     or c.resale_cert_expires_on < current_date + 60
   );

comment on view public.customers_missing_resale_cert is
  'Active customers who have bought in the last year at a tax rate that wants a '
  'resale certificate, and have not produced one or whose certificate has lapsed '
  'or lapses within 60 days. Drives the warning on the customer record and the '
  'list to email. Never affects what anyone is charged — the rate applies from '
  'day one and the paperwork follows.';

grant select on public.customers_missing_resale_cert to authenticated;

commit;
