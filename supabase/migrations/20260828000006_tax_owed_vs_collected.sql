-- What we OWE is not what we COLLECT, and the report has to say both.
--
-- The owner's correction, and it is the important one: Hawaii GET is owed on
-- ALL wholesale sales. Choosing not to charge a customer the 0.5% does not make
-- the sale untaxed — it means MCR pays the tax out of its own margin instead of
-- adding it to the invoice. The filing report must still show 0.5% of every
-- wholesale dollar.
--
-- My previous design got this wrong. customers.tax_rate_id pointed an "exempt"
-- customer at a 0% rate, which nulls the LIABILITY as well as the charge. Do
-- that and MCR under-reports its own General Excise Tax return — on Costco
-- alone, 0.5% of $1,787,745.16.
--
-- So the two ideas are separated:
--
--   THE RATE       decides what is OWED. It always resolves for a taxable sale.
--   PASS-THROUGH   decides whether it is ADDED TO THE INVOICE.
--
-- A customer with pass-through off is charged nothing extra and still appears in
-- the return at the full rate. That is what "we've exempted them" has always
-- meant in practice, and MCR's own books have worked this way for seven years:
-- 805 documents carry a taxable rate label and $0.00 of tax on $1,688,236.10 of
-- sales.

begin;

alter table public.customers
  add column if not exists tax_passed_through boolean not null default true;

comment on column public.customers.tax_passed_through is
  'Whether GET is ADDED to this customer''s invoices. False means we absorb it: '
  'nothing extra on their invoice, and we still owe the state every cent and '
  'still report it. This is NOT an exemption — no such thing exists for GET on a '
  'wholesale sale — and it must never be modelled by pointing the customer at a '
  '0% rate, which would silently shrink the return.';

comment on column public.customers.tax_rate_id is
  'Charge this customer a DIFFERENT rate than the rules would give them. Rare, '
  'and NOT the way to stop charging someone — for that use tax_passed_through, '
  'which keeps the liability while dropping the charge.';

-- The order remembers the decision, because it can change later and an issued
-- invoice must keep explaining itself.
alter table public.orders
  add column if not exists tax_passed_through boolean;

comment on column public.orders.tax_passed_through is
  'Whether GET was added to THIS invoice. Snapshotted from the customer at write '
  'time. tax_amount is what was charged; the liability is order_total x the '
  'rate, whatever tax_amount says.';

-- ── The customers MCR absorbs GET for ────────────────────────────────────────
-- Identified from seven years of QuickBooks: customers carrying a taxable rate
-- label who have NEVER once been charged the tax. Not customers who were
-- occasionally not charged — 94 of those exist and they look like one-offs, not
-- standing arrangements, so they are left alone for a human to judge.
create temporary table _absorb(customer_id text primary key) on commit drop;
insert into _absorb(customer_id) values
    ('mcrimp-cust-c1d6f98fec60f5'),
    ('qbimp-cust-ed6e3af5c682c587c941'),
    ('qbimp-cust-27b17ad1604586e2ba79'),
    ('mcrimp-cust-6bf2724869b4f2'),
    ('mcrimp-cust-de23ab36665d88'),
    ('qbimp-cust-358ee601d2da431cb75f'),
    ('mcrimp-cust-e01872b3ac8ac8'),
    ('qbimp-cust-cedcaee45e9a72105271'),
    ('mcrimp-cust-64ad2521a91645'),
    ('qbimp-cust-aafe209c9a67862ea80e'),
    ('mcrimp-cust-c5b32c3778f91d');

update public.customers c
   set tax_passed_through = false
  from _absorb a
 where c.customer_id = a.customer_id
   and c.company_id = '9ShiyDAXhV';

-- ── The return ───────────────────────────────────────────────────────────────
-- What MCR owes, by rate, whether or not it was collected. The gap between the
-- two columns is what the business paid out of its own margin — which is worth
-- seeing, and is invisible if you only ever sum tax_amount.
create or replace view public.tax_liability_by_rate as
select o.company_id,
       date_trunc('month', o.order_date)::date as period,
       t.tax_rate_id,
       t.code,
       t.label,
       t.statutory_rate,
       count(*)                                as invoices,
       round(sum(o.order_total), 2)            as taxable_sales,
       -- What we OWE: the statutory rate on GROSS RECEIPTS — and in Hawaii the
       -- GET you collect from a customer is itself gross receipts, which is the
       -- entire reason the gross-up exists. So the base is order_total PLUS any
       -- tax charged, never the pre-tax subtotal.
       --
       -- Getting this wrong is not academic. On the pre-tax base the retail
       -- rate came out at $280.28 owed against $292.00 collected — an
       -- impossible-looking surplus that was really just the 4% -> 4.1667%
       -- gross-up doing its job and my formula failing to.
       round(sum((o.order_total + coalesce(o.tax_amount, 0)) * t.statutory_rate), 2) as tax_owed,
       -- What we actually put on the invoices.
       round(sum(coalesce(o.tax_amount, 0)), 2)        as tax_collected,
       -- The difference: absorbed out of margin.
       round(sum((o.order_total + coalesce(o.tax_amount, 0)) * t.statutory_rate)
             - sum(coalesce(o.tax_amount, 0)), 2) as tax_absorbed
  from public.orders o
  join public.tax_rate t on t.tax_rate_id = o.tax_rate_id
 where o.order_status <> 'Canceled'
 group by 1,2,3,4,5,6;

comment on view public.tax_liability_by_rate is
  'The General Excise Tax return, by month and rate. tax_owed is the statutory '
  'rate on GROSS RECEIPTS — which in Hawaii includes any GET collected — and is '
  'what gets filed. It does not care whether the customer was charged. tax_collected is what went on the invoices, and the '
  'difference is what the roaster absorbed out of its own margin.';

grant select on public.tax_liability_by_rate to authenticated;

commit;
