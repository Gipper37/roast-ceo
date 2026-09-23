-- An allocated share is a line figure, not a unit price.
--
-- MY BUG, from 20260923000009, caught by the financial audit before it ever
-- reached production. That migration made discount_kind 'amount' mean PER
-- UNIT. apply_order_discount is a FOURTH consumer of discount_value and I did
-- not patch it: it divides an order-level discount across the lines and writes
-- each line's SHARE into discount_value with kind 'amount'. The trigger would
-- then have multiplied that share by the quantity again.
--
-- Reproduced on a real MCR order (4 lines, $625.00) with a 10% order discount:
--
--   line  qty  list     share   intended    would have become
--   ----  ---  -------  ------  ----------  -----------------
--   d2bb    8   506.00   50.59      455.41   404.72  (101.28 off)
--   6089    2    59.50    5.95       53.55    11.90  ( 47.60 off)
--   2802    1    29.75    2.98       26.77    26.77
--   2f90    1    29.75    2.98       26.77    26.77
--
--   right: order_total 562.50, discounts sum 62.50
--   wrong: order_total 202.42, discounts sum 422.58   -- $360.08 undercharged
--
-- And orders.discount_total would still have read 62.50 beside an order_total
-- of 202.42, on a page that shows no subtotal line, so the arithmetic would
-- never have been visible. 9,195 unposted non-legacy orders have a line with
-- quantity > 1.
--
-- Nothing is wrong on production: it sits at ...007 and there are zero
-- discounts in the database. This fixes ...009 before either ships.
--
-- THE FIX, and why it is not division. Writing share/quantity would lose cents
-- to rounding -- 50.59 over 8 units is 6.32375, and 6.32 x 8 is 50.56 -- so the
-- lines would stop summing to the order discount. apply_order_discount already
-- stamps discount_source = 'order_allocated' on every line it touches, and it
-- has a remainder line to make the allocation exact. Reading that source is
-- exact and needs no new kind.
--
-- The lesson, recorded: a per-unit/per-line semantic change has FOUR consumers
-- in this database, not three. ...009 audited three of them in its own probe.

begin;

CREATE OR REPLACE FUNCTION public.handle_order_detail_logic()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    v_disc_rule       text;
    v_disc_kind       text;
    v_disc_value      numeric;
