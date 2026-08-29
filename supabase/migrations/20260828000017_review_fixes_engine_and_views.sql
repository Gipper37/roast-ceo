-- The pre-release review's fixes: the discount engine stops corrupting money,
-- legacy imports become untouchable from the new UI, the resolver survives its
-- own rate succession, and the filing views work for every tenant.
--
-- All of this was found by a five-lens adversarial review of the staged release
-- and reproduced on prod to the cent before a line of this was written.
--
-- ── P0-1: THE ENGINE COMPOUNDED DISCOUNTS ON EVERY RE-TOUCH ──────────────────
-- unit_price_at_sale was overwritten with the NET (total/qty) at the end of
-- every money pass, and re-read as the LIST basis at the start of the next.
-- So editing a 10% discount to 20% rebased the list to the previous net and
-- discounted again ($101.40 -> 10% -> 91.26 -> "20%" -> 73.01 instead of
-- 81.12); clearing a discount left the discounted price behind with
-- discount_amount 0 and the true list unrecoverable; changing quantity
-- double-discounted. The same rebase broke apply_order_discount's documented
-- idempotency: re-applying shrank the order again, clearing never restored.
--
-- THE FIX IS A DEFINITION. unit_price_at_sale is the agreed PRE-DISCOUNT unit
-- price — the number the customer was quoted — and is NEVER derived from the
-- net. list_price_total = unit_price_at_sale x quantity. total_price = list
-- minus discount. One direction of derivation, so no pass can feed the engine
-- its own output.
--
-- No data repair is needed: the discount engine has never run on prod (000008+
-- land in this same release), and every existing row has discount_amount 0,
-- where net == list and the old snapshot is already the list.
--
-- ── P0-2: LEGACY IMPORTS WERE ONE CLICK FROM RESTATEMENT ─────────────────────
-- apply_order_discount and recompute_order_tax guarded posted only. MCR's 3,796
-- imported QuickBooks orders are unposted, so the new order-page discount UI
-- would happily rewrite lines that must match the document the customer holds,
-- and recompute_order_tax then NULLed the imported tax stamp, dropping the
-- order from the GET return. Both now refuse legacy imports the way they refuse
-- posted invoices.
--
-- ── P1-3: A FAILED RESOLUTION NO LONGER ERASES HISTORY ───────────────────────
-- recompute_order_tax's null branch cleared tax_rate_id. Unresolved means "we
-- could not determine a rate today", not "this order was never taxed" — the
-- existing stamp stays.
--
-- ── P2: OVERRIDE + STANDING DISCOUNT DOUBLE-SUBTRACTED ───────────────────────
-- An operator typing an exact amount means that amount. The customer rule no
-- longer stamps onto a line that carries an amount_override.
--
-- ── P2: THE RESOLVER SURVIVES RATE SUCCESSION ────────────────────────────────
-- 000007/000009 close a rate on apply day and open its successor the day after,
-- repointing the rules at the successor. An order dated on or before apply day
-- then matched a rule whose rate was not yet effective, and resolved NULL. The
-- resolver now falls back to the effective rate of the same company,
-- jurisdiction and kind — which is precisely the predecessor — so backdated and
-- apply-day orders resolve to the rate that was actually in force on their date.
--
-- ── P1-1: THE FILING VIEWS WORKED ONLY FOR MCR ───────────────────────────────
-- tax_liability_by_rate and revenue_recognized INNER JOINed billing_settings,
-- which has exactly one row. Every other tenant's filing report rendered
-- nothing. LEFT JOIN, basis defaulting to accrual, security_invoker preserved.

begin;

-- ═══ 1. The engine, with one direction of derivation ═════════════════════════
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
        -- The review's P0: this used to be overwritten with the net at the
        -- bottom of the block and re-read as the list at the top of the next
        -- pass, so every edit of a discounted line compounded the discount.
        -- It is now written ONLY here, from the catalogue, an override, or
        -- kept — never from anything the discount arithmetic produced.
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

        -- ── THE STANDING DISCOUNT, once, on INSERT ───────────────────────
        -- Not when the operator typed an exact amount: an override means that
        -- amount, and stamping a rule on top double-subtracts (review P2).
        IF TG_OP = 'INSERT' AND NEW.discount_kind IS NULL AND NEW.amount_override IS NULL THEN
            SELECT d.customer_discount_id, d.kind, d.value
              INTO v_disc_rule, v_disc_kind, v_disc_value
              FROM public.resolve_customer_discount(NEW.customer_id, NEW.product_id, NEW.order_date) d;
            IF v_disc_kind IS NOT NULL THEN
                NEW.discount_kind    := v_disc_kind;
                NEW.discount_value   := v_disc_value;
                NEW.discount_rule_id := v_disc_rule;
                NEW.discount_source  := 'customer_rule';
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

