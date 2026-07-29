-- Discounts ADD to invoices (plan Phase 1.8). Actively wrong money.
--
-- handle_order_detail_logic computes every live line as
--     NEW.total_price := quantity * products.price
-- and discount products store a POSITIVE price, because that is the sensible thing
-- to type into a price field ("Discount: $25.20"). So a discount line increases the
-- invoice by exactly the amount it should decrease it — a double-sized error.
--
-- Demonstrated on prod against a real MCR order (rolled back):
--     DISCOUNT line, qty 10 @ price 25.2 -> total_price = 252.0    (must be negative)
--     order_total went 11038.4 -> 11290.4    -- a discount INCREASED the invoice
-- $252 of discount moved the invoice $504 the wrong way.
--
-- Why MCR's imported history is nevertheless correct: legacy imports skip the
-- recompute entirely (`IF NOT v_is_legacy AND ...`), so QuickBooks' own signed
-- amounts were preserved — all 369 discount lines are correctly −$57,324.76. The bug
-- is entirely PROSPECTIVE, and it fires the first time someone puts a discount on an
-- order typed into STRATA. It has not caused a wrong invoice yet only because
-- non-coffee lines cannot be added in new-order entry (that is 1.9) — this lands
-- first so that opening the door does not open the bug.
--
-- Two capabilities, both required by 1.8:
--   1. Discount product types reduce the total, by TYPE rather than by remembering
--      to store a negative price on every such product.
--   2. A line-level amount override, for the negotiated price / odd credit that no
--      quantity × price will ever produce.

begin;

-- ── 1. Which product types reduce an invoice ───────────────────────────────
-- An explicit semantic flag, not a hardcoded 'ptype_discount' string. product_type
-- is a real lookup table and tenants have their own rows in it (Wholesale Bulk,
-- Retail DTC, …), so a tenant that adds its own discount type can mark it here and
-- the engine follows — no code change, no forgotten sign.
alter table public.product_type
  add column if not exists reduces_total boolean not null default false;

comment on column public.product_type.reduces_total is
  'Lines of this type SUBTRACT from the order total. Set for discount types. The stored product price stays positive — the sign is applied at line level.';

update public.product_type
   set reduces_total = true
 where product_type_id = 'ptype_discount'
    or qb_item_type    = 'Discount';

-- ── 2. Line-level amount override ──────────────────────────────────────────
-- NULL = derive the amount from quantity × price as usual. Non-null = this exact
-- amount, sign included. Negative is legal and is the point: a one-off credit, a
-- negotiated line, a QuickBooks-style adjustment.
alter table public.order_details
  add column if not exists amount_override numeric;

comment on column public.order_details.amount_override is
  'Exact line amount, overriding quantity x price. Sign is preserved, so a negative value is a credit line. NULL = derive normally.';

-- ── 3. The engine ──────────────────────────────────────────────────────────
create or replace function public.handle_order_detail_logic()
returns trigger
language plpgsql
as $$
DECLARE
    v_company_id      text;
    v_facility_id     text;
    v_product_weight  numeric;
    v_product_price   numeric;
    v_recipe_id       text;
    v_cogs            numeric;
    v_is_legacy       boolean;
    v_reduces         boolean;
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

        IF NEW.amount_override IS NOT NULL THEN
            -- Verbatim, sign and all. An operator who types an exact amount means it.
            NEW.total_price := NEW.amount_override;
        ELSIF COALESCE(v_reduces, false) THEN
            -- abs() so the result is negative whether the product's price is stored
            -- positive (the normal case, and the one that caused this bug) or
            -- already negative. A discount cannot add, whatever the price field says.
            NEW.total_price := -abs(COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0));
        ELSE
            NEW.total_price := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
        END IF;

        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

    -- 2b. Weight is PHYSICAL, not financial — so a legacy import gets it too.
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
$$;

commit;

notify pgrst, 'reload schema';
