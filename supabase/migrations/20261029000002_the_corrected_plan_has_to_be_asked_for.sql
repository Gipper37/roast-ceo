-- Make every facility's roast plan recompute, now that the arithmetic changed.
--
-- 🔴 WHY THIS IS A SECOND MIGRATION AND NOT AN EDIT. 20261029000001 is already
-- pushed and CI is applying it to staging. An applied migration is never
-- edited: `db push` would not re-apply the changed file, so staging would keep
-- running the old text and stop being a rehearsal of prod.
--
-- 🔴 WHY IT IS NEEDED AT ALL. `roast_plan` is a MAINTAINED TABLE, not a view.
-- `roast_plan_fresh()` recomputes only when `roast_plan_stale()` says so, and
-- that asks one question:
--
--     does a `roast_plan_dirty` row exist, enqueued AFTER the last computed_at?
--
-- Dirty rows are enqueued by triggers on the things that change a plan --
-- roasts, orders, counts, deliveries. **Replacing a FUNCTION enqueues
-- nothing.** So after 20261029000001 lands, every facility would keep being
-- served its previously computed rows, with the old stock arithmetic baked in,
-- until something unrelated happened to touch it.
--
-- That is the quiet failure mode: the fix ships, the owner opens the roast page
-- the next morning, Maui Blend still reads zero, and the reasonable conclusion
-- is that the fix did not work. It did; nobody asked for the answer again.
--
-- One row per facility. The queue is append-only and `roast_plan_stale`
-- compares the MAX enqueued_at against computed_at, so a spare row is harmless
-- and a missing one is not. The recompute itself is lazy -- it happens on the
-- next read of each facility's plan, not here -- so this migration stays cheap
-- and cannot stall the release on a view that takes 1.2-1.6s per facility.

insert into public.roast_plan_dirty (facility_id, reason)
select f.facility_id,
       'stock arithmetic corrected: bag counts are bags, deliveries debit (20261029000001)'
  from public.facilities f;

do $$
declare
  n_facilities integer;
  n_enqueued   integer;
begin
  select count(*) into n_facilities from public.facilities;
  select count(*) into n_enqueued
    from public.roast_plan_dirty
   where reason like 'stock arithmetic corrected%';

  -- 🔴 A notice, never an exception. A verify block that can only RAISE takes
  -- the whole release down with it, and this one is reporting a fact the
  -- release does not depend on: the recompute is lazy, so even a partial
  -- enqueue self-heals the moment anything else touches those facilities.
  raise notice 'roast_plan_dirty: enqueued % row(s) for % facilit(y/ies)',
    n_enqueued, n_facilities;
end $$;
