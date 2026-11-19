-- A bin does not have a bag size.
--
-- `move_coffee_source_to_group(..., p_mode => 'bags', p_bags => N)` turned N
-- bags into a WEIGHT once, up front, at `coffee_inventory.bag_size` of the
-- origin being moved out of -- COALESCE'd to 154 when that origin has none --
-- and then spent that weight walking the actual lots, each of which records
-- its own bag size and gets labelled with it on the way out (:67). So the
-- amount leaving was measured with one denominator and the amount arriving
-- with another.
--
-- Concretely: an origin whose operative size is 152 holding nothing but 100 lb
-- sacks. "Move 2 bags" computed 2 x 152 = 304 lbs and drew 3.04 sacks. The
-- screen that asked the question had it right all along -- CoffeeSourceDetail
-- builds its bag figure as a SUM OF PER-LOT QUOTIENTS, not a division by one
-- size -- and so does `current_stock_bags_exact`, which is what fills
-- `coffee_inventory.in_stock`. The RPC was the only place in the family using
-- a single group-wide size.
--
-- 🔴 MEASURED ON PROD. 14 origins across all four tenants hold lots of more
-- than one bag size right now; 16 origins have no operative size at all, so
-- for those the 154 fallback was the denominator. 127 of 371 lots have an own
-- size differing from their group's.
--
-- WHY PER-LOT AND NOT "SEND POUNDS INSTEAD".
-- Sending pounds from the client is the cleaner contract and it deletes the
-- conversion from here entirely -- but it means renaming the parameter, and
-- `CREATE OR REPLACE` cannot rename an input parameter, so it means DROP and
-- CREATE. That is a breaking change across two repositories: between the
-- migration applying and the frontend deploying, one side calls a signature
-- the other no longer has, and Supabase RPC passes parameters BY NAME. There
-- is no ordering of the two deploys that does not break. Converting inside
-- the loop keeps the signature, so it needs no re-grant, it fixes every
-- caller at once including any outside this repo, and it keeps the operator's
-- unit: "move 5 bags" is five physical sacks, drawn oldest first, each worth
-- what its own lot says a sack of it weighs. That is also exactly the number
-- the screen showed.
--
-- A LOT WITH NO RECORDED BAG SIZE NOW REFUSES rather than guessing, naming
-- the lot. There are 0 such lots on hand today, so this does not fire -- but
-- the alternative is a fourth hardcoded fallback, and inventing a sack weight
-- is how this family of bugs started. `record_per_lot_count` already refuses
-- on the same condition.
--
-- The return gains `moved_bags` and `bags_requested`. A move asked for in bags
-- could not be answered in bags, and a short move -- locked books, lots
-- already consumed -- is silent today. Additive: the only caller
-- (CoffeeSourceDetail.tsx) reads `moved_lbs` and ignores the rest.
--
-- NOT TOUCHED: the 'all' mode, the books-closed guards, the FIFO order, the
-- per-lot clamp at the old :58, the slice INSERT's own `v_lot.bag_size`, and
-- both `recalculate_origin_total_stock` calls.
--
-- PROVENANCE. prod's live body is byte-identical to
-- 20260623000008_move_source_books_closed_per_lot.sql. The body below is that
-- text with the conversion moved into the loop; it was not retyped. The
-- function stays SECURITY INVOKER (prosecdef = f on prod) and CREATE OR
-- REPLACE preserves the existing grants.

begin;

create or replace function public.move_coffee_source_to_group(p_source_id text, p_target_origin text, p_mode text DEFAULT 'all'::text, p_bags numeric DEFAULT NULL::numeric)
 returns jsonb
 language plpgsql
as $function$
DECLARE
  v_company text; v_cur_origin text; v_facility text;
  v_target_company text; v_target_active boolean; v_closed date;
  v_moved numeric := 0; v_take numeric; v_lot record;
  -- bags mode works in BAGS and converts per lot, so it carries a bag budget
  -- and each lot's own size rather than one weight target for the group.
  v_bags_left numeric; v_take_bags numeric; v_lot_size numeric;
  v_moved_bags numeric := 0;
