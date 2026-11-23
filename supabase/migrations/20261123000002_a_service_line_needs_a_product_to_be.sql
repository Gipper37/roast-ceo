-- Which product a service visit's charges become on the invoice.
--
-- An invoice in STRATA is an order, and an order's lines are `order_details`
-- rows. `order_details.product_id` is nullable and 73 of the 41,385 lines on
-- prod are already product-less with only `product_name_snapshot`, so a
-- service line COULD be raised with no product at all.
--
-- The owner chose otherwise, 2026-11-23: *"real product/service which we
-- already have partially in the MCR side (labor, parts, etc) these should be
-- typed something other than coffee obviously"*. He is right, and the reason
-- is downstream: `product_type.qb_item_type` is what tells QuickBooks whether
-- a line is a Service, a Non-inventory Part or an Inventory Part. A line with
-- no product has no type and no QB item, so it lands in the export as
-- nothing. MCR already carries the products this needs -- ptype_service
-- "Labor" ($125) and "Service Fee", ptype_equipment "Parts".
--
-- WHY A MAPPING AND NOT A CONVENTION. Matching a product called "Labor" by
-- name is the kind of magic that works on one tenant and silently picks the
-- wrong row on the next. MCR IS THE TEST CASE, NOT THE SPEC. So each company
-- names its own three products, on the Parts & Labor tab beside the labor
-- rates and markup that already live there, and a visit cannot be invoiced
-- until they are set -- a refusal that names the missing setting, rather than
-- an invoice quietly built on a guess.
--
-- 🔴 NO COLUMN GRANT NEEDED, CHECKED NOT ASSUMED: `authenticated` holds
-- TABLE-level INSERT/SELECT/UPDATE/DELETE on public.company_pricing_default,
-- so these three columns inherit it. The verify block asserts that, so if the
-- table is ever switched to column-level grants this fails here instead of
-- leaving a setting the UI can read and never save.

begin;

alter table public.company_pricing_default
  add column if not exists invoice_labor_product_id text,
  add column if not exists invoice_part_product_id  text,
  add column if not exists invoice_fee_product_id   text;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('invoice_labor_product_id', 'company_pricing_default_invoice_labor_product_id_fkey'),
      ('invoice_part_product_id',  'company_pricing_default_invoice_part_product_id_fkey'),
      ('invoice_fee_product_id',   'company_pricing_default_invoice_fee_product_id_fkey')
    ) as t(col, con)
  loop
    if not exists (
      select 1 from pg_constraint
       where conrelid = 'public.company_pricing_default'::regclass
         and conname  = r.con
    ) then
      -- ON DELETE SET NULL, not CASCADE: deleting the product must blank the
      -- setting, never delete the company's whole pricing row.
      execute format(
        'alter table public.company_pricing_default
           add constraint %I foreign key (%I)
           references public.products(product_id) on delete set null',
        r.con, r.col);
    end if;
  end loop;
end $$;

comment on column public.company_pricing_default.invoice_labor_product_id is
  'The product a service visit''s LABOR lines become on the invoice. Must not be a coffee product; the picker filters to the company''s non-coffee product types and the server re-checks.';
comment on column public.company_pricing_default.invoice_part_product_id is
  'The product a service visit''s PART lines become on the invoice. The specific part name rides on order_details.product_name_snapshot.';
comment on column public.company_pricing_default.invoice_fee_product_id is
  'The product a service visit''s trip fee and other charges become on the invoice.';

do $$
begin
  if not exists (
    select 1 from information_schema.table_privileges
     where table_schema='public' and table_name='company_pricing_default'
       and grantee='authenticated' and privilege_type='UPDATE'
  ) then
    raise exception 'authenticated has no table-level UPDATE on company_pricing_default, so the three new columns need explicit column grants';
  end if;

  if (select count(*) from information_schema.columns
       where table_schema='public' and table_name='company_pricing_default'
         and column_name in ('invoice_labor_product_id','invoice_part_product_id','invoice_fee_product_id')) <> 3 then
    raise exception 'the three invoice product mapping columns were not all created';
  end if;

  -- CONTROL: they are nullable. A NOT NULL here would refuse every existing
  -- pricing row, and both live tenants have one.
  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='company_pricing_default'
       and column_name in ('invoice_labor_product_id','invoice_part_product_id','invoice_fee_product_id')
       and is_nullable = 'NO'
  ) then
    raise exception 'an invoice product mapping column came out NOT NULL; existing pricing rows have no mapping yet';
  end if;
end $$;

commit;
