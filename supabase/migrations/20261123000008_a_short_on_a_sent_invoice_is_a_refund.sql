-- A short on a sent invoice is a refund, not a reprice.
--
-- Owner, 2026-11-23, on a paid invoice whose last line went out short:
--   "ok so does it refund the whole order to AP. why can't we just refund
--    that portion of the order"
--
-- It did refund the whole charge, and nothing underneath was the reason:
-- refundInvoicePayment has always taken an optional amount, the ActivityPay
-- adapter posts whatever cents it is handed, and the refund webhook already
-- reconciles A/R to what the customer KEPT -- shrinking the allocation and the
-- payment row rather than voiding them. The gap was that a paid, emailed
-- invoice is a closed loop: the out-of-stock control is not drawn, a credit
-- memo needs a balance owing, revise-and-reissue is excluded on 'paid', and a
-- plain void is refused for want of a refund. The only button left sent all
-- of it.
--
-- This migration opens exactly one door: a line on a sent invoice may come
-- DOWN, once, with a reason, and the arithmetic that is already there follows
-- it -- the line total, then orders.order_total, then the tax, then the refund
-- for the difference. Everything else the guards refuse today they still
-- refuse: no DELETE, no new line, no quantity going back up, no product
-- change, no discount change, nothing on a voided or imported document.
--
-- Four bodies, three of them CREATE OR REPLACE of a live function -- each one
-- the exact prosrc read out of prod with one block inserted, never retyped.

