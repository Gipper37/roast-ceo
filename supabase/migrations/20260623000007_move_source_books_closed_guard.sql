-- Books-closed guard for move_coffee_source_to_group().
--
-- Dollar COGS in closed periods is ALREADY safe: value_roast_lot_consumption
-- freezes roast_log_lot_consumption.lot_cost for any roast dated <= the company's
-- books_closed_through, and this move never touches lot_cost. The remaining risk
-- is CATEGORICAL: a full re-home ('all') moves lots that closed-period roasts
-- consumed, which would silently re-bucket finalized "lbs/cost by group" history.
-- So we block a full re-home when the source has closed-period consumption.
--
-- A partial 'bags' move only relocates UNCONSUMED remaining (it shrinks the live
-- lots and spins the slice into a new lot) — the closed consumption rows stay on
-- their original lots in the original group — so it is always allowed.
--
-- Dormant until a company sets books_closed_through (MCR = NULL today).

CREATE OR REPLACE FUNCTION public.move_coffee_source_to_group(
  p_source_id text, p_target_origin text, p_mode text DEFAULT 'all', p_bags numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
  v_company text; v_cur_origin text; v_facility text; v_bag_size numeric;
  v_target_company text; v_target_active boolean; v_closed date;
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
    -- books-closed guard (full re-home only; partial moves unconsumed stock)
    SELECT books_closed_through INTO v_closed FROM public.companies WHERE company_id = v_company;
    IF v_closed IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
      JOIN public.roast_log rl ON rl.roast_log_id = rlc.roast_log_id
      WHERE cip.coffee_source_id = p_source_id AND rl.roast_date::date <= v_closed
    ) THEN
      RAISE EXCEPTION 'Cannot re-home "%" — it has roasts in books closed through %. Dollar COGS is locked, but a full re-home would re-categorize those finalized roasts. Move a partial (bag) amount instead, or reorganize going forward.',
        COALESCE((SELECT coffee_name FROM public.coffee_source WHERE coffee_source_id = p_source_id), 'this coffee'), v_closed;
    END IF;

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
      UPDATE public.coffee_inventory_purchased
         SET remaining_lbs = remaining_lbs - v_take,
             amount = GREATEST(COALESCE(amount, 0) - v_take, 0)
       WHERE origin_purchase_id = v_lot.origin_purchase_id;
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
