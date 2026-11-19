-- A count with no bag size wiped the stock and said it worked.
--
-- `apply_group_count_to_lots` converted the counted bags at
-- `coffee_inventory.bag_size` and the conversion was
--
--     v_total_lbs := GREATEST(COALESCE(p_bag_count, 0) * COALESCE(v_bag_size, 0), 0);
--
-- `COALESCE(v_bag_size, 0)`. On an origin with no bag size the whole product is
-- ZERO, so the INSERT below writes 0 to every one of that origin's lots, the
-- statement trigger on coffee_lot_count copies those zeros into
-- `remaining_lbs`, and the function RETURNS VOID -- success. An operator
-- counting their stock erased it and was told nothing went wrong.
--
-- 🔴 MEASURED ON PROD: 16 origins have a NULL or blank `coffee_inventory.
-- bag_size` (14 at 752af3ed-4, 2 at 9ShiyDAXhV), between them 5 on-hand lots
-- and 441.2 lbs. The group count box is reachable on all of them. Nothing has
-- been wiped yet -- of 348 counted lots, not one still answers to a group-path
-- write -- so this closes a hole rather than repairing damage.
--
-- Now it refuses, and the message says what to do about it. Zero stays a
-- legal count: "I have none" is an answer, "I have none because nobody set a
-- bag size" is not.
--
-- WHAT THIS DOES NOT DO, deliberately.
-- It does not clamp the overflow term. The unclamped copy into remaining_lbs
-- is the FEATURE -- a physical count is the truth, which is how found stock
-- becomes recordable -- and prod has a live example that a clamp would
-- destroy: lot 8e0536bc-27af holds 893.90 lbs on a recorded amount of 500
-- because an operator counted 9 bags of a 100 lb coffee against a 5-bag
-- purchase record. Clamping would throw away 393.90 lbs of real coffee.
--
-- It also does not decide what a bag count MEANS on an origin holding sacks of
-- more than one size, which is the larger question behind this one and is a
-- product decision, not a bug: 14 origins across all four tenants are in that
-- state today, and for them no choice of multiplier is right. That is open.
--
-- 🔴 THE GUARD IS A BACKSTOP, NOT THE FIX ON ITS OWN. `recordCoffeeCount`
-- inserts the count into coffee_inventory_history FIRST, then calls this RPC
-- through a helper that returns `{data, error}` and never throws -- and
-- ignores the result. So a raise here would have been invisible, and would
-- have left the group count recorded with the lot layer untouched. The action
-- now validates the bag size BEFORE it writes anything and checks this RPC's
-- error, and the two call sites surface it. This guard stays because
-- `authenticated` holds EXECUTE on the function and can call it directly.
--
-- PROVENANCE. prod's live body, with the conversion guarded; not retyped.

begin;

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
BEGIN
    SELECT company_id, NULLIF(bag_size, '')::numeric, true, origin
      INTO v_company, v_bag_size, v_found, v_name
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;

    -- 🔴 NO SIZE MEANS NO ANSWER, NOT ZERO.
    -- This used to be COALESCE(v_bag_size, 0), so a count on an origin with no
    -- bag size multiplied out to 0, wrote 0 to EVERY one of its lots, let the
    -- recompute copy those zeros into remaining_lbs, and returned success. An
    -- operator counting stock erased it and was told nothing. 16 origins on
    -- prod have no operative size, holding 5 on-hand lots and 441.2 lbs.
    IF NOT COALESCE(v_found, false) THEN
        RAISE EXCEPTION 'No coffee group % at this facility, so there is nothing to apply a count to.', p_origin_id;
    END IF;
    IF v_bag_size IS NULL OR v_bag_size <= 0 THEN
        RAISE EXCEPTION 'Set a bag size on "%" before counting it in bags -- without one there is no weight to record, and a count would wipe the stock instead of correcting it. Set the bag size on the coffee group, or count it lot by lot.',
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
declare v_src text; v_code text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'apply_group_count_to_lots';
  if v_src is null then raise exception 'apply_group_count_to_lots is missing'; end if;

  -- 🔴 STRIP THE COMMENTS BEFORE MATCHING. `prosrc` is the whole body,
  -- comments included, so a check for a pattern the body DOCUMENTS matches the
  -- documentation, not the code. That is how this block first failed: the
  -- comment explaining what COALESCE(v_bag_size, 0) used to do satisfied the
  -- grep for it. Worse is the other direction -- a "must be present" check
  -- passing on a comment -- which reads as green.
  v_code := regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g');

  -- 1. Zero is no longer substituted for a missing size.
  if v_code ~ 'COALESCE\(v_bag_size, 0\)' then
    raise exception 'the missing bag size still coalesces to 0, so a count can still wipe an origin';
  end if;
  if v_code !~ 'v_bag_size IS NULL OR v_bag_size <= 0' then
    raise exception 'the missing-bag-size guard is not present';
  end if;

  -- 2. Controls that must still PASS.
  if v_code !~ 'rn = 1 THEN GREATEST\(0, v_total_lbs - s.total_amount\)' then
    raise exception 'the overflow-to-newest-lot term is gone; found stock would stop being recordable';
  end if;
  if v_code !~ 'LEAST\(s.amount, GREATEST\(0, v_total_lbs - s.prior_sum\)\)' then
    raise exception 'the per-lot base fill is gone';
  end if;
  if v_code !~ 'DELETE FROM public.coffee_lot_count' then
    raise exception 'the same-day delete is gone, so a recount would double-anchor';
  end if;
  if v_code !~ 'COALESCE\(sr.voided, false\) = false' then
    raise exception 'the voided-shipment filter is gone';
  end if;
  if not has_function_privilege('authenticated',
        'public.apply_group_count_to_lots(text,text,date,numeric)', 'EXECUTE') then
    raise exception 'authenticated lost EXECUTE on apply_group_count_to_lots';
  end if;
end $$;

commit;
