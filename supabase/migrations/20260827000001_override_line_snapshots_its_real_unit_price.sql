-- An overridden line should snapshot the price it was ACTUALLY sold at.
--
-- 20260826000002 added unit_price_at_sale and stamps it from the catalogue --
-- but it does so BEFORE the amount_override branch runs. So a line with an
-- override stores the catalogue price beside a total that came from somewhere
-- else. Verified on prod:
--
--     quantity 2 | amount_override 33.50 | total_price 33.50
--     unit_price_at_sale 58.50  ->  implies 117.00
--
-- The money is right; the snapshot beside it is not. Nothing reads it wrongly
-- today because the override branch wins on every recompute, so no invoice or
-- report is affected. It is bad data waiting for the first thing that trusts
-- the column to mean what its name says.
--
-- An override IS a unit price -- it is just expressed as a line total. Dividing
-- by quantity recovers it, which keeps the invariant the column exists to hold:
-- unit_price_at_sale x quantity = total_price, for every line, always.
--
-- Zero quantity leaves it null rather than dividing: there is no unit price for
-- nothing, and a null is honest where a 0 would be a claim.

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
            -- Verbatim, sign and all. An operator who types an exact amount means it.
            NEW.total_price := NEW.amount_override;
            -- ...and the snapshot records what that amount works out to per unit,
            -- so unit_price_at_sale x quantity = total_price stays true here too.
            -- Without this the line kept the CATALOGUE price beside an unrelated
            -- total, which is the defect this migration exists to fix.
            NEW.unit_price_at_sale := CASE
                WHEN COALESCE(NEW.quantity, 0) <> 0
                THEN NEW.amount_override / NEW.quantity
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

-- Repair the rows already written with a mismatched snapshot. Triggers off: this
-- corrects a derived column and must not look like an operator edit, nor re-run
-- the pricing logic on lines it is only annotating.
alter table public.order_details disable trigger user;

update public.order_details
   set unit_price_at_sale = amount_override / quantity
 where amount_override is not null
   and quantity is not null and quantity <> 0
   and (unit_price_at_sale is null
        or abs(unit_price_at_sale * quantity - amount_override) > 0.01);

alter table public.order_details enable trigger user;

commit;
