-- The refusal arrived after the write it was meant to prevent.
--
-- `20261118000006` made a bag count refuse when the sacks on hand are not all
-- one size. It refuses in `apply_group_count_to_lots`, which `recordCoffeeCount`
-- calls SECOND. The first thing that action does is INSERT the audit row --
-- a separate PostgREST request, so a separate COMMITTED transaction -- whose
-- AFTER trigger copies the count onto the group row. So the sequence was:
--
--   1. history INSERT commits  -> inventory_count_bags = 20, last_inventory set,
--                                 inventory_lbs = 20 x 152 = 3,040
--   2. RPC raises, rolls back  -> zero lot anchors, lots still hold 2,840
--
-- 🔴 MEASURED on a cluster carrying prod's schema plus all six of the batch,
-- on a group holding ten 152 lb and ten 132 lb sacks (2,840 lbs), counting 20:
-- the group row keeps "20 bags / 3,040 lbs / counted 2026-11-19" with NO lot
-- anchor, the operator sees an error, and `trg_guard_coffee_baseline` refuses
-- any direct repair. The 200 lbs of coffee that does not exist is exactly what
-- this batch was written to stop.
--
-- 000003's own comment says why the action pre-checks before writing: "the
-- history insert below lands first and propagates to the parent row: refusing
-- only in the database would leave the group count recorded with the lot layer
-- untouched." 000006 then widened the database's refusal (to the LOTS ON HAND)
-- and left that pre-check reading the group's `bag_size` column. The two
-- conditions stopped agreeing, and the gap is the bug.
--
-- 🔴 TWO DIFFERENT POPULATIONS, BOTH MEASURED ON PROD. Do not conflate them.
--   * NEWLY EXPOSED TO THE HALF-COMMIT: 3 origins, all `9ShiyDAXhV` --
--     Chocolate (152, 2 sizes, 7,299.2 lbs), Fruit (154, 2 sizes, 4,432.3),
--     Maui H3 (100, 2 sizes, 679.9). These are the ones where 000006 raises AND
--     the deployed pre-check passes, because the group column is set.
--   * REFUSED BY THE GUARD BELOW: 5 non-demo origins -- those three plus
--     `752af3ed-4` Costa Rica and Rwanda, which each hold one on-hand lot with
--     no recorded size. Those two are NOT newly broken: their group column is
--     blank, so today's pre-check already refuses them with "Set a bag size".
--   Four more at `demo-aloha-coffee-roasters` match the condition, but that
--   company is `is_demo` and its only team member belongs to no other company,
--   so `zzz_guard_demo_readonly` refuses the insert before any of this is
--   reached. Counting those four as exposure overstates it.
--
-- WHAT THIS DOES.
--
-- 1. ONE TRANSACTION FOR THE BAG PATH. `record_group_count_bags` does the
--    validation, the lot anchoring and the audit row in a single function, so a
--    refusal rolls back all of it. That is how `record_group_count_lbs` already
--    works; the bag path was the odd one out.
--
-- 2. A GUARD AT THE FIRST WRITE, for every other caller. `authenticated` holds
--    EXECUTE on these RPCs and table-level INSERT on the history table; a stale
--    tab or a cached RSC bundle still posts the old two-step. So the history
--    table itself now refuses a group count that cannot be reconciled:
--
--      mixed/unsized sacks on hand AND no counted_lbs AND no lot anchor at
--      that date  ->  refuse
--
--    The third term is what keeps the legitimate paths working. Both per-lot
--    writers call `record_per_lot_count` FIRST, which writes `coffee_lot_count`
--    rows at that same date, and only then insert the roll-up row -- so they
--    pass whether or not they carry a weight. The old group-bag two-step
--    inserts history BEFORE anything is anchored, so it is refused with nothing
--    committed. That closes the deploy window: the frontend now on prod cannot
--    half-commit even before it is promoted.
--
-- 🔴 THE THIRD TERM IS A WINDOW MEASURE AND IT HAS A KNOWN HOLE. If an operator
-- per-lot counts a mixed bin in the morning (which anchors `coffee_lot_count`
-- at today) and then types a group bag count into the inline box on the SAME
-- bin and the SAME day, the escape finds that anchor and lets the row through.
-- Reachable: Chocolate holds 240 lot-count rows, Fruit 91, Maui H3 35. The
-- escape exists only because the pre-promote bundle's roll-ups carry no
-- counted_lbs; once the frontend is promoted they do, and the term is dead
-- weight. A follow-up migration drops it, and is deliberately NOT in this
-- batch: CI applies every unapplied file on a release tag, so shipping it now
-- would remove the escape BEFORE the promote and break the per-lot roll-up on
-- the five bins during the very window the escape exists for. Write it after
-- the promote. Recorded in project_open_list.md.
--
-- 🔴 WHAT THIS DELIBERATELY DOES NOT DO, and why each is left alone.
--  * NO SHARED CORE. An earlier draft extracted one from `record_group_count_lbs`
--    so the two paths could not drift. It took the weight to anchor and the bag
--    figure to record as independent arguments, and SECURITY INVOKER wrappers
--    mean the caller needs EXECUTE on it -- so `authenticated` could call it
--    with p_total_lbs 0.01 and p_bag_count 9999 and bypass every size test the
--    wrappers do. The anchoring statement is instead duplicated, and the verify
--    block asserts the two copies are CHARACTER-FOR-CHARACTER identical, which
--    is the drift protection without the new primitive.
--  * `record_group_count_lbs` IS NOT TOUCHED. It is already on staging and it
--    is correct. Rewriting it to delegate bought nothing and risked everything
--    CREATE OR REPLACE risks.
--  * NO ZERO-LOT REFUSAL ON THE BAG PATH. The pounds path raises when the
--    anchoring INSERT matches no rows; `apply_group_count_to_lots` never did,
--    so a bag count on an origin with no anchorable purchase line records today
--    and anchors nothing. Exactly 1 non-demo active origin is in that state.
--    Adding the refusal here would stop it being counted at all, which is the
--    product decision this file declines to make on the way past. Recorded.
--  * NO SECOND RECOMPUTE. The pounds path ends with
--    `PERFORM _recompute_origin_lot_consumption_core`; the bag path never had
--    one, because `trg_coffee_lot_count_recompute` (AFTER INSERT FOR EACH
--    STATEMENT on coffee_lot_count) has already run the same replay inside this
--    transaction. Adding it would make every bag count take the replay's
--    advisory lock twice.
--  * NO CLOSED-BOOKS CHECK. `record_per_lot_count` has one; neither group path
--    ever has. Adding it here would be a new restriction riding along on a fix.
--  * NO PERMISSION CHECK IN THE DATABASE. `requirePermission('inventory.count')`
--    lives in the server action only, for this RPC exactly as for the one it
--    replaces. Recorded, not widened here.
--
-- PROVENANCE. The anchoring INSERT is spliced from the live
-- `record_group_count_lbs` body, not retyped.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 1. THE BAG ENTRY POINT, atomic ------------------------------------------
create or replace function public.record_group_count_bags(p_origin_id text, p_facility_id text, p_count_date date, p_bag_count numeric, p_company_id text default null, p_reason text default null)
 returns jsonb
 language plpgsql
