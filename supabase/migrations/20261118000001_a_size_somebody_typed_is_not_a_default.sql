-- A bag size somebody typed is not a default.
--
-- TWO DEFECTS, ONE STATEMENT. The second is bigger than the one I went in for.
--
-- 1. "JUST THIS ORDER" IS A NO-OP ON A SOURCED LINE.
-- The bag-size pencil on an order line offers "Just this order", and
-- save_shipment_lines faithfully sends it: `bag_size = NULLIF(v_line->>
-- 'bag_size','')` on both its INSERT (:70) and its UPDATE (:92). Then this
-- BEFORE trigger overwrites it with the coffee's standard and recomputes the
-- amount. The operator's choice never reaches disk.
--
-- The trigger is `BEFORE INSERT OR UPDATE OF bags_ordered, facility_id,
-- coffee_source_id, amount_manual` -- bag_size is NOT in that list, which is
-- why a size-only save does persist. Edit Shipment sets bags_ordered,
-- coffee_source_id and amount_manual in the same statement, so there the
-- trigger always fires and always wins.
--
-- 2. 🔴 THE COLUMN THAT RECORDS THE DENOMINATOR IS THE ONE THAT DOES NOT GET
--    THE RESOLVED NUMBER.
-- Look at the two assignments it made:
--
--     NEW.bag_size := v_bag_size_text;              -- the RAW coffee_source value
--     NEW.amount   := NEW.bags_ordered * v_bag_size; -- the COALESCE'd value
--
-- `v_bag_size_text` is whatever the SELECT off coffee_source returned, and it
-- is NULL when the line has no coffee source linked. `v_bag_size` is that
-- value COALESCE'd down to coffee_inventory.bag_size and then to 154. So on
-- any line without a source, a save stored `bag_size = NULL` while pricing
-- `amount` at 154 -- amount and bag_size computed at different denominators,
-- in the same statement, by design. That is the root of the whole
-- bags-vs-pounds family: the row no longer records what its own amount was
-- derived from.
--
-- 🔴 MEASURED ON PROD, not reasoned about. Of 371 coffee_inventory_purchased
-- rows, 126 have no coffee_source_id at all and 2 more point at a source whose
-- bag_size is blank -- 128 rows where a save nulls the size it just priced
-- against. 15 rows carry a NULL bag_size right now. This migration does not
-- backfill those: it stops new ones being made, and the existing 15 become
-- correct the next time their line is saved.
--
-- WHAT CHANGES. The caller's own value becomes term 0 of the COALESCE the
-- function already had, and the RESOLVED size is written back instead of the
-- raw one. `amount = bags_ordered * bag_size` becomes a trigger-enforced
-- invariant rather than a coincidence.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. On an UPDATE that changes
-- coffee_source_id without also sending a bag_size, the line now KEEPS its
-- recorded size instead of adopting the new coffee's standard. That is the
-- same rule 20261117000001 settled on 2026-11-17 -- a standard is for the next
-- order, not the last one -- and every caller today sends the two together
-- (updateCoffeeLine passes bag_size whenever the line editor has it,
-- actions.ts:1243). Clearing the field re-defaults to the standard.
--
-- ONE MORE THING THE LOCAL REHEARSAL FOUND, which I had not gone looking
-- for. The two casts this COALESCE already did -- `v_bag_size_text::numeric`
-- and `ci.bag_size::numeric` -- throw `invalid input syntax for type numeric:
-- ""` on an EMPTY-STRING bag size, which aborts the whole save. That is
-- LATENT, not live: every blank bag_size on prod today is NULL, not '' (4 on
-- coffee_source, 16 on coffee_inventory, 0 empty strings on either), so
-- nothing is crashing. But both columns are plain text with no constraint
-- stopping a '', and `apply_group_count_to_lots` already reads the same
-- coffee_inventory column as `NULLIF(bag_size, '')::numeric` -- so the
-- codebase is inconsistent about a case it knows can happen. Both casts are
-- now NULLIF'd, which also means an empty string falls through to the next
-- term instead of killing the statement.
--
-- PROVENANCE. prod's live body is byte-identical to
-- 20260703000001_bag_size_round_manual_weight.sql (1,707 chars, diffed, not
-- eyeballed). The body below is that text with the COALESCE term added and one
-- assignment changed; it was not retyped.

begin;

create or replace function public.compute_coffee_purchase_amount()
 returns trigger
 language plpgsql
as $function$
DECLARE
    v_bag_size NUMERIC;
    v_bag_size_text TEXT;
