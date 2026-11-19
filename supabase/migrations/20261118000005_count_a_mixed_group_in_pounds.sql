-- Count a mixed group in pounds.
--
-- Owner, 2026-11-18: "Ask for pounds". On a coffee group whose sacks are not
-- all one size, "how many bags?" has no answer -- 14 origins across all four
-- tenants are in that state today, one of them holding 19 different coffees at
-- 3 sizes -- so the box asks for a weight instead. This is the RPC that
-- records one. 20261118000004 added the column it lands in.
--
-- WHY A NEW FUNCTION RATHER THAN A PARAMETER ON THE OLD ONE.
-- CREATE OR REPLACE cannot add or rename a parameter: it would create an
-- OVERLOAD, and two same-arity overloads make a named-argument call AMBIGUOUS.
-- Supabase RPC passes arguments BY NAME, so the moment the overload existed
-- every deployed copy of the frontend calling apply_group_count_to_lots would
-- start failing -- before the new frontend is even built. Separate name, no
-- window.
--
-- WHAT IT DOES, AND WHY THE ORDER IS THIS WAY.
-- The pounds go to the LOT layer first, because that is where this app already
-- keeps counted weight: coffee_lot_count.counted_remaining_lbs is pounds, and
-- the statement trigger on it recomputes remaining_lbs and the origin's stock.
-- Only then is the group's audit row written, so its bag figure can be the
-- canonical post-count one from current_stock_bags_exact -- the same function
-- trg_zzz_sync_in_stock_bags uses for `in_stock`, which divides EACH lot by
-- ITS OWN size and falls back to the effective size for a lot that has none.
-- That keeps coffee_inventory_history.bag_count NOT NULL and keeps the weekly
-- stock view the Reports page reads anchored on a real number, while
-- counted_lbs carries what the operator actually counted.
--
-- 🔴 The distribution below is NOT new arithmetic. It is
-- apply_group_count_to_lots' own SELECT, with `v_total_lbs` coming straight
-- from the caller instead of from p_bag_count x one size. That multiplication
-- is the entire bug: on a group holding 132 lb and 152 lb sacks there is no
-- single size, and whichever one is chosen the product is not the weight on
-- the floor. Nothing else about how a count lands changes.
--
-- WHAT IT DOES NOT DO.
-- No new permission key. A pounds count is the same capability as a bag count
-- -- counting stock -- taken in a different unit, so it answers to the check
-- the count action already makes. A new key would have to be granted to 11
-- roles and 4 plans before the UI could name it, to add nothing.
-- It does not clamp the overflow term: a physical count is the truth, which is
-- how found stock becomes recordable, and prod has a lot holding 893.90 lbs on
-- a recorded 500 that a clamp would throw away.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.record_group_count_lbs(
  p_origin_id   text,
  p_facility_id text,
  p_count_date  date,
  p_total_lbs   numeric,
  p_company_id  text default null,
  p_reason      text default null
) returns jsonb
 language plpgsql
as $function$
DECLARE
    v_company       text;
    v_found         boolean := false;
    v_name          text;
    v_tz            text;
    v_count_moment  timestamptz;
    v_bags_after    numeric;
    v_lots          integer;
