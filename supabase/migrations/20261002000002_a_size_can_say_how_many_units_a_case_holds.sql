-- A size can say how many units a case holds, and the engine can do the maths.
--
-- STEP 1 OF 2. This teaches every costing, depletion and reporting path to
-- multiply a per-unit bill of materials by a case's pack count. It sets that
-- pack count on NOTHING, so `COALESCE(s.units_per_case, 1)` is 1 everywhere
-- and this migration changes no number anywhere. Step 2 converts the data.
--
-- Splitting it this way is the only way either half is provable. The pack
-- count and the divided BOM cannot land apart -- a BOM divided by 40 while the
-- engine still reads it literally understates packaging cost and depletion
-- 40-fold, silently -- so the usual instinct is one enormous migration. This
-- instead makes the ENGINE change provably inert (assert the effective
-- quantity still equals the stored quantity on all 55 rows) and leaves step 2
-- to be a pure data flip against an engine that already knows what to do.
--
-- WHAT A CASE IS, once step 2 runs: a `size` row that names the unit size it
-- is built from (base_size_id) and how many of them it holds (units_per_case).
-- Its `weight` stays the TOTAL, which is what it already holds today and what
-- products.weight_lbs is derived from, so roasted_weight, the coffee cost term
-- and every shipping weight are untouched by any of this.
--
-- THE BOM DISTINCTION HAD NOWHERE TO LIVE. A case needs a bill of materials
-- that is partly per-bag (the bag, the bag's label: 10 of each in a case of
-- ten) and partly per-case (one box, one case label, tape). product_consumables
-- had no column for that, and consumable_type cannot stand in for it: a case
-- label and a bag label are both 'global_consumable_type_label' and exactly one
-- of them multiplies. Hence product_consumables.per_case, defaulting to false
-- so all 55 existing rows keep today's meaning and a box opts in.
--
-- ONE DEFINITION, NOT NINE. Nine places multiply an order quantity or a cost by
-- product_consumables.quantity: update_product_total_cogs,
-- get_product_cogs_on_date, calculate_current_stock_consumables,
-- update_consumable_metrics (twice), calculate_consumable_par,
-- calculate_consumable_restock_level, monthly_consumable_usage_by_item and
-- mv_monthly_consumable_stock_by_item. Nine hand-edited copies of the same CASE
-- expression is how one of them gets missed, so the rule lives in a view,
-- product_consumables_effective, and every one of them reads that instead. The
-- view exposes the adjusted number AS `quantity`, so each call site changes by
-- one token and nothing else.
--
-- 🔴 EVERY FUNCTION BODY BELOW WAS READ WITH pg_get_functiondef AND EDITED, NOT
-- RETYPED. CREATE OR REPLACE rewrites the whole body; retyping one from memory
-- is how roast saving broke for two days.
--
-- update_product_total_cogs needed one change beyond the view swap. It compares
-- NEW.price against total_unit_cogs, and after step 2 price is PER UNIT while
-- total_unit_cogs must stay PER CASE -- because handle_order_detail_logic does
-- `unit_cost_at_sale := quantity * v_cogs` and that quantity is counted in
-- cases. So the comparison moves to the case side via v_case_price. With
-- v_units = 1 it is arithmetically identical to what it does today.

begin;

-- Captured BEFORE the engine is replaced, so the proof compares like with like.
create temporary table _cogs_before on commit drop as
  select product_id, total_unit_cogs, gross_profit_per_unit, cogs_pct, margin_pct,
         total_coffee_cost, total_consumable_cost, weight_lbs
    from public.products;

create temporary table _hist_before on commit drop as
  select p.product_id, p.facility_id,
         public.get_product_cogs_on_date(p.product_id, p.facility_id, current_date - 30) as cogs
    from public.products p
   where p.is_active and p.facility_id is not null;

create temporary table _cons_before on commit drop as
  select consumable_inventory_id, in_stock, par, restock_level, daily_usage, to_order
    from public.consumable_inventory;

-- ── the three columns ────────────────────────────────────────────────────────
alter table public.size
  add column if not exists base_size_id   text references public.size(size_id),
  add column if not exists units_per_case integer;