as $function$
DECLARE
    v_company       text;
    v_found         boolean := false;
    v_name          text;
    v_tz            text;
    v_count_moment  timestamptz;
    v_sizes_on_hand integer;
    v_unsized       integer;
    v_size          numeric;
    v_group_size    numeric;
    v_total_lbs     numeric;
    v_counted_lbs   numeric;
    v_lots          integer;
BEGIN
    SELECT company_id, true, origin, NULLIF(bag_size, '')::numeric
      INTO v_company, v_found, v_name, v_group_size
      FROM public.coffee_inventory
     WHERE origin_id = p_origin_id AND facility_id = p_facility_id
     LIMIT 1;

    IF NOT COALESCE(v_found, false) THEN
        RAISE EXCEPTION 'No coffee group % at this facility, so there is nothing to apply a count to.', p_origin_id;
    END IF;
    IF p_bag_count IS NULL OR p_bag_count < 0 THEN
        RAISE EXCEPTION 'A bag count must be zero or more.';
    END IF;

    v_company := COALESCE(p_company_id, v_company);
    IF v_company IS NULL THEN
        RAISE EXCEPTION 'No company on coffee group "%", so a count cannot be attributed.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    -- 🔴 THE SAME CONDITION AS apply_group_count_to_lots, ON THE SAME SOURCE:
    -- the LOTS ON HAND, not the group's column. An origin is a bin, so it can
    -- hold sacks of several sizes, and then a number of bags is not a quantity.
    -- Asked here, inside the transaction that also writes the audit row, so a
    -- refusal leaves nothing behind.
    SELECT COUNT(DISTINCT NULLIF(cip.bag_size, '')),
           COUNT(*) FILTER (WHERE NULLIF(cip.bag_size, '') IS NULL)
      INTO v_sizes_on_hand, v_unsized
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND COALESCE(cip.remaining_lbs, 0) > 0
       AND (cip.shipment_id IS NULL
            OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false));

    IF COALESCE(v_sizes_on_hand, 0) > 1 OR COALESCE(v_unsized, 0) > 0 THEN
        RAISE EXCEPTION 'The sacks of "%" on hand are not all the same size, so a number of bags does not say how much coffee there is. Count it by weight instead, or count each lot on its own.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    -- One size on hand is the denominator, in preference to the group column:
    -- the column is the operative size for the NEXT order, the lots are what is
    -- on the floor. Falls back to the column when there is nothing on hand,
    -- which is how a count of zero stays possible.
    SELECT NULLIF(MIN(NULLIF(cip.bag_size, '')), '')::numeric
      INTO v_size
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND COALESCE(cip.remaining_lbs, 0) > 0
       AND (cip.shipment_id IS NULL
            OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false));
    v_size := COALESCE(v_size, v_group_size);

    IF v_size IS NULL OR v_size <= 0 THEN
        RAISE EXCEPTION 'Set a bag size on "%" before counting it in bags -- without one there is no weight to record, and a count would wipe the stock instead of correcting it. Set the bag size on the coffee group, or count it lot by lot.',
            COALESCE(NULLIF(v_name, ''), p_origin_id);
    END IF;

    v_total_lbs := GREATEST(p_bag_count * v_size, 0);

    -- 🔴 RECORD THE WEIGHT ONLY WHEN THE GROUP'S OWN SIZE WOULD NOT REPRODUCE
    -- IT. `handle_manual_inventory_update` derives inventory_lbs as
    -- COALESCE(counted_lbs, bags x COALESCE(group bag_size, 154)). When the
    -- size used here IS the group's, that fallback gives the same number, so
    -- storing a weight adds nothing and costs something: the inventory table
    -- prefers counted_lbs for its "Last count" line, so every ordinary bag
    -- count would start reading "3,040 lb" where it reads "20 bags" -- 33
    -- single-size prod origins, the overwhelming majority. When the sizes
    -- differ (a blank column, or a column that disagrees with the floor) the
    -- fallback would be wrong -- 154, the hard-coded default, on a blank one --
    -- so the weight must be stored.
    IF v_size IS DISTINCT FROM v_group_size THEN
        v_counted_lbs := v_total_lbs;
    ELSE
        v_counted_lbs := NULL;
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
           LEAST(s.amount, GREATEST(0, v_total_lbs - s.prior_sum))
           + CASE WHEN s.rn = 1 THEN GREATEST(0, v_total_lbs - s.total_amount) ELSE 0 END,
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
    -- recompute fires via the statement trigger on coffee_lot_count. No second
    -- pass here: the bag path never had one, and the replay takes an advisory
    -- lock that would then be taken twice for one count.
    GET DIAGNOSTICS v_lots = ROW_COUNT;

    INSERT INTO public.coffee_inventory_history
      (history_id, origin_id, facility_id, company_id, inventory_date, bag_count, counted_lbs, notes)
    VALUES
      (gen_random_uuid()::text, p_origin_id, p_facility_id, v_company, p_count_date,
       p_bag_count, v_counted_lbs, p_reason);

    RETURN jsonb_build_object(
      'counted_lbs', v_total_lbs,
      'weight_recorded', v_counted_lbs,
      'bags_recorded', p_bag_count,
      'bag_size_used', v_size,
      'lots_anchored', v_lots
    );
