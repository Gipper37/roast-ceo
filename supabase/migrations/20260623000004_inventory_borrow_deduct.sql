-- Borrow, part 1 — the in-roast deduct (write-side). A roast can consume a lot
-- whose HOME is another group; that lot is what deducts, so its home group loses
-- stock + gains reorder need (per the single-planning-home model). Replay safety
-- (recompute + dispatch trigger made borrow-aware) is part 2 (migration
-- ...000005); both deploy together. See memory/project_lot_home_inventory.md.

-- The explicitly-borrowed lot for a roast (single-origin/post-blend). NULL = no
-- borrow (normal FIFO within the recipe's group).
ALTER TABLE public.roast_log
  ADD COLUMN IF NOT EXISTS borrow_origin_purchase_id text
  REFERENCES public.coffee_inventory_purchased(origin_purchase_id) ON DELETE SET NULL;
COMMENT ON COLUMN public.roast_log.borrow_origin_purchase_id IS
  'Explicit cross-group borrow: the exact lot this roast consumed, even though its home group differs from the recipe origin. Deducts that lot lot-true.';

-- Drop the dead 5-arg overload so adding the force arg can''t create an
-- ambiguous 3rd signature. (Verified: no live caller; recompute + deduct use the
-- 6-arg.)
DROP FUNCTION IF EXISTS public._deduct_origin_fifo(text, text, text, numeric, text);

-- Extend the FIFO deduct with an optional forced lot. When set, that lot is
-- consumed FIRST (regardless of its home origin or received date — it''s an
-- explicit operator pick), then any shortfall falls through to normal FIFO
-- within the cited origin. When NULL, behaviour is exactly as before.
CREATE OR REPLACE FUNCTION public._deduct_origin_fifo(
    p_roast_log_id text, p_origin_id text, p_facility_id text, p_lbs numeric,
    p_preferred_source text, p_roast_date timestamp without time zone,
    p_force_origin_purchase_id text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_lot record;
    v_alloc_total numeric := 0;
    v_lbs_alloc numeric;
BEGIN
    IF COALESCE(p_lbs, 0) <= 0 THEN RETURN; END IF;
    FOR v_lot IN
        SELECT cip.origin_purchase_id, cip.remaining_lbs
          FROM public.coffee_inventory_purchased cip
          LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
         WHERE cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
           -- the cited group's lots, PLUS the explicitly-borrowed lot (any group)
           AND (cip.origin = p_origin_id
                OR cip.origin_purchase_id = p_force_origin_purchase_id)
           -- existed at roast time — the forced lot is exempt (deliberate pick)
           AND (cip.origin_purchase_id = p_force_origin_purchase_id
                OR p_roast_date IS NULL
                OR COALESCE(sr.date_received, cip.created_at::date) <= p_roast_date::date)
         ORDER BY
           -- forced (borrowed) lot first, then preferred source, then FIFO
           CASE WHEN cip.origin_purchase_id = p_force_origin_purchase_id THEN 0 ELSE 1 END,
           CASE WHEN p_preferred_source IS NOT NULL
                     AND cip.coffee_source_id = p_preferred_source THEN 0 ELSE 1 END,
           COALESCE(sr.date_received, cip.created_at::date) ASC,
           cip.created_at ASC
    LOOP
        IF v_alloc_total >= p_lbs THEN EXIT; END IF;
        v_lbs_alloc := LEAST(v_lot.remaining_lbs, p_lbs - v_alloc_total);
        IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;
        UPDATE public.coffee_inventory_purchased
           SET remaining_lbs = remaining_lbs - v_lbs_alloc
         WHERE origin_purchase_id = v_lot.origin_purchase_id;
        INSERT INTO public.roast_log_lot_consumption (roast_log_id, origin_purchase_id, lbs_consumed)
          VALUES (p_roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);
        v_alloc_total := v_alloc_total + v_lbs_alloc;
    END LOOP;
END;
$function$;

-- Incremental deduct on a fresh charge: pass the borrowed lot through for a
-- single-origin / post-blend roast, and refresh the lender lot''s HOME group too
-- (so the group that physically lost the bean updates its stock). Pre-blend
-- per-component borrow is handled later via the planned-lots path.
CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    rl record;
    o text;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_borrow_home text;
BEGIN
    SELECT rl2.roast_log_id, rl2.facility_id, rl2.charge_weight_lbs, rl2.coffee_source_id,
           rl2.recipe_id, rl2.origin_id, rl2.roast_date, rl2.created_at,
           rl2."charged?" AS charged, rl2.external_roast_id, rl2.borrow_origin_purchase_id, rr.roast_type
      INTO rl
      FROM public.roast_log rl2
      LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl2.recipe_id
     WHERE rl2.roast_log_id = p_roast_log_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF rl.charged IS NOT TRUE OR COALESCE(rl.charge_weight_lbs, 0) <= 0 THEN RETURN; END IF;
    IF rl.external_roast_id IS NULL
       AND rl.roast_date < (rl.created_at::date - interval '1 day') THEN RETURN; END IF;
    IF rl.facility_id IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.roast_log_lot_consumption WHERE roast_log_id = p_roast_log_id) THEN RETURN; END IF;

    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id) LOOP
        IF rl.roast_type = 'Pre-Blend' THEN
            SELECT rl.charge_weight_lbs * COALESCE(rc.percentage, 0) INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = rl.recipe_id AND rc.coffee_item = o
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := rl.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        v_pref := NULL;
        IF rl.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = o THEN rl.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = rl.coffee_source_id;
        END IF;

        -- Borrow applies to single-origin / post-blend only (one affected origin).
        v_force := NULL;
        IF rl.roast_type IS DISTINCT FROM 'Pre-Blend'
           AND o = rl.origin_id AND rl.borrow_origin_purchase_id IS NOT NULL THEN
            v_force := rl.borrow_origin_purchase_id;
        END IF;

        PERFORM public._deduct_origin_fifo(rl.roast_log_id, o, rl.facility_id, v_needed, v_pref, rl.roast_date, v_force);
        PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
    END LOOP;

    -- Refresh the lender lot''s home group (the bean physically left it).
    IF rl.borrow_origin_purchase_id IS NOT NULL THEN
        SELECT cip.origin INTO v_borrow_home
          FROM public.coffee_inventory_purchased cip
         WHERE cip.origin_purchase_id = rl.borrow_origin_purchase_id;
        IF v_borrow_home IS NOT NULL THEN
            PERFORM public.recalculate_origin_total_stock(v_borrow_home, rl.facility_id);
        END IF;
    END IF;
END;
$function$;