comment on column public.size.base_size_id is
  'For a case size: the unit size it is built from. NULL for a unit size.';
comment on column public.size.units_per_case is
  'For a case size: how many base units it holds. NULL (never 1) for a unit size, so COALESCE(units_per_case,1) is the one idiom everywhere.';

alter table public.product_consumables
  add column if not exists per_case boolean not null default false;

comment on column public.product_consumables.per_case is
  'True for a line consumed once per CASE (the box, the case label, tape). False, the default, for a line consumed per selling unit, which is multiplied by the size pack count.';

do $$ begin
  alter table public.size add constraint size_case_fields_agree
    check ((base_size_id is null) = (units_per_case is null));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.size add constraint size_units_per_case_gt_one
    check (units_per_case is null or units_per_case > 1);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.size add constraint size_base_is_not_self
    check (base_size_id is null or base_size_id <> size_id);
exception when duplicate_object then null; end $$;

-- ── the one definition ───────────────────────────────────────────────────────
-- security_invoker so RLS still applies: every function below is SECURITY
-- INVOKER, and a view that bypassed RLS here would hand one tenant another
-- tenant's bill of materials.
create or replace view public.product_consumables_effective
  with (security_invoker = true) as
select pc.product_consumable_id,
       pc.product_id,
       pc.consumable_id,
       pc.company_id,
       pc.facility_id,
       pc.per_case,
       pc.quantity as stated_quantity,
       pc.quantity * case when pc.per_case then 1
                          else coalesce(s.units_per_case, 1) end as quantity
  from public.product_consumables pc
  join public.products p on p.product_id = pc.product_id
  left join public.size  s on s.size_id  = p.size;

comment on view public.product_consumables_effective is
  'product_consumables with quantity already scaled to the pack. A per-unit line on a case of ten reports ten; a per_case line reports itself. Read this, never product_consumables.quantity, anywhere a cost or a depletion is computed.';

grant select on public.product_consumables_effective to authenticated;
grant select on public.product_consumables_effective to service_role;

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
        FROM public.recipe_components rc
        JOIN public.coffee_inventory ci ON rc.coffee_item = ci.origin_id
        WHERE rc.recipe_id   = NEW.recipe_id
          AND ci.facility_id = NEW.facility_id;

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

    -- price is PER SELLING UNIT; total_unit_cogs is per CASE, because
    -- handle_order_detail_logic multiplies it by a quantity counted in cases.
    -- So the comparison happens on the case side. v_units is 1 everywhere
    -- until a size is marked as a case, which is why this migration changes
    -- no number.
    v_case_price   := COALESCE(NEW.price, 0) * v_units;
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
              FROM public.recipe_components rc
             WHERE rc.recipe_id   = v_recipe_id
               AND rc.facility_id = p_facility_id
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

CREATE OR REPLACE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count     NUMERIC;
    v_purchased_amount    NUMERIC;
    v_usage_amount        NUMERIC;
    v_resold_usage        NUMERIC;
BEGIN
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id;
    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND sr.date_received IS NOT NULL
      AND COALESCE(sr.voided, false) = false
      AND cp.facility_id = p_facility_id;

    -- BOM usage (this consumable is an ingredient of a made good).
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

    -- ▼▼ RESOLD usage: a product that IS this consumable (source_consumable_id)
    --    depletes 1 unit per unit sold. Same exclusions as BOM usage. ▼▼
    SELECT COALESCE(SUM(od.quantity), 0)
    INTO v_resold_usage
    FROM order_details od
    JOIN orders o   ON od.order_id = o.order_id
    JOIN products p ON od.product_id = p.product_id
    WHERE p.source_consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND COALESCE(o.is_legacy_import, false) = false
      AND o.facility_id = p_facility_id;

    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount - v_resold_usage));
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_consumable_metrics()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_baseline   DATE;
  v_received   NUMERIC;
  v_used       NUMERIC;
  v_resold     NUMERIC;
  v_in_stock   NUMERIC;
  v_par        NUMERIC;
  v_restock    NUMERIC;
  v_92day      NUMERIC;
  v_92_resold  NUMERIC;
