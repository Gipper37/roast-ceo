-- A case may hold different items.
--
-- Owner: "we need to be able to add a case of different items. is that
-- possible in the case set up to make an adjustment to it to make it happen."
--
-- It is not possible in the case set up, and it cannot be. A case here is a
-- SIZE (size.base_size_id + size.units_per_case), and a size is SHARED across
-- products: "2lb (Case of 12)" is twelve of the 2lb size on every product that
-- uses it. A shared row can never say what is inside one roaster's box. So the
-- size stays what it is, and the CONTENTS hang off the product variant.
--
-- 🔴 AND THE CONTENTS MUST BE EXPLODED IN THE DATABASE, NOT IN THE APP.
-- order_details is written from TWELVE places: the orders screen, shop
-- checkout, the Shopify webhook and importer, standing orders, VMI, estimates
-- and the QuickBooks import. A box ordered through the shop has to deduct the
-- same stock as one typed by hand, so the explosion is a trigger. Every one of
-- those callers then gets it for free and none of them needs to know.
--
-- Owner asked the question that settles the shape: "wouldn't the products that
-- are in it pull the right usage out". They would not, on their own. Every
-- usage path joins the ORDER LINE's single product_id:
--   calculate_current_stock_consumables: BOM usage joins
--     product_consumables_effective ON od.product_id, and resold usage joins
--     products ON od.product_id
--   roast demand reads the line's product -> its recipe
--   allocate_line_from_stock looks for pack runs on the line's own product_id
-- So one line for a mixed box deducts the box's own bag and label and nothing
-- else: no coffee, no roast demand, no bag draw. Giving each content its own
-- line makes all three correct with no change to any of them.
--
-- HOW THE MONEY STAYS RIGHT. Component lines carry amount_override = 0, which
-- handle_order_detail_logic honours ahead of the catalogue price, so they
-- price at zero and skip the customer-discount block. update_order_aggregates
-- sums total_price, so the order total is the box's price and nothing is
-- counted twice. The box's own cost stays its own packaging (it has no recipe
-- and no source_consumable_id, so update_product_total_cogs gives it the
-- product_consumables total), and each content carries its own cost on its own
-- line. Nothing needed changing in the COGS engine.
--
-- 🔴 THE BOX MUST WEIGH NOTHING. update_order_aggregates also sums
-- roasted_weight into orders.total_weight, and handle_order_detail_logic sets
-- a line's roasted_weight from its product's weight_lbs. The coffee's weight
-- arrives on the component lines, so a box whose own size carries a weight
-- would add that weight a second time. The guard below refuses a bundle
-- variant whose size has a weight.

begin;

-- ── 1. The type ────────────────────────────────────────────────────────
-- Global (company_id null), like every other real type. A bundle is its own
-- type and not a flavour of coffee, because update_product_total_cogs branches
-- on the type's NAME (COALESCE(pt.product_type,'Coffee') = 'Coffee') and a
-- bundle must take the non-coffee arm: its cost is packaging, not green.
insert into public.product_type (product_type_id, product_type, is_active, company_id)
values ('ptype_bundle', 'Bundle', true, null)
on conflict (product_type_id) do update
  set product_type = excluded.product_type,
      is_active    = true;

-- ── 2. What is in the box ──────────────────────────────────────────────
-- Parent and child are both VARIANTS (products rows), because what you put in
-- a box is a particular size in a particular channel, not an abstract product.
create table if not exists public.product_components (
  product_component_id text primary key default gen_random_uuid()::text,
  company_id           text not null,
  facility_id          text,
  parent_product_id    text not null references public.products(product_id) on delete cascade,
  -- restrict, not cascade: deleting a coffee that is inside somebody's box
  -- should fail loudly rather than quietly empty the box.
  child_product_id     text not null references public.products(product_id) on delete restrict,
  quantity             numeric not null check (quantity > 0),
  sort_order           integer not null default 0,
  created_at           timestamptz not null default now(),
  created_by           text,
  updated_at           timestamptz not null default now(),
  updated_by           text,
  constraint product_components_unique_child unique (parent_product_id, child_product_id),
  constraint product_components_not_itself  check (parent_product_id <> child_product_id)
);

