-- The lock belongs on the operation, not on one of its callers.
--
-- == WHAT HAPPENED ========================================================
--
-- Pushing release-2026-10-29-2 marked all 6 facilities dirty, and the very
-- next read of the roast plan threw:
--
--     ERROR:  duplicate key value violates unique constraint "roast_plan_pkey"
--     DETAIL: Key (facility_id, recipe_id)=(5cc581b9..., rcp-mcr-mama-s-espresso)
--             already exists.
--     CONTEXT: roast_plan_recompute(text) line 17
--              roast_plan_fresh(text) line 13 at PERFORM
--
-- 🔴 THE FUNCTION WAS NOT RETURNING DUPLICATES, and that was measured before
-- anything was changed: 61 rows, 61 distinct (facility_id, recipe_id), one
-- facility, and the union is UNION ALL. Two guesses at the view body came
-- first and both were wrong. The measurement took one query.
--
-- `roast_plan_recompute` is
--
--     delete from roast_plan where facility_id = $1;
--     insert into roast_plan (...) select ... from roast_detail_by_blend($1);
--
-- with NO mutual exclusion of its own. Two of them for one facility
-- interleave -- A deletes, B deletes, B inserts, A inserts -- and A collides
-- with B's rows.
--
-- == THE LOCK EXISTED. IT WAS IN THE WRONG PLACE. =========================
--
--     caller                                  takes pg_advisory_xact_lock
--     roast_plan_fresh                         YES
--     roast_plan_drain   (one-minute cron)     NO
--     roast_plan_reconcile                     NO
--
-- So the guard protected page-read against page-read and nothing else. The
-- drain recomputes every dirty facility once a minute; the page recomputes on
-- any stale read; both write the same rows. The window is one recompute,
-- ~2s at MCR, so a page load landing inside the drain's pass gets a 500.
--
-- Pre-existing since the maintained table shipped on 2026-10-26. The release
-- did not cause it -- enqueueing 6 facilities at once only made the collision
-- certain instead of occasional.
--
-- == THE ORIGIN PLAN HAS THE SAME HOLE, WITH A QUIETER SYMPTOM ============
--
-- `roast_origin_plan_recompute` deletes and inserts too, takes no lock
-- either, and the drain calls it in the same loop. It cannot throw, because
-- its insert carries `on conflict (facility_id, origin) do update` -- so
-- instead of a 500 it silently lets two recomputes write halves of two
-- different snapshots. Checked, not assumed. Both get the lock; only one of
-- them was ever going to tell us.
--
-- == WHAT THIS DOES =======================================================
--
-- Moves the advisory lock INTO both recompute functions, immediately before
-- the delete, using the SAME key the matching `*_fresh` already uses -- so a
-- page read and the drain contend on one lock instead of each holding a
-- private one. Every caller is now serialised per facility for free, and the
-- outer lock in `roast_plan_fresh` becomes harmless belt-and-braces.
--
-- 🔴 WHY NOT `on conflict do update` ON roast_plan TOO. It would silence the
-- error without fixing it: two recomputes would still race, and the loser's
-- rows would survive in the winner's table. The error was the only thing
-- telling us they were racing at all.
--
-- 🔴 NO DEADLOCK. A page read takes exactly one lock, its own facility. The
-- drain takes them in `order by min(enqueued_at)`, so two drains take them in
-- the same order. Nothing acquires a second lock while holding a first except
-- the drain, which never goes backwards.
--
-- 🔴 BOTH BODIES ARE THEIR LIVE pg_get_functiondef TEXT with exactly one
-- insertion each, generated and asserted -- never retyped.
--
-- No roast_plan_dirty enqueue: this changes how the plan is WRITTEN, not what
-- it would compute, so nothing needs recomputing.

begin;