BEGIN
    SELECT order_date, customer_id, company_id, facility_id, COALESCE(is_legacy_import, false)
    INTO   NEW.order_date, NEW.customer_id, v_company_id, v_facility_id, v_is_legacy
    FROM   orders
    WHERE  order_id = NEW.order_id;

    NEW.company_id  := v_company_id;
    NEW.facility_id := v_facility_id;

    IF NOT v_is_legacy
       AND (TG_OP = 'INSERT'
            OR NEW.quantity        IS DISTINCT FROM OLD.quantity
            OR NEW.product_id      IS DISTINCT FROM OLD.product_id
            OR NEW.amount_override IS DISTINCT FROM OLD.amount_override
            OR NEW.discount_kind   IS DISTINCT FROM OLD.discount_kind
            OR NEW.discount_value  IS DISTINCT FROM OLD.discount_value)
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

        -- Repricing happens on a first pricing only: a new line, a changed
        -- product, or a missing snapshot. Otherwise the line keeps the unit
        -- price the customer was quoted.
        v_reprice := TG_OP = 'INSERT'
                     OR NEW.product_id IS DISTINCT FROM OLD.product_id
                     OR NEW.unit_price_at_sale IS NULL;

        -- ── THE LIST UNIT, the one number everything derives from ────────
        -- Written ONLY here, from the catalogue, an override, or kept —
        -- never from anything the discount arithmetic produced.
        IF NEW.amount_override IS NOT NULL THEN
            -- An override is a LINE total; per-unit it is override/qty. On a
            -- discount-type product it is forced negative: typing "50" on a
            -- Sales Discount line means fifty dollars off.
            NEW.unit_price_at_sale := CASE
                WHEN COALESCE(NEW.quantity, 0) = 0 THEN NULL
                WHEN COALESCE(v_reduces, false) THEN -abs(NEW.amount_override) / NEW.quantity
                ELSE NEW.amount_override / NEW.quantity
            END;
        ELSIF v_reprice THEN
            NEW.unit_price_at_sale := CASE
                WHEN COALESCE(v_reduces, false) THEN -abs(COALESCE(v_product_price, 0))
                ELSE v_product_price
            END;
        END IF;
        -- else: keep NEW.unit_price_at_sale exactly as it was.

        -- ── THE STANDING DISCOUNT: on INSERT, and on the clear ───────────
        -- Not when the operator typed an exact amount: an override means that
        -- amount, and stamping a rule on top double-subtracts. On UPDATE the
        -- rule re-resolves ONLY at the moment a discount is cleared (OLD had
        -- one, NEW has none) — the UI's "Clear — back to their rate" — never
        -- on a plain quantity edit of a never-discounted line.
        IF NEW.discount_kind IS NULL AND NEW.amount_override IS NULL
           AND (TG_OP = 'INSERT' OR OLD.discount_kind IS NOT NULL) THEN
            SELECT d.customer_discount_id, d.kind, d.value
              INTO v_disc_rule, v_disc_kind, v_disc_value
              FROM public.resolve_customer_discount(NEW.customer_id, NEW.product_id, NEW.order_date) d;
            IF v_disc_kind IS NOT NULL THEN
                NEW.discount_kind    := v_disc_kind;
                NEW.discount_value   := v_disc_value;
                NEW.discount_rule_id := v_disc_rule;
                NEW.discount_source  := 'customer_rule';
            ELSE
                NEW.discount_rule_id := NULL;
                NEW.discount_source  := NULL;
            END IF;
        END IF;

        -- ── LIST, DISCOUNT, NET — derived forward, never backward ────────
        NEW.list_price_total := CASE
            WHEN NEW.amount_override IS NOT NULL THEN
                CASE WHEN COALESCE(v_reduces, false)
                     THEN -abs(NEW.amount_override)
                     ELSE NEW.amount_override END
            ELSE COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_price_at_sale, 0)
        END;

        -- The gate is KIND-AWARE. `value > 0` means "no discount" for a
        -- percent or an amount, but a 'price' of 0.00 means the customer gets
        -- it FREE -- and the old shared gate would have skipped the block and
        -- charged them full list.
        IF NEW.discount_kind IS NOT NULL
           AND (NEW.discount_kind = 'price' OR COALESCE(NEW.discount_value, 0) > 0) THEN
            NEW.discount_amount := CASE
                WHEN NEW.discount_kind = 'percent'
                    THEN round(abs(NEW.list_price_total) * NEW.discount_value / 100.0, 2)
                -- 'price' is what the customer PAYS, per unit. The discount is
                -- whatever is left over, which is why the rule survives a list
                -- price change: list 11.75 -> 2.75 off; list rises to 12.50 ->
                -- 3.50 off; they pay 9.00 either way.
                WHEN NEW.discount_kind = 'price'
                    THEN greatest(0, round(abs(NEW.list_price_total)
                                           - (NEW.discount_value * COALESCE(NEW.quantity, 0)), 2))
                -- An ALLOCATED share is a LINE figure, not a unit price.
                -- apply_order_discount divides an order-level discount across
                -- the lines and writes each line's share here; multiplying it
                -- by the quantity again is the bug this arm exists to stop.
                WHEN NEW.discount_source = 'order_allocated'
                    THEN least(NEW.discount_value, abs(NEW.list_price_total))
                -- 'amount' is PER UNIT, on the owner's instruction: "it should
                -- be a unit discount, not line". It used to be compared
                -- straight against the line total, so "$2 off" gave $2 off
                -- whether you bought one bag or fifty. Safe to change: there
                -- is not one discounted line anywhere in the database.
                ELSE least(NEW.discount_value * COALESCE(NEW.quantity, 0), abs(NEW.list_price_total))
            END;
        ELSE
            NEW.discount_amount := 0;
        END IF;

        NEW.total_price := NEW.list_price_total
                           - (sign(COALESCE(NEW.list_price_total, 0)) * COALESCE(NEW.discount_amount, 0));

        NEW.roasted_weight    := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
        NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

        IF NEW.recipe_id IS NULL THEN
            NEW.recipe_id := v_recipe_id;
        END IF;
    END IF;

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
$function$;;