END;
$function$;

comment on function public.record_group_count_bags(text,text,date,numeric,text,text) is
  'Records a group stock count entered in BAGS: validates that the sacks on hand are all one known size, converts at that size, anchors the lots and writes the audit row -- all in one transaction, so a refusal leaves nothing behind. Supersedes the two-step (history insert, then apply_group_count_to_lots) which committed the audit row before the refusal could fire. Stores counted_lbs only when the group column would not reproduce the weight, so an ordinary bag count still reads as bags.';

-- 2. THE GUARD AT THE FIRST WRITE -----------------------------------------
create or replace function public.guard_group_count_needs_weight()
 returns trigger
 language plpgsql
as $function$
DECLARE
    v_sizes    integer;
    v_unsized  integer;
    v_anchored boolean;
    v_name     text;
BEGIN
    -- No JWT: service role, cron, migrations, the demo reseed. Already trusted,
    -- the same bypass guard_demo_readonly takes on this same table. (The demo
    -- date refresh also runs under session_replication_role = 'replica', which
    -- disables triggers outright -- a CHECK constraint here would have broken
    -- that nightly cron, which is part of why this is a trigger.)
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- A row that states its weight needs no denominator, so it is never at
    -- issue. This is the ordinary pounds count and, after the promote, the
    -- per-lot roll-ups too.
    IF NEW.counted_lbs IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(DISTINCT NULLIF(cip.bag_size, '')),
           COUNT(*) FILTER (WHERE NULLIF(cip.bag_size, '') IS NULL)
      INTO v_sizes, v_unsized
      FROM public.coffee_inventory_purchased cip
      LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
     WHERE cip.origin = NEW.origin_id AND cip.facility_id = NEW.facility_id
       AND COALESCE(cip.remaining_lbs, 0) > 0
       AND (cip.shipment_id IS NULL
            OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false));

    -- One known size on hand (or nothing on hand): a bag count converts, and
    -- that is the overwhelming majority of counts. Nothing changes for them.
    IF COALESCE(v_sizes, 0) <= 1 AND COALESCE(v_unsized, 0) = 0 THEN
        RETURN NEW;
    END IF;

    -- 🔴 MIXED, AND NO WEIGHT. Allowed only if the LOT LAYER WAS ALREADY
    -- ANCHORED at this date, because then the group figure is a roll-up of
    -- counts that really happened. Both per-lot writers call
    -- record_per_lot_count first and insert their roll-up at the same date, so
    -- they pass; the group-bag two-step inserts BEFORE it anchors, so it does
    -- not. 🔴 THIS TERM IS A WINDOW MEASURE WITH A KNOWN HOLE -- a per-lot
    -- count and a group bag count on the same bin on the same day slips
    -- through it. A follow-up migration drops it once the frontend is promoted
    -- and the roll-ups carry their own weight.
    SELECT EXISTS (
      SELECT 1
        FROM public.coffee_lot_count clc
        JOIN public.coffee_inventory_purchased cip
          ON cip.origin_purchase_id = clc.origin_purchase_id
       WHERE cip.origin = NEW.origin_id AND cip.facility_id = NEW.facility_id
         AND clc.count_date = NEW.inventory_date
    ) INTO v_anchored;

    IF COALESCE(v_anchored, false) THEN
        RETURN NEW;
    END IF;

    SELECT origin INTO v_name FROM public.coffee_inventory
     WHERE origin_id = NEW.origin_id AND facility_id = NEW.facility_id LIMIT 1;

    RAISE EXCEPTION 'The sacks of "%" on hand are not all the same size, so a number of bags does not say how much coffee there is. Count it by weight instead, or count each lot on its own.',
        COALESCE(NULLIF(v_name, ''), NEW.origin_id);