BEGIN
  v_baseline := COALESCE(NEW.last_inventory_date, '2000-01-01');

  SELECT COALESCE(SUM(cip.amount), 0) INTO v_received
  FROM consumable_inventory_purchased cip
  JOIN shipment_received sr ON cip.shipment_id = sr.shipment_id
  WHERE cip.consumable_inventory_item = NEW.consumable_inventory_id
    AND sr.date_received >= v_baseline
    AND (sr.voided IS NULL OR sr.voided = false);

  -- Units consumed since baseline. Imports count: see the header.
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_used
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  -- ▼▼ RESOLD since baseline: a product that IS this consumable. Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= v_baseline
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  v_in_stock := GREATEST(0, COALESCE(NEW.inventory_count, 0) + v_received - v_used - v_resold);
  NEW.in_stock := v_in_stock;

  v_par := calculate_consumable_par(NEW.consumable_inventory_id, NEW.facility_id);
  v_restock := calculate_consumable_restock_level(NEW.consumable_inventory_id, NEW.facility_id);
  NEW.par := v_par;
  NEW.restock_level := v_restock;
  NEW.to_order := CASE WHEN v_in_stock <= v_restock THEN GREATEST(0, v_par - v_in_stock) ELSE 0 END;

  -- Daily usage from 92-day order history. Imports COUNT: see the header.
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0) INTO v_92day
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  -- ▼▼ RESOLD 92-day usage (drives daily_usage → par/restock). Imports count. ▼▼
  SELECT COALESCE(SUM(od.quantity), 0) INTO v_92_resold
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = NEW.consumable_inventory_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND o.facility_id = NEW.facility_id;

  NEW.daily_usage := (v_92day + v_92_resold) / 92.0;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_consumable_par(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_92day_usage    numeric;
  v_monthly_usage  numeric;
  v_target_months  numeric;
  v_buffer         numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  -- ▼▼ RESOLD 92-day usage: a product that IS this consumable (source_consumable_id)
  --    consumes 1 unit per unit sold. Same exclusions as the BOM sum. ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  SELECT COALESCE(rc.target_months, 3)
  INTO v_target_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;

  IF v_target_months IS NULL THEN v_target_months := 3; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  RETURN CEIL(v_monthly_usage * v_target_months * v_buffer);
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_consumable_restock_level(p_consumable_id text, p_facility_id text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_92day_usage       numeric;
  v_monthly_usage     numeric;
  v_reorder_months    numeric;
  v_buffer            numeric;
  v_par               numeric;
  v_result            numeric;
BEGIN
  SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o ON od.order_id = o.order_id
  JOIN public.product_consumables_effective pc ON od.product_id = pc.product_id
  WHERE pc.consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  -- ▼▼ RESOLD 92-day usage (mirrors calculate_consumable_par). ▼▼
  SELECT v_92day_usage + COALESCE(SUM(od.quantity), 0)
  INTO v_92day_usage
  FROM order_details od
  JOIN orders o   ON od.order_id = o.order_id
  JOIN products p ON od.product_id = p.product_id
  WHERE p.source_consumable_id = p_consumable_id
    AND o.order_date >= CURRENT_DATE - interval '92 days'
    AND o.order_status != 'Canceled'
    AND COALESCE(o.is_legacy_import, false) = false
    AND o.facility_id = p_facility_id;

  IF v_92day_usage = 0 THEN RETURN 0; END IF;

  v_monthly_usage := v_92day_usage / 3.0;

  SELECT COALESCE(rc.reorder_months, 1.5)
  INTO v_reorder_months
  FROM consumable_inventory ci
  LEFT JOIN restock_category rc ON rc.restock_category_id = ci.restock_category_id
  WHERE ci.consumable_inventory_id = p_consumable_id
    AND ci.facility_id = p_facility_id
  LIMIT 1;
  IF v_reorder_months IS NULL THEN v_reorder_months := 1.5; END IF;

  SELECT COALESCE(
    (SELECT cp.value_number FROM company_parameters cp
     WHERE cp.parameter_id = '5131610b' AND cp.facility_id = p_facility_id LIMIT 1),
    1.3
  ) INTO v_buffer;

  v_result := CEIL(v_monthly_usage * v_reorder_months * v_buffer);

  v_par := calculate_consumable_par(p_consumable_id, p_facility_id);
  IF v_par <= 0 THEN RETURN 0; END IF;

  RETURN LEAST(v_result, v_par);
END;
$function$;

-- ── the two reporting surfaces ───────────────────────────────────────────────
-- security_invoker is restated: CREATE OR REPLACE VIEW resets reloptions, which
-- is how a 766-row cross-tenant leak shipped once before.
create or replace view public.monthly_consumable_usage_by_item
  with (security_invoker = true) as
SELECT (((od.facility_id || '_'::text) || pc.consumable_id) || '_'::text) || date_trunc('month'::text, o.order_date::timestamp with time zone)::date AS month_item_id,
    date_trunc('month'::text, o.order_date::timestamp with time zone)::date AS month_start,
    pc.consumable_id,
    ci.consumable_inventory_item AS item_name,
    od.facility_id,
    od.company_id,
    round(sum(od.quantity * pc.quantity), 2) AS units_used
   FROM order_details od
     JOIN orders o ON o.order_id = od.order_id
     JOIN public.product_consumables_effective pc ON pc.product_id = od.product_id
     JOIN consumable_inventory ci ON ci.consumable_inventory_id = pc.consumable_id AND ci.facility_id = od.facility_id
  WHERE o.order_status <> 'Canceled'::text
  GROUP BY (date_trunc('month'::text, o.order_date::timestamp with time zone)), pc.consumable_id, ci.consumable_inventory_item, od.facility_id, od.company_id;
grant select on public.monthly_consumable_usage_by_item to authenticated;

-- A materialized view cannot be replaced in place, so it is dropped and rebuilt
-- with both of its indexes and its grants. The unique index is what lets the
-- refresh run CONCURRENTLY, so losing it would quietly change how it refreshes.
-- monthly_consumable_stock_by_item reads the matview, so it has to come down
-- with it and go back exactly as it was. It is deliberately
-- security_invoker=false; restored at that setting rather than quietly
-- 'corrected', because changing who a view runs as is not this migration's
-- business.
drop view if exists public.monthly_consumable_stock_by_item;
drop materialized view if exists public.mv_monthly_consumable_stock_by_item;
create materialized view public.mv_monthly_consumable_stock_by_item as
WITH all_usage AS (
         SELECT o.order_date AS usage_date,
            pc.consumable_id,
            od.facility_id,
            sum(od.quantity * pc.quantity) AS units_used
           FROM order_details od
             JOIN orders o ON o.order_id = od.order_id
             JOIN public.product_consumables_effective pc ON pc.product_id = od.product_id
          WHERE o.order_status <> 'Canceled'::text
          GROUP BY o.order_date, pc.consumable_id, od.facility_id
        ), all_purchases AS (
         SELECT sr.date_received AS received_date,
            p.consumable_inventory_item AS consumable_id,
            p.facility_id,
            p.amount::numeric AS purchased_units
           FROM consumable_inventory_purchased p
             JOIN shipment_received sr ON sr.shipment_id = p.shipment_id
          WHERE sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false
        ), consumables AS (
         SELECT DISTINCT consumable_inventory.consumable_inventory_id AS consumable_id,
            consumable_inventory.facility_id,
            consumable_inventory.company_id,
            consumable_inventory.consumable_inventory_item AS item_name
           FROM consumable_inventory
        ), consumable_first_event AS (
         SELECT events.consumable_id,
            events.facility_id,
            min(events.event_date) AS first_event
           FROM ( SELECT consumable_inventory_history.consumable_id,
                    consumable_inventory_history.facility_id,
                    consumable_inventory_history.inventory_date AS event_date
                   FROM consumable_inventory_history
                UNION ALL
                 SELECT all_purchases.consumable_id,
                    all_purchases.facility_id,
                    all_purchases.received_date
                   FROM all_purchases
                UNION ALL
                 SELECT all_usage.consumable_id,
                    all_usage.facility_id,
                    all_usage.usage_date
                   FROM all_usage) events
          GROUP BY events.consumable_id, events.facility_id
        ), date_spine AS (
         SELECT c.consumable_id,
            c.facility_id,
            c.company_id,
            c.item_name,
            gs.month_start::date AS month_start
           FROM consumables c
             JOIN consumable_first_event fe ON fe.consumable_id = c.consumable_id AND fe.facility_id = c.facility_id
             JOIN LATERAL generate_series(date_trunc('month'::text, fe.first_event::timestamp without time zone)::timestamp with time zone, date_trunc('month'::text, now()), '1 mon'::interval) gs(month_start) ON true
          WHERE fe.first_event < 'infinity'::date
        )
 SELECT (((ds.facility_id || '_'::text) || ds.consumable_id) || '_'::text) || ds.month_start AS month_stock_id,
    ds.month_start,
    ds.consumable_id,
    ds.item_name,
    ds.facility_id,
    ds.company_id,
    GREATEST(0::numeric, round(COALESCE(anchor.anchor_count, 0::numeric) + COALESCE(purch.purchased_units, 0::numeric) - COALESCE(used.units_used, 0::numeric), 0)) AS in_stock
   FROM date_spine ds
     LEFT JOIN LATERAL ( SELECT h.inventory_date AS anchor_date,
            h.inventory_count AS anchor_count
           FROM consumable_inventory_history h
          WHERE h.consumable_id = ds.consumable_id AND h.facility_id = ds.facility_id AND h.inventory_date < (ds.month_start + '1 mon'::interval)::date
          ORDER BY h.inventory_date DESC
         LIMIT 1) anchor ON true
     LEFT JOIN LATERAL ( SELECT COALESCE(sum(ap.purchased_units), 0::numeric) AS purchased_units
           FROM all_purchases ap
          WHERE ap.consumable_id = ds.consumable_id AND ap.facility_id = ds.facility_id AND ap.received_date > COALESCE(anchor.anchor_date, '2000-01-01'::date) AND ap.received_date < (ds.month_start + '1 mon'::interval)::date) purch ON true
     LEFT JOIN LATERAL ( SELECT COALESCE(sum(au.units_used), 0::numeric) AS units_used
           FROM all_usage au
          WHERE au.consumable_id = ds.consumable_id AND au.facility_id = ds.facility_id AND au.usage_date > COALESCE(anchor.anchor_date, '2000-01-01'::date) AND au.usage_date < (ds.month_start + '1 mon'::interval)::date) used ON true;
create unique index idx_monthly_consumable_stock_id
  on public.mv_monthly_consumable_stock_by_item using btree (month_stock_id);
create index idx_monthly_consumable_stock_consumable_facility
  on public.mv_monthly_consumable_stock_by_item using btree (consumable_id, facility_id);
grant select on public.mv_monthly_consumable_stock_by_item to authenticated;
grant all on public.mv_monthly_consumable_stock_by_item to service_role;

create view public.monthly_consumable_stock_by_item
  with (security_invoker = false) as
SELECT month_stock_id,
    month_start,
    consumable_id,
    item_name,
    facility_id,
    company_id,
    in_stock
   FROM mv_monthly_consumable_stock_by_item
  WHERE (company_id IN ( SELECT auth_company_ids() AS auth_company_ids)) OR ( SELECT pg_roles.rolbypassrls
           FROM pg_roles
          WHERE pg_roles.rolname = CURRENT_USER);
grant select on public.monthly_consumable_stock_by_item to authenticated;
grant all    on public.monthly_consumable_stock_by_item to service_role;

do $verify$
declare v_bad int; v_n int;
begin
  -- 🔴 THE CLAIM THIS MIGRATION MAKES: it changes no number. Everything below
  -- exists to fail the release if that is not true.

  -- Nothing is a case yet, so the whole engine change is arithmetically inert.
  select count(*) into v_bad from public.size where units_per_case is not null;
  if v_bad > 0 then
    raise exception '% size row(s) already carry a pack count; this step must set none', v_bad;
  end if;

  -- The view returns exactly what the table holds, row for row.
  select count(*) into v_bad
    from public.product_consumables pc
    join public.product_consumables_effective e using (product_consumable_id)
   where e.quantity is distinct from pc.quantity;
  if v_bad > 0 then
    raise exception '% bill-of-materials row(s) changed value through the new view', v_bad;
  end if;

  select count(*) into v_n from public.product_consumables;
  select count(*) into v_bad from public.product_consumables_effective;
  if v_bad <> v_n then
    raise exception 'the view returns % rows against % in the table', v_bad, v_n;
  end if;

  -- Cached product costs are untouched. These are stored columns, so they only
  -- move if something rewrites them; asserted so a later edit to this migration
  -- cannot start rewriting them unnoticed.
  select count(*) into v_bad
    from _cogs_before b join public.products p using (product_id)
   where p.total_unit_cogs       is distinct from b.total_unit_cogs
      or p.gross_profit_per_unit is distinct from b.gross_profit_per_unit
      or p.cogs_pct              is distinct from b.cogs_pct
      or p.margin_pct            is distinct from b.margin_pct
      or p.total_coffee_cost     is distinct from b.total_coffee_cost
      or p.total_consumable_cost is distinct from b.total_consumable_cost
      or p.weight_lbs            is distinct from b.weight_lbs;
  if v_bad > 0 then raise exception '% product(s) had a cached cost change', v_bad; end if;

  -- 🔴 The historical COGS function is RE-RUN against the replaced body and
  -- compared to what the old body returned minutes ago, for every active
  -- product. This is the assertion that matters: four recost functions call it
  -- and write the answer onto historical order lines.
  select count(*) into v_bad
    from _hist_before b
   where public.get_product_cogs_on_date(b.product_id, b.facility_id, current_date - 30)
         is distinct from b.cogs;
  if v_bad > 0 then
    raise exception '% product(s) now return a different historical COGS', v_bad;
  end if;

  select count(*) into v_n from _hist_before;
  if v_n < 100 then
    raise exception 'only % products were re-costed; the comparison is too thin to trust', v_n;
  end if;

  -- Consumable stock, par and reorder levels are untouched.
  select count(*) into v_bad
    from _cons_before b join public.consumable_inventory c using (consumable_inventory_id)
   where c.in_stock      is distinct from b.in_stock
      or c.par            is distinct from b.par
      or c.restock_level  is distinct from b.restock_level
      or c.daily_usage    is distinct from b.daily_usage
      or c.to_order       is distinct from b.to_order;
  if v_bad > 0 then raise exception '% consumable(s) had stock or par change', v_bad; end if;

  -- Every call site reads the view. A function left on the raw table is the one
  -- that silently under-counts the day a size becomes a case.
  select count(*) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('update_product_total_cogs','get_product_cogs_on_date',
                       'calculate_current_stock_consumables','update_consumable_metrics',
                       'calculate_consumable_par','calculate_consumable_restock_level')
     and p.prosrc !~ 'product_consumables_effective';
  if v_bad > 0 then
    raise exception '% costing function(s) still read product_consumables directly', v_bad;
  end if;

  -- And none of them lost SECURITY INVOKER on the way through.
  select count(*) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname in ('update_product_total_cogs','get_product_cogs_on_date',
                       'calculate_current_stock_consumables','update_consumable_metrics',
                       'calculate_consumable_par','calculate_consumable_restock_level');
  if v_bad > 0 then raise exception '% function(s) became SECURITY DEFINER', v_bad; end if;

  if not exists (select 1 from pg_class
                  where relname = 'product_consumables_effective'
                    and reloptions::text like '%security_invoker=true%') then
    raise exception 'product_consumables_effective is not security_invoker';
  end if;
  if not exists (select 1 from pg_class
                  where relname = 'monthly_consumable_usage_by_item'
                    and reloptions::text like '%security_invoker=true%') then
    raise exception 'monthly_consumable_usage_by_item lost security_invoker';
  end if;
  if not exists (select 1 from pg_class
                  where relname = 'monthly_consumable_stock_by_item'
                    and reloptions::text like '%security_invoker=false%') then
    raise exception 'monthly_consumable_stock_by_item did not come back as it was';
  end if;
  select count(*) into v_bad from pg_indexes
   where tablename = 'mv_monthly_consumable_stock_by_item';
  if v_bad <> 2 then
    raise exception 'the matview came back with % index(es), expected 2', v_bad;
  end if;
end;
$verify$;

commit;
