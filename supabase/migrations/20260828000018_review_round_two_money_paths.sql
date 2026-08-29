-- Round two of the review: the money paths the first round did not reach.
--
-- Four fixes, one theme — every path that writes money must speak the same
-- one-direction language as the trigger, and cash-basis filing must actually
-- see the cash.
--
-- 1. recompute_invoice_ar_state stamps orders.paid_at. The cash-basis filing
--    views key on paid_at, but the only writer was shop checkout — an invoice
--    paid through the A/R panel changed invoice_state and nothing else, so a
--    cash-basis tenant's filing report never gained a go-forward payment.
--    Now: fully paid stamps paid_at (the latest live payment's received_date);
--    a void that regresses the state clears it again — but only when the A/R
--    ledger owns the determination, so a checkout-stamped paid_at on an order
--    with no ledger rows is never erased.
--
-- 2. propagate_price_log_to_orders derives instead of clobbering. It wrote
--    quantity × new price straight into total_price: on a discounted line the
--    net became the gross, the stored discount went stale, and
--    list − discount = net stopped holding. It now writes the LIST unit and
--    re-derives discount and net exactly the way handle_order_detail_logic
--    does.
--
-- 3. handle_order_detail_logic honors the UI's promise on clear. "Clear —
--    back to their rate" nulled the discount fields, but the standing
--    customer rule only ever resolved on INSERT, so clearing a manual
--    discount reverted the line to FULL LIST, not the customer's rate. The
--    rule now re-resolves at the moment a discount is cleared (and only at
--    that moment — a quantity edit on a never-discounted line still does not
--    conjure one).
--
-- 4. guard_posted_order_immutable learns the new columns: discount_kind,
--    discount_value and tax_passed_through were mutable on a posted invoice.

begin;

-- ═══ 1. Cash lands in the filing report ══════════════════════════════════════
CREATE OR REPLACE FUNCTION public.recompute_invoice_ar_state(p_order_id text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_total bigint; v_paid bigint; v_state text; v_due date; v_posted boolean; v_new text;
        v_paid_at timestamptz; v_has_ledger boolean;
BEGIN
  SELECT round((COALESCE(order_total,0) + COALESCE(tax_amount,0)) * 100)::bigint,
         invoice_state, due_date, posted, paid_at
    INTO v_total, v_state, v_due, v_posted, v_paid_at
    FROM public.orders WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT COALESCE(v_posted,false) OR v_state IS NULL THEN RETURN v_state; END IF;
  IF v_state IN ('void','written_off') THEN RETURN v_state; END IF;

  SELECT COALESCE(SUM(a.amount_cents),0) INTO v_paid
    FROM public.invoice_payment_allocations a
    JOIN public.invoice_payments p ON p.payment_id = a.payment_id
   WHERE a.order_id = p_order_id AND p.voided_at IS NULL;
  v_paid := v_paid + COALESCE((SELECT SUM(amount_cents) FROM public.credit_memos
                                WHERE applied_to_order_id = p_order_id AND voided_at IS NULL), 0);

  v_new := CASE
             WHEN v_paid >= v_total AND v_total > 0 THEN 'paid'
             WHEN v_paid > 0 THEN 'partial'
             WHEN v_due IS NOT NULL AND v_due < current_date THEN 'overdue'
             ELSE 'open'
           END;

  IF v_new = 'paid' AND v_paid_at IS NULL THEN
    -- Cash basis recognizes on the day the money arrived, not the day someone
    -- recorded it — the latest live payment's received_date, falling back to
    -- now() when a credit memo alone settled the balance.
    UPDATE public.orders o
       SET invoice_state = 'paid',
           paid_at = COALESCE(
             (SELECT MAX(p.received_date)::timestamptz
                FROM public.invoice_payment_allocations a
                JOIN public.invoice_payments p ON p.payment_id = a.payment_id
               WHERE a.order_id = p_order_id AND p.voided_at IS NULL),
             now())
     WHERE o.order_id = p_order_id;
  ELSIF v_new <> 'paid' AND v_state = 'paid' AND v_paid_at IS NOT NULL THEN
    -- Regressing out of paid (a voided payment) un-recognizes the cash — but
    -- only when the A/R ledger made the paid determination. An order paid at
    -- shop checkout has paid_at and no ledger rows; that stamp is not ours to
    -- erase.
    SELECT EXISTS (SELECT 1 FROM public.invoice_payment_allocations WHERE order_id = p_order_id)
        OR EXISTS (SELECT 1 FROM public.credit_memos WHERE applied_to_order_id = p_order_id)
      INTO v_has_ledger;
    UPDATE public.orders
       SET invoice_state = v_new,
           paid_at = CASE WHEN v_has_ledger THEN NULL ELSE paid_at END
     WHERE order_id = p_order_id;
  ELSIF v_new IS DISTINCT FROM v_state THEN
    UPDATE public.orders SET invoice_state = v_new WHERE order_id = p_order_id;
  END IF;
  RETURN v_new;
END; $function$;

-- The invoices already bitten: posted, fully paid, never stamped. As of
-- writing that is MCR's entire posted history (2 invoices) — both were paid
-- through the A/R panel and are invisible to cash-basis filing. Stamp them
-- from their latest live payment.
UPDATE public.orders o
   SET paid_at = COALESCE(
         (SELECT MAX(p.received_date)::timestamptz
            FROM public.invoice_payment_allocations a
            JOIN public.invoice_payments p ON p.payment_id = a.payment_id
           WHERE a.order_id = o.order_id AND p.voided_at IS NULL),
         now())
 WHERE o.posted
   AND o.invoice_state = 'paid'
   AND o.paid_at IS NULL;

-- ═══ 2. Price propagation speaks the one-direction language ══════════════════
CREATE OR REPLACE FUNCTION public.propagate_price_log_to_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_date_end date;
    v_reduces  boolean;
BEGIN
    -- Skip zero/null prices — can't fix orders with no price information
    IF NEW.price IS NULL OR NEW.price = 0 THEN
        RETURN NEW;
    END IF;

    -- End of this entry's validity window: the date_updated of the next price
    -- log entry for this product. Scoped by PRODUCT only — see the header note
    -- on why facility cannot narrow what a product_id match already narrowed.
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
    -- LIST unit; list, discount and net derive from it. The old version wrote
    -- quantity × price straight into total_price, which on a discounted line
    -- replaced the net with the gross and orphaned the stored discount.
    UPDATE public.order_details od
    SET    unit_price_at_sale = CASE WHEN v_reduces THEN -abs(NEW.price) ELSE NEW.price END,
           list_price_total   = CASE WHEN v_reduces
                                     THEN -abs(od.quantity * NEW.price)
                                     ELSE  od.quantity * NEW.price END,
           discount_amount    = CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
               ELSE 0
           END,
           total_price        = (CASE WHEN v_reduces
                                      THEN -abs(od.quantity * NEW.price)
                                      ELSE  od.quantity * NEW.price END)
                                - (CASE WHEN v_reduces THEN -1 ELSE 1 END) * (CASE
               WHEN od.discount_kind = 'percent' AND COALESCE(od.discount_value, 0) > 0
                   THEN round(abs(od.quantity * NEW.price) * od.discount_value / 100.0, 2)
               WHEN od.discount_kind IS NOT NULL AND COALESCE(od.discount_value, 0) > 0
                   THEN least(od.discount_value, abs(od.quantity * NEW.price))
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
      AND  od.amount_override IS NULL;

    RETURN NEW;
END;
$function$;

-- ═══ 3. Clearing a discount restores the customer's rate ═════════════════════
-- Identical to 000017's version except the standing-rule block: the rule now
-- also re-resolves on the UPDATE that clears a discount (OLD had one, NEW has
-- none), and a resolution that finds nothing scrubs the stale rule pointer.
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

        IF NEW.discount_kind IS NOT NULL AND COALESCE(NEW.discount_value, 0) > 0 THEN
            NEW.discount_amount := CASE
                WHEN NEW.discount_kind = 'percent'
                    THEN round(abs(NEW.list_price_total) * NEW.discount_value / 100.0, 2)
                ELSE least(NEW.discount_value, abs(NEW.list_price_total))
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
$function$;

-- ═══ 4. The posted guard learns the new columns ══════════════════════════════
CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % is a posted invoice and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.posted THEN
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (NEW.tax_amount       IS DISTINCT FROM OLD.tax_amount)
    OR (NEW.tax_rate         IS DISTINCT FROM OLD.tax_rate)
    OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
    OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
    OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
    OR (NEW.tax_passed_through IS DISTINCT FROM OLD.tax_passed_through)
    OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
    OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
    OR (NEW.discount_total   IS DISTINCT FROM OLD.discount_total)
    OR (NEW.invoice_number   IS DISTINCT FROM OLD.invoice_number)
    OR (NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence)
    OR (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
    OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
    OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
    OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
    OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
    OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
    OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
    OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
    OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
    THEN
      RAISE EXCEPTION 'order % is a posted invoice — its document fields are locked (void-and-reissue or issue a credit memo to change it)', OLD.order_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

commit;
