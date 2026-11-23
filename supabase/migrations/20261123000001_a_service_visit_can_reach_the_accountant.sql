-- A completed service visit had nowhere to go.
--
-- `equipment_visit` is invoice-shaped already -- labor_subtotal,
-- parts_subtotal, trip_fee, tax_rate, discount_amount and a generated
-- grand_total -- and its status CHECK has admitted 'invoiced' since
-- 20260517000017. Nothing has ever set it, because there was no column
-- joining a visit to the order that bills it and no key saying who may do so.
-- So the tech filled in the money and the document stopped there.
--
-- WHAT THIS ADDS
--   1. equipment_visit.order_id -> orders(order_id). An invoice in STRATA is
--      an order; this is the join that lets a visit say which one bills it.
--   2. equipment.visit_invoice -- the key for "turn this visit into a draft
--      invoice". The owner's call, 2026-11-23: the TECH presses it and gets a
--      DRAFT; the accountant reviews and issues. So the tech holds this key
--      and still holds nothing on `orders.invoice_state`.
--   3. A truer label on equipment.manage_pricing, which has silently governed
--      maintenance template and program AUTHORING since 20260517000015 (see
--      the RLS note below) while calling itself a pricing key.
--
-- 🔴 NO COLUMN GRANT IS NEEDED FOR order_id, AND I CHECKED RATHER THAN ASSUMED.
-- A new column inherits no column-level privilege, but `authenticated` holds
-- TABLE-level INSERT/SELECT/UPDATE/DELETE on public.equipment_visit (unlike
-- public.customers, where UPDATE is granted column by column and a new column
-- is silently unwritable). Verified on prod 2026-11-23 against
-- information_schema.table_privileges. The verify block below asserts it, so
-- if that ever changes this migration fails loudly instead of shipping a
-- column the app cannot write.
--
-- 🔴 WHY THE TEMPLATE WORK NEEDS NO NEW KEY AND NO NEW POLICY.
-- maintenance_template, _step, _part, maintenance_program and
-- maintenance_program_template ALREADY carry full tenant write policies:
-- insert/update/delete scoped to `company_id in (select auth_company_ids())`
-- and gated on auth_has_permission('equipment.manage_pricing'), with the
-- global rows (company_id is null) readable but not writable. The frontend
-- must therefore gate template authoring on equipment.manage_pricing and
-- nothing else -- a button whose key is not the policy's key reads to the
-- operator as a mystery refusal.

begin;

-- ============================================================
-- 1. The join from a visit to the order that bills it
-- ============================================================
alter table public.equipment_visit
  add column if not exists order_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.equipment_visit'::regclass
       and conname  = 'equipment_visit_order_id_fkey'
  ) then
    alter table public.equipment_visit
      add constraint equipment_visit_order_id_fkey
      foreign key (order_id) references public.orders(order_id) on delete set null;
  end if;
end $$;

comment on column public.equipment_visit.order_id is
  'The draft/issued order that bills this visit. Set when a tech sends the visit to accounting; on delete set null so voiding an invoice returns the visit to ''completed'' rather than orphaning it.';

create index if not exists idx_equipment_visit_order_id
  on public.equipment_visit (order_id) where order_id is not null;

-- A visit may bill to at most one order. Two visits must never share one,
-- or "which visit did this invoice come from" has no answer.
create unique index if not exists uq_equipment_visit_order_id
  on public.equipment_visit (order_id) where order_id is not null;

-- ============================================================
-- 2. equipment.visit_invoice
-- ============================================================
insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order, default_deny_message)
values
  ('equipment.visit_invoice', 'equipment', 'Send a service visit to accounting',
   'Turn a completed service visit into a DRAFT invoice for the accountant to review and issue. Does not issue it, and does not change an invoice''s state.',
   true, 95,
   'You don''t have permission to send a visit to accounting. Ask an administrator, or ask your accountant to raise the invoice.')
on conflict (permission_id) do update
  set category    = excluded.category,
      label       = excluded.label,
      description = excluded.description,
      is_plan_gated = excluded.is_plan_gated,
      default_deny_message = excluded.default_deny_message,
      updated_at  = now();

-- The roles that actually attend equipment, plus the back office. Deliberately
-- NOT assistant_roaster / roastmaster / staff / sales_person: logging the work
-- you did is a different act from raising a bill for it.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'equipment.visit_invoice', true
from unnest(array[
  'company_admin','facility_admin','manager','roastery_manager',
  'equipment_tech','accounting_admin'
]) as r
on conflict (role_id, permission_id) do update set granted = true, updated_at = now();

