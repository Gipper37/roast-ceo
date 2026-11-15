-- A box costs what it takes to pack it, and what is in it.
--
-- Owner, 2026-11-14: *"all that needed to be added was the selection of a
-- consumable inventory item (the carton) as the carton. that inventory item
-- will have its own cost as all items do."*
--
-- He was right, and my first pass at this migration got the shape of it wrong
-- twice over. Both corrections are the reason this file looks the way it does.
--
-- 🔴 WHAT WAS ACTUALLY BROKEN: ONE ARM OF ONE TRIGGER.
--
-- `update_product_total_cogs` branches on the product type's NAME
-- (`v_is_coffee := COALESCE(v_kind,'Coffee') = 'Coffee'`). `ptype_bundle`'s
-- name is 'Bundle', so a box took the ELSE arm, which hardcodes
-- `v_consumable_cost_total := 0` and writes both cost columns NULL. A $48 box
-- with a $4.25 carton read COGS $0.00, gross profit $48.00, COGS% 0.0% -- in
-- green, directly above a Consumables table printing that carton at $4.25.
--
-- That zero did not stay on a screen. `handle_order_detail_logic` reads
-- `COALESCE(p.total_unit_cogs, 0)` and writes
-- `unit_cost_at_sale := quantity * v_cogs`, so the box's order line was BORN at
-- cost 0. And it changed later on its own: `get_product_cogs_on_date` and
-- `product_cogs_for_keys` have no type branch and both already returned the BOM
-- cost for the same box, so `recost_orders_for_consumable_purchases` -- fired by
-- `shipment_received` -- rewrote that line the moment the next carton arrived.
-- Nobody had to touch the box. The new arm makes the trigger agree with the two
-- dated engines, which is the whole of the stored-cost fix.
--
-- 🔴 AND `total_unit_cogs` MUST STAY THE CARTON ALONE. This is the correction.
--
-- A mixed case is sold as ONE line and costed as SEVERAL:
-- `trg_explode_bundle_order_line` writes a child `order_details` row per item
-- inside, with the real quantity, `parent_order_detail_id` set and price 0, and
-- `handle_order_detail_logic` stamps each child with its OWN product's cost. So
-- the coffee in the box is already costed, on the lines that hold it.
--
-- Measured on staging: one box sold writes revenue 48 / cost 0 on the parent
-- and revenue 0 / cost 6.166 on its child. Putting the contents into
-- `products.total_unit_cogs` as well took the same box from 7.068 to 13.234 and
-- `customer_profitability` from 82.4% margin to 71.9% -- a 10.5-point lie on the
-- screen you would use to decide whether to keep an account. NOT ONE of the 186
-- relations in this database mentions `parent_order_detail_id`, so nothing
-- anywhere filters the children out. This is also Shopify's model: price on the
-- parent, cost and stock on the components, "sales reporting at the component
-- level".
--
-- 🔴 SO THE BOX'S TRUE COST IS A READ, NOT A COLUMN: `product_bundle_costs`.
--
-- Carton + SUM(child cost x quantity), derived on read, exactly as
-- `lib/shop/shipWeight.ts` derives a box's weight and for the same reason -- a
-- stored figure goes stale the moment a child's cost moves, and nothing fires a
-- trigger on the parent when a child changes. One join, no recursion:
-- `guard_product_component` already refuses a box inside a box in all three
-- directions.
--
-- The product screens, the cost centre and the target-COGS price back-solver
-- read that view. The order path reads the column and is untouched.
--
-- 🔴 WHY `product_margins` AND NOT `data_quality_issues`: nothing reads
-- `data_quality_issues`. Grepped: its only references in the app are the two
-- generated type files. The Data Health page reads `product_margins` and
-- `order_details` directly. An earlier draft of this migration taught the
-- unread view to flag a zero-cost box and reported the row count as a result;
-- it was dead code. `product_margins` is the one the cost centre actually
-- opens, and correcting the total there makes `data_quality_issues` right as a
-- side effect, since it reads `product_margins`.
--
-- 🔴 AND IT CANNOT SHIP WITHOUT THE VIEW. `unitPriceForTargetCogs` bails at
-- `cogs <= 0`, so a box's "price for a target COGS%" box is inert today only
-- because the cost is zero. The trigger arm alone would switch it on with the
-- carton as the whole cost: at a $0.902 carton and a 40% target it would
-- propose $2.26 for a box that sells at $48 and holds $6.17 of coffee.
--
-- 🔴 THE TRIGGER BODY BELOW IS THE DEPLOYED ONE, TAKEN FROM pg_proc AND EDITED
-- AT FOUR ANCHORS. CREATE OR REPLACE rewrites the whole function, so none of it
-- was retyped: the declaration, the flag, the cost arm and the two stored
-- columns are the only changes, and 20261026000001's case-price reasoning is
-- carried through verbatim.
--
-- Not in this migration, and still open: `trg_product_cogs_touch` is
-- `AFTER UPDATE OF total_unit_cogs` and nothing ever names that column in a SET
-- list, so `product_cogs_recompute_queue` is never filled by a cost change --
-- for every product type, not just boxes. Recorded, deliberately out of scope.
begin;

