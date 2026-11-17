-- A standard bag size is for the NEXT order, not the last one.
--
-- Owner, 2026-11-17, asked which way this should go and chose "Future orders
-- only".
--
-- WHAT IT DOES TODAY, AND WHY THAT IS A DATA-LOSS BUG.
-- `trg_propagate_coffee_source_bag_size` fires AFTER UPDATE OF bag_size on
-- coffee_source and rewrites EVERY purchase row of that source:
--
--     set bag_size = NEW.bag_size, amount = bags_ordered * NEW.bag_size
--     where coffee_source_id = NEW.coffee_source_id and bags_ordered is not null
--
-- No date bound. No shipment-state bound. And no `amount_manual` exclusion --
-- which is the part that destroys data, because `amount_manual` means a human
-- read a number off the invoice and typed it in. That row keeps saying it is
-- manual afterwards, and nothing repairs it: the BEFORE trigger that would
-- re-derive the amount (`trg_compute_coffee_purchase_amount`) watches
-- `bags_ordered, facility_id, coffee_source_id, amount_manual`
-- (20260626000001:71-75), not bag_size or amount, so it never fires. The new
-- amount then cascades through trg_coffee_purchase_add,
-- trg_push_last_coffee_cost, trg_update_green_metrics_from_purchased and
-- update_shipment_on_coffee -- moving stock, last cost, green metrics and the
-- totals of shipments that closed months ago.
--
-- 🔴 MEASURED ON PROD, not reasoned about. 361 purchase rows carry a
-- bags_ordered across 130 sources; 6 of them are `amount_manual`. Those 6 all
-- store a DERIVED per-bag size, so today their amount happens to equal
-- bags x bag_size and the damage is invisible. It appears on the click. The
-- worst of them, `csrc_a6837a97a66e2a7e` (USA - Maui H3), holds two rows of 10
-- bags weighed at 13.23 and 12.82 lbs per bag = 132.3 and 128.2 lbs. One
-- "Update standard" to 132 on that source turns them into 10 x 132 = 1,320 and
-- 1,320 lbs -- ten times the real weight, on rows still flagged manual, with
-- the cost and green-metric cascade following.
--
-- WHY IT WAS WRITTEN THIS WAY, because the intent was good.
-- _archive/20260313100123 added the amount recalculation so that "a wrong
-- bag_size entry would [not] leave all historical lbs incorrect" -- i.e. this
-- is a REPAIR mechanism. The problem is that the trigger cannot tell a repair
-- ("I typed 132 when the bag was always 152") from an ordinary change ("we buy
-- 69 kg sacks now"), and it answers both by restating history. The UI says the
-- opposite in so many words -- "Update the source's standard (applies to
-- future orders)" (BagSizeField.tsx:345) -- so the destructive reading is not
-- one any operator has been offered.
--
-- WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
-- The rewrite of the purchase table goes. A purchase keeps the size it was
-- bought at, which is what "future orders only" means and what the button
-- already claims. Repairing a past lot stays possible and stays EXPLICIT --
-- Edit Shipment edits that line, and a platform-wide correction is a migration
-- that names its rows (_archive/20260323000152 is the precedent, and it would
-- now have to write its own UPDATE instead of leaning on this trigger).
--
-- The coffee_inventory loop STAYS. That column is the operative bag size for
-- the origin at a facility -- present tense, what bags of this origin come in
-- now -- not a record of what was bought. Leaving it is what keeps the new
-- standard meaningful for the next order.
--
-- 🔴 That loop has a separate bug this migration does NOT touch, because one
-- change at a time: it is keyed on (origin, facility) derived from the
-- source's purchases, so changing ONE source's standard overwrites the
-- operative size for the whole origin, including sibling sources that use a
-- different bag. Recorded in project_open_list.md.
--
-- 🔴 WHAT THE VERIFY BLOCK BELOW CANNOT SEE.
-- It reads the catalogue, so it proves the statement is gone and the loop is
-- still there -- not that the trigger behaves. A behavioural test would have
-- to write a purchase row inside this transaction, and a half-cleaned fixture
-- in a release migration is worse than the gap. The behaviour is proven on
-- staging after CI applies it, by repeating the click that produced the
-- evidence above.
--
-- The body below is prod's own `pg_get_functiondef` output with ONE statement
-- removed. It was not retyped: CREATE OR REPLACE rewrites the whole body, so
-- retyping it is how the rest of it gets silently changed.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.propagate_coffee_source_bag_size()
returns trigger
language plpgsql
as $function$
DECLARE
    r RECORD;