CREATE OR REPLACE FUNCTION public.guard_posted_order_detail_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_posted boolean; v_type text;
BEGIN
  v_posted := public.order_document_is_closed(COALESCE(NEW.order_id, OLD.order_id));

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- 🔴 THE QUICKBOOKS IMPORTER BUILDS ITS HEADERS 'Delivered' AND INSERTS THE
  -- LINES AS A SECOND STATEMENT, so once a header stamps closed on INSERT
  -- every line of every imported invoice is refused -- nothing imports. And
  -- revertQbImport deletes children first by design, so a half-landed batch
  -- cannot be undone through the product either. Imported history is already
  -- unreachable from every screen and refused by finalize_invoice, and
  -- guard_order_invoice_columns and handle_order_detail_logic both carve it
  -- out exactly here; this guard was the one that did not.
  IF EXISTS (SELECT 1 FROM public.orders o
              WHERE o.order_id = COALESCE(NEW.order_id, OLD.order_id)
                AND COALESCE(o.is_legacy_import, false)) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- The one sanctioned append: a late-fee line, inserted by apply_late_fee
    -- in THIS transaction (the sentinel names the order). Product type alone
    -- was spoofable over PostgREST — RLS is tenancy-only (review P1).
    SELECT p.product_type INTO v_type FROM public.products p WHERE p.product_id = NEW.product_id;
    IF v_type = 'ptype_late_fee'
       AND current_setting('app.late_fee_append', true) = NEW.order_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'invoice % has gone to the customer — void it or issue a credit memo', NEW.order_id;
  END IF;

  -- Correcting the price of something nobody was ever billed for. What was
  -- delivered is untouched: quantity, product and the override all stand. See
  -- the header — this is the width of the "apply to past orders" true-up and
  -- nothing else, and it is decided from the row, not from a caller's claim.
  -- 🔴 PIN THE DISCOUNT INPUTS, NOT ONLY THE OUTPUTS. trg_handle_order_details
  -- sorts BEFORE this guard and derives list_price_total, discount_amount,
  -- total_price, unit_cost_at_sale and roasted_weight from discount_kind and
  -- discount_value. So an exception that let those two through was not a
  -- price correction at all: one PATCH of {"discount_kind":"percent",
  -- "discount_value":100} took a closed line's net to zero, restated
  -- orders.order_total through update_order_aggregates, and re-stamped the
  -- line's COGS at TODAY's product cost -- which is what customer_profitability
  -- reads. 12,001 closed orders / 26,419 lines / $5.2m of line money.
  --
  -- The true-up itself never writes them (it SETs only unit_price_at_sale,
  -- list_price_total, discount_amount, total_price), so pinning them costs
  -- the feature nothing and makes the exception exactly its own width.
  --
  -- 🔴 AND ASK THE REASON, NOT THE INVOICE NUMBER. 20261112000005 added two
  -- terms the old expression could not reach -- money recorded, and
  -- voided/written off -- because the owner's rule is "if a payment has been
  -- recorded it shouldn't be editable" and "not editable if voided". Inferring
  -- "never billed" from invoice_number re-admitted every one of those rows
  -- that happens to carry no STRATA number: three prod orders are Delivered
  -- with paid_at stamped and no number today, one of them carrying $91.10.
  -- document_closed_reason is the column that was added for this question.
  IF  NEW.quantity         IS NOT DISTINCT FROM OLD.quantity
  AND NEW.product_id       IS NOT DISTINCT FROM OLD.product_id
  AND NEW.amount_override  IS NOT DISTINCT FROM OLD.amount_override
  AND NEW.discount_kind    IS NOT DISTINCT FROM OLD.discount_kind
  AND NEW.discount_value   IS NOT DISTINCT FROM OLD.discount_value
  AND NEW.discount_source  IS NOT DISTINCT FROM OLD.discount_source
  AND NEW.discount_rule_id IS NOT DISTINCT FROM OLD.discount_rule_id
  AND NEW.quantity_ordered IS NOT DISTINCT FROM OLD.quantity_ordered
  AND NEW.short_reason     IS NOT DISTINCT FROM OLD.short_reason
  AND EXISTS (SELECT 1 FROM public.orders o
               WHERE o.order_id = NEW.order_id
                 AND o.document_closed_reason IN ('delivered', 'shipped')
                 AND o.invoice_number  IS NULL
                 AND o.invoice_sent_at IS NULL
                 AND o.shop_order_ref  IS NULL
                 AND NOT COALESCE(o.is_legacy_import, false)
                 -- 🔴 THE REASON CANNOT ANSWER "HAS ANYONE BEEN BILLED". It
                 -- records what closed the document FIRST, and the CASE that
                 -- writes it ranks 'delivered' above 'paid' because delivery
                 -- comes first in the real workflow. So a delivered order
                 -- whose payment was recorded still reads 'delivered' -- the
                 -- three prod orders this carve-out's own comment names are
                 -- exactly those, one of them carrying $91.10. Ask the money.
                 AND o.paid_at IS NULL
                 AND COALESCE(o.invoice_state, '') NOT IN ('paid', 'partial')
                 AND NOT EXISTS (SELECT 1 FROM public.invoice_payment_allocations a
                                   JOIN public.invoice_payments ip ON ip.payment_id = a.payment_id
                                  WHERE a.order_id = o.order_id
                                    AND ip.voided_at IS NULL)) THEN
    RETURN NEW;
  END IF;

  -- ── A SHORT IS NOT A REPRICE. IT IS WHAT WE ACTUALLY SHIPPED. ──────────
  -- Owner, 2026-11-23, looking at a paid invoice with a line that went out
  -- short: *"why can't we just refund that portion of the order"*. Until now
  -- there was no way to say it. Marking a line out of stock is drawn only
  -- while `canShort && !invoiceLocked`, a credit memo needs a balance owing,
  -- revise-and-reissue is excluded on 'paid', and a plain void is refused by
  -- zx_guard_void_needs_refund -- so on a paid, emailed invoice the only
  -- button left sent the WHOLE charge back. The lock message says "void it or
  -- issue a credit memo" and the menu beside it offers neither.
  --
  -- The quantity is the one honest lever: it is what 26 SQL functions and 9
  -- views read as "what this customer got", and lowering it restates the line
  -- forward through the arithmetic that is already there -- total_price, then
  -- orders.order_total via update_order_aggregates, then the refund for
  -- exactly the difference. quantity_ordered keeps what they ASKED for, so
  -- the document can still say "9 of 10" rather than quietly becoming an
  -- order for nine.
  --
  -- ONE DIRECTION ONLY. A short may come down and never go back up: the money
  -- has already gone back to the card and there is no path in this app that
  -- re-charges it. The undo stays refused for the same reason it always was.
  --
  -- 🔴 A TYPED AMOUNT MOVES WITH THE COUNT, AND ONLY TO ONE FIGURE.
  -- handle_order_detail_logic reads amount_override as a LINE total with the
  -- quantity nowhere in the expression, so a line overridden to $160.20 for
  -- ten and shorted to nine would bill the whole $160.20 for nine. The app
  -- already solves that: overrideForCount holds the UNIT the operator meant
  -- and restates the line -- nine at $16.02 is $144.18 -- and both short
  -- writers go through it. 1,323 override lines sit on 436 closed documents,
  -- 69 of them on paid invoices, so refusing them would have left a real
  -- population with no way to short and no refund.
  --
  -- So the override may move, but ONLY to that one figure, and only DOWN.
  -- Like the tax terms below, the arithmetic is the test: the single value
  -- admitted is the one the sanctioned restatement produces from this line's
  -- own OLD amount over its own OLD count. Anything else -- a raise, a retype,
  -- a clear -- is refused, and a clear is what the UNDO writes, which is one
  -- more reason the undo stays shut.
  --
  -- A 'ptype_discount' line can never be shorted (NOT_SHORTABLE), so the
  -- override here is never the negative, reduces_total kind and numeric
  -- round() agrees with the app's Math.round for every value that can reach
  -- it. If they ever did disagree by a cent this REFUSES rather than paying
  -- out, which is the right way round.
  IF  NEW.quantity         IS NOT NULL
  AND OLD.quantity         IS NOT NULL
  AND NEW.quantity         <  OLD.quantity
  AND NEW.quantity         >= 0
  AND nullif(btrim(COALESCE(NEW.short_reason, '')), '') IS NOT NULL
  -- Written ONCE, to what was asked for: either it already held that, or this
  -- is the first short and it takes the quantity this line is coming down from.
  AND NEW.quantity_ordered IS NOT DISTINCT FROM COALESCE(OLD.quantity_ordered, OLD.quantity)
  AND (  (NEW.amount_override IS NULL AND OLD.amount_override IS NULL)
      -- OLD.quantity > 0 is guaranteed above (NEW.quantity < OLD.quantity and
      -- NEW.quantity >= 0), so the division is safe.
      OR (OLD.amount_override IS NOT NULL
          AND NEW.amount_override IS NOT DISTINCT FROM
                round(OLD.amount_override / OLD.quantity * NEW.quantity, 2)))
  AND NEW.product_id       IS NOT DISTINCT FROM OLD.product_id
  AND NEW.discount_kind    IS NOT DISTINCT FROM OLD.discount_kind
  AND NEW.discount_value   IS NOT DISTINCT FROM OLD.discount_value
  AND NEW.discount_source  IS NOT DISTINCT FROM OLD.discount_source
  AND NEW.discount_rule_id IS NOT DISTINCT FROM OLD.discount_rule_id
  AND NEW.parent_order_detail_id IS NOT DISTINCT FROM OLD.parent_order_detail_id
  -- A voided or written-off document is settled history: nothing to refund and
  -- nothing to restate. Legacy is already carved out above.
  AND EXISTS (SELECT 1 FROM public.orders o
               WHERE o.order_id = NEW.order_id
                 AND COALESCE(o.document_closed_reason, '') NOT IN ('voided', 'written_off')
                 AND COALESCE(o.invoice_state, '')          NOT IN ('void', 'written_off')) THEN
    RETURN NEW;
  END IF;

  -- Every number the invoice shows, not just the net. A discount that can move
  -- while total_price stands still is a silently restated invoice.
  IF (NEW.quantity         IS DISTINCT FROM OLD.quantity)
  OR (NEW.product_id       IS DISTINCT FROM OLD.product_id)
  OR (NEW.total_price      IS DISTINCT FROM OLD.total_price)
  OR (NEW.list_price_total IS DISTINCT FROM OLD.list_price_total)
  OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
  OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
  OR (NEW.discount_amount  IS DISTINCT FROM OLD.discount_amount)
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override)
  OR (NEW.quantity_ordered IS DISTINCT FROM OLD.quantity_ordered)
  OR (NEW.short_reason     IS DISTINCT FROM OLD.short_reason)
  -- 🔴 THE RATE IS A FIGURE THE CUSTOMER WAS CHARGED AT. Nothing writes it on
  -- a closed document, and re-pointing a line at a cheaper rate is the first
  -- half of a tax write-down.
  OR (NEW.tax_rate_id      IS DISTINCT FROM OLD.tax_rate_id)
  -- The line's tax may fall, and ONLY to the figure its own stored rate makes
  -- of its own new total_price -- which is the one thing a short produces, and
  -- the one thing resettle_order_tax_after_short writes. Any other value, a
  -- rise, or a stamp appearing where there was none, is refused. COALESCE
  -- because a NULL comparison would leave the whole OR unknown, and an
  -- unknown does not raise.
  OR (NEW.tax_amount IS DISTINCT FROM OLD.tax_amount
      AND NOT COALESCE(
              NEW.tax_amount < OLD.tax_amount
          AND NEW.tax_amount IS NOT DISTINCT FROM (
                CASE WHEN COALESCE((SELECT o.tax_passed_through FROM public.orders o
                                     WHERE o.order_id = NEW.order_id), true)
                     THEN round(COALESCE(NEW.total_price, 0)
                                * COALESCE((SELECT t.charge_rate FROM public.tax_rate t
                                             WHERE t.tax_rate_id = NEW.tax_rate_id), 0), 2)
                     ELSE 0 END),
          false)) THEN
    RAISE EXCEPTION 'invoice % has gone to the customer, so its lines are locked — void it or issue a credit memo', OLD.order_id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.guard_posted_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_why text; v_billed boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.posted THEN
      RAISE EXCEPTION 'order % carries an invoice number and cannot be deleted — void it instead', OLD.order_id;
    END IF;
    RETURN OLD;
  END IF;

  -- A NUMBER IS WRITE-ONCE, NOT CLOSED-LOCKED. Blank becomes a number at any
  -- time -- that is how a delivered order still gets an invoice for the driver
  -- to get signed, a cheque recorded, or a card charged. A number never becomes
  -- a different number, open or closed, which is the thing that actually
  -- matters: an invoice number the customer has quoted cannot be restated.
  IF (OLD.invoice_number IS NOT NULL AND NEW.invoice_number IS DISTINCT FROM OLD.invoice_number)
  OR (OLD.invoice_sequence IS NOT NULL AND NEW.invoice_sequence IS DISTINCT FROM OLD.invoice_sequence) THEN
    RAISE EXCEPTION 'invoice % already carries number % — a number cannot be changed or cleared (void and reissue instead)', OLD.order_id, OLD.invoice_number;
  END IF;

  IF COALESCE(OLD.document_closed_at, NEW.document_closed_at) IS NOT NULL THEN
    v_why := COALESCE(OLD.document_closed_reason, NEW.document_closed_reason, 'emailed');
    -- 🔴 TAX IS DERIVED, AND finalize_invoice RESOLVES IT AT THE MOMENT OF
    -- NUMBERING. Its last act before minting is recompute_order_tax, whose
    -- final statement writes these columns -- so locking them on a closed
    -- document breaks the exact flow this migration exists to enable:
    -- accounting invoices a delivered order, the guard raises, and finalize's
    -- own `exception when others` swallows it to a NOTICE nobody sees over
    -- PostgREST. The invoice is issued with no tax at all. Measured on prod:
    -- 30 delivered, never-billed orders would have lost $69.03 of tax the
    -- roaster owes, silently, growing with every delivered-and-unbilled order.
    --
    -- So the rule here is the one 20261112000007 states for lines: A FIGURE
    -- THE CUSTOMER HAS SEEN NEVER MOVES. Never numbered and never sent means
    -- nobody has seen it, and a derived figure may still be resolved. The
    -- discount INPUTS stay locked either way -- those are a decision, not an
    -- arithmetic, and the owner's rule is that a delivered order is not
    -- editable.
    --
    -- Written to be the SAME test 20261112000007 uses on the lines, so the
    -- header and the lines cannot disagree about which orders a correction
    -- may still reach: if the lines moved, the arithmetic over them has to be
    -- allowed to follow, or the invoice contradicts itself.
    v_billed := (OLD.invoice_number IS NOT NULL
              OR OLD.invoice_sent_at IS NOT NULL
              OR OLD.shop_order_ref  IS NOT NULL
              OR COALESCE(OLD.is_legacy_import, false)
              -- The money terms, for the reason order_figures_are_final
              -- carries them: the reason says what closed the document
              -- first, and delivery outranks payment.
              OR OLD.paid_at IS NOT NULL
              OR COALESCE(OLD.invoice_state, '') IN ('paid', 'partial')
              OR COALESCE(OLD.document_closed_reason, '') NOT IN ('delivered', 'shipped'));
    IF (NEW.customer_id      IS DISTINCT FROM OLD.customer_id)
    OR (NEW.order_date       IS DISTINCT FROM OLD.order_date)
    OR (v_billed AND (
           -- 🔴 TAX IS PER LINE, SO A SHORT HAS TO BE ABLE TO FOLLOW IT
           -- DOWN. order_details.tax_amount is the money; orders.tax_amount
           -- is their sum, written by recompute_order_tax -- which raises
           -- outright once the invoice has been sent, exactly so a figure the
           -- customer has seen cannot move. That is still the rule. What a
           -- short needs is narrower: the same arithmetic over FEWER units.
           --
           -- So this term admits one shape and nothing else -- a header that
           -- has just become the re-sum of its own lines, is strictly LOWER
           -- than it was, and leaves every other tax column where it stood.
           -- It cannot be used to restate tax, because the only value it
           -- accepts is the one the lines themselves already add up to.
           -- resettle_order_tax_after_short is what produces it.
           --
           -- Measured on prod before writing this: of 16,277 closed
           -- documents, every one whose lines carry a tax stamp agrees with
           -- its header to the cent (514 non-legacy, 0 disagreements). The
           -- 3,773 that disagree are header-only tax -- 3,701 QuickBooks
           -- imports and 72 non-legacy orders stamped before the per-line
           -- model, none of them paid. resettle_order_tax_after_short refuses
           -- those outright rather than restating them from lines that were
           -- never stamped.
           ((NEW.tax_amount IS DISTINCT FROM OLD.tax_amount)
            AND NOT (
                    NEW.tax_amount < OLD.tax_amount
                AND NEW.tax_amount IS NOT DISTINCT FROM (
                      SELECT round(COALESCE(SUM(od.tax_amount), 0), 2)
                        FROM public.order_details od
                       WHERE od.order_id = NEW.order_id)
                AND NEW.tax_rate           IS NOT DISTINCT FROM OLD.tax_rate
                AND NEW.tax_rate_id        IS NOT DISTINCT FROM OLD.tax_rate_id
                AND NEW.tax_basis          IS NOT DISTINCT FROM OLD.tax_basis
                AND NEW.prices_include_tax IS NOT DISTINCT FROM OLD.prices_include_tax
                AND NEW.tax_passed_through IS NOT DISTINCT FROM OLD.tax_passed_through))
        OR (NEW.tax_rate           IS DISTINCT FROM OLD.tax_rate)
        OR (NEW.tax_rate_id        IS DISTINCT FROM OLD.tax_rate_id)
        OR (NEW.tax_basis          IS DISTINCT FROM OLD.tax_basis)
        OR (NEW.prices_include_tax IS DISTINCT FROM OLD.prices_include_tax)
        OR (NEW.tax_passed_through IS DISTINCT FROM OLD.tax_passed_through)
        OR (NEW.discount_total     IS DISTINCT FROM OLD.discount_total)))
    OR (NEW.discount_kind    IS DISTINCT FROM OLD.discount_kind)
    OR (NEW.discount_value   IS DISTINCT FROM OLD.discount_value)
    OR (
      (   (NEW.bill_to_name     IS DISTINCT FROM OLD.bill_to_name)
       OR (NEW.bill_to_address  IS DISTINCT FROM OLD.bill_to_address)
       OR (NEW.bill_to_address_2 IS DISTINCT FROM OLD.bill_to_address_2)
       OR (NEW.bill_to_city     IS DISTINCT FROM OLD.bill_to_city)
       OR (NEW.bill_to_state    IS DISTINCT FROM OLD.bill_to_state)
       OR (NEW.bill_to_zip      IS DISTINCT FROM OLD.bill_to_zip)
       OR (NEW.bill_to_country  IS DISTINCT FROM OLD.bill_to_country)
       OR (NEW.bill_to_email    IS DISTINCT FROM OLD.bill_to_email)
       OR (NEW.bill_to_phone    IS DISTINCT FROM OLD.bill_to_phone)
      )
      -- The one way in: no JWT, an order holding no address, a whole address
      -- arriving, and any contact the order already holds left as it is. Once
      -- this has fired the order holds an address, so it can only fire once.
      AND NOT (
            auth.uid() IS NULL
        AND nullif(btrim(OLD.bill_to_address), '')   IS NULL
        AND nullif(btrim(OLD.bill_to_address_2), '') IS NULL
        AND nullif(btrim(OLD.bill_to_city), '')      IS NULL
        AND nullif(btrim(OLD.bill_to_state), '')     IS NULL
        AND nullif(btrim(OLD.bill_to_zip), '')       IS NULL
        AND nullif(btrim(NEW.bill_to_address), '')   IS NOT NULL
        AND nullif(btrim(NEW.bill_to_city), '')      IS NOT NULL
        AND nullif(btrim(NEW.bill_to_state), '')     IS NOT NULL
        AND nullif(btrim(NEW.bill_to_zip), '')       IS NOT NULL
        AND (nullif(btrim(OLD.bill_to_name), '')  IS NULL OR NEW.bill_to_name  IS NOT DISTINCT FROM OLD.bill_to_name)
        AND (nullif(btrim(OLD.bill_to_email), '') IS NULL OR NEW.bill_to_email IS NOT DISTINCT FROM OLD.bill_to_email)
        AND (nullif(btrim(OLD.bill_to_phone), '') IS NULL OR NEW.bill_to_phone IS NOT DISTINCT FROM OLD.bill_to_phone)
      )
    )
    THEN
      RAISE EXCEPTION 'this invoice is closed (%) — its document fields are locked. Void and reissue it, or issue a credit memo.', v_why;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

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
        -- 🔴 A SHORT MUST NOT RESTATE WHAT THE COFFEE COST US. v_cogs is
        -- products.total_unit_cogs read a moment ago -- TODAY's cost. On a
        -- new line or a changed product that is right: that IS the snapshot.
        -- But re-stamping it because the quantity moved silently restates the
        -- margin on a closed sale at today's green price, which is what
        -- customer_profitability reads. The guard above already refuses a
        -- quantity edit on a closed document for every reason except a short,
        -- so until now this line could not be reached that way.
        --
        -- On a short, scale the snapshot the line already carries: the cost
        -- of nine of the same thing, at the cost it was booked at. The
        -- closed-document test sits LAST so it is only asked on the rare
        -- lower-quantity update, not on every insert.
        NEW.unit_cost_at_sale := CASE
            WHEN TG_OP = 'UPDATE'
             AND NEW.product_id IS NOT DISTINCT FROM OLD.product_id
             AND COALESCE(OLD.quantity, 0) > 0
             AND COALESCE(NEW.quantity, 0) < COALESCE(OLD.quantity, 0)
             AND OLD.unit_cost_at_sale IS NOT NULL
             AND public.order_document_is_closed(NEW.order_id)
            THEN round(OLD.unit_cost_at_sale
                       * (COALESCE(NEW.quantity, 0)::numeric / OLD.quantity::numeric), 2)
            ELSE COALESCE(NEW.quantity, 0) * v_cogs
        END;

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