BEGIN
  SELECT company_id, origin_id INTO v_company, v_cur_origin
    FROM public.coffee_source WHERE coffee_source_id = p_source_id;
  IF v_company IS NULL THEN RAISE EXCEPTION 'coffee source % not found', p_source_id; END IF;

  SELECT company_id, is_active INTO v_target_company, v_target_active
    FROM public.coffee_inventory WHERE origin_id = p_target_origin;
  IF v_target_company IS NULL THEN RAISE EXCEPTION 'target group % not found', p_target_origin; END IF;
  IF v_target_company <> v_company THEN RAISE EXCEPTION 'target group belongs to a different company'; END IF;
  IF COALESCE(v_target_active, false) = false THEN RAISE EXCEPTION 'target group is archived'; END IF;
  IF p_target_origin = v_cur_origin THEN RAISE EXCEPTION 'source is already homed in that group'; END IF;

  SELECT facility_id INTO v_facility
    FROM public.coffee_inventory WHERE origin_id = v_cur_origin LIMIT 1;
  SELECT books_closed_through INTO v_closed FROM public.companies WHERE company_id = v_company;

  IF p_mode = 'all' THEN
    -- block only if the source still HOLDS stock received in a closed period
    IF v_closed IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
      WHERE cip.coffee_source_id = p_source_id AND cip.origin = v_cur_origin
        AND COALESCE(cip.remaining_lbs, 0) > 0
        AND COALESCE(sr.date_received, cip.created_at::date) <= v_closed
    ) THEN
      RAISE EXCEPTION 'Cannot re-home all of "%" — some of its on-hand stock was received in books closed through % and is part of finalized inventory. Move the newer (post-close) stock with a partial bag amount, or reorganize going forward.',
        COALESCE((SELECT coffee_name FROM public.coffee_source WHERE coffee_source_id = p_source_id), 'this coffee'), v_closed;
    END IF;

    UPDATE public.coffee_source SET origin_id = p_target_origin WHERE coffee_source_id = p_source_id;
    UPDATE public.coffee_inventory_purchased SET origin = p_target_origin
      WHERE coffee_source_id = p_source_id AND origin = v_cur_origin;
    SELECT COALESCE(SUM(GREATEST(remaining_lbs, 0)), 0) INTO v_moved
      FROM public.coffee_inventory_purchased WHERE coffee_source_id = p_source_id AND origin = p_target_origin;

  ELSIF p_mode = 'bags' THEN
    v_bags_left := COALESCE(p_bags, 0);
    IF v_bags_left <= 0 THEN RAISE EXCEPTION 'bags must be greater than 0'; END IF;
    FOR v_lot IN
      SELECT cip.origin_purchase_id, cip.remaining_lbs, cip.cost_lb, cip.bag_size
        FROM public.coffee_inventory_purchased cip
        LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
       WHERE cip.coffee_source_id = p_source_id AND cip.origin = v_cur_origin
         AND COALESCE(cip.remaining_lbs, 0) > 0
         -- unlocked only: post-close lots (or any lot when books are open)
         AND (v_closed IS NULL OR COALESCE(sr.date_received, cip.created_at::date) > v_closed)
       ORDER BY COALESCE(sr.date_received, cip.created_at::date) ASC, cip.created_at ASC
    LOOP
      EXIT WHEN v_bags_left <= 0;
      -- THE DENOMINATOR IS THE LOT'S, NEVER THE GROUP'S. A group is a bin and
      -- it holds sacks of more than one size, so "move N bags" has no single
      -- weight: it is N physical sacks, drawn oldest first, each worth what
      -- that lot says a sack of it weighs.
      v_lot_size := NULLIF(v_lot.bag_size, '')::numeric;
      IF v_lot_size IS NULL OR v_lot_size <= 0 THEN
        RAISE EXCEPTION 'Lot % of "%" has no bag size recorded, so a move measured in bags cannot be weighed against it. Set that lot''s bag size first, or move its stock from the lot drawer.',
          v_lot.origin_purchase_id,
          COALESCE((SELECT coffee_name FROM public.coffee_source WHERE coffee_source_id = p_source_id), 'this coffee');
      END IF;
      v_take_bags := LEAST(v_lot.remaining_lbs / v_lot_size, v_bags_left);
      -- Clamp to what the lot actually holds: the division above can land a
      -- hair over on a lot whose remaining_lbs is not a whole number of bags.
      v_take := LEAST(v_lot.remaining_lbs, v_take_bags * v_lot_size);
      IF v_take <= 0 THEN CONTINUE; END IF;
      UPDATE public.coffee_inventory_purchased
         SET remaining_lbs = remaining_lbs - v_take,
             amount = GREATEST(COALESCE(amount, 0) - v_take, 0)
       WHERE origin_purchase_id = v_lot.origin_purchase_id;
      INSERT INTO public.coffee_inventory_purchased
        (origin_purchase_id, origin, coffee_source_id, company_id, facility_id, amount, remaining_lbs, cost_lb, bag_size, entry_method, created_at)
      VALUES
        (gen_random_uuid()::text, p_target_origin, p_source_id, v_company, v_facility, v_take, v_take, v_lot.cost_lb, v_lot.bag_size, 'manual', now());
      v_moved := v_moved + v_take;
      v_moved_bags := v_moved_bags + v_take_bags;
      v_bags_left := v_bags_left - v_take_bags;
    END LOOP;
    IF v_moved = 0 THEN
      RAISE EXCEPTION 'No movable stock for "%" — its on-hand lots are either fully consumed or locked in books closed through %.',
        COALESCE((SELECT coffee_name FROM public.coffee_source WHERE coffee_source_id = p_source_id), 'this coffee'), v_closed;
    END IF;

  ELSE
    RAISE EXCEPTION 'unknown mode % (use all | bags)', p_mode;
  END IF;

  PERFORM public.recalculate_origin_total_stock(v_cur_origin, v_facility);
  PERFORM public.recalculate_origin_total_stock(p_target_origin, v_facility);
  RETURN jsonb_build_object('moved_lbs', v_moved, 'moved_bags', v_moved_bags,
    'bags_requested', CASE WHEN p_mode = 'bags' THEN COALESCE(p_bags, 0) ELSE NULL END,
    'mode', p_mode, 'from_origin', v_cur_origin, 'to_origin', p_target_origin);
