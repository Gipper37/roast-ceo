-- Costing a recipe that is made of recipes.
--
-- A post-blend parent (Maui Blend DK/LT = 50% MB DK + 50% MB LT) carries
-- `recipe_components` rows whose `coffee_item` is NULL and whose
-- `component_recipe_id` names a child recipe. Both cost paths join straight to
-- `coffee_inventory` on `rc.coffee_item`, so a parent matched nothing.
--
-- 🔴 WHY THIS LANDS BEFORE ANY PRODUCT MOVES. `update_product_total_cogs` is a
-- BEFORE trigger on `products`, and its coffee total is
-- `COALESCE(SUM(...), 0)`. Re-pointing a product at a parent therefore does not
-- error and does not go NULL: it writes total_coffee_cost = 0, leaves
-- total_unit_cogs at bag cost alone, inflates margin_pct, and overwrites the
-- last_active_* snapshot so the fallback goes too. The only symptom is a margin
-- that looks good. Moving MCR's 15 Maui Blend variants before this is in place
-- would silently restate the roastery's largest product line.
--
-- `get_product_cogs_on_date` fails softer -- it loops components and calls the
-- per-origin dated cost helpers, and a NULL coffee_item returns NULL, so the
-- component is skipped and `v_has_any_cost` stays false -- but it still prices
-- a parent at nothing.
--
-- ── ONE FLATTENING, TWO CALLERS ───────────────────────────────────────────
--
-- Both now read `recipe_effective_green`, which returns a recipe's green
-- components with one level of recipe components resolved and the shares
-- multiplied through. Expressed once because the two callers filter by facility
-- differently and duplicating the walk is how the two drift apart.
--
-- 🔴 ONE LEVEL, DELIBERATELY, matching `recipe_demand_source`, which is also one
-- hop. A grandchild is not resolved and must not be: the composer refuses to
-- nest, and silently flattening two levels here would price something the
-- demand side cannot plan.
--
-- 🔴 EXISTING BEHAVIOUR IS BYTE-IDENTICAL for a recipe with no recipe
-- components: the second branch is gated on `component_recipe_id IS NOT NULL`,
-- which has zero rows on production today, and the first branch reproduces the
-- old row source exactly. Both function bodies below were taken from the LIVE
-- definitions and patched by script at one call site each, never retyped.

begin;