-- Plan leg. Every other equipment.* key is enterprise + enterprise_plus; a
-- granted role under a denying plan is a silent no, so both legs must agree.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p, 'equipment.visit_invoice', true, 'equipment module is enterprise-only, matching every other equipment.* key'
from unnest(array['enterprise','enterprise_plus']) as p
on conflict (plan_id, permission_id) do update set granted = true, updated_at = now();

-- Named denies for the two lower plans, so the gate reads the same way the
-- rest of the module does instead of relying on an absent row.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p, 'equipment.visit_invoice', false, 'equipment module is enterprise-only'
from unnest(array['starter','pro']) as p
on conflict (plan_id, permission_id) do update set granted = false, updated_at = now();

-- ============================================================
-- 3. Say what equipment.manage_pricing really governs
-- ============================================================
update public.permissions
   set label       = 'Manage equipment catalog, pricing + PM templates',
       description = 'Create and edit labor rates, pricing defaults, the parts catalog, and this company''s own preventive-maintenance templates and programs. Distinct from per-task cost entry.',
       updated_at  = now()
 where permission_id = 'equipment.manage_pricing';

-- ============================================================
-- Verify. Every assertion below is something this file just made true, so
-- the block either passes or names exactly what did not land.
-- ============================================================
do $$
declare v_n int;
begin
  -- 1. the column and its FK exist
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='equipment_visit' and column_name='order_id'
  ) then
    raise exception 'equipment_visit.order_id was not created';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid='public.equipment_visit'::regclass and conname='equipment_visit_order_id_fkey'
  ) then
    raise exception 'equipment_visit.order_id has no foreign key to orders, so a deleted order would leave a dangling invoice link';
  end if;

  -- 2. 🔴 the app can actually WRITE the new column. A new column inherits no
  --    column-level privilege; this passes only because the grant here is
  --    table-level. If that ever changes, fail here rather than in the UI.
  if not exists (
    select 1 from information_schema.table_privileges
     where table_schema='public' and table_name='equipment_visit'
       and grantee='authenticated' and privilege_type='UPDATE'
  ) then
    raise exception 'authenticated has no table-level UPDATE on equipment_visit, so order_id needs an explicit column grant';
  end if;

  -- 3. the key is in the catalogue. A key absent from `permissions` is denied
  --    silently however the role rows read.
  if not exists (select 1 from public.permissions where permission_id='equipment.visit_invoice') then
    raise exception 'equipment.visit_invoice is missing from the permissions catalogue';
  end if;

  -- 4. both legs admit the same roles, or the gate never opens
  select count(*) into v_n from public.role_permissions
   where permission_id='equipment.visit_invoice' and granted;
  if v_n <> 6 then
    raise exception 'equipment.visit_invoice is granted to % roles, expected 6', v_n;
  end if;
  if not exists (
    select 1 from public.plan_permissions
     where permission_id='equipment.visit_invoice' and plan_id='enterprise_plus' and granted
  ) then
    raise exception 'equipment.visit_invoice is not granted on enterprise_plus; every live tenant would be denied by the plan leg';
  end if;

  -- 5. CONTROL: the roles that must NOT hold it. Without this, granting the
  --    key to everyone passes checks 3 and 4 just as well.
  select count(*) into v_n from public.role_permissions
   where permission_id='equipment.visit_invoice'
     and role_id in ('staff','sales_person','assistant_roaster','roastmaster','accounting_view')
     and granted;
  if v_n <> 0 then
    raise exception 'equipment.visit_invoice leaked to % role(s) that should not raise bills', v_n;
  end if;

  -- 6. CONTROL: the template policies this work depends on are still here and
  --    still name equipment.manage_pricing. The frontend gates on that key
  --    because these policies do; if they are ever renamed, the button opens
  --    onto a refusal.
  select count(*) into v_n from pg_policies
   where schemaname='public'
     and tablename in ('maintenance_template','maintenance_program')
     and qual like '%equipment.manage_pricing%';
  if v_n < 4 then
    raise exception 'expected the tenant write policies on maintenance_template/_program to gate on equipment.manage_pricing; found % ', v_n;
  end if;
end $$;

commit;
