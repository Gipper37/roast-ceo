-- Deleting an order, or a line off one, checks a permission.
--
-- ── Batch 2, and deliberately narrower than batch 1 ──────────────────────
--
-- The audit's example was exactly this: `DELETE /rest/v1/orders?order_id=eq.<id>`
-- straight at PostgREST, going around every requirePermission() in the server
-- actions. `safeupdate` is preloaded, so it blocks an UNQUALIFIED delete and
-- not that one. 15,630 of 15,860 orders are unposted and therefore deletable
-- today; `zzz_guard_posted_order_immutable` protects only the 230 posted ones.
--
-- 🔴 INSERT AND UPDATE ARE DELIBERATELY NOT GATED HERE, and that is a finding
-- rather than an omission. Seventeen different permission keys legitimately
-- write these two tables -- order.create / edit / pack, delivery.* x3,
-- invoice.send / void / write_off / print, payments.terms_edit, payment.record,
-- ar.late_fee_apply, estimate.edit, config.import_data, customer.edit. A policy
-- OR-ing seventeen keys would be admitted by every role that can do anything at
-- all, so it would read as security and buy almost none, while any key I missed
-- would break ordering for somebody mid-shift. Orders are written by nearly
-- everyone for good reasons; that is the honest shape of this table.
--
-- DELETE is the opposite, and that is why it is worth doing on its own: the app
-- barely deletes at all. Every delete in the codebase, checked before writing:
--
--   accounting/estimates/actions.ts:271  orders         gated order.create
--   orders/actions.ts:1265               orders         gated order.create  (cleanup after a failed create)
--   orders/actions.ts:1184               order_details  gated order.edit    (removing a line)
--   api/cron/standing-orders:275         orders         NO gate, but it uses the SERVICE client,
--                                                       so it never passes through RLS
--
-- The keys below are exactly those, so nothing that works today stops working.
-- `order.cancel` is admitted beside `order.create` because cancelling is the
-- act this actually is; `order.create` is kept because it is what the two
-- cleanup paths hold, and dropping it would leave a staff user staring at an
-- orphaned half-created order when a create fails.
--
-- What it buys, stated honestly: of eleven roles, it stops accounting_view,
-- equipment_tech and sales_person deleting an order, and those three plus
-- staff removing a line. It does not stop a roastmaster. The stronger move is
-- to revoke DELETE from `authenticated` on both tables outright and route the
-- three cleanup paths through a SECURITY DEFINER function -- that removes the
-- capability instead of gating it, and it needs those three call sites changed,
-- so it is its own piece of work.
--
-- 🔴 Reads, inserts and updates keep the policy they have. The existing
-- `tenant_company_access` is cmd=ALL, so a DELETE-specific policy ADDED beside
-- it would not restrict anything -- permissive policies are OR-ed. The ALL
-- policy is therefore replaced by SELECT/INSERT/UPDATE copies that behave
-- exactly as before, plus a gated DELETE.

begin;

-- ── orders ───────────────────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.orders;

create policy orders_tenant_read on public.orders
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy orders_tenant_insert on public.orders
  for insert to authenticated
  with check (company_id in (select auth_company_ids()));

create policy orders_tenant_update on public.orders
  for update to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

create policy orders_delete_needs_permission on public.orders
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and (auth_has_permission('order.cancel', company_id)
      or auth_has_permission('order.create', company_id)));

-- ── order_details ────────────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.order_details;

create policy order_details_tenant_read on public.order_details
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy order_details_tenant_insert on public.order_details
  for insert to authenticated
  with check (company_id in (select auth_company_ids()));

create policy order_details_tenant_update on public.order_details
  for update to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

create policy order_details_delete_needs_permission on public.order_details
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('order.edit', company_id));

do $$
declare t text; n_all int; n_del int; n_del_gated int; n_rw int;
begin
  foreach t in array array['orders','order_details'] loop
    -- 🔴 No cmd=ALL survivor. A permissive ALL policy beside the gated DELETE
    -- would OR with it and the gate would do nothing at all.
    select count(*) into n_all from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd='*';
    if n_all <> 0 then raise exception '% still has a cmd=ALL policy, which would defeat the DELETE gate', t; end if;

    select count(*) into n_del from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd='d';
    if n_del <> 1 then raise exception '% has % DELETE policies, expected exactly 1', t, n_del; end if;

    select count(*) into n_del_gated from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd='d'
       and pg_get_expr(p.polqual,p.polrelid) like '%auth_has_permission%';
    if n_del_gated <> 1 then raise exception '%''s DELETE policy names no permission', t; end if;

    -- and reads/inserts/updates still exist, or the app goes dark
    select count(*) into n_rw from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd in ('r','a','w');
    if n_rw < 3 then raise exception '% lost a read/insert/update policy (% left)', t, n_rw; end if;
  end loop;

  raise notice 'deleting an order or a line now needs a permission; reads, inserts and updates are unchanged';
end $$;

commit;