-- A trigger function on `products` and one reporting view. Neither rewrites a
-- row, but both take a lock worth bounding.
set local lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.update_product_total_cogs()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_coffee_cost_total     numeric := 0;
    v_consumable_cost_total numeric := 0;
    v_weight                numeric;
    v_total_cogs            numeric;
    v_gross_profit          numeric;
    v_cogs_pct              numeric;
    v_margin_pct            numeric;
    v_kind                  text;
    v_is_coffee             boolean;
    v_is_bundle             boolean;
    v_units                 numeric := 1;
    v_case_price            numeric;
BEGIN
    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = false THEN
        RETURN NEW;
    END IF;

    SELECT s.weight INTO v_weight
    FROM public.size s
    WHERE s.size_id = NEW.size
    LIMIT 1;

    IF v_weight IS NOT NULL THEN
        NEW.weight_lbs := v_weight;
    END IF;

    -- How many selling units a case holds, 1 for anything that is not a case.
    -- weight_lbs above stays the CASE total, so the coffee term is untouched.
    SELECT COALESCE(s.units_per_case, 1) INTO v_units
    FROM public.size s WHERE s.size_id = NEW.size LIMIT 1;
    v_units := COALESCE(v_units, 1);

    SELECT pt.product_type INTO v_kind
    FROM public.product_type pt
    WHERE pt.product_type_id = NEW.product_type;
    v_is_coffee := (COALESCE(v_kind, 'Coffee') = 'Coffee');
    -- 🔴 THE ID, NOT THE NAME. v_is_coffee above reads product_type.product_type
    -- and that column is tenant-editable -- MCR carries 'Wholesale Retail',
    -- 'Retail DTC', 'Wholesale Bulk' and 'Sample' alongside the globals. A box
    -- is identified by the row that cannot be renamed.
    v_is_bundle := (NEW.product_type = 'ptype_bundle');

    IF v_is_coffee THEN
        -- ▼ lot-precise cached roasted cost, fall back to group latest_cost ▼
        SELECT COALESCE(SUM(COALESCE(ci.latest_roasted_cost, ci.latest_cost) * rc.percentage), 0)
        INTO v_coffee_cost_total
        FROM public.recipe_effective_green(NEW.recipe_id) rc
        JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
        WHERE ci.facility_id = NEW.facility_id;

        SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
        INTO v_consumable_cost_total
        FROM public.product_consumables_effective pc
        JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
        WHERE pc.product_id  = NEW.product_id
          AND ci.facility_id = NEW.facility_id;

        v_total_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;
    ELSIF v_is_bundle THEN
        -- A MIXED CASE COSTS WHAT IT TAKES TO PACK IT, AND NOTHING ELSE.
        --
        -- Owner, 2026-11-14: *"you should be able to add the box as a bom cuz
        -- that is part of building the product."* The carton, its label and any
        -- filler are the box's whole cost. Asked which of the two live inputs
        -- is the cost -- the BOM or the hand-entered products.unit_cost -- he
        -- chose the BOM, so `unit_cost` is deliberately NOT read here.
        --
        -- 🔴 THE CONTENTS ARE NOT IN THIS NUMBER, and must never be. Selling a
        -- box writes one order line per bag inside it (explode_bundle_order_line)
        -- and each of those carries its own unit_cost_at_sale. Adding the
        -- contents here would charge the same coffee twice on one order.
        --
        -- 🔴 NO `* v_units`. product_consumables_effective has already applied
        -- the pack count: quantity * CASE WHEN per_case THEN 1 ELSE
        -- COALESCE(units_per_case, 1) END. Multiplying again is the exact bug
        -- 20261026000001 was written to undo, one level further in.
        SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
        INTO v_consumable_cost_total
        FROM public.product_consumables_effective pc
        JOIN public.consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
        WHERE pc.product_id  = NEW.product_id
          AND ci.facility_id = NEW.facility_id;

        v_coffee_cost_total := 0;
        v_total_cogs        := v_consumable_cost_total;
    ELSE
        IF NEW.source_consumable_id IS NOT NULL THEN
            SELECT ci.last_cost_unit INTO NEW.unit_cost
            FROM public.consumable_inventory ci
            WHERE ci.consumable_inventory_id = NEW.source_consumable_id
              AND ci.facility_id = NEW.facility_id;
        END IF;
        v_coffee_cost_total     := 0;
        v_consumable_cost_total := 0;
        v_total_cogs            := COALESCE(NEW.unit_cost, 0) * v_units;
    END IF;

    -- 🔴 price is the price of THE THING BEING SOLD, and for a case row that
    -- IS the case. It is not a per-unit price to be multiplied up.
    --
    -- This read `* v_units` on the premise that "price is PER SELLING UNIT".
    -- That premise is false for a case, and prod says so three ways:
    --   order_details: "Maui Blend - 2oz (Case of 40)" sold quantity 1 at
    --     unit_price_at_sale 105.46 for total_price 105.46, and
    --     products.price on that variant is also 105.46. One case, one price.
    --   arithmetic: the Costco 2lb case of 12 is 24 lb at price 260.08, which
    --     is $10.84/lb wholesale. Multiplied by 12 it reads $3,120.96, or
    --     $130/lb, against a COGS of $5.52/lb.
    --   the screen: the case form tells the roaster "the case is the thing a
    --     customer buys and the thing you ship, so its weight and its price are
    --     the case total", and then the number underneath disagreed with it.
    --
    -- What it cost: every case product reported a gross profit and a COGS% off
    -- by the pack count. Costco Maui Blend showed 4.2% COGS where the truth is
    -- 51.0%, and Ka'u showed 9.1% where the truth is 90.7%. A roaster pricing
    -- off that screen would have read a 90% margin on a job that barely covers
    -- its coffee.
    --
    -- It was latent from 20261002000002 and harmless while units_per_case was
    -- NULL everywhere, because COALESCE made v_units 1. Step 2 set the pack
    -- counts on 2026-10-04 and turned it live. That is the shape of a two-step
    -- migration: step 1 can be provably inert and still be wrong.
    v_case_price   := COALESCE(NEW.price, 0);
    v_gross_profit := v_case_price - v_total_cogs;
    v_cogs_pct     := CASE WHEN v_case_price > 0
                           THEN ROUND(v_total_cogs / v_case_price * 100, 1) ELSE NULL END;
    v_margin_pct   := CASE WHEN v_case_price > 0
                           THEN ROUND((1 - v_total_cogs / v_case_price) * 100, 1) ELSE NULL END;

    IF COALESCE(NEW.is_active, true) = false
       AND COALESCE(OLD.is_active, true) = true THEN
        NEW.last_active_unit_cogs             := v_total_cogs;
        NEW.last_active_cogs_pct              := v_cogs_pct;
        NEW.last_active_gross_profit_per_unit := v_gross_profit;
        NEW.last_active_margin_pct            := v_margin_pct;
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    IF NEW.merge_into_id IS NOT NULL THEN
        NEW.total_coffee_cost      := NULL;
        NEW.total_consumable_cost  := NULL;
        NEW.total_unit_cogs        := NULL;
        NEW.gross_profit_per_unit  := NULL;
        NEW.cogs_pct               := NULL;
        NEW.margin_pct             := NULL;
        RETURN NEW;
    END IF;

    IF v_is_coffee THEN
        NEW.total_coffee_cost     := v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0);
        NEW.total_consumable_cost := v_consumable_cost_total;
    ELSIF v_is_bundle THEN
        -- NULL coffee, because a box holds none of its own: the coffee in it is
        -- costed on the contents' own lines. A real number in the consumable
        -- column is also what makes the cost tiles render at all -- GroupDetail
        -- and ProductDetail both hide the breakdown when BOTH columns are null,
        -- so a box used to show no cost rather than a zero.
        NEW.total_coffee_cost     := NULL;
        NEW.total_consumable_cost := v_consumable_cost_total;
    ELSE
        NEW.total_coffee_cost     := NULL;
        NEW.total_consumable_cost := NULL;
    END IF;
    NEW.total_unit_cogs                   := v_total_cogs;
    NEW.gross_profit_per_unit             := v_gross_profit;
    NEW.cogs_pct                          := v_cogs_pct;
    NEW.margin_pct                        := v_margin_pct;
    NEW.last_active_unit_cogs             := v_total_cogs;
    NEW.last_active_cogs_pct              := v_cogs_pct;
    NEW.last_active_gross_profit_per_unit := v_gross_profit;
    NEW.last_active_margin_pct            := v_margin_pct;

    RETURN NEW;
