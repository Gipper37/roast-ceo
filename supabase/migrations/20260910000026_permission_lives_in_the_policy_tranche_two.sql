-- M11 phase 2, tranche 2: the five tables with no company_id of their own.
--
-- Held back from tranche 1 because auth_has_permission(key, company_id) needs a
-- company_id and these rows do not carry one — they inherit their tenant from a
-- parent, and their existing policies already say so. The permission check
-- follows the same parent, so scope and permission are answered by the same
-- row rather than by two different ideas of who owns this record.
--
-- Same admission test as tranche 1: no SECURITY INVOKER function writes any of
-- these, so no trigger elsewhere can be caught out by the new gate. Each key is
-- the one the app's own action already requires.
--
-- recipe_weekly_targets is the odd one: it is scoped by FACILITY, so the
-- company comes from facilities. The read policy keeps the facility scope
-- exactly as it was.

begin;

-- ── customer_delivery_day — a customer's standing delivery weekday ────────
drop policy if exists tenant_company_access on public.customer_delivery_day;
create policy customer_delivery_day_tenant_read on public.customer_delivery_day
  for select to authenticated
  using (customer_id in (select c.customer_id from public.customers c
                          where c.company_id in (select public.auth_company_ids())));
create policy customer_delivery_day_write on public.customer_delivery_day
  for all to authenticated
  using (exists (select 1 from public.customers c
                  where c.customer_id = customer_delivery_day.customer_id
                    and c.company_id in (select public.auth_company_ids())
                    and (public.auth_has_permission('delivery.assign_customer_day', c.company_id)
                      or public.auth_has_permission('delivery.manage_zones', c.company_id))))
  with check (exists (select 1 from public.customers c
                  where c.customer_id = customer_delivery_day.customer_id
                    and c.company_id in (select public.auth_company_ids())
                    and (public.auth_has_permission('delivery.assign_customer_day', c.company_id)
                      or public.auth_has_permission('delivery.manage_zones', c.company_id))));

-- ── sales_area_day — which weekdays a delivery zone runs ──────────────────
drop policy if exists tenant_company_access on public.sales_area_day;
create policy sales_area_day_tenant_read on public.sales_area_day
  for select to authenticated
  using (sales_area_id in (select a.id from public.sales_area a
                            where a.company_id in (select public.auth_company_ids())));
create policy sales_area_day_write on public.sales_area_day
  for all to authenticated
  using (exists (select 1 from public.sales_area a
                  where a.id = sales_area_day.sales_area_id
                    and a.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('delivery.manage_zones', a.company_id)))
  with check (exists (select 1 from public.sales_area a
                  where a.id = sales_area_day.sales_area_id
                    and a.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('delivery.manage_zones', a.company_id)));

-- ── vmi_checkin_items — the lines of a vendor-managed inventory visit ─────
drop policy if exists tenant_via_checkin on public.vmi_checkin_items;
create policy vmi_checkin_items_tenant_read on public.vmi_checkin_items
  for select to authenticated
  using (vmi_checkin_id in (select v.vmi_checkin_id from public.vmi_checkins v
                             where v.company_id in (select public.auth_company_ids())));
create policy vmi_checkin_items_write on public.vmi_checkin_items
  for all to authenticated
  using (exists (select 1 from public.vmi_checkins v
                  where v.vmi_checkin_id = vmi_checkin_items.vmi_checkin_id
                    and v.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('customer.edit', v.company_id)))
  with check (exists (select 1 from public.vmi_checkins v
                  where v.vmi_checkin_id = vmi_checkin_items.vmi_checkin_id
                    and v.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('customer.edit', v.company_id)));

-- ── maintenance_program_template — which templates a program includes ─────
-- Keeps its catalog_read_global companion policy: a program with a NULL
-- company is shared reference data and stays readable.
drop policy if exists tenant_company_access on public.maintenance_program_template;
create policy maintenance_program_template_tenant_read on public.maintenance_program_template
  for select to authenticated
  using (program_id in (select p.program_id from public.maintenance_program p
                         where p.company_id in (select public.auth_company_ids())));
create policy maintenance_program_template_write on public.maintenance_program_template
  for all to authenticated
  using (exists (select 1 from public.maintenance_program p
                  where p.program_id = maintenance_program_template.program_id
                    and p.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('equipment.manage_pricing', p.company_id)))
  with check (exists (select 1 from public.maintenance_program p
                  where p.program_id = maintenance_program_template.program_id
                    and p.company_id in (select public.auth_company_ids())
                    and public.auth_has_permission('equipment.manage_pricing', p.company_id)));

-- ── recipe_weekly_targets — facility-scoped, so the company comes from it ─
drop policy if exists tenant_facility_access on public.recipe_weekly_targets;
create policy recipe_weekly_targets_tenant_read on public.recipe_weekly_targets
  for select to authenticated
  using (facility_id in (select public.auth_facility_ids()));
create policy recipe_weekly_targets_write on public.recipe_weekly_targets
  for all to authenticated
  using (exists (select 1 from public.facilities f
                  where f.facility_id = recipe_weekly_targets.facility_id
                    and f.facility_id in (select public.auth_facility_ids())
                    and public.auth_has_permission('roast_target.edit', f.company_id)))
  with check (exists (select 1 from public.facilities f
                  where f.facility_id = recipe_weekly_targets.facility_id
                    and f.facility_id in (select public.auth_facility_ids())
                    and public.auth_has_permission('roast_target.edit', f.company_id)));

-- ── Probe ─────────────────────────────────────────────────────────────────
do $probe$
declare
  v_t   text;
  v_bad text := '';
begin
  foreach v_t in array array['customer_delivery_day','sales_area_day','vmi_checkin_items',
                             'maintenance_program_template','recipe_weekly_targets'] loop
    if (select count(*) from pg_policies
         where schemaname='public' and tablename=v_t and cmd='SELECT'
           and policyname = v_t||'_tenant_read') <> 1 then
      v_bad := v_bad || v_t || ':no-read ';
    end if;
    if (select count(*) from pg_policies
         where schemaname='public' and tablename=v_t and cmd='ALL'
           and coalesce(qual,'')||coalesce(with_check,'') like '%auth_has_permission%') <> 1 then
      v_bad := v_bad || v_t || ':no-gated-write ';
    end if;
    -- no ungated FOR ALL survivor to OR the gate away
    if exists (select 1 from pg_policies
                where schemaname='public' and tablename=v_t and cmd='ALL'
                  and coalesce(qual,'')||coalesce(with_check,'') not like '%auth_has_permission%') then
      v_bad := v_bad || v_t || ':ungated-all-survived ';
    end if;
  end loop;
  if v_bad <> '' then
    raise exception 'tranche 2 did not land cleanly: %', v_bad;
  end if;
end
$probe$;

commit;