CREATE OR REPLACE FUNCTION public.roast_plan_recompute(p_facility_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rows   int;
  v_roast  date;
  v_orders date;
begin
  select w.roast_week_start, w.orders_week_start
    into v_roast, v_orders
    from public.facility_week_starts(p_facility_id) w;

  if v_roast is null then
    return 0;
  end if;

  -- 🔴 THE LOCK BELONGS HERE, NOT IN THE CALLER. This is the delete-then-
  -- insert, so this is where mutual exclusion has to be. Same key as
  -- roast_plan_fresh, so a page read and the drain serialise against each
  -- other instead of each holding a private lock. Taken AFTER the null
  -- guard: hashtext of null is null, and locking on null errors.
  perform pg_advisory_xact_lock(hashtext('roast_plan_fresh:' || p_facility_id));

  delete from public.roast_plan where facility_id = p_facility_id;

  insert into public.roast_plan (
    facility_id, recipe_id, roast_blend_id, company_id,
    in_stock_roasted, total_ordered, total_roasted, roasted_left,
    roasts_remaining, avg_weekly_lbs, backstock_buffer_pct, buffer_target,
    effective_target, buffer_left, weekly_target_override,
    roast_week_start, orders_week_start, computed_at
  )
  select
    r.facility_id, r.recipe_id, r.roast_blend_id, r.company_id,
    r.in_stock_roasted, r.total_ordered, r.total_roasted, r.roasted_left,
    r.roasts_remaining, r.avg_weekly_lbs, r.backstock_buffer_pct, r.buffer_target,
    r.effective_target, r.buffer_left, r.weekly_target_override,
    v_roast, v_orders, now()
  from public.roast_detail_by_blend(p_facility_id) r
  where r.company_id is not null;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION public.roast_origin_plan_recompute(p_facility_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rows int;
begin
  if p_facility_id is null then
    return 0;
  end if;

  -- 🔴 THE LOCK BELONGS HERE, NOT IN THE CALLER. This is the delete-then-
  -- insert, so this is where mutual exclusion has to be. Same key as
  -- roast_origin_plan_fresh, so a page read and the drain serialise against each
  -- other instead of each holding a private lock. Taken AFTER the null
  -- guard: hashtext of null is null, and locking on null errors.
  perform pg_advisory_xact_lock(hashtext('roast_origin_plan_fresh:' || p_facility_id));

  with live as (
    select d.facility_id, d.origin, d.roast_detail_id, d.company_id,
           d.in_stock_roasted, d.total_roasted, d.total_ordered,
           d.final_roasted_weight, d.green_to_roast, d.roasts_remaining
      from public.roast_detail d
     where d.facility_id = p_facility_id
  ),
  gone as (
    -- Reads `live`, NOT roast_detail again. An origin that stopped existing
    -- must leave, and only within this facility.
    delete from public.roast_origin_plan p
     where p.facility_id = p_facility_id
       and not exists (
         select 1 from live l where l.origin is not distinct from p.origin
       )
    returning 1
  ),
  upserted as (
    insert into public.roast_origin_plan as p
      (facility_id, origin, roast_detail_id, company_id, in_stock_roasted,
       total_roasted, total_ordered, final_roasted_weight, green_to_roast,
       roasts_remaining, computed_at)
    select l.facility_id, l.origin, l.roast_detail_id, l.company_id,
           l.in_stock_roasted, l.total_roasted, l.total_ordered,
           l.final_roasted_weight, l.green_to_roast, l.roasts_remaining, now()
      from live l
    on conflict (facility_id, origin) do update
      set roast_detail_id      = excluded.roast_detail_id,
          company_id           = excluded.company_id,
          in_stock_roasted     = excluded.in_stock_roasted,
          total_roasted        = excluded.total_roasted,
          total_ordered        = excluded.total_ordered,
          final_roasted_weight = excluded.final_roasted_weight,
          green_to_roast       = excluded.green_to_roast,
          roasts_remaining     = excluded.roasts_remaining,
          computed_at          = now()
    returning p.facility_id
  )
  select (select count(*) from upserted) into v_rows;

  return v_rows;
end;
$function$;

commit;
