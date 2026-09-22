-- The one-time catch-up: name every lot the purchase record already accounts for.
--
-- 20260908000018 records the gaps and 20260908000019 knows how to close them,
-- but nothing runs the pass over the history that existed before either shipped.
-- Naming otherwise happens only on the NEXT replay of an origin — so without
-- this, a roastery's first look at the reconciliation queue is a large number
-- that would have cleared itself in one press, and the release depends on
-- somebody remembering a runbook step. A one-time historical catch-up is a
-- backfill; leaving it as a step somebody has to remember is how it does not
-- happen.
--
-- Measured on prod before this lands (Maui Coffee Roasters, last 90 days):
--   413 short component draws
--   273 of them (8,034 lb) are behind the count anchor -> named here
--   140 (2,263 lb) are after it -> a real receipt, not this
--
-- ── Why this is safe, in the terms the last bad backfill failed ───────────
-- 20260908000011 damaged live COGS because it SUBSTITUTED a value it invented —
-- a case price standing in for a unit cost. This one invents nothing:
--   · it writes only attribution the purchase record already supports, capped
--     at each lot's purchased amount minus everything already attributed to it;
--   · it touches NO remaining_lbs, no cost basis, no consumable, no product;
--   · every row is marked attribution_only, so "identified" is distinguishable
--     from "deducted" forever after;
--   · it is limited to roasts at or before the count anchor, where the running
--     arithmetic was genuinely lost — never where a live count says the lot was
--     empty (see 20260908000023);
--   · re-running it names nothing, because the rows it would add already exist.
--
-- The queue's "Name everything that can be named" button runs the same function
-- and stays: gaps keep accruing, and this only covers the ones alive today.

begin;

-- ── What this cost the first time, and why it now has a budget ───────────
--
-- The measurement in the header was taken against Maui alone: 413 short
-- draws. Production carries 16,597 across 60 company/facility/origin groups
-- and four roasteries, Social Hour US holding 7,411 by itself. The database
-- cancels a statement at 120 seconds and the whole DO block is one
-- statement, so the first attempt was killed part way and took 62 later
-- migrations down with it.
--
-- Raising the timeout was the wrong answer and it was tried: at 30 minutes
-- the pass ran for eleven of them inside one transaction, holding a lock on
-- every row it had touched, and a roastery archiving a product on the live
-- site got "canceling statement due to lock timeout" instead. A backfill
-- that nothing depends on must never be the reason somebody cannot work.
--
-- So it is bounded on both sides now:
--
--   lock_timeout gives up after a second rather than waiting on anybody. A
--   row a person is editing is skipped, which the per-origin handler below
--   already treats as normal.
--
--   a wall-clock budget stops the loop rather than the server stopping it.
--   Whatever is not reached stays in the reconciliation queue, which the
--   header already says is an acceptable resting place, and the queue's
--   "Name everything that can be named" button finishes it on demand.
--
-- The result always commits, so it can never strand the release again, and
-- it is idempotent: a later run names only what this one did not reach.
set local lock_timeout = '1s';
-- 3 minutes is the backstop, not the plan. The loop's own 60 second budget
-- is what decides when it stops; this only catches a single origin that
-- starts just under the wire and then runs long.
set local statement_timeout = '3min';

do $$
declare
  r record;
  v_res jsonb;
  v_roasts int := 0;
  v_lbs numeric := 0;
  v_skipped int := 0;
  -- clock_timestamp, not now(): now() is frozen at the start of the
  -- transaction and would never advance inside this loop.
  v_deadline timestamptz := clock_timestamp() + interval '60 seconds';
begin
  -- Per (company, facility, origin) so one tenant's bad row cannot strand the
  -- rest, and so the advisory lock inside is taken at the same grain the engine
  -- uses everywhere else.
  for r in
    select distinct s.company_id, s.facility_id, s.origin_id
      from public.roast_lot_shortfall s
     where s.waived_at is null
  loop
    -- Stop ourselves before the server does. Leaving the rest in the queue
    -- is a known, documented state; failing the release is not.
    if clock_timestamp() > v_deadline then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    begin
      v_res := public._attribute_unsourced_for_origin(r.company_id, r.facility_id, r.origin_id, null);
      v_roasts := v_roasts + coalesce((v_res->>'roasts_repaired')::int, 0);
      v_lbs    := v_lbs    + coalesce((v_res->>'lbs_named')::numeric, 0);
    exception when others then
      -- One origin failing must not take the release down. The gap simply stays
      -- in the queue, which is where it already was.
      raise warning 'naming skipped for %/%/%: %', r.company_id, r.facility_id, r.origin_id, sqlerrm;
    end;
  end loop;

  if v_skipped > 0 then
    raise notice 'Named the green for % roast(s), % lb. % origin group(s) were left for the queue: the budget ran out.', v_roasts, round(v_lbs, 1), v_skipped;
  else
    raise notice 'Named the green for % roast(s), % lb.', v_roasts, round(v_lbs, 1);
  end if;
end
$$;

commit;