BEGIN
    -- Skip if bag_size didn't change or has no value to propagate
    IF NEW.bag_size IS NOT DISTINCT FROM OLD.bag_size THEN
        RETURN NEW;
    END IF;
    IF NEW.bag_size IS NULL THEN
        RETURN NEW;
    END IF;

    -- Update coffee_inventory (operative bag size for the origin category)
    FOR r IN
        SELECT DISTINCT p.origin, p.facility_id
        FROM public.coffee_inventory_purchased p
        WHERE p.coffee_source_id = NEW.coffee_source_id
          AND p.facility_id IS NOT NULL
    LOOP
        UPDATE public.coffee_inventory
        SET bag_size = NEW.bag_size
        WHERE origin_id   = r.origin
          AND facility_id = r.facility_id;
    END LOOP;

    -- A standard is for the next order. Past purchases keep the size they were
    -- bought at, and a weighed net amount is never recomputed behind the
    -- operator's back. Repair a recorded lot by editing that lot.
    RETURN NEW;
END;
$function$;

comment on function public.propagate_coffee_source_bag_size() is
  'Pushes a changed coffee_source.bag_size to the operative size on coffee_inventory for the origins/facilities that source is held at. It does NOT restate recorded purchases: a standard applies to the next order, not the last one (owner, 2026-11-17). Until then it also rewrote every purchase row of the source, recomputing amount as bags_ordered x the new size with no amount_manual exclusion, which silently replaced operator-entered invoice net weights and moved stock, last cost, green metrics and closed shipment totals behind them.';

do $$
declare
  v_src     text;
  v_trigger text;
begin
  select p.prosrc into v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'propagate_coffee_source_bag_size';

  if v_src is null then
    raise exception 'propagate_coffee_source_bag_size no longer exists, so the trigger on coffee_source points at nothing';
  end if;

  -- 1. The statement that restated history is gone.
  --    🔴 Matched as an UPDATE of that table, NOT as a bare mention of its
  --    name: the surviving loop still SELECTs FROM it, and a name-only grep
  --    would also hit this file's own comments, which is how a prosrc check
  --    lies to you.
  if v_src ~* 'update\s+(public\.)?coffee_inventory_purchased' then
    raise exception 'the body still UPDATEs coffee_inventory_purchased, so changing a standard would still restate recorded purchases';
  end if;

  -- 2. And the function was not simply gutted: the forward-looking half is
  --    still there. Without this, deleting the whole body would pass check 1.
  if v_src !~* 'update\s+public\.coffee_inventory\M' then
    raise exception 'the body no longer updates coffee_inventory, so a new standard would not reach the origin operative size at all';
  end if;

  -- 3. The early-exit guards are intact. CREATE OR REPLACE rewrites the whole
  --    body, so this is the assertion that the rest of it survived the edit.
  if v_src !~* 'IS NOT DISTINCT FROM OLD\.bag_size' then
    raise exception 'the no-op guard is gone; the trigger would do work on an UPDATE that did not change bag_size';
  end if;
  if v_src !~* 'NEW\.bag_size IS NULL' then
    raise exception 'the null guard is gone; clearing a standard would push NULL to coffee_inventory';
  end if;

  -- 4. The trigger itself is untouched and still narrow.
  select pg_get_triggerdef(t.oid) into v_trigger
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where c.relname = 'coffee_source'
    and t.tgname  = 'trg_propagate_coffee_source_bag_size'
    and not t.tgisinternal;

  if v_trigger is null then
    raise exception 'trg_propagate_coffee_source_bag_size is missing from coffee_source';
  end if;
  if v_trigger !~* 'AFTER UPDATE OF bag_size' then
    raise exception 'trg_propagate_coffee_source_bag_size is no longer AFTER UPDATE OF bag_size, so it fires on writes it was never meant to see: %', v_trigger;
  end if;
end $$;

commit;
