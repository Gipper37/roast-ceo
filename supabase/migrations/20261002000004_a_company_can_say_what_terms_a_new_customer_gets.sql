-- A company can say what terms a new customer gets.
--
-- Payment terms live on the customer and nowhere else, so "the default is Net
-- 15" was only ever true of whichever customer you were looking at. There was
-- no company-level default to change, which made the honest answer to "where do
-- I change that" be "one customer at a time, 368 times".
--
-- MCR's actual spread, on prod:
--   cod 121 · card 120 · net_30 87 · net_15 35
-- so most customers are not Net 15, and a new one gets NULL and inherits
-- nothing at all.
--
-- The column is nullable and set to nothing here. A null default means a new
-- customer carries no terms, which is exactly what happens today, so this
-- changes no behaviour until somebody picks one on the settings page.
--
-- It references payment_terms(terms_id) rather than storing a number, so the
-- default can only ever be a term the company actually has, and renaming or
-- re-describing that term carries through.

begin;

alter table public.companies
  add column if not exists default_payment_terms text references public.payment_terms(terms_id);

comment on column public.companies.default_payment_terms is
  'Terms a newly created customer inherits. NULL means none, which is the behaviour that predates this column.';

do $verify$
declare v_bad int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='companies'
                    and column_name='default_payment_terms') then
    raise exception 'the column was not added';
  end if;

  -- Nothing was set, so nothing changed.
  select count(*) into v_bad from public.companies where default_payment_terms is not null;
  if v_bad > 0 then
    raise exception '% company(ies) already carry a default; this migration must set none', v_bad;
  end if;

  -- No customer's terms moved.
  select count(*) into v_bad from public.customers where updated_at > now() - interval '1 minute';
  if v_bad > 0 then
    raise exception 'this touched % customer row(s); it must touch none', v_bad;
  end if;
end;
$verify$;

commit;