END;

$function$;

-- ── What a box really costs ────────────────────────────────────────────────
-- One row per mixed case. `packaging_cost` is the carton BOM the trigger above
-- stores; `contents_cost` is what the order will book on the exploded child
-- lines, computed the same way `handle_order_detail_logic` computes it
-- (quantity x the child's own `total_unit_cogs`), so the figure a product page
-- shows and the figure the order books are the same arithmetic.
--
-- 🔴 LEFT JOIN TO `products`, DELIBERATELY. A component row whose child is gone
-- -- or hidden from this reader by RLS -- would be dropped by an inner join and
-- the box would quietly cost less, with nothing saying so.
-- `children_missing_cost` is how a caller can say the total is a floor rather
-- than reporting it as the answer. Same rule, same reason, as
-- `lib/shop/shipWeight.ts`'s `failed`.
create or replace view public.product_bundle_costs as
select
    p.product_id                                      as parent_product_id,
    p.company_id,
    p.facility_id,
    p.price,
    coalesce(p.total_unit_cogs, 0::numeric)           as packaging_cost,
    coalesce(c.contents_cost, 0::numeric)             as contents_cost,
    coalesce(p.total_unit_cogs, 0::numeric)
      + coalesce(c.contents_cost, 0::numeric)         as total_unit_cogs,
    coalesce(c.item_count, 0::numeric)                as item_count,
    coalesce(c.children_missing_cost, 0)              as children_missing_cost,
    round(p.price
          - (coalesce(p.total_unit_cogs, 0::numeric)
             + coalesce(c.contents_cost, 0::numeric)), 2) as gross_profit_per_unit,
    round((coalesce(p.total_unit_cogs, 0::numeric)
           + coalesce(c.contents_cost, 0::numeric))
          / nullif(p.price, 0::numeric) * 100::numeric, 1) as cogs_pct,
    round((p.price
           - (coalesce(p.total_unit_cogs, 0::numeric)
              + coalesce(c.contents_cost, 0::numeric)))
          / nullif(p.price, 0::numeric) * 100::numeric, 1) as margin_pct
  from products p
  left join lateral (
    select sum(coalesce(ch.total_unit_cogs, 0::numeric) * pc.quantity) as contents_cost,
           sum(pc.quantity)                                            as item_count,
           count(*) filter (
             where coalesce(ch.total_unit_cogs, 0::numeric) = 0::numeric
           )::int                                                      as children_missing_cost
      from product_components pc
      left join products ch on ch.product_id = pc.child_product_id
     where pc.parent_product_id = p.product_id
  ) c on true
 where p.product_type = 'ptype_bundle';

alter view public.product_bundle_costs set (security_invoker = true);

-- Cost is staff information. `product_margins` grants anon SELECT and this view
-- deliberately does not: nothing on the storefront reads a margin.
revoke all on public.product_bundle_costs from public;
revoke all on public.product_bundle_costs from anon;
grant select on public.product_bundle_costs to authenticated, service_role;

-- ── The margin report, which the cost centre actually opens ────────────────
-- 🔴 ONE CHANGE: `total_unit_cogs` becomes the box's REAL cost for a mixed
-- case, so every figure derived from it here -- gross profit, margin and the
-- `data_warning` flag that hides a row behind "incomplete cost data" -- is
-- right without a single frontend change. The column list is unchanged in name,
-- type and order, which is what CREATE OR REPLACE requires with
-- `data_quality_issues` depending on it.
--
-- A box with a carton and contents lands at a real margin, so it stops tripping
-- the >90% "suspiciously high margin" arm it would otherwise trip for ever.
-- That arm needs no bundle exception; it needed the cost to be true.
create or replace view public.product_margins as
 SELECT p.product_id,
    p.product_name,
    p.company_id,
    p.facility_id,
    p.price,
    COALESCE(b.total_unit_cogs, p.total_unit_cogs) AS total_unit_cogs,
    round(p.price - COALESCE(b.total_unit_cogs, p.total_unit_cogs), 2) AS gross_profit_per_unit,
    round((p.price - COALESCE(b.total_unit_cogs, p.total_unit_cogs))
          / NULLIF(p.price, 0::numeric) * 100::numeric, 1) AS margin_pct,
    p.weight_lbs,
    p.size,
        CASE
            WHEN COALESCE(b.total_unit_cogs, p.total_unit_cogs) = 0::numeric THEN true
            WHEN ((p.price - COALESCE(b.total_unit_cogs, p.total_unit_cogs)) / NULLIF(p.price, 0::numeric) * 100::numeric) < 0::numeric THEN true
            WHEN ((p.price - COALESCE(b.total_unit_cogs, p.total_unit_cogs)) / NULLIF(p.price, 0::numeric) * 100::numeric) > 90::numeric THEN true
            ELSE false
        END AS data_warning
   FROM products p
     LEFT JOIN product_bundle_costs b ON b.parent_product_id = p.product_id
  WHERE p.is_active = true;

alter view public.product_margins set (security_invoker = true);

-- ── Verify ─────────────────────────────────────────────────────────────────
-- 🔴 STRUCTURAL ONLY, AND EVERY ASSERTION IS SOMETHING THE DESIGN REQUIRES.
-- A block that asserts what the design FORBIDS can only raise, and a raise here
-- rolls back the whole release.
do $verify$
declare
  v_src  text;
  v_def  text;
  v_opts text;
begin
  select prosrc into v_src from pg_proc
   where oid = 'public.update_product_total_cogs'::regproc;

  if v_src not like '%v_is_bundle%' then
    raise exception 'update_product_total_cogs has no bundle arm';
  end if;
  if v_src not like '%ptype_bundle%' then
    raise exception 'the bundle arm must key on the type ID, which is not renameable';
  end if;
  -- the coffee arm, untouched: if CREATE OR REPLACE lost it, every coffee
  -- variant's cost would silently become zero.
  if v_src not like '%recipe_effective_green%' then
    raise exception 'the coffee arm lost its green-cost read';
  end if;
  if v_src not like '%COALESCE(NEW.unit_cost, 0) * v_units%' then
    raise exception 'the resold/other arm lost its unit_cost term';
  end if;

  select pg_get_viewdef('public.product_bundle_costs'::regclass, true) into v_def;
  if v_def not like '%product_components%' then
    raise exception 'product_bundle_costs does not read what is in the box';
  end if;
  select array_to_string(reloptions, ',') into v_opts from pg_class
   where oid = 'public.product_bundle_costs'::regclass;
  if coalesce(v_opts, '') not like '%security_invoker=true%' then
    raise exception 'product_bundle_costs must be security_invoker, or it reads across tenants';
  end if;

  select pg_get_viewdef('public.product_margins'::regclass, true) into v_def;
  if v_def not like '%product_bundle_costs%' then
    raise exception 'product_margins is not using the box cost';
  end if;
  if v_def not like '%data_warning%' then
    raise exception 'product_margins lost data_warning, which the cost centre filters on';
  end if;
  select array_to_string(reloptions, ',') into v_opts from pg_class
   where oid = 'public.product_margins'::regclass;
  if coalesce(v_opts, '') not like '%security_invoker=true%' then
    raise exception 'product_margins must stay security_invoker (pg_get_viewdef drops it)';
  end if;

  -- The views PLAN: a definition naming a column that does not exist would
  -- otherwise only fail the first time somebody opened a page.
  perform 1 from public.product_bundle_costs where false;
  perform 1 from public.product_margins where false;
  perform 1 from public.data_quality_issues where false;
end
$verify$;

commit;
