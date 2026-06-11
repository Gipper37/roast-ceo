-- ============================================================================
-- Active coffee source per group + lot-deduction rework
-- ============================================================================
-- Adds a transient "active source" pointer per coffee group (origin, facility)
-- — "what's loaded in the hopper for this group right now." Roasts deduct from
-- the group's active source first (FIFO within it), instead of guessing via
-- blind FIFO or relying on a single per-roast coffee_source_id.
--
-- Also fixes a real bug: the old deduct_from_lot_on_roast treated ANY recipe
-- with components as a pre-blend (deducting all components by %). Post-blend
-- and single-origin roasts are logged per origin, so they must deduct only
-- their own origin. We now branch on the recipe's roast_type.
-- ============================================================================

-- 1. Active source pointer per group (origin × facility).
ALTER TABLE public.coffee_inventory
  ADD COLUMN IF NOT EXISTS active_coffee_source_id text
  REFERENCES public.coffee_source(coffee_source_id) ON DELETE SET NULL;

COMMENT ON COLUMN public.coffee_inventory.active_coffee_source_id IS
  'Transient pointer to the coffee_source currently being roasted for this '
  'group. Roasts deduct from this source first (FIFO within it). Updated when '
  'the roaster swaps lots (typically prompted on depletion). NULL = fall back '
  'to plain FIFO across the origin.';

-- 2. Rewrite the deduction trigger.
CREATE OR REPLACE FUNCTION public.deduct_from_lot_on_roast()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_component record;
    v_lot record;
    v_lbs_to_deduct numeric;
    v_lbs_alloc numeric;
    v_alloc_total numeric;
    v_origin_id text;
    v_roast_type text;
    v_is_preblend boolean;
    v_preferred_source text;
BEGIN
    -- Skip non-charge rows
    IF NEW."charged?" IS NOT TRUE OR COALESCE(NEW.charge_weight_lbs, 0) <= 0 THEN
        RETURN NEW;
    END IF;
    -- Skip historical inserts (importers + manual backfill paths)
    IF NEW.roast_date < NEW.created_at - interval '1 hour' THEN
        RETURN NEW;
    END IF;
    -- Skip Artisan imports specifically
    IF NEW.external_roast_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Recipe roast_type is authoritative for pre- vs post-blend. Only a
    -- Pre-Blend consumes all components in one roast; Post-Blend + Single
    -- Origin are logged per origin and deduct only their own origin.
    SELECT rr.roast_type INTO v_roast_type
      FROM public.roast_recipes rr
     WHERE rr.recipe_id = NEW.recipe_id;
    v_is_preblend := (v_roast_type = 'Pre-Blend');

    IF v_is_preblend THEN
        -- Pre-blend: deduct every component's share by percentage.
        FOR v_component IN
            SELECT rc.coffee_item AS origin_id, COALESCE(rc.percentage, 0) AS pct
              FROM public.recipe_components rc
             WHERE rc.recipe_id = NEW.recipe_id
               AND rc.coffee_item IS NOT NULL
               AND COALESCE(rc.percentage, 0) > 0
        LOOP
            v_lbs_to_deduct := NEW.charge_weight_lbs * (v_component.pct / 100.0);
            IF v_lbs_to_deduct <= 0 THEN CONTINUE; END IF;

            -- Preferred source for this component's group: an explicit
            -- per-roast pick that belongs to this origin wins; otherwise the
            -- group's active_coffee_source_id.
            SELECT CASE WHEN cs.origin_id = v_component.origin_id THEN NEW.coffee_source_id ELSE NULL END
              INTO v_preferred_source
              FROM public.coffee_source cs WHERE cs.coffee_source_id = NEW.coffee_source_id;
            IF v_preferred_source IS NULL THEN
                SELECT active_coffee_source_id INTO v_preferred_source
                  FROM public.coffee_inventory
                 WHERE origin_id = v_component.origin_id AND facility_id = NEW.facility_id;
            END IF;

            PERFORM public._deduct_origin_fifo(
                NEW.roast_log_id, v_component.origin_id, NEW.facility_id,
                v_lbs_to_deduct, v_preferred_source);
            PERFORM public.recalculate_origin_total_stock(v_component.origin_id, NEW.facility_id);
        END LOOP;
    ELSE
        -- Single-origin / post-blend: deduct the full charge from origin_id.
        v_origin_id := NEW.origin_id;
        IF v_origin_id IS NULL THEN RETURN NEW; END IF;
        v_preferred_source := NEW.coffee_source_id;
        IF v_preferred_source IS NULL THEN
            SELECT active_coffee_source_id INTO v_preferred_source
              FROM public.coffee_inventory
             WHERE origin_id = v_origin_id AND facility_id = NEW.facility_id;
        END IF;
        PERFORM public._deduct_origin_fifo(
            NEW.roast_log_id, v_origin_id, NEW.facility_id,
            NEW.charge_weight_lbs, v_preferred_source);
        PERFORM public.recalculate_origin_total_stock(v_origin_id, NEW.facility_id);
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Shared FIFO deductor: drains the preferred source's lots first, then the
--    rest of the origin oldest-first. Writes roast_log_lot_consumption rows.
CREATE OR REPLACE FUNCTION public._deduct_origin_fifo(
    p_roast_log_id text,
    p_origin_id text,
    p_facility_id text,
    p_lbs numeric,
    p_preferred_source text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_lot record;
    v_alloc_total numeric := 0;
    v_lbs_alloc numeric;
BEGIN
    FOR v_lot IN
        SELECT cip.origin_purchase_id, cip.remaining_lbs
          FROM public.coffee_inventory_purchased cip
          LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
         WHERE cip.origin = p_origin_id
           AND cip.facility_id = p_facility_id
           AND COALESCE(cip.remaining_lbs, 0) > 0
         ORDER BY
           -- Preferred (active) source's lots drain first
           CASE WHEN p_preferred_source IS NOT NULL
                     AND cip.coffee_source_id = p_preferred_source THEN 0 ELSE 1 END,
           -- then FIFO by received date (oldest first)
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
$$;
