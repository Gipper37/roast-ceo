-- Refine the books-closed guard on move_coffee_source_to_group to be per-LOT, not
-- per-source-history (operator correction):
--
--   A lot is LOCKED only if it has remaining_lbs > 0 AND was received on/before the
--   company's books_closed_through — i.e. it is still-on-hand stock that sits in a
--   finalized period's ending inventory under its current group. Moving it would
--   alter closed books.
--
--   Spent/used-up lots (remaining = 0) do NOT lock the source — they're gone, and
--   their frozen COGS (roast_log_lot_consumption.lot_cost) is untouched by a move.
--   Lots received AFTER the close are freely movable.
--
--   So: 'all' is blocked only when the source still holds LOCKED stock; 'bags'
--   moves UNLOCKED lots only (post-close / books-open), never locked ones.
--
-- Dormant until a company sets books_closed_through (all tenants NULL today).

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
    v_lbs_to_move := COALESCE(p_bags, 0) * v_bag_size;
    IF v_lbs_to_move <= 0 THEN RAISE EXCEPTION 'bags must be greater than 0'; END IF;
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
    IF v_moved = 0 THEN
      RAISE EXCEPTION 'No movable stock for "%" — its on-hand lots are either fully consumed or locked in books closed through %.',
        COALESCE((SELECT coffee_name FROM public.coffee_source WHERE coffee_source_id = p_source_id), 'this coffee'), v_closed;
    END IF;

  ELSE
    RAISE EXCEPTION 'unknown mode % (use all | bags)', p_mode;
  END IF;

  PERFORM public.recalculate_origin_total_stock(v_cur_origin, v_facility);
  PERFORM public.recalculate_origin_total_stock(p_target_origin, v_facility);
  RETURN jsonb_build_object('moved_lbs', v_moved, 'mode', p_mode, 'from_origin', v_cur_origin, 'to_origin', p_target_origin);
END;
$function$;