BEGIN
    SELECT company_id, true, origin
      INTO v_company, v_found, v_name
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;

    IF NOT COALESCE(v_found, false) THEN
        RAISE EXCEPTION 'No coffee group % at this facility, so there is nothing to apply a count to.', p_origin_id;
    END IF;

    -- A weight is the one thing this function needs the caller to get right;
    -- it invents no denominator, so there is nothing else to guard.
    IF p_total_lbs IS NULL OR p_total_lbs < 0 THEN
        RAISE EXCEPTION 'A counted weight must be zero or more.';
    END IF;

    v_company := COALESCE(p_company_id, v_company);
    IF v_company IS NULL THEN
        RAISE EXCEPTION 'No company on coffee group "%", so a count cannot be attributed.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    -- The count's moment resolves in the FACILITY's timezone. A count dated
    -- today lands now; a back-dated one lands at the end of that day, so it
    -- sits after everything already recorded on it.
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

    -- Recounting the same day replaces that day's checkpoint rather than
    -- double-anchoring it.
    DELETE FROM public.coffee_lot_count clc
     USING public.coffee_inventory_purchased cip
     WHERE clc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND clc.count_date = p_count_date;

    INSERT INTO public.coffee_lot_count (origin_purchase_id, count_date, count_at, counted_remaining_lbs, company_id, reason)
    SELECT s.origin_purchase_id, p_count_date, v_count_moment,
           -- base fill (capped at this lot's amount), plus — for the newest lot
           -- only — any overflow beyond the sum of all lot amounts.
           LEAST(s.amount, GREATEST(0, p_total_lbs - s.prior_sum))
           + CASE WHEN s.rn = 1 THEN GREATEST(0, p_total_lbs - s.total_amount) ELSE 0 END,
           v_company, p_reason
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
    GET DIAGNOSTICS v_lots = ROW_COUNT;

    -- 🔴 A group with no purchase line gets no rows above, so the count would
    -- anchor nothing while still claiming to have been recorded. 24 of prod's
    -- 80 origins are in that state. Say so instead.
    IF v_lots = 0 THEN
        RAISE EXCEPTION 'There are no received lots of "%" to record a count against. Receive a shipment, or add a baseline lot, then count it.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    -- Now the lots carry the weight, so this is the canonical bag figure: each
    -- lot divided by its OWN size. It is what `in_stock` will show.
    v_bags_after := public.current_stock_bags_exact(p_origin_id, p_facility_id);

    INSERT INTO public.coffee_inventory_history
      (history_id, origin_id, facility_id, company_id, inventory_date, bag_count, counted_lbs, notes)
    VALUES
      (gen_random_uuid()::text, p_origin_id, p_facility_id, v_company, p_count_date,
       round(COALESCE(v_bags_after, 0), 2), p_total_lbs, p_reason);

    -- The history insert pushes to the group row, which re-derives inventory_lbs
    -- from counted_lbs and in_stock_lbs from that. Settle the lot-derived
    -- figures last, the way the bag path does when its RPC runs after the
    -- history insert. The core only recomputes consumption -- not
    -- attribute_after_stock_event, which the statement trigger already ran and
    -- which must not be run twice for one count.
    PERFORM public._recompute_origin_lot_consumption_core(p_origin_id, p_facility_id);

    RETURN jsonb_build_object(
      'counted_lbs', p_total_lbs,
      'bags_recorded', round(COALESCE(v_bags_after, 0), 2),
      'lots_anchored', v_lots
    );
END;
$function$;

comment on function public.record_group_count_lbs(text,text,date,numeric,text,text) is
  'Records a group coffee count taken in POUNDS. For a group holding sacks of more than one size a bag count has no answer, so the box asks for a weight; this applies it to the lots (newest first, overflow to the newest), then writes the audit row with the canonical post-count bag figure and the counted weight. Unlike apply_group_count_to_lots it multiplies nothing by an origin-level bag size.';

revoke all on function public.record_group_count_lbs(text,text,date,numeric,text,text) from public;
grant execute on function public.record_group_count_lbs(text,text,date,numeric,text,text) to authenticated;

do $$
declare v_src text; v_code text;
begin
  -- 🔴 THE DEPENDENCY, ASSERTED FIRST. plpgsql parses a function body lazily,
  -- so CREATE OR REPLACE above succeeds even on a database where
  -- 20261118000004 never landed and `counted_lbs` does not exist -- and a
  -- prosrc grep would then report green on a function that throws on its first
  -- call. Caught exactly that way in the local rehearsal: 000004 rolled back
  -- and this file still said OK.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='coffee_inventory_history'
                    and column_name='counted_lbs') then
    raise exception 'coffee_inventory_history.counted_lbs is missing, so 20261118000004 has not been applied to this database';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='coffee_inventory'
                    and column_name='counted_lbs') then
    raise exception 'coffee_inventory.counted_lbs is missing, so 20261118000004 has not been applied to this database';
  end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    into v_code
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='record_group_count_lbs';
  if v_code is null then raise exception 'record_group_count_lbs is missing'; end if;

  -- 1. THE POINT OF THE FUNCTION: no bag-size multiplication anywhere in it.
  --    Comments stripped first, or this check matches the header explaining it.
  if v_code ~* 'bag_size' then
    raise exception 'record_group_count_lbs references bag_size; a pounds count must not resolve a denominator at all';
  end if;
  if v_code !~ 'p_total_lbs - s\.prior_sum' then
    raise exception 'the counted weight is not what gets distributed across the lots';
  end if;

  -- 2. Controls carried over from the bag path, each of which has its own
  --    reason to exist and would be invisible if dropped.
  if v_code !~ 'rn = 1 THEN GREATEST\(0, p_total_lbs - s\.total_amount\)' then
    raise exception 'the overflow-to-newest-lot term is missing; found stock would not be recordable';
  end if;
  if v_code !~ 'DELETE FROM public\.coffee_lot_count' then
    raise exception 'the same-day delete is missing, so a recount would double-anchor the day';
  end if;
  if v_code !~ 'COALESCE\(sr\.voided, false\) = false' then
    raise exception 'the voided-shipment filter is missing';
  end if;
  if v_code !~ 'current_stock_bags_exact' then
    raise exception 'the audit row does not get the canonical per-lot bag figure';
  end if;
  if v_code !~ 'counted_lbs' then
    raise exception 'the counted weight is never recorded on the audit row';
  end if;
  if v_code !~ 'v_lots = 0' then
    raise exception 'the no-lots-to-anchor refusal is missing';
  end if;
  -- attribution must not be re-run; the statement trigger already did it.
  if v_code ~ 'PERFORM public\.recompute_origin_lot_consumption\(' then
    raise exception 'it calls the wrapper, which re-runs attribute_after_stock_event for a count that already attributed once';
  end if;
  if v_code !~ '_recompute_origin_lot_consumption_core' then
    raise exception 'the lot-derived figures are never settled after the history push';
  end if;

  -- 3. It is callable, and the OLD path is untouched.
  if not has_function_privilege('authenticated',
        'public.record_group_count_lbs(text,text,date,numeric,text,text)', 'EXECUTE') then
    raise exception 'authenticated cannot EXECUTE record_group_count_lbs';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='apply_group_count_to_lots') then
    raise exception 'apply_group_count_to_lots is gone; the bag path still has callers';
  end if;
  -- 🔴 And it is NOT an overload: exactly one function by this name, or a
  -- named-argument call from the frontend would be ambiguous.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='record_group_count_lbs') <> 1 then
    raise exception 'record_group_count_lbs is overloaded; Supabase calls RPCs by name and the call would be ambiguous';
  end if;
end $$;

commit;
