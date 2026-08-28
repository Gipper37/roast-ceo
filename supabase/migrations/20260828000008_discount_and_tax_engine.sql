-- The discount and tax engine: lines compute their own net, orders compute
-- their own tax.
--
-- 20260828000002 laid the schema and the resolver and deliberately computed
-- nothing. This turns it on.
--
-- ── THE TWO TRAPS, BOTH VERIFIED ON PROD BEFORE WRITING THIS ─────────────────
--
-- (1) guard_posted_order_immutable LOCKS orders.discount_total. It is NULL on
--     both posted orders, and NULL -> 0 counts as a change: tested, and the
--     update raises 'order ... is a posted invoice'. So the backfill below runs
--     with the guard neutralised. Skip that and every header write on every
--     posted invoice — recording a payment, marking shipped, voiding — starts
--     failing the moment discount_total becomes a maintained column.
--
-- (2) guard_posted_order_detail_immutable locks quantity, product_id and
--     total_price and knows NOTHING about the six discount columns. Verified: it
--     mentions none of them. That means on a POSTED invoice someone could move
--     discount_amount without touching total_price — the net holds still, the
--     invariant list - discount = net breaks silently, and last quarter's
--     discount reporting restates. The guard now names every one of them.
--
-- ── WHAT COMPUTES, AND WHEN ──────────────────────────────────────────────────
-- A line resolves its discount ONCE, on INSERT, and snapshots it. Everything
-- afterwards re-derives the money from the stored kind and value, never from the
-- rule — so renegotiating a deal cannot restate an issued invoice.
--
-- Tax and order-level discounts are CALLED, not triggered. Money arithmetic
-- hidden inside a trigger chain is how a total ends up depending on the order
-- rows happened to be written in. The app calls apply_order_discount() and
-- recompute_order_tax() at the moments it means to, and both are idempotent.

begin;

-- ── Trap 1 ───────────────────────────────────────────────────────────────────
alter table public.orders disable trigger user;
update public.orders set discount_total = 0 where discount_total is null;
alter table public.orders enable trigger user;

-- ── Trap 2 ───────────────────────────────────────────────────────────────────
create or replace function public.guard_posted_order_detail_immutable()
returns trigger
language plpgsql
as $function$
DECLARE v_posted boolean;
BEGIN
  SELECT posted INTO v_posted FROM public.orders
   WHERE order_id = COALESCE(NEW.order_id, OLD.order_id);

  IF NOT COALESCE(v_posted, false) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'cannot remove a line from posted invoice % — void or issue a credit memo', OLD.order_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'cannot add a line to posted invoice % — void or issue a credit memo', NEW.order_id;
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
  OR (NEW.amount_override  IS DISTINCT FROM OLD.amount_override) THEN
    RAISE EXCEPTION 'line on posted invoice % is locked — void or issue a credit memo', OLD.order_id;
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

        -- ── DISCOUNT ────────────────────────────────────────────────────
        -- Resolved ONCE, when the line is first written, and then snapshotted.
        -- A deal renegotiated next March must never restate an invoice issued
        -- last June — the same rule unit_price_at_sale exists to enforce, applied
        -- to the other half of the number.
        --
        -- Only on INSERT, and only when nobody has already set a discount by
        -- hand: a discount typed on the line beats the customer's standing deal.
        IF TG_OP = 'INSERT' AND NEW.discount_kind IS NULL THEN
            SELECT d.customer_discount_id, d.kind, d.value
              INTO v_disc_rule, v_disc_kind, v_disc_value
              FROM public.resolve_customer_discount(NEW.customer_id, NEW.product_id, NEW.order_date) d;
            IF v_disc_kind IS NOT NULL THEN
                NEW.discount_kind   := v_disc_kind;
                NEW.discount_value  := v_disc_value;
                NEW.discount_rule_id := v_disc_rule;
                NEW.discount_source := 'customer_rule';
            END IF;
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

        -- ── GROSS, DISCOUNT, NET ────────────────────────────────────────
        -- Whatever the branches above decided becomes the LIST price; the
        -- discount comes off it; total_price keeps meaning the NET, which is what
        -- 21 places already read and what order_total sums.
        NEW.list_price_total := NEW.total_price;

        IF NEW.discount_kind IS NOT NULL AND COALESCE(NEW.discount_value, 0) > 0 THEN
            NEW.discount_amount := CASE
                WHEN NEW.discount_kind = 'percent'
                    THEN round(abs(NEW.list_price_total) * NEW.discount_value / 100.0, 2)
                -- A fixed amount can never exceed the line: a discount reduces a
                -- charge, it does not turn one into a payment.
                ELSE least(NEW.discount_value, abs(NEW.list_price_total))
            END;
        ELSE
            NEW.discount_amount := 0;
        END IF;

        -- Signed so a credit-memo or discount line (already negative) is reduced
        -- toward zero rather than made more negative.
        NEW.total_price := NEW.list_price_total
                           - (sign(COALESCE(NEW.list_price_total, 0)) * COALESCE(NEW.discount_amount, 0));

        -- Keep the unit snapshot consistent with the net actually charged.
        IF COALESCE(NEW.quantity, 0) <> 0 THEN
            NEW.unit_price_at_sale := NEW.total_price / NEW.quantity;
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
$function$

