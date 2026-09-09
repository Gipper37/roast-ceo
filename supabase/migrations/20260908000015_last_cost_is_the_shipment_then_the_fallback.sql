-- last_cost_unit is derived truth: the last shipment's landed cost, or the
-- roaster's stated cost when nothing has shipped. Restoring the second half.
--
-- Owner, 2026-09-08, settling the design: *"i thought last unit cost was the
-- truth. doesn't it just stamp the last cost from shipments or from fallback if
-- there's no shipments? it is not a manual override though. it is the fallback.
-- and last unit cost should only take it if there's no shipment."*
--
-- So the model is:
--     fallback_unit_cost  the roaster STATES this. It is the manual figure.
--     last_cost_unit      DERIVED. Latest received shipment's landed cost;
--                         the stated cost when there is no shipment.
--
-- 20260908000011 implemented exactly that and I panicked. Its backfill moved 8
-- consumables onto case prices — because on MCR the stated costs are wrong, not
-- because the rule was — and 20260908000014 responded by deleting the fallback
-- branch outright. That was an over-correction: it left last_cost_unit with
-- nothing to say for any consumable that has never had a delivery, which is
-- most of a new tenant's catalogue.
--
-- Owner, on being shown the case prices: *"i know that fallback costs are wrong
-- on a lot but that doesn't mean the code is wrong."* Correct. The branch comes
-- back. Fixing the stated costs is data work, and it is his.
--
-- What is KEPT from 20260908000014: the date gate (a delivery prices nothing
-- until it arrives) and the `is distinct from` guard, so a refresh that changes
-- nothing does not churn updated_at and wake every downstream trigger.
--
-- 🔴 NO BACKFILL IN THIS MIGRATION. 20260908000011's mass backfill over all 346
-- rows is what turned a wrong rule into 45 products showing impossible COGS.
-- The triggers keep every row correct from here; the existing rows correct
-- themselves the next time anything touches them. A sweep across live cost data
-- needs to be a decision, not a side effect of a function change.

begin;

create or replace function public.refresh_last_consumable_cost(
  p_item_id     text,
  p_facility_id text
)
returns numeric
language plpgsql
as $$
declare
  v_cost numeric;
begin
  -- 1. The last shipment that actually arrived.
  select cp.cost_unit::numeric + coalesce(sr.shipping_cost_unit, 0)
    into v_cost
    from public.consumable_inventory_purchased cp
    join public.shipment_received sr on sr.shipment_id = cp.shipment_id
   where cp.consumable_inventory_item = p_item_id
     and cp.facility_id               = p_facility_id
     and cp.cost_unit is not null
     and cp.cost_unit::text <> ''
     and cp.cost_unit::numeric > 0
     and coalesce(sr.voided, false) = false
     and sr.date_received is not null
   order by sr.date_received desc, cp.created_at desc
   limit 1;

  -- 2. Nothing has shipped: the roaster's stated cost. Facility-scoped — the
  --    same item at two sites can be bought on different terms.
  if v_cost is null then
    select nullif(fallback_unit_cost, 0) into v_cost
      from public.consumable_inventory
     where consumable_inventory_id = p_item_id
       and facility_id = p_facility_id;
  end if;

  if v_cost is null then return null; end if;

  update public.consumable_inventory
     set last_cost_unit = v_cost, updated_at = now()
   where consumable_inventory_id = p_item_id
     and facility_id = p_facility_id
     and last_cost_unit is distinct from v_cost;

  return v_cost;
end;
$$;

comment on function public.refresh_last_consumable_cost(text, text) is
  'last_cost_unit, derived: the landed cost of the most recent RECEIVED delivery, or consumable_inventory.fallback_unit_cost when nothing has shipped. Never a manual override — fallback_unit_cost is where a roaster states a cost.';

-- ─────────────────────────────────────────────────────────────────────────────
-- The same stated cost, read the same way, by the date-aware path.
--
-- Its fallback branch was `where consumable_inventory_id = p_consumable_id
-- limit 1` with no facility predicate, so a two-facility tenant got whichever
-- row the planner reached first. Everything else in this function is already
-- facility-scoped; this one line was not.
create or replace function public.get_consumable_cost_on_date(
  p_consumable_id text,
  p_facility_id   text,
  p_order_date    date
)
returns numeric
language sql
stable
as $$
  select coalesce(
    -- Priority 1: the latest delivery received ON OR BEFORE that date.
    (select cp.cost_unit + coalesce(sr.shipping_cost_unit, 0)
       from public.consumable_inventory_purchased cp
       join public.shipment_received sr on sr.shipment_id = cp.shipment_id
      where cp.consumable_inventory_item = p_consumable_id
        and cp.facility_id               = p_facility_id
        and cp.cost_unit is not null
        and cp.cost_unit                  > 0
        and coalesce(sr.voided, false) = false
        and sr.date_received is not null
        and sr.date_received <= p_order_date
      order by sr.date_received desc, cp.created_at desc
      limit 1),
    -- Priority 2: the order predates every delivery — use the earliest one
    -- rather than pretending the item was free.
    (select cp.cost_unit + coalesce(sr.shipping_cost_unit, 0)
       from public.consumable_inventory_purchased cp
       join public.shipment_received sr on sr.shipment_id = cp.shipment_id
      where cp.consumable_inventory_item = p_consumable_id
        and cp.facility_id               = p_facility_id
        and cp.cost_unit is not null
        and cp.cost_unit                  > 0
        and coalesce(sr.voided, false) = false
        and sr.date_received is not null
      order by sr.date_received asc, cp.created_at asc
      limit 1),
    -- Priority 3: nothing has ever shipped — the roaster's stated cost, from
    -- THIS facility.
    (select nullif(ci.fallback_unit_cost, 0)
       from public.consumable_inventory ci
      where ci.consumable_inventory_id = p_consumable_id
        and ci.facility_id             = p_facility_id
      limit 1)
  );
$$;

comment on function public.get_consumable_cost_on_date(text, text, date) is
  'What one unit of a consumable cost on a given date: the latest delivery received by then, else the earliest delivery, else the roaster''s stated fallback. Facility-scoped throughout — the fallback branch was not, so a two-facility tenant could read the other site''s number.';

commit;
