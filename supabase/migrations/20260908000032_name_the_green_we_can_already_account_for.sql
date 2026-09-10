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

do $$
declare
  r record;
  v_res jsonb;
  v_roasts int := 0;
  v_lbs numeric := 0;
begin
  -- Per (company, facility, origin) so one tenant's bad row cannot strand the
  -- rest, and so the advisory lock inside is taken at the same grain the engine
  -- uses everywhere else.
  for r in
    select distinct s.company_id, s.facility_id, s.origin_id
      from public.roast_lot_shortfall s
     where s.waived_at is null
  loop
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

  raise notice 'Named the green for % roast(s), % lb.', v_roasts, round(v_lbs, 1);
end
$$;

commit;
