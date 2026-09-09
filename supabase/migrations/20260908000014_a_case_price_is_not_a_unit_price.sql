-- Undoing damage I did to prod an hour ago.
--
-- 20260908000011 was right that an unreceived delivery must not price an item.
-- It was wrong about what to do INSTEAD. When no received delivery exists it
-- overwrote last_cost_unit with consumable_inventory.fallback_unit_cost — and
-- on MCR that column does not hold a per-unit price. It holds CASE prices:
-- 846.00 for 8lbs of lavender flavour, 628.00 for a 25lb box of vanilla,
-- 85.00 for a roll of labels.
--
-- The backfill therefore moved 8 consumables from a real per-unit figure to a
-- case price:
--     16oz Hula Label - Black        0.163   -> 85.00
--     Mama's Organic Label           0.163   -> 85.00
--     16oz Nicky Beans Kona Label    0.167   -> 85.00
--     8oz Hula Label - Black         0.163   -> 85.00
--     Oval Wholebean / Oval Ground   0.09414 -> 70.00
--     Highland Grogg                 23.35   -> 465.15
--     LAVENDAR FALVOR                40.665  -> 143.15
-- and Kona Blend Dark - 1lb - Wholesale went to COGS 92.77 on a 15.50 price.
-- (Three rows in the same run were genuine repairs and stay: Guittard White
-- Choc 216.56->32.94, Guittard Sweet Ground 139.375->20.00, Cafiza 77.60->15.00.)
--
-- ── WHY fallback_unit_cost IS FULL OF CASE PRICES ───────────────────────────
-- Not rot for its own sake. The only screen that lets a roaster type a
-- consumable's unit cost — Cost Center's "Unit Cost" cell,
-- stratos/app/app/(app)/cost-center/actions.ts updateConsumableUnitCost —
-- writes last_cost_unit, NOT fallback_unit_cost. So the per-unit numbers the
-- roaster has been typing for months live in the cache, and whatever is in
-- fallback_unit_cost arrived by some other route. Repointing that screen is the
-- real repair and it is a frontend change; it is NOT smuggled into this
-- migration, which exists to put prod back.
--
-- ── THE RULE THIS ESTABLISHES ───────────────────────────────────────────────
-- A derived cache may not INVENT a number. If there is no received delivery to
-- compute a landed cost from, refresh_last_consumable_cost now leaves the
-- existing value alone rather than substituting a figure from a column that was
-- never verified to mean the same thing. Overwriting good data with a guess is
-- worse than leaving a stale number, because the stale one is at least the
-- number somebody entered on purpose.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Stop it happening again.
create or replace function public.refresh_last_consumable_cost(
  p_item_id     text,
  p_facility_id text
)
returns numeric
language plpgsql
as $$
declare
  v_latest_cost numeric;
begin
  -- Landed cost of the most recent RECEIVED delivery. The date gate stays:
  -- coffee that has not landed cannot be what a bag costs today.
  select cp.cost_unit::numeric + coalesce(sr.shipping_cost_unit, 0)
    into v_latest_cost
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

  -- 🔴 NO FALLBACK SUBSTITUTION. Nothing received means this function has
  -- nothing to say, and saying nothing is the correct answer. It previously
  -- reached for fallback_unit_cost here, which on real data is a case price.
  if v_latest_cost is null then
    return null;
  end if;

  update public.consumable_inventory
     set last_cost_unit = v_latest_cost, updated_at = now()
   where consumable_inventory_id = p_item_id
     and facility_id = p_facility_id
     and last_cost_unit is distinct from v_latest_cost;   -- no pointless writes

  return v_latest_cost;
end;
$$;

comment on function public.refresh_last_consumable_cost(text, text) is
  'Recompute last_cost_unit from the most recent RECEIVED delivery (unit price + per-unit shipping). Returns null and writes NOTHING when no delivery has been received — a derived cache must not invent a number, and fallback_unit_cost is not a per-unit price on real tenants.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Put the 8 back.
--
-- Deterministic: the pre-backfill value was the old rule's answer — the landed
-- cost of the most recent purchase regardless of whether it had been received.
-- Scoped to rows that currently equal fallback_unit_cost (the signature of the
-- bad substitution) and that have a purchase to recompute from, so the three
-- genuine repairs above are not undone.
update public.consumable_inventory ci
   set last_cost_unit = sub.old_value, updated_at = now()
  from (
    select ci2.consumable_inventory_id id, ci2.facility_id fac,
           (select cp.cost_unit + coalesce(sr.shipping_cost_unit, 0)
              from public.consumable_inventory_purchased cp
              left join public.shipment_received sr on sr.shipment_id = cp.shipment_id
             where cp.consumable_inventory_item = ci2.consumable_inventory_id
               and cp.facility_id = ci2.facility_id
               and coalesce(cp.cost_unit, 0) > 0
               and coalesce(sr.voided, false) = false
             order by sr.date_received desc nulls last, cp.created_at desc
             limit 1) as old_value
      from public.consumable_inventory ci2
     where ci2.last_cost_unit is not distinct from ci2.fallback_unit_cost
       and not exists (
         select 1 from public.consumable_inventory_purchased cp
           join public.shipment_received sr on sr.shipment_id = cp.shipment_id
          where cp.consumable_inventory_item = ci2.consumable_inventory_id
            and cp.facility_id = ci2.facility_id
            and coalesce(cp.cost_unit, 0) > 0
            and coalesce(sr.voided, false) = false
            and sr.date_received is not null)
  ) sub
 where ci.consumable_inventory_id = sub.id
   and ci.facility_id is not distinct from sub.fac
   and sub.old_value is not null
   and ci.last_cost_unit is distinct from sub.old_value;

commit;