-- ─────────────────────────────────────────────────────────────────────────
-- The tax a short leaves overstated.
--
-- recompute_order_tax is the one function that knows this arithmetic, and it
-- raises on a sent invoice by design -- a figure the customer has seen never
-- moves. This is the one sanctioned exception, written as narrowly as it can
-- be: the SAME per-line formula, over the SAME rate each line was stamped
-- with, on fewer units.
--
-- 🔴 IT DOES NOT RE-RESOLVE THE RATE. resolve_tax_rate keys on the channel,
-- the product type, the customer and the ORDER DATE, and any of those rules
-- may have been edited since the invoice went out. Re-resolving would quietly
-- re-rate a sent invoice. The rate on the line is the rate the customer was
-- charged, and it stays.
--
-- 🔴 AND IT REFUSES A DOCUMENT WHOSE HEADER DOES NOT ALREADY EQUAL ITS LINES.
-- 3,773 closed documents on prod carry header-only tax with no line stamps at
-- all (3,701 QuickBooks imports, 72 pre-per-line orders). Re-summing those
-- from their lines would read as a $12,312 tax write-down. If the lines cannot
-- account for the header, this is not ours to restate -- say so, and let the
-- refund go out without the tax.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.resettle_order_tax_after_short(p_order_id text)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_o       record;
  v_hdr_now numeric;
  v_line    record;
  v_charge  numeric;
  v_new     numeric;
  v_sum     numeric;
