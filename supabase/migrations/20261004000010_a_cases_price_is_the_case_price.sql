-- A case's price IS the case price. It was being multiplied by the pack count.
--
-- `update_product_total_cogs` computed `v_case_price := NEW.price * v_units` on
-- the premise, stated in its own comment, that "price is PER SELLING UNIT". For
-- a case row the selling unit IS the case, so every case product reported a
-- gross profit and a COGS% off by its pack count.
--
-- Costco Maui Blend showed PRICE $260.08 "per unit, $3,120.96 per case", a gross
-- profit of $2,988.41 and 4.2% COGS. The case is 24 lb and costs $132.55 to
-- make, so the truth is $127.53 and 51.0%. Ka'u read 9.1% where it is 90.7%.
-- A roaster pricing off that screen would have read a 90% margin on a job that
-- barely covers its coffee.
--
-- Prod says the price is the case price three ways:
--   order_details: "Maui Blend - 2oz (Case of 40)" sold quantity 1 at
--     unit_price_at_sale 105.46 for total_price 105.46, and products.price on
--     that variant is 105.46. One case, one price, confirmed by a real sale.
--   arithmetic: 24 lb at 260.08 is $10.84/lb wholesale; x12 is $130/lb against
--     a $5.52/lb cost.
--   the screen itself: the case form says "the case is the thing a customer buys
--     and the thing you ship, so its weight and its price are the case total".
--
-- 🔴 LATENT, THEN ACTIVATED BY ITS OWN STEP 2. 20261002000002 introduced this on
-- 2026-10-02 and was provably inert, because units_per_case was NULL on all 38
-- sizes and COALESCE made v_units 1. 20261004000005 and 000006 set the pack
-- counts yesterday and turned it live. "This migration changes no number" was
-- true and the logic was still wrong; a two-step migration can hide a defect in
-- the half that does nothing.
--
-- The body below is pg_get_functiondef output with one expression and its
-- comment replaced. Nothing else is retyped.
begin;

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
$function$

;

-- Recompute every product the bug touched. The trigger has no column list, so
-- touching a row re-derives weight, both cost terms, the profit and the two
-- percentages together. Only products on a case size were ever wrong: v_units is
-- 1 for everything else and 1 multiplies to itself.
do $recompute$
declare v_n int; v_rec record;
begin
  select count(*) into v_n
    from public.products p join public.size s on s.size_id = p.size
   where s.units_per_case is not null;
  if v_n = 0 then
    raise notice 'no product sits on a case size here; nothing to recompute';
  else
    raise notice 'recomputing % product(s) on a case size', v_n;
    for v_rec in
      select p.product_id, p.product_name, p.price, p.cogs_pct as old_pct,
             round(p.gross_profit_per_unit::numeric, 2) as old_gp
        from public.products p join public.size s on s.size_id = p.size
       where s.units_per_case is not null and p.price is not null
       order by p.product_name
    loop
      raise notice '  % was %%% COGS, gross profit %', v_rec.product_name, v_rec.old_pct, v_rec.old_gp;
    end loop;
    -- updated_at only; the trigger does the rest.
    update public.products p
       set updated_at = now()
      from public.size s
     where s.size_id = p.size and s.units_per_case is not null;
  end if;
end $recompute$;

do $verify$
declare v_bad int; v_rec record;
begin
  -- 1. The percentages now agree with the stored price, not with price x pack.
  select count(*) into v_bad
    from public.products p join public.size s on s.size_id = p.size
   where s.units_per_case is not null and p.price > 0 and p.total_unit_cogs is not null
     and p.cogs_pct is distinct from round(p.total_unit_cogs / p.price * 100, 1);
  if v_bad > 0 then
    raise exception '% case product(s) still report a COGS%% that is not cogs/price', v_bad;
  end if;

  -- 2. Gross profit is price minus cost, on the case.
  select count(*) into v_bad
    from public.products p join public.size s on s.size_id = p.size
   where s.units_per_case is not null and p.price is not null and p.total_unit_cogs is not null
     and round(p.gross_profit_per_unit::numeric, 6)
         is distinct from round((p.price - p.total_unit_cogs)::numeric, 6);
  if v_bad > 0 then
    raise exception '% case product(s) hold a gross profit that is not price minus cogs', v_bad;
  end if;

  -- 3. Nothing OFF a case size moved: v_units was already 1 there.
  select count(*) into v_bad
    from public.products p left join public.size s on s.size_id = p.size
   where coalesce(s.units_per_case, 1) = 1 and p.price > 0 and p.total_unit_cogs is not null
     and p.cogs_pct is distinct from round(p.total_unit_cogs / p.price * 100, 1);
  if v_bad > 0 then
    raise exception '% non-case product(s) disagree with cogs/price; this file should not have touched them', v_bad;
  end if;

  for v_rec in
    select p.product_name, p.price, round(p.total_unit_cogs::numeric,2) as cogs,
           round(p.gross_profit_per_unit::numeric,2) as gp, p.cogs_pct
      from public.products p join public.size s on s.size_id = p.size
     where s.units_per_case is not null and p.price is not null
     order by p.product_name
  loop
    raise notice '  CORRECTED: % price % cogs % profit % at %%% COGS',
      v_rec.product_name, v_rec.price, v_rec.cogs, v_rec.gp, v_rec.cogs_pct;
  end loop;
end $verify$;

commit;