BEGIN
    IF NEW.bags_ordered IS NOT NULL THEN
        IF COALESCE(NEW.amount_manual, false) AND NEW.amount IS NOT NULL AND NEW.amount > 0 THEN
            -- Operator entered an exact net weight: honor amount as the lot total,
            -- derive the per-bag size so the bag count (lbs / bag_size) stays right.
            IF NEW.bags_ordered > 0 THEN
                -- Round to 2 dp + trim trailing zeros so the derived per-bag size
                -- doesn't leak full numeric scale into the UI (was "153.4400000000000").
                NEW.bag_size := trim_scale(round(NEW.amount / NEW.bags_ordered, 2))::text;
            END IF;
            -- NEW.amount left as the entered value.
        ELSE
            -- Default: recompute the total from bags × resolved bag_size.
            -- 0. NEW.bag_size  (what the caller supplied FOR THIS LINE)
            -- 1. coffee_source.bag_size (the coffee's own standard)
            -- 2. coffee_inventory.bag_size (operative size for this origin)
            -- 3. 154 (universal fallback)
            -- Term 0 is why "Just this order" now survives a save. On an
            -- UPDATE that does not mention the column, NEW.bag_size holds the
            -- row's existing value, so a recorded line keeps the size it was
            -- recorded at -- the same rule 20261117000001 settled for the
            -- sibling trigger. Clearing the field in Edit Shipment arrives
            -- here as NULL (save_shipment_lines sends NULLIF(...,'')), so
            -- re-defaulting to the standard is still one click away.
            SELECT cs.bag_size
            INTO v_bag_size_text
            FROM public.coffee_source cs
            WHERE cs.coffee_source_id = NEW.coffee_source_id
            LIMIT 1;

            v_bag_size := COALESCE(
                NULLIF(NEW.bag_size, '')::numeric,
                NULLIF(v_bag_size_text, '')::numeric,
                (SELECT NULLIF(ci.bag_size, '')::numeric
                 FROM public.coffee_inventory ci
                 WHERE ci.origin_id = NEW.origin AND ci.facility_id = NEW.facility_id
                 LIMIT 1),
                154
            );

            NEW.bag_size := trim_scale(round(v_bag_size, 2))::text;
            NEW.amount   := NEW.bags_ordered * v_bag_size;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- The catalogue can only show that the right text is installed. It cannot show
-- that "Just this order" now survives a save -- that is proven on staging once
-- CI applies this, by setting a per-line size in Edit Shipment and re-opening
-- the shipment.
do $$
declare
  v_src     text;
  v_trigger text;
begin
  select p.prosrc into v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'compute_coffee_purchase_amount';

  if v_src is null then
    raise exception 'compute_coffee_purchase_amount is missing';
  end if;

  -- 1. The caller's own value is consulted first.
  if v_src !~ 'COALESCE\(\s*NULLIF\(NEW\.bag_size' then
    raise exception 'the supplied bag_size is not the first COALESCE term, so "Just this order" is still a no-op';
  end if;

  -- 2. The raw-value assignment is gone, so bag_size and amount can no longer
  --    be derived at different denominators.
  if v_src ~ 'NEW\.bag_size\s*:=\s*v_bag_size_text' then
    raise exception 'bag_size is still assigned the raw coffee_source value while amount uses the resolved one';
  end if;

  -- 3. An empty-string size falls through instead of aborting the save.
  if v_src !~ 'NULLIF\(v_bag_size_text' or v_src !~ 'NULLIF\(ci\.bag_size' then
    raise exception 'an empty-string bag size can still abort the save with a numeric cast error';
  end if;

  -- 4. Controls that must still PASS -- a check that only ever fires on
  --    failure proves nothing about the parts it never looked at.
  if v_src !~ '154' then
    raise exception 'the universal 154 fallback is gone; a line with no source anywhere would price at zero';
  end if;
  if v_src !~ 'NEW\.amount\s*/\s*NEW\.bags_ordered' then
    raise exception 'the amount_manual branch is gone; an exact net weight would stop deriving its per-bag size';
  end if;

  -- 5. The trigger is untouched and still narrow. bag_size staying OUT of the
  --    OF list is load-bearing: it is what lets a size-only save through
  --    without a recompute.
  select pg_get_triggerdef(t.oid) into v_trigger
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where c.relname = 'coffee_inventory_purchased'
    and t.tgname  = 'trg_compute_coffee_purchase_amount'
    and not t.tgisinternal;

  if v_trigger is null then
    raise exception 'trg_compute_coffee_purchase_amount is missing from coffee_inventory_purchased';
  end if;
  if v_trigger !~ 'BEFORE INSERT OR UPDATE OF bags_ordered, facility_id, coffee_source_id, amount_manual' then
    raise exception 'the trigger OF list changed, so this function now fires on writes it was never measured against: %', v_trigger;
  end if;
end $$;

commit;