END;
$function$;

comment on function public.guard_group_count_needs_weight() is
  'Refuses a group stock count that cannot be reconciled: mixed or unsized sacks on hand, no counted weight, and no lot anchor at that date. Fires BEFORE INSERT so nothing commits -- the bug it closes is that apply_group_count_to_lots refused only AFTER the audit row had already landed in its own transaction and propagated to the group row.';

-- Sorts before trg_audit_insert so the refusal happens before the audit stamp.
-- BEFORE row triggers fire in alphabetical order by name.
drop trigger if exists trg_aaa_guard_group_count_weight on public.coffee_inventory_history;
create trigger trg_aaa_guard_group_count_weight
  before insert on public.coffee_inventory_history
  for each row execute function public.guard_group_count_needs_weight();

-- 3. GRANT -----------------------------------------------------------------
-- 🔴 A new function nobody can execute fails SILENTLY at the app, so this is
-- part of the change, not housekeeping.
grant execute on function public.record_group_count_bags(text,text,date,numeric,text,text) to authenticated;

do $$
declare
  v_bags text; v_lbs text; v_guard text; v_trg text; v_n integer;
  v_frag_bags text; v_frag_lbs text;
begin
  -- ---- 1. exactly one definition, so no ambiguous overload reaches PostgREST.
  -- 🔴 Two same-arity overloads make Supabase's by-name RPC call ambiguous and
  -- break the deployed frontend the moment the migration lands.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='record_group_count_bags';
  if v_n <> 1 then
    raise exception 'public.record_group_count_bags has % definitions; an overload makes the RPC call ambiguous', v_n;
  end if;

  select regexp_replace(p.prosrc,'--[^'||chr(10)||']*','','g') into v_bags
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='record_group_count_bags';
  select regexp_replace(p.prosrc,'--[^'||chr(10)||']*','','g') into v_lbs
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='record_group_count_lbs';
  select regexp_replace(p.prosrc,'--[^'||chr(10)||']*','','g') into v_guard
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='guard_group_count_needs_weight';
  if v_bags is null then raise exception 'record_group_count_bags is missing'; end if;
  if v_lbs  is null then raise exception 'record_group_count_lbs is missing'; end if;

  -- ---- 2. the pounds path is UNTOUCHED: still its own body, not delegating.
  -- If a draft that extracted a shared core was ever applied here, this catches
  -- it -- that core took the anchored weight and the recorded bag figure as
  -- independent arguments and authenticated could execute it.
  if v_lbs ~ '_record_group_count_core' then
    raise exception 'record_group_count_lbs delegates to a shared core; that core lets a caller anchor one weight and record a different bag count, bypassing every size test';
  end if;
  if v_lbs !~ 'INSERT INTO public.coffee_lot_count' then
    raise exception 'record_group_count_lbs no longer owns its anchoring statement';
  end if;

  -- ---- 3. 🔴 THE DRIFT ASSERTION, which is why there is no shared core.
  -- The two paths anchor with the same windowed distribution. Compared
  -- CHARACTER-FOR-CHARACTER after normalising only the weight variable's name,
  -- so an edit to one that is not made to the other fails the release.
  v_frag_bags := substring(v_bags from 'INSERT INTO public\.coffee_lot_count[\s\S]*?\) s;');
  v_frag_lbs  := substring(v_lbs  from 'INSERT INTO public\.coffee_lot_count[\s\S]*?\) s;');
  if v_frag_bags is null or v_frag_lbs is null then
    raise exception 'could not find the anchoring statement in both paths (bags: %, lbs: %)',
      v_frag_bags is not null, v_frag_lbs is not null;
  end if;
  if replace(v_frag_bags, 'v_total_lbs', '@W@') <> replace(v_frag_lbs, 'p_total_lbs', '@W@') then
    raise exception 'the two anchoring statements have drifted apart. bags:%  lbs:%', v_frag_bags, v_frag_lbs;
  end if;

  -- ---- 4. the bag path refuses a mixed bin, on the LOTS, before converting.
  if v_bags !~ 'v_sizes_on_hand' or v_bags !~ 'COALESCE\(cip.remaining_lbs, 0\) > 0' then
    raise exception 'record_group_count_bags does not test the sizes of the lots ON HAND';
  end if;
  if v_bags !~ 'p_bag_count \* v_size' then
    raise exception 'record_group_count_bags no longer converts the bag count at the on-hand size';
  end if;
  -- it records the figure the operator typed, not a derived one.
  if v_bags !~ 'p_count_date,[\s]*$|p_bag_count, v_counted_lbs' then
    raise exception 'record_group_count_bags no longer records the typed bag figure';
  end if;
  -- the weight is stored only when the group column would not reproduce it.
  if v_bags !~ 'v_size IS DISTINCT FROM v_group_size' then
    raise exception 'record_group_count_bags stores a weight unconditionally; every ordinary bag count would start reading as pounds on the inventory table';
  end if;

  -- ---- 5. and the two things it must NOT have picked up from the pounds path.
  if v_bags ~ 'IF v_lots = 0 THEN' then
    raise exception 'the bag path gained a zero-lot refusal; apply_group_count_to_lots never had one and 1 live origin would stop being countable';
  end if;
  if v_bags ~ '_recompute_origin_lot_consumption' then
    raise exception 'the bag path gained a second recompute; the statement trigger on coffee_lot_count has already run it in this transaction';
  end if;

  -- ---- 6. the guard, and the four terms that keep it narrow.
  if v_guard is null then raise exception 'guard_group_count_needs_weight is missing'; end if;
  if v_guard !~ 'auth.uid\(\) IS NULL' then
    raise exception 'the guard lost its service-role bypass, so seeds and the demo reseed would be refused';
  end if;
  if v_guard !~ 'NEW.counted_lbs IS NOT NULL' then
    raise exception 'the guard no longer lets a row that states its weight through';
  end if;
  if v_guard !~ 'clc.count_date = NEW.inventory_date' then
    raise exception 'the guard no longer exempts an already-anchored date, so the per-lot roll-up would be refused mid-flight';
  end if;
  if v_guard !~ 'COALESCE\(v_sizes, 0\) <= 1 AND COALESCE\(v_unsized, 0\) = 0' then
    raise exception 'the guard no longer passes single-size bins, so ordinary bag counts would be refused';
  end if;

  select pg_get_triggerdef(t.oid) into v_trg
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname='public' and c.relname='coffee_inventory_history'
     and t.tgname='trg_aaa_guard_group_count_weight' and not t.tgisinternal;
  if v_trg is null then
    raise exception 'trg_aaa_guard_group_count_weight is missing from coffee_inventory_history';
  end if;
  if v_trg !~* 'BEFORE INSERT' then
    raise exception 'the guard is not BEFORE INSERT, so the row would commit before it fired: %', v_trg;
  end if;
  if 'trg_aaa_guard_group_count_weight' >= 'trg_audit_insert' then
    raise exception 'the guard no longer sorts before trg_audit_insert';
  end if;

  -- ---- 7. controls that must PASS: the app can still call both entry points,
  -- and the old RPC stays as the backstop for a direct caller.
  if not has_function_privilege('authenticated',
        'public.record_group_count_bags(text,text,date,numeric,text,text)', 'EXECUTE') then
    raise exception 'authenticated cannot EXECUTE record_group_count_bags, so the count box would fail silently';
  end if;
  if not has_function_privilege('authenticated',
        'public.record_group_count_lbs(text,text,date,numeric,text,text)', 'EXECUTE') then
    raise exception 'authenticated lost EXECUTE on record_group_count_lbs';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='apply_group_count_to_lots') then
    raise exception 'apply_group_count_to_lots is gone; its refusal is still the backstop for direct callers';
  end if;
end $$;

commit;