-- ═══ 2. apply_order_discount: legacy guard ═══════════════════════════════════
-- The body is otherwise unchanged from 000012 — with the trigger fixed, its
-- clear step is self-healing: clearing the discount fields fires the recompute,
-- which rebuilds list from the (now stable) unit snapshot and restores the net.
create or replace function public.apply_order_discount(
  p_order_id text,
  p_kind     text,
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
  if exists (select 1 from public.orders
              where order_id = p_order_id
                and (coalesce(posted,false) or coalesce(is_legacy_import,false))) then
    -- Legacy refuses for the same reason posted does: the imported invoice must
    -- keep matching the QuickBooks document the customer holds (review P0-2).
    raise exception 'order % is posted or imported history — its amounts are locked', p_order_id;
  end if;

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

  if v_biggest is null then
    update public.orders set discount_total = 0 where order_id = p_order_id;
    return 0;
  end if;

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
        v_share := 0;
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

-- ═══ 3. recompute_order_tax: legacy guard, and null keeps the stamp ══════════
create or replace function public.recompute_order_tax(p_order_id text)
returns numeric
language plpgsql
as $function$
declare
  v_o         record;
  v_rate_id   text;
  v_charge    numeric;
  v_statutory numeric;
  v_pass      boolean;
  v_tax       numeric;
begin
  select o.order_id, o.company_id, o.facility_id, o.customer_id, o.order_date,
         o.order_total, coalesce(o.posted,false) as posted,
         coalesce(o.is_legacy_import,false) as legacy
    into v_o from public.orders o where o.order_id = p_order_id;
  if not found then return null; end if;
  if v_o.posted or v_o.legacy then
    raise exception 'order % is posted or imported history — its tax is locked', p_order_id;
  end if;

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
    -- Unresolved means "no rate could be determined TODAY" — it does not mean
    -- this order was never taxed. The existing stamp is history and stays
    -- (review P1-3: the old branch nulled tax_rate_id, silently removing
    -- invoices from the filing report).
    return null;
  end if;

  select t.charge_rate, t.statutory_rate into v_charge, v_statutory
    from public.tax_rate t where t.tax_rate_id = v_rate_id;
  select coalesce(c.tax_passed_through, true) into v_pass
    from public.customers c where c.customer_id = v_o.customer_id;

  v_tax := case when coalesce(v_pass, true)
                then round(coalesce(v_o.order_total,0) * coalesce(v_charge,0), 2)
                else 0 end;

  update public.orders
     set tax_rate_id = v_rate_id,
         tax_rate = case when coalesce(v_pass, true) then v_charge else v_statutory end,
         tax_amount = v_tax,
         tax_passed_through = coalesce(v_pass, true)
   where order_id = p_order_id;
  return v_tax;
end;
$function$;

-- ═══ 4. The resolver survives rate succession ════════════════════════════════
create or replace function public.resolve_tax_rate(
  p_company_id      text,
  p_facility_id     text default null,
  p_channel_id      text default null,
  p_product_type_id text default null,
  p_customer_id     text default null,
  p_on_date         date default null
)
returns text
language plpgsql
stable
as $$
declare
  v_on_date date := coalesce(p_on_date, current_date);
  v_rate_id text;
begin
  if not exists (
    select 1 from public.billing_settings b
     where b.company_id = p_company_id and b.tax_enabled
  ) then
    return null;
  end if;

  if p_customer_id is not null then
    select c.tax_rate_id into v_rate_id
      from public.customers c
      join public.tax_rate t on t.tax_rate_id = c.tax_rate_id
     where c.customer_id = p_customer_id
       and t.is_active
       and t.effective_from <= v_on_date
       and (t.effective_to is null or t.effective_to >= v_on_date);
    if v_rate_id is not null then
      return v_rate_id;
    end if;
  end if;

  -- The rule names A rate; the date picks WHICH generation of it. When a rate
  -- is closed and succeeded (000007/000009 close on apply day, open the
  -- successor the day after, and repoint the rules), an order dated before the
  -- succession must resolve to the predecessor — same company, jurisdiction and
  -- kind — not to nothing. Without this, every backdated and apply-day order
  -- resolved NULL the moment a rate was ever re-issued.
  select eff.tax_rate_id
    into v_rate_id
    from public.tax_rule r
    join public.tax_rate t on t.tax_rate_id = r.tax_rate_id
    join lateral (
      select t2.tax_rate_id
        from public.tax_rate t2
       where t2.company_id      = t.company_id
         and t2.jurisdiction_id = t.jurisdiction_id
         and t2.kind            = t.kind
         and t2.is_active
         and t2.effective_from <= v_on_date
         and (t2.effective_to is null or t2.effective_to >= v_on_date)
       order by (t2.tax_rate_id = t.tax_rate_id) desc, t2.effective_from desc
       limit 1
    ) eff on true
   where r.company_id = p_company_id
     and r.is_active
     and (r.facility_id     is null or r.facility_id     = p_facility_id)
     and (r.channel_id      is null or r.channel_id      = p_channel_id)
     and (r.product_type_id is null or r.product_type_id = p_product_type_id)
   order by r.match_specificity desc
   limit 1;

  return v_rate_id;
end;
$$;

-- ═══ 5. The filing views work for every tenant ═══════════════════════════════
drop view if exists public.tax_liability_by_rate;
create view public.tax_liability_by_rate as
select o.company_id,
       date_trunc('month', case when coalesce(b.accounting_basis,'accrual') = 'cash'
                                then o.paid_at::date
                                else o.order_date end)::date as period,
       coalesce(b.accounting_basis,'accrual') as accounting_basis,
       t.tax_rate_id, t.code, t.label, t.statutory_rate,
       count(*)                                as invoices,
       round(sum(o.order_total), 2)            as taxable_sales,
       round(sum((o.order_total + coalesce(o.tax_amount, 0)) * t.statutory_rate), 2) as tax_owed,
       round(sum(coalesce(o.tax_amount, 0)), 2) as tax_collected,
       round(sum((o.order_total + coalesce(o.tax_amount, 0)) * t.statutory_rate)
             - sum(coalesce(o.tax_amount, 0)), 2) as tax_absorbed
  from public.orders o
  join public.tax_rate t on t.tax_rate_id = o.tax_rate_id
  -- LEFT: billing_settings has one row today, and an INNER join silently blanked
  -- the filing report for every tenant that had never saved billing settings.
  left join public.billing_settings b on b.company_id = o.company_id
 where o.order_status <> 'Canceled'
   and (coalesce(b.accounting_basis,'accrual') <> 'cash' or o.paid_at is not null)
 group by 1,2,3,4,5,6,7;
alter view public.tax_liability_by_rate set (security_invoker = true);
grant select on public.tax_liability_by_rate to authenticated;

drop view if exists public.revenue_recognized;
create view public.revenue_recognized as
select o.company_id,
       date_trunc('month', case when coalesce(b.accounting_basis,'accrual') = 'cash'
                                then o.paid_at::date
                                else o.order_date end)::date as period,
       coalesce(b.accounting_basis,'accrual') as accounting_basis,
       count(distinct o.order_id)                    as invoices,
       round(sum(o.order_total), 2)                  as revenue,
       round(sum(coalesce(o.tax_amount, 0)), 2)      as tax_collected,
       round(sum(o.order_total + coalesce(o.tax_amount, 0)), 2) as gross_receipts,
       (select round(coalesce(sum(o2.order_total), 0), 2)
          from public.orders o2
         where o2.company_id = o.company_id
           and o2.order_status <> 'Canceled'
           and o2.paid_at is null
           and coalesce(b.accounting_basis,'accrual') = 'cash') as unrecognized_outstanding
  from public.orders o
  left join public.billing_settings b on b.company_id = o.company_id
 where o.order_status <> 'Canceled'
   and (coalesce(b.accounting_basis,'accrual') <> 'cash' or o.paid_at is not null)
 group by 1, 2, 3, b.accounting_basis;
alter view public.revenue_recognized set (security_invoker = true);
grant select on public.revenue_recognized to authenticated;

commit;