;

-- ── An order-level discount, ALLOCATED to the lines ──────────────────────────
-- Never stored only on the header. order_total is a sum of the lines and 21
-- places read those lines; a discount that lived only on the order would be
-- invisible to every one of them and would overstate revenue and margin.
--
-- Allocated in proportion to each line's net, with the rounding remainder given
-- to the largest line so the parts always add back to the whole.
create or replace function public.apply_order_discount(
  p_order_id text,
  p_kind     text,        -- 'percent' | 'amount' | null to clear
  p_value    numeric
)
returns numeric
language plpgsql
as $function$
declare
  v_base      numeric;
  v_target    numeric;
  v_allocated numeric := 0;
  v_biggest   text;
  r           record;
begin
  if exists (select 1 from public.orders where order_id = p_order_id and coalesce(posted,false)) then
    raise exception 'order % is posted — void or issue a credit memo', p_order_id;
  end if;

  -- Clear any previous order-level allocation first, so this is idempotent and
  -- re-applying does not compound. Line-level and customer-rule discounts are
  -- left alone; only our own allocation is reversible here.
  update public.order_details
     set discount_kind = null, discount_value = null, discount_amount = 0,
         discount_source = null, total_price = list_price_total
   where order_id = p_order_id and discount_source = 'order_allocated';

  update public.orders
     set discount_kind = p_kind, discount_value = p_value
   where order_id = p_order_id;

  if p_kind is null or coalesce(p_value,0) <= 0 then
    update public.orders set discount_total = 0 where order_id = p_order_id;
    return 0;
  end if;

  -- Only positive lines that DO NOT already carry their own discount. Two
  -- reasons, and they are the same reason:
  --
  --   The rule says a line gets ONE discount and something set on the line beats
  --   the order-level one. Allocating over a line that already has a customer
  --   rule or a hand-typed amount would silently replace it.
  --
  --   And it would not be reversible. Re-applying has to REPLACE the previous
  --   allocation, which means undoing it — but undoing a line whose own discount
  --   had been overwritten cannot restore what was there. Caught in rehearsal:
  --   applying 10% twice gave $73.00 and then $73.50, because the first pass had
  --   eaten a line discount it could not put back.
  --
  -- A credit-memo line is excluded too: taking a share off a negative line would
  -- increase what the customer owes.
  select coalesce(sum(total_price),0) into v_base
    from public.order_details
   where order_id = p_order_id and total_price > 0
     and coalesce(discount_source,'') in ('', 'order_allocated');
  if v_base <= 0 then
    update public.orders set discount_total = 0 where order_id = p_order_id;
    return 0;
  end if;

  v_target := least(
    case when p_kind = 'percent' then round(v_base * p_value / 100.0, 2) else p_value end,
    v_base);

  select order_detail_id into v_biggest
    from public.order_details
   where order_id = p_order_id and total_price > 0
     and coalesce(discount_source,'') in ('', 'order_allocated')
   order by total_price desc, order_detail_id limit 1;

  for r in
    select order_detail_id, total_price
      from public.order_details
     where order_id = p_order_id and total_price > 0
       and coalesce(discount_source,'') in ('', 'order_allocated')
     order by total_price desc, order_detail_id
  loop
    declare v_share numeric;
    begin
      if r.order_detail_id = v_biggest then
        v_share := 0;  -- settled last, so it absorbs the remainder
      else
        v_share := round(v_target * r.total_price / v_base, 2);
        v_allocated := v_allocated + v_share;
        update public.order_details
           set discount_amount = v_share,
               discount_kind   = 'amount',
               discount_value  = v_share,
               discount_source = 'order_allocated',
               total_price     = list_price_total - v_share
         where order_detail_id = r.order_detail_id;
      end if;
    end;
  end loop;

  if v_biggest is null then
    update public.orders set discount_total = 0 where order_id = p_order_id;
    return 0;
  end if;

  update public.order_details
     set discount_amount = v_target - v_allocated,
         discount_kind   = 'amount',
         discount_value  = v_target - v_allocated,
         discount_source = 'order_allocated',
         total_price     = list_price_total - (v_target - v_allocated)
   where order_detail_id = v_biggest;

  update public.orders set discount_total = v_target where order_id = p_order_id;
  return v_target;
