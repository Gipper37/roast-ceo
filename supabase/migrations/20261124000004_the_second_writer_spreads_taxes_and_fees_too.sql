-- The second writer of shipping_cost_unit spreads taxes and fees too.
--
-- 🔴 WHAT 20261124000003 MISSED, AND HOW. That migration put taxes/fees into
-- the landed-cost spread by editing `calculate_shipping_per_unit()`, the
-- trigger on shipment_received. I checked the ELEVEN functions that READ
-- `shipping_cost_unit` and never asked the other question: who else WRITES it.
--
-- Two functions do. `calculate_shipment_totals_for(text, text)` sets the same
-- column from `ROUND(shipping_cost / v_total_weight, 3)`, and it is reached
-- from `calculate_shipment_totals()` via the row triggers
-- `update_shipment_on_coffee` and `update_shipment_on_consumable` -- so it
-- fires on any INSERT, UPDATE or DELETE of a shipment LINE.
--
-- Reproduced locally against both real bodies and all three real triggers,
-- shipping 200 + taxes 50 over 100 units, where the honest rate is 2.50:
--
--     shipment + first line created   -> 2.000     (second writer, last to fire)
--     header re-saved                 -> 2.5000    (correct)
--     any line touched                -> 2.000     (clobbered)
--     a second line added, 150 units  -> 1.333     (clobbered; honest 1.6667)
--
-- So the taxes were dropped by whichever writer touched the row last, and a
-- newly entered order lost them immediately, because the line insert fires
-- after the header. 20261124000003's verify block could not catch it: it
-- asserts the text of calculate_shipping_per_unit and nothing else.
--
-- 🔴 AND THE ROUNDING DISAGREED ALREADY, SINCE 2026-10-30. Migration
-- 20261030000004 deliberately removed `ROUND(..., 3)` from
-- calculate_shipping_per_unit -- three decimals is not enough for a per-unit
-- rate on a 4,000 lb shipment -- and left it in this function. So the column
-- has been non-deterministic for weeks: the stored precision depended on
-- whether a header or a line was saved last. Both writers are made identical
-- here, which is the only state in which the column has one meaning.
--
-- Nothing is backfilled. taxes_fees is NULL everywhere, so for every existing
-- shipment the new numerator equals the old one; the only values that move are
-- ones somebody recomputes after typing a figure. The historical 3-decimal
-- values left by this function are not rewritten either -- they are corrected
-- the next time anything touches the shipment, exactly as 20261030000004 left
-- them.

begin;

-- pg_get_functiondef's own text with ONE term changed, the numerator.
-- Nothing else was retyped.
CREATE OR REPLACE FUNCTION public.calculate_shipment_totals_for(p_shipment_id text, p_facility_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_total_weight NUMERIC;
BEGIN
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0) FROM coffee_inventory_purchased
         WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0) FROM consumable_inventory_purchased
         WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id
    );
    UPDATE shipment_received SET
        shipment_total_weight_units = v_total_weight,
        -- Same numerator as calculate_shipping_per_unit(), and the same NULL
        -- rule: neither box filled in still reads NULL rather than 0. No NEW.
        -- prefix here -- this is a plain UPDATE, not a trigger function, so the
        -- columns are the table's own.
        shipping_cost_unit = CASE
            WHEN v_total_weight > 0 THEN
                CASE
                    WHEN shipping_cost IS NULL AND taxes_fees IS NULL THEN NULL
                    ELSE (COALESCE(shipping_cost, 0) + COALESCE(taxes_fees, 0)) / v_total_weight
                END
            ELSE 0
        END
    WHERE shipment_id = p_shipment_id AND facility_id = p_facility_id;
END;
$function$;

-- Verify. 🔴 THIS BLOCK ASSERTS BOTH WRITERS, which is the whole lesson of
-- the bug above. Every assertion is something this migration (or its
-- predecessor) has just made true, so it can only pass or only raise.
do $verify$
declare
    v_spu   text;
    v_totals text;
    v_writers int;
begin
    select p.prosrc into v_spu from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'calculate_shipping_per_unit';
    select p.prosrc into v_totals from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'calculate_shipment_totals_for';

    if v_spu is null then raise exception 'calculate_shipping_per_unit() is missing'; end if;
    if v_totals is null then raise exception 'calculate_shipment_totals_for() is missing'; end if;

    -- Asserted on the EXPRESSION, not on the column name: taxes_fees appears in
    -- these functions' comments too, so a name match would pass on prose alone.
    if position('(COALESCE(NEW.shipping_cost, 0) + COALESCE(NEW.taxes_fees, 0)) / v_total_weight' in v_spu) = 0 then
        raise exception 'calculate_shipping_per_unit() does not spread taxes_fees';
    end if;
    if position('(COALESCE(shipping_cost, 0) + COALESCE(taxes_fees, 0)) / v_total_weight' in v_totals) = 0 then
        raise exception 'calculate_shipment_totals_for() does not spread taxes_fees';
    end if;

    -- The old freight-only spread is gone from the one place it survived.
    if position('ROUND(shipping_cost / v_total_weight' in v_totals) > 0 then
        raise exception 'calculate_shipment_totals_for() still rounds a freight-only rate';
    end if;

    -- 🔴 AND NOBODY ELSE WRITES THE COLUMN. If a third writer is ever added
    -- without a term for taxes, this is what refuses the release rather than
    -- letting the two halves of the system disagree about one shipment.
    select count(*) into v_writers
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosrc ~* 'shipping_cost_unit[[:space:]]*=';
    if v_writers <> 2 then
        raise exception 'expected exactly 2 writers of shipping_cost_unit, found %', v_writers;
    end if;

    -- All three triggers that reach those two writers are still attached.
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                    where c.relname = 'shipment_received' and t.tgname = 'trigger_update_shipping_unit_cost'
                      and not t.tgisinternal) then
        raise exception 'trigger_update_shipping_unit_cost is gone';
    end if;
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                    where c.relname = 'coffee_inventory_purchased' and t.tgname = 'update_shipment_on_coffee'
                      and not t.tgisinternal) then
        raise exception 'update_shipment_on_coffee is gone';
    end if;
    if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                    where c.relname = 'consumable_inventory_purchased' and t.tgname = 'update_shipment_on_consumable'
                      and not t.tgisinternal) then
        raise exception 'update_shipment_on_consumable is gone';
    end if;
end
$verify$;

commit;