CREATE OR REPLACE FUNCTION public.propagate_price_log_to_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_date_end date;
    v_reduces  boolean;
    v_today    date;
BEGIN
    -- An order is LOCKED AT CREATION. Entering a price must not reach back and
    -- rewrite orders that already exist -- that is the owner's instruction and
    -- it is the safe default: "we don't want to touch existing orders in the
    -- normal case."
    --
    -- This function still exists, because the case it was written for is real:
    -- "the only case that was meant for was for truing up inaccurate history."
    -- That is now something you ASK for on the price entry, once, deliberately,
    -- rather than something every price change does silently.
    IF NOT COALESCE(NEW.backfill_orders, false) THEN
        RETURN NEW;
    END IF;

    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- A future-dated entry is STAGED, not live: there is nothing to rewrite
    -- yet. The hourly cron touches the row when its date arrives and this
    -- trigger runs again, then against real orders in its window. "Future" is
    -- judged in the FACILITY's timezone, same as the sync trigger.
    SELECT (now() AT TIME ZONE COALESCE(f.time_zone, 'UTC'))::date
    INTO   v_today
    FROM   public.products p
    LEFT   JOIN public.facilities f ON f.facility_id = p.facility_id
    WHERE  p.product_id = NEW.product_id;
    IF NEW.date_updated > COALESCE(v_today, current_date) THEN
        RETURN NEW;
    END IF;

    -- End of this entry's validity window: the date_updated of the next price
    -- log entry for this product. Scoped by PRODUCT only — see the header note
    -- on why facility cannot narrow what a product_id match already narrowed.
    -- A staged future entry correctly ends the window: orders dated on/after
    -- it belong to the staged price, applied when it comes due.
    SELECT MIN(ppl.date_updated) INTO v_date_end
    FROM public.products_price_log ppl
    WHERE ppl.product_id    = NEW.product_id
      AND ppl.price_log_id <> NEW.price_log_id
      AND ppl.date_updated  > NEW.date_updated;

    SELECT COALESCE(pt.reduces_total, false) INTO v_reduces
    FROM   public.products p
    LEFT   JOIN public.product_type pt ON pt.product_type_id = p.product_type
    WHERE  p.product_id = NEW.product_id;

    -- One direction, same as handle_order_detail_logic: the new price is the
    -- LIST unit; list, discount and net derive from it.
    UPDATE public.order_details od
    SET    unit_price_at_sale = CASE WHEN v_reduces THEN -abs(NEW.price) ELSE NEW.price END,
           list_price_total   = CASE WHEN v_reduces
                                     THEN -abs(od.quantity * NEW.price)
                                     ELSE  od.quantity * NEW.price END,
           discount_amount    = CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               -- 'price' is what they PAY per unit; the discount is the rest.
               -- A price of 0.00 is a free item, so this arm deliberately does
               -- not require value > 0.
               WHEN od.discount_kind = 'price'
                   THEN greatest(0, round(abs(od.quantity * NEW.price)
                                          - (od.discount_value * od.quantity), 2))
               -- An allocated share is a LINE figure; see handle_order_detail_logic.
               WHEN od.discount_source = 'order_allocated'
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
               -- 'amount' is PER UNIT, matching handle_order_detail_logic.
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value * od.quantity, abs(od.quantity * NEW.price))
               ELSE 0
           END,
           total_price        = (CASE WHEN v_reduces
                                      THEN -abs(od.quantity * NEW.price)
                                      ELSE  od.quantity * NEW.price END)
                                - (CASE WHEN v_reduces THEN -1 ELSE 1 END) * (CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               -- 'price' is what they PAY per unit; the discount is the rest.
               -- A price of 0.00 is a free item, so this arm deliberately does
               -- not require value > 0.
               WHEN od.discount_kind = 'price'
                   THEN greatest(0, round(abs(od.quantity * NEW.price)
                                          - (od.discount_value * od.quantity), 2))
               -- An allocated share is a LINE figure; see handle_order_detail_logic.
               WHEN od.discount_source = 'order_allocated'
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
               -- 'amount' is PER UNIT, matching handle_order_detail_logic.
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value * od.quantity, abs(od.quantity * NEW.price))
               ELSE 0
           END)
    FROM   public.orders o
    WHERE  od.order_id    = o.order_id
      AND  od.product_id  = NEW.product_id
      AND  o.order_status <> 'Canceled'
      AND  o.order_date   >= NEW.date_updated
      AND  (v_date_end IS NULL OR o.order_date < v_date_end)
      AND  COALESCE(od.quantity, 0) > 0
      -- The four guards from 000004, unchanged.
      AND  NOT COALESCE(o.is_legacy_import, false)
      AND  NOT COALESCE(o.posted, false)
      AND  od.amount_override IS NULL
      -- And a fifth. `posted` is the immutability LOCK, not "invoiced": at MCR
      -- 3,761 orders carry an invoice number and only 203 are posted -- 201 of
      -- those by the QuickBooks importer, with exactly ONE invoice ever sent
      -- from STRATA. So `NOT posted` was protecting almost nothing. Anything
      -- you have invoiced is now off limits regardless, because a figure a
      -- customer has already been sent must never move underneath them.
      AND  o.invoice_number IS NULL
      -- And a sixth. A true-up is for HISTORY. An order still Open or Packed
      -- has not happened yet, and repricing a live order underneath the person
      -- working it is not correcting history, it is changing a commitment.
      --
      -- The split on MCR's own data is exact: the 40 uninvoiced orders dated
      -- before their invoicing cutover are all Delivered, spanning Jun 2025 to
      -- Jun 2026 -- genuinely historical, never invoiced, and precisely what
      -- this function exists for. The 100 uninvoiced orders after it are all
      -- Open, dated Aug-Sep 2026. Forty in, one hundred out.
      --
      -- Allow-list rather than `<> 'Open'`: a status added later should have to
      -- be let in deliberately, not inherit permission to rewrite money.
      AND  o.order_status IN ('Delivered', 'Shipped')
      -- And a seventh. The owner assumed emailing an invoice locked the order.
      -- It does not: finalize_invoice is what locks, and the send path has a
      -- fallback --
      --   invoiceNumber: order.invoice_number ?? order.shop_order_ref ?? order.order_id
      -- so a document with a total on it can be emailed to a customer for an
      -- order that was never finalized, and nothing about it was locked.
      --
      -- invoice_sent_at IS stamped on every send path, so it is the honest
      -- record of "this figure has been in front of a customer". A number
      -- somebody has been sent must never move, finalized or not.
      AND  o.invoice_sent_at IS NULL
      -- And the last one. A shop order is FINAL at checkout: the buyer was
      -- shown a total, agreed to it, and in the card flow has already paid.
      -- sendOrderConfirmationEmail goes out from the checkout itself, and it
      -- does NOT stamp invoice_sent_at -- that column belongs to the invoice
      -- paths -- so a delivered shop order would otherwise have satisfied
      -- every other guard here.
      --
      -- The owner: "order confirmation from the shop is a final."
      AND  o.shop_order_ref IS NULL;

    RETURN NEW;
END;
$function$;;

do $$
declare
  v_src text;
  v_n   int;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.handle_order_detail_logic()'::regprocedure;
  if position('order_allocated' in v_src) = 0 then
    raise exception 'handle_order_detail_logic still reads an allocated share per unit';
  end if;

  select prosrc into v_src from pg_proc
  where oid = 'public.propagate_price_log_to_orders()'::regprocedure;
  v_n := (length(v_src) - length(replace(v_src, '''order_allocated''', '')))
         / length('''order_allocated''');
  if v_n <> 2 then
    raise exception 'propagate_price_log_to_orders needs the allocated arm in BOTH copies of its CASE, found %', v_n;
  end if;

  -- Everything 000008-000012 put in this function must still be here.
  if position('backfill_orders' in v_src) = 0
     or position('o.invoice_number IS NULL' in v_src) = 0
     or position('order_status IN (''Delivered'', ''Shipped'')' in v_src) = 0
     or position('o.invoice_sent_at IS NULL' in v_src) = 0
     or position('o.shop_order_ref IS NULL' in v_src) = 0 then
    raise exception 'a guard from 000008-000012 was lost in this rewrite';
  end if;
end $$;

commit;
