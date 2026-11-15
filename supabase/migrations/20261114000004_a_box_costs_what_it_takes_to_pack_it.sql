-- A box costs what it takes to pack it.
--
-- Owner, 2026-11-14: *"you should be able to add the box as a bom cuz that is
-- part of building the product."*
--
-- He already could. `product_consumables` has no type guard, the Consumables
-- editor is already rendered on a mixed case, and the stock side is right:
-- measured on staging, selling three boxes took the carton 10 → 7 while the
-- bags inside still drew on their own exploded lines. Par, reorder and monthly
-- usage all count it, one carton per BOX.
--
-- 🔴 WHAT WAS WRONG WAS THE COST, IN FOUR PLACES.
--
-- `update_product_total_cogs` branches on the product type's NAME
-- (`v_is_coffee := COALESCE(v_kind,'Coffee') = 'Coffee'`), `ptype_bundle`'s
-- name is 'Bundle', so a box took the ELSE arm, which hardcodes
-- `v_consumable_cost_total := 0` and writes both cost columns NULL. A $48 box
-- with a $4.25 carton read COGS $0.00, gross profit $48.00, COGS% 0.0% -- in
-- green, directly above a Consumables table printing that carton at $4.25.
--
-- That zero did not stay on a screen. `handle_order_detail_logic` reads
-- `COALESCE(p.total_unit_cogs, 0)` and writes
-- `unit_cost_at_sale := quantity * v_cogs`, so the box's order line was BORN at
-- cost 0 (measured: 0 on the box, 18.498 on its child) -- wrong gross profit on
-- the order, in customer profitability and in the profit report.
--
-- And it changed later on its own: `get_product_cogs_on_date` and
-- `product_cogs_for_keys` have no type branch and both returned 4.25 for the
-- same box, so `recost_orders_for_consumable_purchases` -- fired by
-- `shipment_received` -- rewrote that line 0 → 12.75 when the next carton
-- arrived. Nobody had to touch the box.
--
-- Nothing flagged any of it: `data_quality_issues` says "Suspiciously high
-- margin" above 90% but filters on `total_unit_cogs > 0`, and the cost centre
-- drops bundle lines from its missing-cost list as "no cost by design" -- true
-- before a box could have a bill of materials, false after.
--
-- 🔴 WHICH INPUT IS THE BOX'S COST was his to decide, because a bundle has two
-- live ones: the BOM, read by both dated engines and ignored by this trigger,
-- and the hand-entered `products.unit_cost`, read by this trigger and ignored
-- by both dated engines. He chose the BOM. So the new arm reads the BOM and
-- deliberately does not read `unit_cost`, which is what makes this trigger
-- agree with the two engines that recost history.
--
-- 🔴 THE BODY BELOW IS THE DEPLOYED ONE, TAKEN FROM pg_proc AND EDITED AT FOUR
-- ANCHORS. CREATE OR REPLACE rewrites the whole function, so none of it was
-- retyped: the declaration, the flag, the cost arm and the two stored columns
-- are the only changes, and 20261026000001's case-price reasoning is carried
-- through verbatim.
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

-- ── The report that could not see a zero ──────────────────────────────────
create or replace view public.data_quality_issues as
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    p.margin_pct,
        CASE
            WHEN p.margin_pct < 0::numeric THEN 'Selling below cost'::text
            WHEN p.margin_pct > 90::numeric THEN 'Suspiciously high margin'::text
            ELSE NULL::text
        END AS issue
   FROM product_margins p
     JOIN products pp ON pp.product_id = p.product_id
