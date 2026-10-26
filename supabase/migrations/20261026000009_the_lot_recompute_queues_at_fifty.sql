-- The lot recompute goes to the queue at 50 roasts, not 400.
--
-- Owner, 2026-10-26 02:00, after a 55P03 lock timeout turned up in the dev
-- portal: *"no we're fixing this now... yes go with 2 but change threshold to
-- 50."*
--
-- ── WHAT WAS HAPPENING ───────────────────────────────────────────────────
--
-- Charging a roast fires trg_lot_consumption_recompute -> roast_log_lot_recompute
-- -> recompute_or_enqueue, which chooses:
--
--     IF v_depth > 400 THEN  enqueue_lot_recompute(...)              -- async
--     ELSE                   recompute_origin_lot_consumption(...)   -- INLINE
--
-- `v_depth` is charged roasts at that facility since the last GREEN lot count
-- (`coffee_lot_count`). The inline branch replays all of them, inside the
-- write transaction, holding `pg_advisory_xact_lock(hashtext(origin),
-- hashtext(facility))` plus row locks on coffee_inventory_purchased and
-- roast_log_lot_consumption for its whole duration.
--
-- 🔴 AT 400, THE ENQUEUE BRANCH HAD NEVER RUN. Measured on prod 2026-10-26,
-- every facility was inline:
--
--     MCR      last green lot count 2026-09-27   depth 220   INLINE
--     (other)  2026-10-05                        depth  78   INLINE
--     (other)  2026-10-18                        depth  60   INLINE
--     demo     2026-10-25                        depth   0   INLINE
--
-- And the inline cost SCALES WITH DEPTH, so it degrades as a roastery roasts:
-- MCR went 48 -> 98 -> 160 -> 218 -> 220 over the four weeks since its last
-- green lot count, and its charge UPDATE now measures 7-15s (worst 46s).
--
-- 🔴 The threshold was backwards: it ran inline exactly while the replay was
-- expensive enough to hurt, and only went async once it was enormous. A
-- roastery's writes got slower every week until an arbitrary cliff fixed them.
--
-- ── WHY 50 ───────────────────────────────────────────────────────────────
--
-- His number. It keeps the inline path for the case it was written for -- a
-- fresh count where the replay is a handful of roasts and a round trip through
-- the queue would be pure latency -- and routes everything else to the drain.
--
-- 🔴 THE QUEUE IS LIVE AND DRAINS: cron job `lot_recompute_drain` runs
-- `CALL public.drain_lot_recompute_queue()` EVERY MINUTE. Verified on prod
-- before writing this. So the async branch is not theoretical, it is simply
-- the branch nobody ever reached.
--
-- 🔴 BODY TAKEN VERBATIM from `pg_get_functiondef` on prod and changed at ONE
-- token, because CREATE OR REPLACE rewrites the whole function and retyping it
-- is how you lose a clause nobody remembers
-- ([[gotcha_never_retype_a_function_body]]).

begin;

CREATE OR REPLACE FUNCTION public.recompute_or_enqueue(p_origin text, p_facility text, p_company text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_wm timestamptz;
    v_depth int;
BEGIN
    IF p_origin IS NULL OR p_facility IS NULL THEN RETURN; END IF;
    SELECT MAX(clc.count_at) INTO v_wm
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = clc.origin_purchase_id
     WHERE cip.origin = p_origin AND cip.facility_id = p_facility;
    -- Facility-wide post-watermark charged-roast count: a cheap, conservative
    -- OVER-estimate of replay depth (the replay filters to this origin).
    SELECT count(*) INTO v_depth
      FROM public.roast_log rl
     WHERE rl.facility_id = p_facility
       AND rl."charged?" = true
       AND COALESCE(rl.charge_weight_lbs, 0) > 0
       AND (v_wm IS NULL OR COALESCE(rl.roast_date_utc, rl.roast_date::timestamptz) > v_wm);
    IF v_depth > 50 AND p_company IS NOT NULL THEN
        PERFORM public.enqueue_lot_recompute(p_company, p_origin, p_facility, p_reason);
    ELSE
        PERFORM public.recompute_origin_lot_consumption(p_origin, p_facility);
    END IF;
END;
$function$;


-- Prove it, rather than assume it.
do $$
declare n_new int; n_old int;
begin
  select count(*) into n_new from pg_proc
   where proname='recompute_or_enqueue' and pg_get_functiondef(oid) like '%v_depth > 50%';
  select count(*) into n_old from pg_proc
   where proname='recompute_or_enqueue' and pg_get_functiondef(oid) like '%v_depth > 400%';
  if n_new <> 1 or n_old <> 0 then
    raise exception 'threshold did not take (new %, old %)', n_new, n_old;
  end if;
  -- And the branch it now routes to must exist, or every charge silently
  -- stops recomputing instead of merely deferring it.
  if not exists (select 1 from pg_proc where proname='enqueue_lot_recompute') then
    raise exception 'enqueue_lot_recompute is missing; routing to it would drop the work';
  end if;
  if not exists (select 1 from pg_proc where proname='drain_lot_recompute_queue') then
    raise exception 'drain_lot_recompute_queue is missing; the queue would never empty';
  end if;
end $$;

commit;
