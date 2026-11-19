-- A group holding two sack sizes cannot be counted in bags.
--
-- 20261118000003 refused a bag count when the origin had NO bag size, and said
-- in its own header that the larger question -- what a bag count means on a
-- group holding sacks of more than one size -- was still open. 20261118000005
-- answered it: that group is counted in POUNDS. This closes the bag door
-- behind it, which is the same principle generalised. No size means no answer,
-- and no SINGLE size means no answer either.
--
-- 🔴 MEASURED, not reasoned about. On the local rehearsal, a group holding ten
-- 152 lb sacks and ten 132 lb sacks -- 2,840 lbs, exactly 20 bags -- was
-- counted by entering 20. The old path multiplied by the origin's one size and
-- stored 3,040 lbs, then the overflow term put the extra 200 lbs on the 132 lb
-- lot, so `in_stock` came out at 21.52 bags. The operator counted twenty sacks
-- and the app recorded twenty-one and a half, plus 200 lbs of coffee that does
-- not exist. 14 origins across all four tenants are in that state on prod
-- today, the worst holding 19 coffees at 3 sizes.
--
-- WHY A GUARD AND NOT JUST THE NEW SCREEN.
-- The count box will ask for pounds on these groups, so this should never
-- fire from the app. It fires for everything else: `authenticated` holds
-- EXECUTE on this function and can call it directly, an older deployed copy of
-- the frontend keeps calling it, and the next feature that wants a count will
-- find it first. 20261118000003 learned that lesson the hard way -- its own
-- guard was invisible because the caller ignored the RPC's error -- so the
-- refusal has to live where the arithmetic lives.
--
-- WHAT IT DOES NOT DO.
-- It does not touch the per-lot path. record_per_lot_count takes a bag count
-- PER LOT and converts each at that lot's own size, which is well defined no
-- matter how many sizes the group holds; it is only the group-level single
-- multiplication that has no answer.
-- It does not refuse a group with ONE known size and a blank origin column --
-- that group has an answerable bag count, and 20261118000003 would have
-- refused it. This fixes that too: the test is now the LOTS, which is what the
-- operator is looking at, not the origin's column.
--
-- PROVENANCE. 20261118000003's body, with the size resolved from the lots and
-- one branch added. Not retyped from prod: 000003 is the version that must be
-- in force when this runs, and it is asserted below.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.apply_group_count_to_lots(p_origin_id text, p_facility_id text, p_count_date date, p_bag_count numeric)
 returns void
 language plpgsql
as $function$
DECLARE
    v_company text;
    v_bag_size numeric;
    v_found boolean := false;
    v_name text;
    v_total_lbs numeric;
    v_tz text;
    v_count_moment timestamptz;
    v_sizes_on_hand integer;
    v_unsized_on_hand integer;
