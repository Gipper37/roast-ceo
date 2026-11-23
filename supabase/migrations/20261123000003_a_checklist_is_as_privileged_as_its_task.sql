-- A task's checklist must be as privileged as the task.
--
-- `maintenance_template` writes gate on
-- auth_has_permission('equipment.manage_pricing', company_id) -- three
-- separate INSERT/UPDATE/DELETE policies, added when programs were
-- overhauled. Its two child tables were left on the original
-- `tenant_company_access FOR ALL`, which checks only that the parent
-- template belongs to a company the caller is in. No permission check.
--
-- So today: a `staff` user cannot rename a maintenance task, and can
-- rewrite its entire checklist -- the steps, the measurement ranges, which
-- steps are required -- straight through PostgREST. The same for the parts
-- a task calls for. The checklist IS the task; splitting the gate means the
-- weaker half decides.
--
-- This was reachable before and nothing read the steps back, so nothing
-- showed it. The authoring UI lands in the same batch, which is why it is
-- being closed now and not later.
--
-- 🔴 A KEY AND ITS POLICY MUST ADMIT THE SAME ROLES, and both directions
-- fail silently: a policy stricter than the button is a refusal the user
-- cannot explain, a policy looser than the button is this. The new policies
-- name `equipment.manage_pricing` because that is what the parent table
-- already names and what the server actions already call
-- requirePermission() with -- NOT a new key, so no permissions rows change
-- and no plan gating moves.
--
-- Reads are unchanged: global rows readable by everyone, tenant rows by
-- that tenant. Only writes tighten.

begin;

-- ── maintenance_template_step ──────────────────────────────────────
-- Replaces tenant_company_access (FOR ALL, no permission check) with a
-- tenant read plus three permission-gated write policies, mirroring
-- maintenance_template's own shape.
drop policy if exists tenant_company_access on public.maintenance_template_step;

create policy maintenance_template_step_tenant_read
  on public.maintenance_template_step
  for select to authenticated
  using (
    template_id in (
      select template_id from public.maintenance_template
      where company_id in (select auth_company_ids())
    )
  );

create policy maintenance_template_step_write_insert
  on public.maintenance_template_step
  for insert to authenticated
  with check (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_step.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );

create policy maintenance_template_step_write_update
  on public.maintenance_template_step
  for update to authenticated
  using (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_step.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  )
  with check (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_step.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );

create policy maintenance_template_step_write_delete
  on public.maintenance_template_step
  for delete to authenticated
  using (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_step.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );


-- ── maintenance_template_part ──────────────────────────────────────
-- Same split, same reason: which parts a task consumes is part of the
-- task's definition, and the task is manage_pricing.
drop policy if exists tenant_company_access on public.maintenance_template_part;

create policy maintenance_template_part_tenant_read
  on public.maintenance_template_part
  for select to authenticated
  using (
    template_id in (
      select template_id from public.maintenance_template
      where company_id in (select auth_company_ids())
    )
  );

create policy maintenance_template_part_write_insert
  on public.maintenance_template_part
  for insert to authenticated
  with check (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_part.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );

create policy maintenance_template_part_write_update
  on public.maintenance_template_part
  for update to authenticated
  using (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_part.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  )
  with check (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_part.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );

create policy maintenance_template_part_write_delete
  on public.maintenance_template_part
  for delete to authenticated
  using (
    exists (
      select 1 from public.maintenance_template t
      where t.template_id = maintenance_template_part.template_id
        and t.company_id in (select auth_company_ids())
        and auth_has_permission('equipment.manage_pricing', t.company_id)
    )
  );


-- ── Verify ─────────────────────────────────────────────────────────
do $$
declare
  n int;
  tbl text;
begin
  foreach tbl in array array['maintenance_template_step', 'maintenance_template_part']
  loop
    -- The old catch-all is gone.
    select count(*) into n from pg_policies
     where schemaname = 'public' and tablename = tbl
       and policyname = 'tenant_company_access';
    if n <> 0 then
      raise exception '% still has tenant_company_access', tbl;
    end if;

    -- Every write command is covered, and every one names the key.
    select count(*) into n from pg_policies
     where schemaname = 'public' and tablename = tbl
       and cmd in ('INSERT', 'UPDATE', 'DELETE')
       and coalesce(qual, '') || coalesce(with_check, '') like '%equipment.manage_pricing%';
    if n <> 3 then
      raise exception '% has % permission-gated write policies, expected 3', tbl, n;
    end if;

    -- CONTROL: the global catalogue is still readable. If this broke, every
    -- roaster would lose all 67 seeded tasks, which is the opposite failure
    -- and the one a "writes are tighter now" check would never notice.
    select count(*) into n from pg_policies
     where schemaname = 'public' and tablename = tbl
       and policyname = 'catalog_read_global' and cmd = 'SELECT';
    if n <> 1 then
      raise exception '% lost its global read policy', tbl;
    end if;

    -- CONTROL: a tenant read policy exists too, or a roaster can write a
    -- step it cannot then see.
    select count(*) into n from pg_policies
     where schemaname = 'public' and tablename = tbl
       and cmd = 'SELECT' and policyname <> 'catalog_read_global';
    if n < 1 then
      raise exception '% has no tenant read policy', tbl;
    end if;

    -- CONTROL: no write policy is left ungated. Counts ALL write policies,
    -- so one added without the key fails here rather than passing because
    -- the three gated ones exist.
    select count(*) into n from pg_policies
     where schemaname = 'public' and tablename = tbl
       and (cmd in ('INSERT', 'UPDATE', 'DELETE') or cmd = 'ALL')
       and coalesce(qual, '') || coalesce(with_check, '') not like '%equipment.manage_pricing%';
    if n <> 0 then
      raise exception '% has % write policies that do not name equipment.manage_pricing', tbl, n;
    end if;
  end loop;

  -- CONTROL: the key this leans on is real and held by someone. An
  -- unknown key is denied silently, so gating on a typo would lock the
  -- whole catalogue rather than fail loudly.
  select count(*) into n from public.role_permissions
   where permission_id = 'equipment.manage_pricing' and granted;
  if n < 1 then
    raise exception 'equipment.manage_pricing is granted to no role';
  end if;

  raise notice 'maintenance_template_step + _part writes now gate on equipment.manage_pricing';
end $$;

commit;