END;
$function$;

-- A catalogue check cannot show that 2 bags of a 100 lb coffee now moves 200
-- lbs. That is proven on staging once CI applies this.
do $$
declare
  v_src text;
begin
  select p.prosrc into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'move_coffee_source_to_group';

  if v_src is null then
    raise exception 'move_coffee_source_to_group is missing';
  end if;

  -- 1. The group-wide denominator, and its invented 154, are gone.
  if v_src ~ 'COALESCE\(bag_size::numeric, 154\)' then
    raise exception 'the group-wide bag size is still being read, so bags mode still converts at one denominator';
  end if;

  -- 2. The conversion happens at the lot.
  if v_src !~ 'NULLIF\(v_lot\.bag_size' then
    raise exception 'bags are not being converted at each lot own size';
  end if;

  -- 3. Controls that must still PASS. A guard that only ever fires on failure
  --    says nothing about the parts it never looked at.
  if v_src !~ 'books closed through' then
    raise exception 'a books-closed guard went missing';
  end if;
  if v_src !~ 'unknown mode' then
    raise exception 'the mode guard went missing, so an unknown mode would silently do nothing';
  end if;
  if v_src !~ 'recalculate_origin_total_stock' then
    raise exception 'the stock recompute calls went missing, so both origins would keep stale totals';
  end if;
  if v_src !~ 'ORDER BY COALESCE\(sr\.date_received' then
    raise exception 'the FIFO order went missing, so a move would no longer draw the oldest lot first';
  end if;

  -- 4. CREATE OR REPLACE kept the grants. If this ever fails, every operator
  --    gets a permission error that reads like a PIN fault.
  if not has_function_privilege('authenticated',
        'public.move_coffee_source_to_group(text,text,text,numeric)', 'EXECUTE') then
    raise exception 'authenticated lost EXECUTE on move_coffee_source_to_group';
  end if;
end $$;

commit;