create index if not exists product_components_parent_idx on public.product_components (parent_product_id);
create index if not exists product_components_child_idx  on public.product_components (child_product_id);
create index if not exists product_components_company_idx on public.product_components (company_id);

alter table public.product_components enable row level security;

create policy product_components_read on public.product_components
  for select using (company_id in (select auth_company_ids()));

create policy product_components_insert on public.product_components
  for insert with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('product.bundle_manage', company_id)
  );

create policy product_components_update on public.product_components
  for update using (
    company_id in (select auth_company_ids())
    and auth_has_permission('product.bundle_manage', company_id)
  ) with check (
    company_id in (select auth_company_ids())
    and auth_has_permission('product.bundle_manage', company_id)
  );

create policy product_components_delete on public.product_components
  for delete using (
    company_id in (select auth_company_ids())
    and auth_has_permission('product.bundle_manage', company_id)
  );

revoke all on public.product_components from public, anon;
grant select, insert, update, delete on public.product_components to authenticated;

-- ── 3. The permission ──────────────────────────────────────────────────
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values ('product.bundle_manage', 'Products', 'Build mixed cases',
        'Choose what goes inside a mixed case and how many of each.', false, 50)
on conflict (permission_id) do update
  set category = excluded.category,
      label    = excluded.label,
      description = excluded.description,
      sort_order  = excluded.sort_order;

-- The same six roles that may create a product. Deciding what goes in a box is
-- the same job as deciding what a product is.
insert into public.role_permissions (role_id, permission_id, granted, updated_by)
select r.role_id, 'product.bundle_manage', true, 'migration:20261112000002'
  from (values ('company_admin'),('facility_admin'),('accounting_admin'),
               ('manager'),('roastery_manager'),('roastmaster')) as r(role_id)
on conflict (role_id, permission_id) do update
  set granted = true, deny_message = null,
      updated_at = now(), updated_by = 'migration:20261112000002';

-- The key is not plan-gated, so these rows are not consulted today. They are
-- written anyway: a plan-gated key missing a plan row denies that plan
-- SILENTLY, so if anyone ever flips is_plan_gated this cannot strand a tenant.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, 'product.bundle_manage', true,
       'Mixed cases: every plan, same as creating a product'
  from public.subscription_plans p
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted,
      updated_reason = excluded.updated_reason,
      updated_at = now();

-- ── 4. The line that says "I came out of that box" ─────────────────────
-- Null on every line that exists today and on every ordinary line forever
-- after, so every existing reader is untouched until a box is actually sold.
-- ON DELETE CASCADE: removing the box removes what came out of it, and on a
-- posted invoice guard_posted_order_detail_immutable refuses the delete first.
alter table public.order_details
  add column if not exists parent_order_detail_id text
    references public.order_details(order_detail_id) on delete cascade;

create index if not exists order_details_parent_idx
  on public.order_details (parent_order_detail_id)
  where parent_order_detail_id is not null;

comment on column public.order_details.parent_order_detail_id is
  'Set when this line is a component of a mixed case. The parent line carries the price and the customer sees it; this line carries the stock, the roast demand and its own cost at zero price.';

-- ── 5. What a box may contain ──────────────────────────────────────────
create or replace function public.guard_product_component()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_parent record;
  v_child  record;
  v_weight numeric;
begin
  select p.product_id, p.company_id, p.product_type, p.size
    into v_parent from public.products p where p.product_id = NEW.parent_product_id;
  select p.product_id, p.company_id, p.product_type
    into v_child  from public.products p where p.product_id = NEW.child_product_id;

  if v_parent.product_id is null then
    raise exception 'no such product %', NEW.parent_product_id;
  end if;
  if v_child.product_id is null then
    raise exception 'no such product %', NEW.child_product_id;
  end if;
  if v_parent.company_id is distinct from v_child.company_id then
    raise exception 'a box and its contents must belong to the same company';
  end if;
  if NEW.company_id is distinct from v_parent.company_id then
    raise exception 'product_components.company_id must be the box''s company';
  end if;

  -- One level only. The order-line explosion stops at the children it writes,
  -- so a box inside a box would ship with its own contents never exploded --
  -- stock silently short by everything in the inner box. Refuse it outright
  -- rather than half-support it.
  if v_child.product_type = 'ptype_bundle' then
    raise exception 'a mixed case cannot contain another mixed case';
  end if;
  if exists (select 1 from public.product_components c
              where c.parent_product_id = NEW.child_product_id) then
    raise exception 'a mixed case cannot contain another mixed case';
  end if;

  -- The box must weigh nothing of its own: orders.total_weight sums every
  -- line's roasted_weight, and the coffee's weight arrives on the contents.
  select s.weight into v_weight from public.size s where s.size_id = v_parent.size;
  if coalesce(v_weight, 0) <> 0 then
    raise exception 'a mixed case must use a size with no weight (size % carries % lbs); the weight comes from its contents', v_parent.size, v_weight;
  end if;

  return NEW;
