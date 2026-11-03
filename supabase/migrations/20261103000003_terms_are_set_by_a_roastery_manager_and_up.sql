-- A customer's payment terms are set by a roastery manager and up, and accounting.
--
-- Owner, 2026-11-03: "terms can be edited by roastery manager and up, including
-- accounting."
--
-- Two different rules were live for one column. The shop page and the per-order
-- override asked `payments.terms_edit` (company_admin, facility_admin, manager).
-- The customer page asked `customer.edit`, which eight roles hold, so a sales
-- person or a roastmaster could put an account on Net 90 from one screen and be
-- refused on another. And the database enforced neither: orders have
-- guard_order_invoice_columns, customers had nothing, so any member of a tenant
-- could PATCH the column over REST.
--
-- So:
--   * roastery_manager and accounting_admin gain the key. accounting_view does
--     not: it is the view-only role. They also gain what the key already opens
--     on an order: the per-order terms override and the due date.
--   * the column is guarded here, the way orders.payment_terms already is.
--
-- 🔴 THE IMPORT CARVE-OUT IS DELIBERATE. A QuickBooks customer import writes the
-- term QB holds, under config.import_data, through the caller's own client. The
-- orders guard makes the same exception (v_import). Refusing here would abort a
-- whole import chunk over one row. The cost, said out loud: roastmaster holds
-- config.import_data and not this key, so for that one role this guard does not
-- stop a direct write. The app still does: the customer page, the shop page and
-- the order override all ask payments.terms_edit.
--
-- 🔴 NULL ON INSERT IS NOT AN EDIT. Omitting the term is how a customer follows
-- the company default (20261103000002), and every role that may add a customer
-- may do that. Only naming a term needs the key.
--
-- auth.uid() null is service role, cron, migrations and the storefront's admin
-- client: trusted, and the same early return as guard_order_invoice_columns.
--
-- The key stays plan-gated (enterprise and up), as it has always been. Every
-- live tenant is enterprise_plus and a trial resolves to enterprise, so nobody
-- loses anything today.

insert into public.role_permissions (role_id, permission_id, granted, updated_by)
values
  ('roastery_manager', 'payments.terms_edit', true, 'migration:20261103000003'),
  ('accounting_admin', 'payments.terms_edit', true, 'migration:20261103000003')
on conflict (role_id, permission_id) do update
  set granted      = true,
      deny_message = null,
      updated_at   = now(),
      updated_by   = 'migration:20261103000003';

-- It said "Net 15 / 30 / 60 vs card", from when terms also chose the checkout.
update public.permissions
   set description = 'When a customer''s invoices are due, on the customer and on one order.'
 where permission_id = 'payments.terms_edit';

create or replace function public.guard_customer_payment_terms()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if auth.uid() is null then return new; end if;

  if tg_op = 'INSERT' then
    if new.payment_terms is null then return new; end if;
  elsif new.payment_terms is not distinct from old.payment_terms then
    return new;
  end if;

  if public.auth_has_permission('payments.terms_edit', new.company_id)
     or public.auth_has_permission('config.import_data', new.company_id) then
    return new;
  end if;

  raise exception 'Only a roastery manager or above, or accounting, can change a customer''s payment terms.'
    using errcode = 'insufficient_privilege';
end;
$function$;

revoke all on function public.guard_customer_payment_terms() from public, anon, authenticated;

drop trigger if exists zzz_guard_customer_payment_terms on public.customers;
create trigger zzz_guard_customer_payment_terms
  before insert or update of payment_terms on public.customers
  for each row execute function public.guard_customer_payment_terms();

do $$
declare
  missing text;
begin
  select string_agg(r, ', ') into missing
    from unnest(array['company_admin','facility_admin','manager','roastery_manager','accounting_admin']) r
   where not exists (
     select 1 from public.role_permissions rp
      where rp.role_id = r and rp.permission_id = 'payments.terms_edit' and rp.granted
   );
  if missing is not null then
    raise exception 'these roles should set payment terms and cannot: %', missing;
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.customers'::regclass
       and tgname = 'zzz_guard_customer_payment_terms' and not tgisinternal
  ) then
    raise exception 'customers.payment_terms is not guarded';
  end if;
end $$;
