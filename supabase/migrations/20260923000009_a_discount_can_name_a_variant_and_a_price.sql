-- A discount can name a variant, and can say what the customer pays.
--
-- Two gaps, both found by the owner asking the right question: "set a price
-- render a discount doesn't really work if we're choosing by product group
-- that has variants does it?"
--
-- It does not. resolve_customer_discount matched scope='product' against the
-- product GROUP, and a group holds variants at different prices -- Maui Blend
-- has eight, from $6.83 for a 2oz to $245.00 for a 10x2lb case. "They pay $9"
-- is not a statement a group can carry. The same mismatch already made a flat
-- "$5 off Maui Blend" take $5 off the 2oz and $5 off the case.
--
-- So: scope 'variant', matching products.product_id, ranked ABOVE 'product'.
-- A variant has exactly one price, which is the level a price statement lives
-- at, and it also makes "$2 off the 12oz but not the 5lb case" expressible for
-- the first time.
--
-- And kind 'price': the value is what the customer PAYS per unit, not what
-- comes off. The discount is derived at order time, so the rule survives a
-- list price change instead of quietly going stale:
--
--   list 11.75, they pay 9.00  ->  discount recorded 2.75
--   MCR raises list to 12.50   ->  discount recorded 3.50, they still pay 9.00
--
-- Storing the derived 2.75 instead, which is what the frontend was doing,
-- means the target silently stops being the target the day a price moves.
--
-- THREE THINGS AN AUDIT OF EVERY CONSUMER TURNED UP, each of which would have
-- shipped a real overcharge:
--
--  1. handle_order_detail_logic matched 'percent' by name and sent EVERY other
--     kind to one ELSE that reads the value as dollars off. A 'price' rule of
--     9.00 against a list of 11.75 would have taken 9.00 off and charged the
--     customer 2.75 -- the discount and the price exactly inverted.
--  2. The gate `COALESCE(discount_value,0) > 0` means "no discount" for a
--     percent or an amount. For a price it means FREE, and the gate would have
--     skipped the block and charged full list. It is kind-aware now.
--  3. customer_discount_scope_ref_present names every scope in one of its two
--     arms, so 'variant' failed the CHECK even with the scope list widened.
--     Three constraints needed it, not one.
--
-- ALSO, on the owner's instruction: 'amount' becomes PER UNIT. It was compared
-- straight against the line total, so "$2 off" gave $2 off whether you bought
-- one bag or fifty. "it should be a unit discount, not line". Safe to change
-- today and never again: there is not one discounted line in the database --
-- 0 of 37,638 -- and zero customer_discount rows in any tenant.
--
-- A 'price' rule is confined to scope 'product' or 'variant'. There is no list
-- price to subtract from on "everything" or on a category, so a target price
-- there would have no meaning.

begin;

-- ── the rule table ───────────────────────────────────────────────────────
alter table public.customer_discount drop constraint if exists customer_discount_kind_check;
alter table public.customer_discount add constraint customer_discount_kind_check
  check (kind = any (array['percent'::text, 'amount'::text, 'price'::text]));

alter table public.customer_discount drop constraint if exists customer_discount_scope_check;
alter table public.customer_discount add constraint customer_discount_scope_check
  check (scope = any (array['all'::text, 'product_type'::text, 'product'::text,
                            'distribution'::text, 'variant'::text]));

alter table public.customer_discount drop constraint if exists customer_discount_scope_ref_present;
alter table public.customer_discount add constraint customer_discount_scope_ref_present
  check (
    (scope = any (array['all'::text, 'distribution'::text]) and scope_ref is null)
    or (scope = any (array['product_type'::text, 'product'::text, 'variant'::text])
        and scope_ref is not null)
  );

-- A price you pay only means something against a thing that HAS a price.
alter table public.customer_discount drop constraint if exists customer_discount_price_needs_a_target;
alter table public.customer_discount add constraint customer_discount_price_needs_a_target
  check (kind <> 'price' or scope = any (array['product'::text, 'variant'::text]));

-- ── the line ─────────────────────────────────────────────────────────────
alter table public.order_details drop constraint if exists order_details_discount_kind_check;
alter table public.order_details add constraint order_details_discount_kind_check
  check (discount_kind is null or discount_kind = any (array['percent'::text, 'amount'::text, 'price'::text]));

CREATE OR REPLACE FUNCTION public.resolve_customer_discount(p_customer_id text, p_product_id text, p_on_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(customer_discount_id text, kind text, value numeric, scope text)
 LANGUAGE sql
 STABLE
AS $function$
  select d.customer_discount_id, d.kind, d.value, d.scope
  from public.customer_discount d
  join public.products p on p.product_id = p_product_id
  left join public.product_groups pg on pg.group_id = p.group_id
  where d.customer_id = p_customer_id
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      -- Resold goods: the same derived test the Products page filter uses.
      -- Deliberately not the Consumable product type, which would also catch
      -- the internal supplies that are never resold.
      or (d.scope = 'distribution'  and p.source_consumable_id is not null)
      or (d.scope = 'product_type'  and d.scope_ref = p.product_type)
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
      -- A VARIANT is the thing a customer actually buys, and the only level
      -- at which a price exists: one group can hold 8 variants from $6.83 to
      -- $245, so "they pay $9" is not a statement the group can carry.
      or (d.scope = 'variant'       and d.scope_ref = p.product_id)
    )
  -- Most specific wins. Distribution sits above a plain type because "resold
  -- goods" is the narrower statement about the same item.
  order by case d.scope
             when 'variant' then 5
             when 'product' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc
  limit 1;
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
$function$;

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
      AND  o.invoice_number IS NULL;

    RETURN NEW;
END;
$function$;


do $$
declare
  v_src text;
begin
  -- The resolver must know a variant, and rank it above a group.
  select prosrc into v_src from pg_proc
  where oid = 'public.resolve_customer_discount(text,text,date)'::regprocedure;
  if position('d.scope = ''variant''' in v_src) = 0 then
    raise exception 'resolve_customer_discount does not match a variant';
  end if;
  if position('when ''variant'' then 5' in v_src) = 0 then
    raise exception 'a variant does not outrank a group in resolve_customer_discount';
  end if;

  -- Both money paths must know a price, or one of them silently charges the
  -- target as a discount. This is the check that would have caught the bug.
  select prosrc into v_src from pg_proc
  where oid = 'public.handle_order_detail_logic()'::regprocedure;
  if position('discount_kind = ''price''' in v_src) = 0 then
    raise exception 'handle_order_detail_logic does not handle a price kind';
  end if;
  if position('NEW.discount_kind = ''price'' OR' in v_src) = 0 then
    raise exception 'the discount gate in handle_order_detail_logic is not kind-aware';
  end if;

  select prosrc into v_src from pg_proc
  where oid = 'public.propagate_price_log_to_orders()'::regprocedure;
  if (length(v_src) - length(replace(v_src, 'od.discount_kind = ''price''', '')))
     / length('od.discount_kind = ''price''') <> 2 then
    raise exception 'propagate_price_log_to_orders needs the price arm in BOTH copies of its CASE';
  end if;
  -- 000008's guards must have survived being re-emitted here.
  if position('backfill_orders' in v_src) = 0 or position('o.invoice_number IS NULL' in v_src) = 0 then
    raise exception 'the 000008 guards were lost when the function was rewritten';
  end if;
end $$;

commit;
