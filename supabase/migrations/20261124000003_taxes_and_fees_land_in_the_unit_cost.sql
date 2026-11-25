-- Taxes and fees land in the unit cost.
--
-- Owner, 2026-11-24: "theres no line for fees/charges like i asked a while
-- back. only shipping. that should be on the new order form and the record
-- shipemtn form", then "should be the same for coffee. call it taxes/fees",
-- then "yes taxes and fees should go into the unit cost."
--
-- A supplier invoice carries more than freight: duty, brokerage, fuel
-- surcharge, state tax on packaging. Today the only landed-cost box is
-- shipping, so every one of those is either typed into shipping (which then
-- misreports freight) or left out of COGS entirely.
--
-- WHY THIS IS ONE NEW COLUMN AND NOT A SECOND PER-UNIT FIGURE.
-- `shipment_received.shipping_cost_unit` is the hub: ELEVEN functions read it
-- to price a receipt, and the app reads it once more on the consumable detail
-- page. A parallel `taxes_fees_unit` would mean editing all twelve and would
-- leave every future reader free to forget the second term. So the spread
-- stays single-valued: `shipping_cost_unit` becomes the LANDED cost per unit,
-- and the trigger that maintains it gains one addend.
--
-- 🔴 THE NAME NOW UNDERSTATES WHAT IT HOLDS. Renaming it is a twelve-reader
-- change for a cosmetic gain, so it keeps its name and carries a COMMENT that
-- says what is in it. Read that comment before adding a thirteenth reader.
--
-- NOTHING IS BACKFILLED. taxes_fees is NULL on all 15k existing shipments and
-- NULL contributes nothing, so every historical `shipping_cost_unit` is
-- unchanged and no COGS figure moves until somebody types a number.

begin;

alter table public.shipment_received
  add column if not exists taxes_fees numeric;

comment on column public.shipment_received.taxes_fees is
  'Duty, brokerage, surcharges and tax on a received shipment, in the facility currency. Nullable, like shipping_cost: NULL means not entered, 0 means there were none. Spread over the shipment the same way freight is -- see shipping_cost_unit.';

comment on column public.shipment_received.shipping_cost_unit is
  'LANDED cost per unit: (shipping_cost + taxes_fees) / shipment_total_weight_units, maintained by calculate_shipping_per_unit(). Despite the name it is NOT freight alone. NULL when neither box was filled in.';

-- The body below is pg_get_functiondef's own text with ONE term changed, the
-- numerator. Nothing else in it was retyped.
CREATE OR REPLACE FUNCTION public.calculate_shipping_per_unit()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Anti-Recursion: Stop if we are already inside this trigger
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    -- 2. Calculate the TRUE Total Weight (Coffee LBS + Consumable UNITS)
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0)
        FROM coffee_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0)
        FROM consumable_inventory_purchased
        WHERE shipment_id = NEW.shipment_id
          AND facility_id = NEW.facility_id
    );

    -- 3. Update BOTH the Total Weight and the LANDED Cost Per Unit
    --    (shipping + taxes/fees; see the column comment)
    UPDATE shipment_received
    SET shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN
                -- Nothing entered on either box still reads NULL, exactly as it
                -- did when shipping was the only term: a divide by NULL. Readers
                -- rely on that -- the consumable purchase table prints "No
                -- shipping or taxes/fees recorded on this shipment" for it --
                -- so a defaulted 0 here would silently relabel every shipment
                -- that carried no landed cost at all.
                CASE
                    WHEN NEW.shipping_cost IS NULL AND NEW.taxes_fees IS NULL THEN NULL
                    ELSE (COALESCE(NEW.shipping_cost, 0) + COALESCE(NEW.taxes_fees, 0)) / v_total_weight
                END
            ELSE 0
        END,
        shipment_total_weight_units = v_total_weight
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$function$;

-- Verify. Every assertion below is something this migration has just made
-- true, so the block can only pass or only raise.
do $verify$
declare
    v_src text;
begin
    if not exists (
        select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name   = 'shipment_received'
           and column_name  = 'taxes_fees'
    ) then
        raise exception 'shipment_received.taxes_fees was not added';
    end if;

    -- 🔴 A NEW COLUMN INHERITS NO COLUMN PRIVILEGE. shipment_received's grants
    -- to authenticated are table-level today, so this column is covered the
    -- moment it exists -- but that is a fact about the table as it stands, not
    -- a guarantee. If someone narrows the table to column grants later, this
    -- assertion is what turns a silently unwritable box into a failed release.
    if not has_column_privilege('authenticated', 'public.shipment_received', 'taxes_fees', 'UPDATE') then
        raise exception 'authenticated cannot UPDATE shipment_received.taxes_fees';
    end if;
    if not has_column_privilege('authenticated', 'public.shipment_received', 'taxes_fees', 'INSERT') then
        raise exception 'authenticated cannot INSERT shipment_received.taxes_fees';
    end if;
    if not has_column_privilege('authenticated', 'public.shipment_received', 'taxes_fees', 'SELECT') then
        raise exception 'authenticated cannot SELECT shipment_received.taxes_fees';
    end if;

    -- The spread actually adds the new term. Asserted on the EXPRESSION, not on
    -- the column name: the word taxes_fees appears in this function's comments
    -- too, so a name match would pass on prose alone.
    select p.prosrc into v_src
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'calculate_shipping_per_unit';
    if v_src is null then
        raise exception 'calculate_shipping_per_unit() is missing';
    end if;
    if position('(COALESCE(NEW.shipping_cost, 0) + COALESCE(NEW.taxes_fees, 0)) / v_total_weight' in v_src) = 0 then
        raise exception 'calculate_shipping_per_unit() does not spread taxes_fees';
    end if;

    -- And it is still wired up. The trigger carries no column list, so an
    -- UPDATE that touches only taxes_fees re-runs the spread; that is the whole
    -- reason no further plumbing is needed.
    if not exists (
        select 1
          from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_proc  p on p.oid = t.tgfoid
         where c.relname = 'shipment_received'
           and p.proname = 'calculate_shipping_per_unit'
           and not t.tgisinternal
    ) then
        raise exception 'calculate_shipping_per_unit() is not attached to shipment_received';
    end if;
end
$verify$;

commit;