end
$fn$;

drop trigger if exists trg_guard_product_component on public.product_components;
create trigger trg_guard_product_component
  before insert or update on public.product_components
  for each row execute function public.guard_product_component();

-- ── 6. The explosion ───────────────────────────────────────────────────
-- SECURITY DEFINER because the component lines must be written for every
-- caller that could write the parent line, including the shop checkout running
-- as a customer with no product permissions at all. It writes nothing the
-- parent line did not already establish: order_id, company_id and facility_id
-- are copied from NEW, so it cannot reach another tenant.
create or replace function public.explode_bundle_order_line(p_order_detail_id text)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_line  record;
  r       record;
  v_n     integer := 0;
begin
  select * into v_line from public.order_details where order_detail_id = p_order_detail_id;
  if v_line.order_detail_id is null then return 0; end if;
  -- never explode a component line: that is what would recurse
  if v_line.parent_order_detail_id is not null then return 0; end if;

  for r in
    select pc.child_product_id, pc.quantity
      from public.product_components pc
     where pc.parent_product_id = v_line.product_id
     order by pc.sort_order, pc.child_product_id
  loop
    insert into public.order_details (
      order_detail_id, order_id, product_id, quantity, item_status,
      company_id, facility_id, coffee_prep,
      amount_override, parent_order_detail_id
    ) values (
      gen_random_uuid()::text, v_line.order_id, r.child_product_id,
      coalesce(v_line.quantity, 0) * r.quantity, v_line.item_status,
      v_line.company_id, v_line.facility_id, v_line.coffee_prep,
      -- 0, not null: handle_order_detail_logic takes an override ahead of the
      -- catalogue price, so this is what holds the line at zero and keeps the
      -- customer discount off it. The box carries the price.
      0, v_line.order_detail_id
    );
    v_n := v_n + 1;
  end loop;

  return v_n;
end
$fn$;

revoke all on function public.explode_bundle_order_line(text) from public, anon;

create or replace function public.trg_explode_bundle_order_line()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.parent_order_detail_id is not null then
    return null;
  end if;

  if TG_OP = 'UPDATE' then
    -- quantity, product or status moved: rebuild rather than patch, so a
    -- changed product cannot leave the previous box's contents behind.
    if NEW.quantity   is not distinct from OLD.quantity
   and NEW.product_id is not distinct from OLD.product_id
   and NEW.item_status is not distinct from OLD.item_status then
      return null;
    end if;
    if NEW.item_status is distinct from OLD.item_status
   and NEW.quantity   is not distinct from OLD.quantity
   and NEW.product_id is not distinct from OLD.product_id then
      update public.order_details
         set item_status = NEW.item_status
       where parent_order_detail_id = NEW.order_detail_id;
      return null;
    end if;
    delete from public.order_details where parent_order_detail_id = NEW.order_detail_id;
  end if;

  perform public.explode_bundle_order_line(NEW.order_detail_id);
  return null;
end
$fn$;

drop trigger if exists trg_explode_bundle_ins on public.order_details;
create trigger trg_explode_bundle_ins
  after insert on public.order_details
  for each row execute function public.trg_explode_bundle_order_line();

drop trigger if exists trg_explode_bundle_upd on public.order_details;
create trigger trg_explode_bundle_upd
  after update of quantity, product_id, item_status on public.order_details
  for each row execute function public.trg_explode_bundle_order_line();

commit;