-- `facility_id` is returned rather than filtered, because the two callers
-- disagree about what to filter: the trigger filters `coffee_inventory`, the
-- dated one filters the component row. Returning it keeps both exactly as they
-- were.
create or replace function public.recipe_effective_green(p_recipe_id text)
returns table (coffee_item text, percentage numeric, facility_id text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- Green the recipe holds directly.
  select rc.coffee_item, rc.percentage, rc.facility_id
    from public.recipe_components rc
   where rc.recipe_id = p_recipe_id
     and rc.coffee_item is not null

  union all

  -- Green held by a child recipe, at the product of the two shares. The
  -- child's own facility wins where it has one, because that is the row whose
  -- green this is.
  select child.coffee_item,
         coalesce(rc.percentage, 0::numeric) * coalesce(child.percentage, 0::numeric),
         coalesce(child.facility_id, rc.facility_id)
    from public.recipe_components rc
    join public.recipe_components child
      on child.recipe_id = rc.component_recipe_id
   where rc.recipe_id = p_recipe_id
     and rc.component_recipe_id is not null
     and child.coffee_item is not null
$fn$;

comment on function public.recipe_effective_green(text) is
  'A recipe''s green components with ONE level of recipe components resolved and shares multiplied. Matches recipe_demand_source, which is also one hop.';

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

CREATE OR REPLACE FUNCTION public.get_product_cogs_on_date(p_product_id text, p_facility_id text, p_order_date date)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_recipe_id         text;
    v_weight_lbs        numeric;
    v_source_consumable text;
    v_coffee_cost       numeric := 0;
    v_consumable_cost   numeric := 0;
    v_units             numeric := 1;
    v_component_cost    numeric;
    v_rec               record;
    v_has_any_cost      boolean := false;
BEGIN
    SELECT recipe_id, weight_lbs, source_consumable_id
      INTO v_recipe_id, v_weight_lbs, v_source_consumable
      FROM public.products
     WHERE product_id = p_product_id
     LIMIT 1;

    SELECT COALESCE(s.units_per_case, 1) INTO v_units
      FROM public.products p JOIN public.size s ON s.size_id = p.size
     WHERE p.product_id = p_product_id;
    v_units := COALESCE(v_units, 1);

    IF v_recipe_id IS NOT NULL AND COALESCE(v_weight_lbs, 0) > 0 THEN
        FOR v_rec IN
            SELECT rc.coffee_item, rc.percentage
              FROM public.recipe_effective_green(v_recipe_id) rc
             WHERE rc.facility_id = p_facility_id
        LOOP
            v_component_cost := COALESCE(
                public.get_origin_roasted_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date),
                public.get_coffee_cost_on_date(v_rec.coffee_item, p_facility_id, p_order_date)
            );
            IF v_component_cost IS NOT NULL THEN
                v_coffee_cost  := v_coffee_cost + (v_component_cost * COALESCE(v_rec.percentage, 0));
                v_has_any_cost := true;
            END IF;
        END LOOP;
    END IF;

    FOR v_rec IN
        SELECT pc.consumable_id, pc.quantity
          FROM public.product_consumables_effective pc
         WHERE pc.product_id   = p_product_id
           AND pc.facility_id  = p_facility_id
    LOOP
        v_component_cost := public.get_consumable_cost_on_date(
            v_rec.consumable_id, p_facility_id, p_order_date
        );
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * COALESCE(v_rec.quantity, 1));
            v_has_any_cost    := true;
        END IF;
    END LOOP;

    -- ▼▼ RESOLD: the product IS its source consumable (no recipe, no BOM) — its
    --    per-unit cost is the consumable's cost on that date (quantity 1). ▼▼
    IF v_source_consumable IS NOT NULL THEN
        v_component_cost := public.get_consumable_cost_on_date(v_source_consumable, p_facility_id, p_order_date);
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * v_units);
            v_has_any_cost    := true;
        END IF;
    END IF;

    IF NOT v_has_any_cost THEN
        RETURN NULL;
    END IF;

    RETURN (v_coffee_cost * COALESCE(v_weight_lbs, 0)) + v_consumable_cost;
END;
$function$;

do $$
declare
  n_direct numeric;
  n_fn     int;
begin
  -- The helper reproduces the old answer for an ordinary recipe. Picks any
  -- recipe that has green components; skips silently if a tenant has none.
  select count(*) into n_fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'recipe_effective_green';
  if n_fn <> 1 then raise exception 'recipe_effective_green did not install'; end if;

  -- Both cost paths must now go through it, or a parent still prices at zero.
  select count(*) into n_fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('update_product_total_cogs','get_product_cogs_on_date')
     and pg_get_functiondef(p.oid) like '%recipe_effective_green%';
  if n_fn <> 2 then
    raise exception 'expected both cost functions to call recipe_effective_green, found %', n_fn;
  end if;

  -- 🔴 A recipe with no recipe components must be unchanged. Compare the
  -- helper against the old expression for every such recipe on this database.
  select coalesce(sum(abs(a.old_pct - b.new_pct)), 0) into n_direct
    from (select rc.recipe_id, sum(rc.percentage) old_pct
            from public.recipe_components rc where rc.coffee_item is not null
           group by rc.recipe_id) a
    join lateral (select coalesce(sum(g.percentage), 0) new_pct
                    from public.recipe_effective_green(a.recipe_id) g) b on true
   where not exists (select 1 from public.recipe_components x
                      where x.recipe_id = a.recipe_id and x.component_recipe_id is not null);
  if n_direct > 0.0000001 then
    raise exception 'recipe_effective_green changed an ordinary recipe by %', n_direct;
  end if;
end $$;

commit;