-- 🔴 A MIXED CASE'S OWN MARGIN IS NOT COMPARABLE TO A BAG'S, so it is held back
-- from the high-margin arm and from nothing else.
--
-- Costing the box correctly gives it a 91.1% margin: $48 against a $4.25
-- carton. That is not a pricing fault, it is the shape of a bundle -- the
-- coffee in the box is costed on the CONTENTS' own order lines, where it
-- belongs, so the box's own row can only ever show packaging against the whole
-- price. Measured on staging: the moment the carton was added, Data Health went
-- from "No cost recorded" to "Suspiciously high margin", and it would have said
-- that about every mixed case for ever. A report that cries wolf once per box
-- stops being read, which is what it cost the Revised orders bar.
--
-- "Selling below cost" is KEPT for a box: priced under its own packaging is a
-- real fault and nothing structural makes it fire.
  WHERE p.data_warning = true AND p.total_unit_cogs > 0::numeric
    AND NOT (pp.product_type = 'ptype_bundle' AND p.margin_pct > 90::numeric)
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Missing coffee cost'::text AS issue
   FROM coffee_inventory ci
  WHERE COALESCE(ci.latest_cost, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM coffee_inventory ci
  WHERE ci.latest_cost > 0::numeric AND COALESCE(ci.last_cost_lb, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Missing consumable cost'::text AS issue
   FROM consumable_inventory c
  WHERE COALESCE(c.last_cost_unit, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM consumable_inventory c
  WHERE COALESCE(c.fallback_unit_cost, 0::numeric) > 0::numeric AND COALESCE(c.last_cost_unit, 0::numeric) > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM consumable_inventory_purchased cip
          WHERE cip.consumable_inventory_item = c.consumable_inventory_id AND cip.facility_id = c.facility_id AND cip.cost_unit IS NOT NULL AND cip.cost_unit::text <> ''::text AND cip.cost_unit > 0::numeric))
UNION ALL
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    NULL::numeric AS margin_pct,
    'Missing product price'::text AS issue
   FROM products p
  WHERE p.is_active AND p.merge_into_id IS NULL AND NOT (EXISTS ( SELECT 1
           FROM products_price_log ppl
          WHERE ppl.product_id = p.product_id))
UNION ALL
-- 🔴 A PRODUCT THAT SHOULD COST SOMETHING AND COSTS NOTHING.
--
-- The arm above is `data_warning = true AND total_unit_cogs > 0`, and
-- product_margins sets data_warning true precisely WHEN total_unit_cogs = 0 --
-- so every zero-cost product was computed as a warning and then thrown away by
-- the filter. On prod that is 72 active variants today, 28 of them already
-- carrying a bill of materials. The one surface built to catch a suspicious
-- margin could not see the suspicious case.
--
-- It is a separate arm, not a relaxed filter, because a zero is not a high
-- margin: it says nobody recorded a cost. Scoped to products that SHOULD have
-- one -- a BOM line, a recipe, a resold source, or a mixed case, whose cost is
-- its packaging -- so services, discounts and equipment do not fill the report
-- with rows nobody can act on. 37 rows on prod, against 72 unscoped.
--
-- A mixed case with no packaging recorded lands here, which is the prompt that
-- was missing: the box, its label and its filler counted as nothing while the
-- bags inside counted correctly, and nothing anywhere said so.
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    NULL::numeric AS margin_pct,
    'No cost recorded'::text AS issue
   FROM products p
  WHERE p.is_active AND p.merge_into_id IS NULL
    AND COALESCE(p.total_unit_cogs, 0::numeric) = 0::numeric
    AND (p.product_type = 'ptype_bundle'
         OR p.recipe_id IS NOT NULL
         OR p.source_consumable_id IS NOT NULL
         OR (EXISTS ( SELECT 1
               FROM product_consumables pc
              WHERE pc.product_id = p.product_id)));

alter view public.data_quality_issues set (security_invoker = true);

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

  select pg_get_viewdef('public.data_quality_issues'::regclass, true) into v_def;
  if v_def not like '%No cost recorded%' then
    raise exception 'data_quality_issues has no zero-cost arm';
  end if;
  if v_def not like '%Suspiciously high margin%' then
    raise exception 'data_quality_issues lost its high-margin arm';
  end if;

  select array_to_string(reloptions, ',') into v_opts from pg_class
   where oid = 'public.data_quality_issues'::regclass;
  if coalesce(v_opts, '') not like '%security_invoker=true%' then
    raise exception 'data_quality_issues must stay security_invoker (pg_get_viewdef drops it)';
  end if;

  -- The view PLANS: a definition that references a column that does not exist
  -- would otherwise only fail the first time somebody opened Data Health.
  perform 1 from public.data_quality_issues where false;
end
$verify$;

commit;