begin
  select o.order_id,
         coalesce(o.tax_amount, 0)          as tax_amount,
         coalesce(o.tax_passed_through, true) as pass,
         coalesce(o.is_legacy_import, false) as legacy
    into v_o
    from public.orders o
   where o.order_id = p_order_id;
  if not found then
    raise exception 'order % does not exist', p_order_id;
  end if;

  if v_o.legacy then
    raise exception 'order % is imported history — its tax is not ours to restate', p_order_id;
  end if;

  select round(coalesce(sum(coalesce(od.tax_amount, 0)), 0), 2)
    into v_hdr_now
    from public.order_details od
   where od.order_id = p_order_id;

  if v_hdr_now is distinct from round(v_o.tax_amount, 2) then
    raise exception
      'order % carries % of tax that its lines do not account for (they add up to %) — its tax cannot be restated from them',
      p_order_id, round(v_o.tax_amount, 2), v_hdr_now;
  end if;

  -- Each line's OWN stored rate, over its new total_price.
  for v_line in
    select od.order_detail_id, od.total_price, od.tax_rate_id,
           coalesce(od.tax_amount, 0) as tax_amount
      from public.order_details od
     where od.order_id = p_order_id
       and od.tax_rate_id is not null
  loop
    select t.charge_rate into v_charge
      from public.tax_rate t where t.tax_rate_id = v_line.tax_rate_id;

    v_new := case when v_o.pass
                  then round(coalesce(v_line.total_price, 0) * coalesce(v_charge, 0), 2)
                  else 0 end;

    if v_new > v_line.tax_amount then
      raise exception
        'line % would take more tax, not less (% -> %) — this only ever follows a short',
        v_line.order_detail_id, v_line.tax_amount, v_new;
    end if;

    if v_new is distinct from v_line.tax_amount then
      update public.order_details
         set tax_amount = v_new
       where order_detail_id = v_line.order_detail_id;
    end if;
  end loop;

  select round(coalesce(sum(coalesce(od.tax_amount, 0)), 0), 2)
    into v_sum
    from public.order_details od
   where od.order_id = p_order_id;

  if v_sum > round(v_o.tax_amount, 2) then
    raise exception 'order % tax would rise from % to %', p_order_id, v_o.tax_amount, v_sum;
  end if;

  if v_sum is distinct from round(v_o.tax_amount, 2) then
    update public.orders set tax_amount = v_sum where order_id = p_order_id;
  end if;

  return v_sum;