end;
$function$;

comment on function public.apply_order_discount is
  'Take a percentage or an amount off a whole order, allocated across its lines '
  'in proportion to their value with the remainder on the largest. Idempotent: '
  'calling it again replaces the previous allocation rather than compounding. '
  'Refuses on a posted invoice.';

-- ── Tax on an order ──────────────────────────────────────────────────────────
-- Computed on order_total, which is the sum of the NET lines — so the ordering
-- is discount first, then tax, which is the correct one.
create or replace function public.recompute_order_tax(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_o       record;
  v_rate_id text;
  v_charge  numeric;
  v_pass    boolean;
  v_tax     numeric;
begin
  select o.order_id, o.company_id, o.facility_id, o.customer_id, o.order_date,
         o.order_total, coalesce(o.posted,false) as posted
    into v_o
    from public.orders o where o.order_id = p_order_id;
  if not found then return null; end if;
  if v_o.posted then
    raise exception 'order % is posted — its tax is locked', p_order_id;
  end if;

  -- One rate for the order, resolved from its most-sold product type. Per-line
  -- tax is a later problem: MCR's seven years of QuickBooks contain ZERO
  -- invoices carrying two different rates, so order-level reproduces all of it.
  select public.resolve_tax_rate(
           v_o.company_id, v_o.facility_id,
           (select p.channel from public.order_details od
              join public.products p on p.product_id = od.product_id
             where od.order_id = p_order_id
             group by p.channel order by sum(od.total_price) desc nulls last limit 1),
           (select p.product_type from public.order_details od
              join public.products p on p.product_id = od.product_id
             where od.order_id = p_order_id
             group by p.product_type order by sum(od.total_price) desc nulls last limit 1),
           v_o.customer_id, v_o.order_date)
    into v_rate_id;

  if v_rate_id is null then
    -- Unresolved is not zero. Leave the amount alone and let the caller show
    -- that nothing was determined, rather than quietly charging nothing.
    update public.orders set tax_rate_id = null where order_id = p_order_id;
    return null;
  end if;

  select t.charge_rate into v_charge from public.tax_rate t where t.tax_rate_id = v_rate_id;
  select coalesce(c.tax_passed_through, true) into v_pass
    from public.customers c where c.customer_id = v_o.customer_id;

  -- Pass-through decides only whether it is ADDED to the invoice. The rate is
  -- recorded either way, because the liability exists either way and the return
  -- is built from the rate, not from what was charged.
  v_tax := case when coalesce(v_pass, true)
                then round(coalesce(v_o.order_total,0) * coalesce(v_charge,0), 2)
                else 0 end;

  update public.orders
     set tax_rate_id = v_rate_id,
         tax_rate = v_charge,
         tax_amount = v_tax,
         tax_passed_through = coalesce(v_pass, true)
   where order_id = p_order_id;
  return v_tax;
end;
$function$;

comment on function public.recompute_order_tax is
  'Resolve and stamp this order''s tax. Computed on order_total, which is the sum '
  'of NET lines, so discounts come off before tax. Returns NULL when no rate '
  'resolves — which means unresolved, not zero, and the caller must surface it. '
  'Refuses on a posted invoice.';

commit;
