-- ============================================================================
-- Group count: overflow excess onto the newest lot (don't lose bags)
-- ============================================================================
-- apply_group_count_to_lots distributes a group bag-count across the origin's
-- lots newest-first, capping each lot at its received `amount`. If the counted
-- total exceeds the sum of lot amounts (common for migrated baselines where the
-- lot amounts under-state what's physically on hand), the excess had nowhere to
-- go — the lots summed to less than the count and the group/lot views diverged
-- (e.g. Maui Yellow: counted 4 bags, one lot capped at 2.18, 1.8 bags lost).
--
-- Fix: the NEWEST lot absorbs any overflow beyond the total lot amount, so the
-- lots always sum to the counted total. (The UI also warns and offers "Add
-- source" so the operator can attribute the overflow to a specific source
-- instead.) When the count fits within the lot amounts, behaviour is unchanged.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_group_count_to_lots(p_origin_id text, p_facility_id text, p_count_date date, p_bag_count numeric)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_company text;
    v_bag_size numeric;
    v_total_lbs numeric;
    v_tz text;
    v_count_moment timestamptz;
BEGIN
    SELECT company_id, NULLIF(bag_size, '')::numeric
      INTO v_company, v_bag_size
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;
    v_total_lbs := GREATEST(COALESCE(p_bag_count, 0) * COALESCE(v_bag_size, 0), 0);

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    IF p_count_date >= (now() AT TIME ZONE v_tz)::date THEN
        v_count_moment := now();
    ELSE
        v_count_moment := (p_count_date + 1)::timestamp AT TIME ZONE v_tz;
    END IF;

    UPDATE public.coffee_inventory
       SET last_inventory_at = v_count_moment
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id;

    DELETE FROM public.coffee_lot_count clc
     USING public.coffee_inventory_purchased cip
     WHERE clc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND clc.count_date = p_count_date;

    INSERT INTO public.coffee_lot_count (origin_purchase_id, count_date, count_at, counted_remaining_lbs, company_id)
    SELECT s.origin_purchase_id, p_count_date, v_count_moment,
           -- base fill (capped at this lot's amount), plus — for the newest lot
           -- only — any overflow beyond the sum of all lot amounts.
           LEAST(s.amount, GREATEST(0, v_total_lbs - s.prior_sum))
           + CASE WHEN s.rn = 1 THEN GREATEST(0, v_total_lbs - s.total_amount) ELSE 0 END,
           v_company
    FROM (
      SELECT cip.origin_purchase_id, cip.amount,
             COALESCE(SUM(cip.amount) OVER (
                ORDER BY COALESCE(sr.date_received, cip.created_at::date) DESC, cip.created_at DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prior_sum,
             ROW_NUMBER() OVER (
                ORDER BY COALESCE(sr.date_received, cip.created_at::date) DESC, cip.created_at DESC) AS rn,
             COALESCE(SUM(cip.amount) OVER (), 0) AS total_amount
        FROM public.coffee_inventory_purchased cip
        LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
       WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
         AND cip.amount IS NOT NULL
         AND (cip.shipment_id IS NULL
              OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false))
    ) s;
    -- recompute fires via the statement trigger on coffee_lot_count.
END;
$function$;