end;
$function$;

-- 🔴 A NEW FUNCTION INHERITS NO EXECUTE GRANT. The short runs as the person
-- pressing the button, so the row-level policies on orders and order_details
-- are what bound it -- this is deliberately NOT security definer.
REVOKE ALL ON FUNCTION public.resettle_order_tax_after_short(text) FROM public;
GRANT EXECUTE ON FUNCTION public.resettle_order_tax_after_short(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6. THE FEATURE'S OWN PERMISSION KEY, which I should have written first.
--
-- Every feature here ships its key, its roles and its plans in the migration
-- that creates it, BEFORE any frontend names it. I had not done that for this
-- one: the press borrowed order.out_of_stock from the short and payment.refund
-- from the refund, and nothing anywhere said "this tenant, this role, may turn
-- a shortage into money going back".
--
-- 🔴 AND IT IS THE DEPLOY INTERLOCK. An unknown key is denied SILENTLY, so
-- until this migration lands currentUserCan('order.short_refund') is false for
-- everyone and the control is never drawn. That is what lets the frontend ship
-- before, with, or after this file without ever offering a press the database
-- would refuse -- the standing rule being that the screen must not offer what
-- the database will refuse, and must not withhold what it would allow. Without
-- it the ordering is a promise somebody has to keep by hand, and the four
-- guard carve-outs above are exactly the kind of thing that arrives late.
--
-- Granted to the INTERSECTION of the two halves, measured on prod rather than
-- assumed: order.out_of_stock is granted to 8 roles and payment.refund to 3
-- (accounting_admin, company_admin, facility_admin). A packer can report an
-- empty shelf; a packer may not send money back. Plan-gated to match
-- payment.refund, which is enterprise and enterprise_plus only.
-- ─────────────────────────────────────────────────────────────────────────
insert into public.permissions (permission_id, category, label, description, is_plan_gated, sort_order)
values ('order.short_refund', 'Payments', 'Refund a line that went out short',
        'Mark a line out of stock on an invoice the customer has already paid by card. The count drops to what you actually sent, what they owe drops with it, and the difference goes back to their card in the same press. No credit memo is sent: the invoice itself shows the refund. Also needs permission to refund payments.',
        true, 72)
on conflict (permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id, granted)
values ('accounting_admin', 'order.short_refund', true),
       ('company_admin',    'order.short_refund', true),
       ('facility_admin',   'order.short_refund', true)
on conflict (role_id, permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted)
values ('enterprise',      'order.short_refund', true),
       ('enterprise_plus', 'order.short_refund', true),
       ('pro',             'order.short_refund', false),
       ('starter',         'order.short_refund', false)
on conflict (plan_id, permission_id) do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- Did the four bodies actually land? CREATE OR REPLACE rewrites the whole
-- function, and a replace built by string surgery that silently missed its
-- anchor leaves the OLD body in place and reports success. Each test below
-- names a fragment of CODE, not of a comment.
-- ─────────────────────────────────────────────────────────────────────────
DO $verify$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'guard_posted_order_detail_immutable';
  IF v_src IS NULL OR position('NEW.quantity         <  OLD.quantity' in v_src) = 0 THEN
    RAISE EXCEPTION 'guard_posted_order_detail_immutable did not take the short carve-out';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'guard_posted_order_immutable';
  IF v_src IS NULL OR position('SELECT round(COALESCE(SUM(od.tax_amount), 0), 2)' in v_src) = 0 THEN
    RAISE EXCEPTION 'guard_posted_order_immutable did not take the tax re-sum carve-out';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'handle_order_detail_logic';
  IF v_src IS NULL OR position('THEN round(OLD.unit_cost_at_sale' in v_src) = 0 THEN
    RAISE EXCEPTION 'handle_order_detail_logic did not take the COGS pin';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'guard_posted_order_detail_immutable';
  IF position('NEW.tax_rate_id      IS DISTINCT FROM OLD.tax_rate_id' in v_src) = 0 THEN
    RAISE EXCEPTION 'guard_posted_order_detail_immutable did not take the line-tax pin';
  END IF;

  IF to_regprocedure('public.resettle_order_tax_after_short(text)') IS NULL THEN
    RAISE EXCEPTION 'resettle_order_tax_after_short was not created';
  END IF;
  IF NOT has_function_privilege('authenticated',
         'public.resettle_order_tax_after_short(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'resettle_order_tax_after_short is not executable by authenticated';
  END IF;

  -- The key is the interlock, so a silent miss here ships a control nobody
  -- can reach and no error anywhere says why.
  IF NOT EXISTS (SELECT 1 FROM public.permissions
                  WHERE permission_id = 'order.short_refund' AND is_plan_gated) THEN
    RAISE EXCEPTION 'order.short_refund was not created, or is not plan gated';
  END IF;
  IF (SELECT count(*) FROM public.role_permissions
       WHERE permission_id = 'order.short_refund' AND granted) <> 3 THEN
    RAISE EXCEPTION 'order.short_refund should be granted to exactly 3 roles, found %',
      (SELECT count(*) FROM public.role_permissions
        WHERE permission_id = 'order.short_refund' AND granted);
  END IF;
  IF (SELECT count(*) FROM public.plan_permissions
       WHERE permission_id = 'order.short_refund' AND granted) <> 2 THEN
    RAISE EXCEPTION 'order.short_refund should be granted to exactly 2 plans, found %',
      (SELECT count(*) FROM public.plan_permissions
        WHERE permission_id = 'order.short_refund' AND granted);
  END IF;
END
$verify$;