BEGIN
    SELECT company_id, NULLIF(bag_size, '')::numeric, true, origin
      INTO v_company, v_bag_size, v_found, v_name
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;

    IF NOT COALESCE(v_found, false) THEN
        RAISE EXCEPTION 'No coffee group % at this facility, so there is nothing to apply a count to.', p_origin_id;
    END IF;

    -- 🔴 THE SIZES ACTUALLY ON THE FLOOR decide whether bags mean anything,
    -- not the origin's column. A lot on hand with no size recorded counts as
    -- its own unknown: it must not drop out of the set and leave one size
    -- looking unanimous.
    SELECT COUNT(DISTINCT NULLIF(cip.bag_size, '')),
           COUNT(*) FILTER (WHERE NULLIF(cip.bag_size, '') IS NULL)
      INTO v_sizes_on_hand, v_unsized_on_hand
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND COALESCE(cip.remaining_lbs, 0) > 0
       AND (cip.shipment_id IS NULL
            OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false));

    IF COALESCE(v_sizes_on_hand, 0) > 1 OR COALESCE(v_unsized_on_hand, 0) > 0 THEN
        RAISE EXCEPTION 'The sacks of "%" on hand are not all the same size, so a number of bags does not say how much coffee there is. Count it by weight instead, or count each lot on its own.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    -- One size on the floor is an answer even when the group's own column is
    -- blank, so prefer what is there over what was configured.
    v_bag_size := COALESCE(
      (SELECT NULLIF(cip.bag_size, '')::numeric
         FROM public.coffee_inventory_purchased cip
         LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
        WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
          AND COALESCE(cip.remaining_lbs, 0) > 0
          AND NULLIF(cip.bag_size, '') IS NOT NULL
          AND (cip.shipment_id IS NULL
               OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false))
        LIMIT 1),
      v_bag_size);

    -- 🔴 NO SIZE MEANS NO ANSWER, NOT ZERO. This used to coalesce to 0, so a
    -- count on a sizeless origin multiplied out to 0, wrote 0 to EVERY lot and
    -- returned success: the operator erased their stock and was told nothing.
    IF v_bag_size IS NULL OR v_bag_size <= 0 THEN
        RAISE EXCEPTION 'Set a bag size on "%" before counting it in bags -- without one there is no weight to record, and a count would wipe the stock instead of correcting it. Set the bag size on the coffee group, or count it by weight.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;
    IF p_bag_count IS NULL OR p_bag_count < 0 THEN
        RAISE EXCEPTION 'A bag count must be zero or more.';
    END IF;

    v_total_lbs := GREATEST(COALESCE(p_bag_count, 0) * v_bag_size, 0);

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

do $$
declare v_code text;
begin
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_code
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='apply_group_count_to_lots';
  if v_code is null then raise exception 'apply_group_count_to_lots is missing'; end if;

  -- 1. The new refusal, and the size now comes off the floor.
  if v_code !~ 'v_sizes_on_hand, 0\) > 1' then
    raise exception 'the mixed-size refusal is not present; a bag count would still multiply by one invented size';
  end if;
  if v_code !~ 'v_unsized_on_hand, 0\) > 0' then
    raise exception 'a lot on hand with no recorded size would drop out of the set and leave one size looking unanimous';
  end if;
  if v_code !~ 'COALESCE\(cip\.remaining_lbs, 0\) > 0' then
    raise exception 'the size test is not scoped to the lots ON HAND';
  end if;

  -- 2. Controls from 20261118000003 that must still hold. Without these,
  --    gutting the function would pass check 1.
  if v_code ~ 'COALESCE\(v_bag_size, 0\)' then
    raise exception 'the missing bag size coalesces to 0 again, so a count can still wipe an origin';
  end if;
  if v_code !~ 'v_bag_size IS NULL OR v_bag_size <= 0' then
    raise exception 'the missing-bag-size guard from 20261118000003 is gone';
  end if;
  if v_code !~ 'rn = 1 THEN GREATEST\(0, v_total_lbs - s\.total_amount\)' then
    raise exception 'the overflow-to-newest-lot term is gone; found stock would stop being recordable';
  end if;
  if v_code !~ 'LEAST\(s\.amount, GREATEST\(0, v_total_lbs - s\.prior_sum\)\)' then
    raise exception 'the per-lot base fill is gone';
  end if;
  if v_code !~ 'DELETE FROM public\.coffee_lot_count' then
    raise exception 'the same-day delete is gone, so a recount would double-anchor';
  end if;
  if v_code !~ 'COALESCE\(sr\.voided, false\) = false' then
    raise exception 'the voided-shipment filter is gone';
  end if;
  if v_code !~ 'p_bag_count IS NULL OR p_bag_count < 0' then
    raise exception 'the negative-count guard is gone';
  end if;
  if not has_function_privilege('authenticated',
        'public.apply_group_count_to_lots(text,text,date,numeric)', 'EXECUTE') then
    raise exception 'authenticated lost EXECUTE on apply_group_count_to_lots';
  end if;

  -- 3. The pounds path this refusal points operators at must EXIST, or the
  --    message tells them to do something impossible.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='record_group_count_lbs') then
    raise exception 'record_group_count_lbs is missing, so the refusal above tells the operator to count by weight with no way to do it';
  end if;
end $$;

commit;
