-- A roaster who tracks lots pins the LOT, not just the coffee.
--
-- Groundwork only. Nothing in the frontend may name a permission key or a
-- setting before it exists — an unknown key resolves to denied for every role,
-- silently — so the column, the setting and the key land here first.
--
-- ── WHY A LOT PIN AT ALL ───────────────────────────────────────────────
-- `coffee_inventory.active_coffee_source_id` names a COFFEE, never a lot, and
-- there is no lot-grain pointer anywhere in the schema. That was fine while the
-- only question was "which coffee", because lot choice inside a coffee is
-- already settled: _deduct_origin_fifo walks that coffee's lots oldest-received
-- first, and roast/page.tsx ranks them the same way for display.
--
-- It stops being fine the moment two lots of ONE coffee are in stock at once,
-- which is routine: a source can hold 8 live lots at MCR, 12 at Social Hour US.
-- "Pinned to Nicaragua Olomega" then does not say WHICH Olomega, so a switch
-- notice naming only the coffee is ambiguous exactly when it matters, and a
-- roaster who deliberately opened a particular bag has nowhere to record it.
--
-- The pin is therefore two columns, not one: the coffee, and optionally the lot
-- within it. A null lot means "whichever is oldest", which is today's behaviour
-- and stays the default.
--
-- ── WHY IT IS A SETTING ────────────────────────────────────────────────
-- Naming a lot is bookkeeping a roastery either does or does not do. Where it
-- is not done, a lot pin would only ever repeat what FIFO already decides, and
-- the switch notice would interrupt to announce a choice nobody made. Measured
-- on prod, the two are cleanly separated by whether receipts carry lot codes:
--   MCR                108 of 108 lots coded   (100%)
--   Social Hour US     118 of 123              (96%)
--   Social Hour UK       7 of 14               (50%)
--   demo                 2 of 109              (2%)
-- So the setting defaults OFF and is switched ON below only for facilities that
-- already code the majority of their receipts. That is a description of what
-- they are doing, not a new behaviour imposed on them.
--
-- ── WHY roast_shortfall.resolve ────────────────────────────────────────
-- `roast_lot_shortfall` has been written on every draw since 20260611000002 and
-- is read by NOTHING in the application: 2,889 rows across four tenants, 46,835
-- lb unmet, and not one row ever waived. A roast that could not find its green
-- is a real event — the count is behind, or a shipment was never recorded — and
-- saying so is the point of the ledger. Resolving one is an assertion that the
-- green was there after all, so it is a supervisor act and gets its own key
-- rather than riding on roast.log, which a bagger holds.

begin;

-- ── 1. The lot pin ─────────────────────────────────────────────────────
-- ON DELETE SET NULL for the same reason active_coffee_source_id has it: a lot
-- that goes away must not wedge the group, it must fall back to FIFO.
alter table public.coffee_inventory
  add column if not exists active_origin_purchase_id text
    references public.coffee_inventory_purchased(origin_purchase_id) on delete set null;

comment on column public.coffee_inventory.active_origin_purchase_id is
  'The exact lot loaded for this coffee group, when the facility tracks lots. '
  'NULL means "the oldest received lot of the pinned coffee", which is what '
  '_deduct_origin_fifo does anyway. Only meaningful alongside '
  'active_coffee_source_id: a lot pin naming a lot of some OTHER coffee is a '
  'contradiction, and the check below refuses it.';

-- A lot pin that belongs to a different coffee than the coffee pin is not a
-- state anything could act on. Refuse it in the database rather than teaching
-- every reader to second-guess the pair.
create or replace function public.coffee_inventory_lot_pin_matches_source()
returns trigger
language plpgsql
as $fn$
declare v_src text;
begin
  if new.active_origin_purchase_id is null then return new; end if;
  select cip.coffee_source_id into v_src
    from public.coffee_inventory_purchased cip
   where cip.origin_purchase_id = new.active_origin_purchase_id;
  if v_src is distinct from new.active_coffee_source_id then
    raise exception 'That lot belongs to a different coffee than the one loaded for this group.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_coffee_inventory_lot_pin on public.coffee_inventory;
create trigger trg_coffee_inventory_lot_pin
  before insert or update of active_origin_purchase_id, active_coffee_source_id
  on public.coffee_inventory
  for each row execute function public.coffee_inventory_lot_pin_matches_source();

-- ── 2. The setting ─────────────────────────────────────────────────────
-- Boolean parameters carry their value in text_value as 'on'/'off' — the shape
-- smartroast_enabled, require_coffee_source and bin_card_autoprint already use.
insert into public.standard_parameters (parameters_id, parameter, amount, text_value, data_type)
values ('lot_tracking', 'Track green coffee by lot', null, 'off', 'boolean')
on conflict (parameters_id) do update
  set parameter = excluded.parameter, data_type = excluded.data_type;

