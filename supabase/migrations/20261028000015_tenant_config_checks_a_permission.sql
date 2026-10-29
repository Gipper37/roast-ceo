-- Tenant-wide configuration checks a permission to be written.
--
-- Batch 3. Three tables whose rows are not records of work but SETTINGS: one
-- row changes behaviour for everybody in the tenant at once.
--
--   company_parameters       the tenant's own parameter store, read through
--                            get_param() by costing, retention, the roast
--                            reset day, par and restock maths. ZERO code
--                            writers today.
--   company_pricing_default  the default equipment pricing. One writer, and it
--                            already demands equipment.manage_pricing.
--   shop_order_ref_counter   mints the public order reference a customer
--                            quotes back to you.
--
-- ── Checked before writing, not after ────────────────────────────────────
--
-- 🔴 allocate_shop_order_ref, which writes the counter, is SECURITY INVOKER --
-- so it runs under the CALLER's RLS and a policy here could have broken
-- checkout. All three of its call sites (actions-checkout.ts 562, 753, 2192)
-- use createAdminClient(), which bypasses RLS entirely. Verified by reading
-- the client at each site, not by assuming the shop is admin-side.
--
-- Keys are the ones that already exist for exactly these acts:
--   config.parameters         "Edit company parameters" -- company_admin,
--                             facility_admin, manager, roastery_manager
--   equipment.manage_pricing  what the single real writer already calls
--   shop.configure            the counter is shop configuration
--
-- ── Reads are untouched ──────────────────────────────────────────────────
--
-- 🔴 All three policies were cmd=ALL, and ALL covers SELECT. get_param() reads
-- company_parameters on costing, retention and par paths that run for every
-- role, so gating the existing policy would have taken those readings away and
-- the failure would have looked like wrong numbers rather than a refusal. Each
-- becomes a company-scoped SELECT that behaves exactly as before plus gated
-- INSERT/UPDATE/DELETE -- the same shape as batches 1 and 2.

begin;

-- ── company_parameters ───────────────────────────────────────────────────
drop policy if exists tenant_company_access on public.company_parameters;

create policy company_parameters_read on public.company_parameters
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy company_parameters_insert on public.company_parameters
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('config.parameters', company_id));

create policy company_parameters_update on public.company_parameters
  for update to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('config.parameters', company_id))
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('config.parameters', company_id));

create policy company_parameters_delete on public.company_parameters
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('config.parameters', company_id));

-- ── company_pricing_default ──────────────────────────────────────────────
drop policy if exists tenant_company_access on public.company_pricing_default;

create policy company_pricing_default_read on public.company_pricing_default
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy company_pricing_default_insert on public.company_pricing_default
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('equipment.manage_pricing', company_id));

create policy company_pricing_default_update on public.company_pricing_default
  for update to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('equipment.manage_pricing', company_id))
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('equipment.manage_pricing', company_id));

create policy company_pricing_default_delete on public.company_pricing_default
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('equipment.manage_pricing', company_id));

-- ── shop_order_ref_counter ───────────────────────────────────────────────
drop policy if exists tenant_company_access on public.shop_order_ref_counter;

create policy shop_order_ref_counter_read on public.shop_order_ref_counter
  for select to authenticated
  using (company_id in (select auth_company_ids()));

create policy shop_order_ref_counter_insert on public.shop_order_ref_counter
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('shop.configure', company_id));

create policy shop_order_ref_counter_update on public.shop_order_ref_counter
  for update to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('shop.configure', company_id))
  with check (company_id in (select auth_company_ids())
    and auth_has_permission('shop.configure', company_id));

create policy shop_order_ref_counter_delete on public.shop_order_ref_counter
  for delete to authenticated
  using (company_id in (select auth_company_ids())
    and auth_has_permission('shop.configure', company_id));

do $$
declare t text; n_read int; n_write int; n_ungated int;
begin
  foreach t in array array['company_parameters','company_pricing_default','shop_order_ref_counter'] loop
    select count(*) into n_read from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd='r';
    if n_read < 1 then raise exception '% lost its read policy -- get_param would start returning nothing', t; end if;

    select count(*) into n_write from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd in ('a','w','d');
    if n_write <> 3 then raise exception '% has % write policies, expected 3', t, n_write; end if;

    select count(*) into n_ungated from pg_policy p join pg_class c on c.oid=p.polrelid
     where c.relname=t and p.polcmd in ('a','w','d')
       and coalesce(pg_get_expr(p.polqual,p.polrelid),'')||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),'')
           not like '%auth_has_permission%';
    if n_ungated > 0 then raise exception '% still has % ungated write policy(ies)', t, n_ungated; end if;

    -- 🔴 A surviving cmd=ALL would OR with these and defeat every one of them.
    if exists (select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
                where c.relname=t and p.polcmd='*') then
      raise exception '% still has a cmd=ALL policy', t;
    end if;
  end loop;

  raise notice 'tenant parameters, default pricing and the shop order counter now check a permission to be written';
end $$;

commit;
