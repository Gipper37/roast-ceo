-- A typed amount on a DISCOUNT line takes money off, it does not add it.
--
-- 20260827000001 wired amount_override into live order entry. Its branch order
-- put the override BEFORE the reduces_total rule, so the override won outright
-- and the sign was never applied. Verified on prod: adding MCR's "Sales
-- Discount" product to an order and typing 50 in the Total column produced
-- total_price = +50.00 — fifty dollars ADDED to what the customer owes.
--
-- This is the "discounts ADD instead of subtract" defect, reachable from the
-- ordinary New Order screen the moment a per-line amount could be typed.
--
-- The computed path has always been right: `-abs(quantity * price)` when
-- product_type.reduces_total. The override path now applies the same rule to
-- the same products. Someone typing "50" on a discount line means fifty off,
-- and there is no reading of that keystroke where they meant to charge more.
--
-- Normal lines are still taken verbatim, sign and all — an operator who types
-- an exact amount on an ordinary line means it, including a negative.
--
-- NO BACKFILL, and for a stronger reason than "nothing is wrong". There ARE 17
-- existing override lines on reduces_total products — my first guess of zero was
-- wrong — but every one of them is on a LEGACY QuickBooks order, and
-- handle_order_detail_logic skips legacy imports outright. This function cannot
-- reach them whatever it says, so a backfill here would be theatre.
--
-- Their state, checked rather than assumed:
--   16 "Sales Discount" lines, all already NEGATIVE, -$1,800.20 total. Correct.
--    1 "Coffee" line at +$53.25, positive. Also correct — and it exposes a
--      DATA problem rather than a code one: product mcrimp-prod-b9420ab63d958528
--      is named "Coffee" and is an ordinary coffee product, but the QuickBooks
--      importer typed it as product_type Discount, so reduces_total is true for
--      it. Its 34 historical lines total +$502.13 and are right; it is the TYPE
--      that is wrong. Left alone deliberately: re-typing a product is a data
--      decision for the owner, not a side effect of a trigger fix. Note it is
--      ACTIVE — sell it on a new order and this rule would force the line
--      negative, which is the type's fault, not this migration's.

begin;

create or replace function public.handle_order_detail_logic()
returns trigger
language plpgsql
as $function$
DECLARE
    v_company_id      text;
    v_facility_id     text;
    v_product_weight  numeric;
    v_product_price   numeric;
    v_recipe_id       text;
    v_cogs            numeric;
    v_is_legacy       boolean;
    v_reduces         boolean;
    v_reprice         boolean;
BEGIN
    -- 1. Always sync order metadata from parent (+ read the legacy-import flag).
    SELECT order_date, customer_id, company_id, facility_id, COALESCE(is_legacy_import, false)
    INTO   NEW.order_date, NEW.customer_id, v_company_id, v_facility_id, v_is_legacy
    FROM   orders
    WHERE  order_id = NEW.order_id;

    NEW.company_id  := v_company_id;
    NEW.facility_id := v_facility_id;

    -- 2. Recompute price/weight/cost from the product on INSERT / qty / product /
    --    override change. SKIP for a legacy QB import: the historical amounts
    --    (signed credit-memo totals, discounted prices, period COGS) are supplied by
    --    the importer and must be preserved EXACTLY. Live orders unchanged.
    IF NOT v_is_legacy
       AND (TG_OP = 'INSERT'
            OR NEW.quantity        IS DISTINCT FROM OLD.quantity
            OR NEW.product_id      IS DISTINCT FROM OLD.product_id
            OR NEW.amount_override IS DISTINCT FROM OLD.amount_override)
    THEN
        SELECT p.weight_lbs,
               p.price,
               p.recipe_id,
               COALESCE(p.total_unit_cogs, 0),
               COALESCE(pt.reduces_total, false)
        INTO   v_product_weight, v_product_price, v_recipe_id, v_cogs, v_reduces
        FROM   products p
        LEFT   JOIN public.product_type pt ON pt.product_type_id = p.product_type
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        -- Which price applies. A NEW line, or a line whose PRODUCT changed, is
        -- being priced for the first time -- the catalogue is the right source.
        -- An existing line whose quantity moved is NOT being repriced: it keeps
        -- the unit price it was sold at, because that is what the customer
        -- agreed to.
        v_reprice := TG_OP = 'INSERT'
                     OR NEW.product_id IS DISTINCT FROM OLD.product_id
                     OR NEW.unit_price_at_sale IS NULL;

        IF v_reprice THEN
            NEW.unit_price_at_sale := v_product_price;
        ELSE
            v_product_price := NEW.unit_price_at_sale;
        END IF;

        IF NEW.amount_override IS NOT NULL THEN
            -- The amount the operator typed. On a DISCOUNT product it is forced
            -- negative, exactly as the computed path below forces it: a discount
            -- cannot add, and someone typing "50" on a Sales Discount line means
            -- fifty dollars OFF. Before this the override branch ran first and
            -- won outright, so that keystroke ADDED $50 to the order — verified
            -- on prod. Everything else is taken verbatim, sign included, because
            -- an operator who types an exact amount on a normal line means it.
            NEW.total_price := CASE
                WHEN COALESCE(v_reduces, false) THEN -abs(NEW.amount_override)
                ELSE NEW.amount_override
            END;
            -- The snapshot records what that works out to per unit, so
            -- unit_price_at_sale x quantity = total_price stays true here too,
            -- sign and all.
            NEW.unit_price_at_sale := CASE
                WHEN COALESCE(NEW.quantity, 0) <> 0
                THEN NEW.total_price / NEW.quantity
                ELSE NULL
            END;
        ELSIF COALESCE(v_reduces, false) THEN
            -- abs() so the result is negative whether the product's price is stored
            -- positive (the normal case, and the one that caused this bug) or
            -- already negative. A discount cannot add, whatever the price field says.
            NEW.total_price := -abs(COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0));
            -- Same invariant on the discount path: the snapshot carries the sign
            -- the line actually charges, not the catalogue's positive figure.
            NEW.unit_price_at_sale := -abs(COALESCE(v_product_price, 0));
        ELSE
            NEW.total_price := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
        END IF;

        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

    -- 2b. Weight is PHYSICAL, not financial -- so a legacy import gets it too.
    --     The skip above exists to protect QuickBooks' historical AMOUNTS (signed
    --     credit-memo totals, negotiated prices, period COGS). roasted_weight is not
    --     one of those: QuickBooks never supplied it, it is simply quantity x the
    --     product's own weight. Skipping it left every imported coffee line at 0 lbs,
    --     so imported orders showed "Total Weight 0 lbs" and every pounds-based
    --     report undercounted history. Only fills a BLANK, so it can never overwrite
    --     a weight the operator or the live path already set.
    IF NEW.product_id IS NOT NULL AND COALESCE(NEW.roasted_weight, 0) = 0 THEN
        SELECT p.weight_lbs INTO v_product_weight
        FROM   products p
        WHERE  p.product_id = NEW.product_id
          AND  p.company_id = v_company_id;

        IF COALESCE(v_product_weight, 0) > 0 THEN
            NEW.roasted_weight := COALESCE(NEW.quantity, 0) * v_product_weight;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

commit;
