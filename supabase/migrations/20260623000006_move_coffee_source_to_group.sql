-- Safe, atomic re-home / partial-move of a coffee source between groups, for the
-- UI "Move to group" modal. Fixes the gap where changing a source's Primary Coffee
-- Group only relabelled it (origin_id) and left its lots — and therefore its stock —
-- stranded in the old group.
--
--   mode 'all'  -> re-home the source (coffee_source.origin_id) AND move ALL its
--                  lots to the target group.
--   mode 'bags' -> split p_bags worth of stock (FIFO across the source's lots in its
--                  current group) into a NEW lot homed in the target group; the
--                  source's primary home is UNCHANGED. A partial allocation.
--
-- Stock total is preserved (move/split only). Refreshes total_stock for both groups
-- via recalculate_origin_total_stock (SUM of lots — no re-seed, no zeroing). Moving
-- coffee_source.origin_id / cip.origin fires no consumption recompute.

CREATE OR REPLACE FUNCTION public.move_coffee_source_to_group(
  p_source_id text, p_target_origin text, p_mode text DEFAULT 'all', p_bags numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
  v_company text; v_cur_origin text; v_facility text; v_bag_size numeric;
  v_target_company text; v_target_active boolean;
  v_lbs_to_move numeric; v_moved numeric := 0; v_take numeric; v_lot record;
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

  SELECT facility_id, COALESCE(bag_size::numeric, 154) INTO v_facility, v_bag_size
    FROM public.coffee_inventory WHERE origin_id = v_cur_origin LIMIT 1;

  IF p_mode = 'all' THEN
    UPDATE public.coffee_source SET origin_id = p_target_origin WHERE coffee_source_id = p_source_id;
    UPDATE public.coffee_inventory_purchased SET origin = p_target_origin
      WHERE coffee_source_id = p_source_id AND origin = v_cur_origin;
    SELECT COALESCE(SUM(GREATEST(remaining_lbs, 0)), 0) INTO v_moved
      FROM public.coffee_inventory_purchased WHERE coffee_source_id = p_source_id AND origin = p_target_origin;

  ELSIF p_mode = 'bags' THEN
    v_lbs_to_move := COALESCE(p_bags, 0) * v_bag_size;
    IF v_lbs_to_move <= 0 THEN RAISE EXCEPTION 'bags must be greater than 0'; END IF;
    FOR v_lot IN
      SELECT origin_purchase_id, remaining_lbs, cost_lb, bag_size
        FROM public.coffee_inventory_purchased
       WHERE coffee_source_id = p_source_id AND origin = v_cur_origin AND COALESCE(remaining_lbs, 0) > 0
       ORDER BY created_at ASC
    LOOP
      EXIT WHEN v_moved >= v_lbs_to_move;
      v_take := LEAST(v_lot.remaining_lbs, v_lbs_to_move - v_moved);
      IF v_take <= 0 THEN CONTINUE; END IF;
      -- shrink the source's lot in its current group
      UPDATE public.coffee_inventory_purchased
         SET remaining_lbs = remaining_lbs - v_take,
             amount = GREATEST(COALESCE(amount, 0) - v_take, 0)
       WHERE origin_purchase_id = v_lot.origin_purchase_id;
      -- create the moved slice as a new lot in the target group (amount set directly,
      -- so compute_coffee_purchase_amount [which only fires on bags_ordered] is a no-op)
      INSERT INTO public.coffee_inventory_purchased
        (origin_purchase_id, origin, coffee_source_id, company_id, facility_id, amount, remaining_lbs, cost_lb, bag_size, entry_method, created_at)
      VALUES
        (gen_random_uuid()::text, p_target_origin, p_source_id, v_company, v_facility, v_take, v_take, v_lot.cost_lb, v_lot.bag_size, 'manual', now());
      v_moved := v_moved + v_take;
    END LOOP;

  ELSE
    RAISE EXCEPTION 'unknown mode % (use all | bags)', p_mode;
  END IF;

  PERFORM public.recalculate_origin_total_stock(v_cur_origin, v_facility);
  PERFORM public.recalculate_origin_total_stock(p_target_origin, v_facility);
  RETURN jsonb_build_object('moved_lbs', v_moved, 'mode', p_mode, 'from_origin', v_cur_origin, 'to_origin', p_target_origin);
END;
$function$;