-- Switched on for facilities that already code the majority of their receipts.
-- Reading the behaviour off the data rather than asking a question whose answer
-- is already written down.
insert into public.company_parameters (company_id, facility_id, parameter_id, value, display_name)
select x.company_id, x.facility_id, 'lot_tracking', 'on', 'Track green coffee by lot'
  from (
    select cip.company_id, cip.facility_id,
           count(*) lots,
           count(*) filter (where cip.lot_id is not null and btrim(cip.lot_id) <> '') coded
      from public.coffee_inventory_purchased cip
     where cip.facility_id is not null
     group by 1, 2
  ) x
 where x.lots > 0
   and x.coded::numeric / x.lots >= 0.80
   and not exists (
     select 1 from public.company_parameters cp
      where cp.parameter_id = 'lot_tracking'
        and cp.facility_id = x.facility_id);

-- ── 3. Resolving a shortfall is a supervisor act ───────────────────────
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values ('roast_shortfall.resolve', 'Roasting', 'Resolve a green shortfall',
        'Clear a roast''s record of green it could not find, once the receipt or count that explains it has been entered.',
        false, 95)
on conflict (permission_id) do update
  set category = excluded.category, label = excluded.label, description = excluded.description;

-- Who may say the green was there after all. Deliberately NOT staff or
-- assistant_roaster: the people who record counts are not the people who
-- overrule them.
insert into public.role_permissions (role_id, permission_id, granted)
select r, 'roast_shortfall.resolve', true
  from (values ('company_admin'), ('facility_admin'), ('manager'), ('roastery_manager'), ('roastmaster')) as t(r)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- Not plan-gated, so no plan_permissions rows: a roastery on any plan that can
-- log a roast can be told its green did not add up, and can say why.

-- ── 4. The one dangling pin on prod ────────────────────────────────────
-- A pin survives its coffee leaving the group: nothing clears it when a source
-- is re-homed or a borrow is withdrawn, and the readers silently ignored a pin
-- they could not find rather than repairing it. Exactly one such row exists
-- across every tenant — MCR's Chocolate, still pointing at a Honduras that
-- moved to Fruit on 2026-06-26. Null it and let FIFO answer; the next charge in
-- that group writes the real answer.
--
-- This moves a POINTER. It deducts nothing and re-attributes nothing.
update public.coffee_inventory ci
   set active_coffee_source_id = null
  from public.coffee_source cs
 where cs.coffee_source_id = ci.active_coffee_source_id
   and cs.origin_id is distinct from ci.origin_id
   and not (ci.origin_id = any(coalesce(cs.allowed_origin_ids, '{}')));

do $verify$
declare v_bad int; v_on int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='coffee_inventory'
                    and column_name='active_origin_purchase_id') then
    raise exception 'the lot pin column is missing';
  end if;

  if not exists (select 1 from public.permissions where permission_id='roast_shortfall.resolve') then
    raise exception 'roast_shortfall.resolve is missing from permissions';
  end if;

  -- A key nobody holds is denied for everybody, silently. That is the failure
  -- this project has shipped twice; assert against it rather than trusting the
  -- insert above.
  select count(*) into v_bad from public.role_permissions
   where permission_id='roast_shortfall.resolve' and granted;
  if v_bad = 0 then raise exception 'roast_shortfall.resolve is granted to no role'; end if;

  -- Nobody who merely records counts may overrule them.
  if exists (select 1 from public.role_permissions
              where permission_id='roast_shortfall.resolve' and granted
                and role_id in ('staff','assistant_roaster','sales_person','accounting_view')) then
    raise exception 'roast_shortfall.resolve reached a role that only records counts';
  end if;

  -- No pin may name a coffee that is not in its group.
  select count(*) into v_bad
    from public.coffee_inventory ci
    join public.coffee_source cs on cs.coffee_source_id = ci.active_coffee_source_id
   where cs.origin_id is distinct from ci.origin_id
     and not (ci.origin_id = any(coalesce(cs.allowed_origin_ids, '{}')));
  if v_bad > 0 then raise exception '% pin(s) still name a coffee outside their group', v_bad; end if;

  -- And no lot pin may name a lot of a different coffee.
  select count(*) into v_bad
    from public.coffee_inventory ci
    join public.coffee_inventory_purchased cip
      on cip.origin_purchase_id = ci.active_origin_purchase_id
   where cip.coffee_source_id is distinct from ci.active_coffee_source_id;
  if v_bad > 0 then raise exception '% lot pin(s) name a lot of another coffee', v_bad; end if;

  select count(*) into v_on from public.company_parameters where parameter_id='lot_tracking';
  raise notice 'lot_tracking switched on for % facility(ies)', v_on;
end;
$verify$;

commit;
