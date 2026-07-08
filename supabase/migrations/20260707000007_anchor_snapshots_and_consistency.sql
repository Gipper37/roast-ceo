-- Phase 4 of the lot-engine rearchitecture: bound replay depth + self-heal.
--
-- The count watermark already bounds replay depth — but only where operators
-- count. Never/stale-counted origins grow unbounded (deep replays forever).
-- Fix: a weekly job writes SYNTHETIC per-lot checkpoints for stale deep
-- origins, as ordinary coffee_lot_count rows (reason='system: replay
-- checkpoint') equal to the CURRENT derived per-lot state — pinning the full
-- FIFO frontier (including exhausted lots, each lot gets its own row). The
-- existing statement-level count trigger then runs one replay that converges
-- to the exact same state (a snapshot is a state no-op — validated), and every
-- future replay anchors there. Count history shows the rows with their reason
-- chip (CountHistoryModal renders `reason`), so operators see checkpoints for
-- what they are. BC's "automatic cost adjustment window" made tunable.
--
-- Also: nightly consistency check (defer-guard-drift insurance from the P2
-- risk list) — any origin whose cached totals disagree with the per-lot truth
-- gets enqueued for a self-healing replay.

-- ── 1. Snapshot stale deep anchors ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.snapshot_stale_origin_anchors(
    p_min_anchor_age interval DEFAULT interval '30 days',
    p_min_depth      int      DEFAULT 300,
    p_max_origins    int      DEFAULT 5,
    p_only_origin    text     DEFAULT NULL,   -- targeted manual checkpoint
    p_only_facility  text     DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_o record;
    n int := 0;
BEGIN
    FOR v_o IN
        WITH groups AS (
            SELECT ci.origin_id, ci.facility_id, ci.company_id
              FROM public.coffee_inventory ci
             WHERE (p_only_origin IS NULL OR ci.origin_id = p_only_origin)
               AND (p_only_facility IS NULL OR ci.facility_id = p_only_facility)
        ), anchored AS (
            SELECT g.*, (
                SELECT MAX(clc.count_at)
                  FROM public.coffee_lot_count clc
                  JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = clc.origin_purchase_id
                 WHERE cip.origin = g.origin_id AND cip.facility_id = g.facility_id
            ) AS anchor_at
              FROM groups g
        ), measured AS (
            SELECT a.*, (
                SELECT count(*)
                  FROM public.roast_log rl
                 WHERE rl.facility_id = a.facility_id
                   AND rl."charged?" = true
                   AND COALESCE(rl.charge_weight_lbs, 0) > 0
                   AND (a.anchor_at IS NULL
                        OR COALESCE(rl.roast_date_utc, rl.roast_date::timestamptz) > a.anchor_at)
            ) AS depth
              FROM anchored a
        )
        SELECT * FROM measured m
         WHERE (m.anchor_at IS NULL OR m.anchor_at < now() - p_min_anchor_age)
           AND m.depth > p_min_depth
           -- only groups that actually have seeded lots to pin
           AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased cip
                        WHERE cip.origin = m.origin_id AND cip.facility_id = m.facility_id
                          AND cip.remaining_lbs IS NOT NULL)
         ORDER BY m.depth DESC
         LIMIT p_max_origins
    LOOP
        -- One INSERT statement per origin: the statement-level count trigger
        -- fires ONE replay, which converges to the identical state and moves
        -- the anchor to now. Every received/baseline lot gets its own row
        -- (zeros included — that's the exhausted FIFO frontier).
        INSERT INTO public.coffee_lot_count
            (id, origin_purchase_id, count_date, counted_remaining_lbs, company_id, count_at, reason)
        SELECT gen_random_uuid()::text,
               cip.origin_purchase_id,
               CURRENT_DATE,
               cip.remaining_lbs,
               v_o.company_id,
               now(),
               'system: replay checkpoint'
          FROM public.coffee_inventory_purchased cip
         WHERE cip.origin = v_o.origin_id
           AND cip.facility_id = v_o.facility_id
           AND cip.remaining_lbs IS NOT NULL
           AND (cip.shipment_id IS NULL
                OR EXISTS (SELECT 1 FROM public.shipment_received sr
                            WHERE sr.shipment_id = cip.shipment_id
                              AND sr.date_received IS NOT NULL
                              AND COALESCE(sr.voided, false) = false));
        n := n + 1;
    END LOOP;
    RETURN n;
END;
$$;

-- ── 2. Nightly consistency check → self-healing enqueue ────────────────────
-- Catches defer-guard drift (a code path that silences the per-row triggers
-- but forgets to reconcile): if a group's cached totals disagree with per-lot
-- truth by > 0.1 lb, enqueue a replay to re-derive everything.
CREATE OR REPLACE FUNCTION public.enqueue_inconsistent_origins()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    v_o record;
    n int := 0;
BEGIN
    FOR v_o IN
        SELECT ci.origin_id, ci.facility_id, ci.company_id
          FROM public.coffee_inventory ci
         WHERE ci.company_id IS NOT NULL
           AND (
             abs(COALESCE(ci.total_stock_lbs, 0) - COALESCE((
                SELECT SUM(GREATEST(cip.remaining_lbs, 0))
                  FROM public.coffee_inventory_purchased cip
                  LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
                 WHERE cip.origin = ci.origin_id AND cip.facility_id = ci.facility_id
                   AND cip.remaining_lbs IS NOT NULL
                   AND (cip.shipment_id IS NULL
                        OR (sr.date_received IS NOT NULL AND COALESCE(sr.voided, false) = false))
             ), 0)) > 0.1
             OR abs(COALESCE(ci.total_stock_lbs, 0) - COALESCE(ci.in_stock_lbs, 0)) > 0.1
           )
    LOOP
        PERFORM public.enqueue_lot_recompute(
            v_o.company_id, v_o.origin_id, v_o.facility_id, 'nightly consistency self-heal');
        n := n + 1;
    END LOOP;
    RETURN n;
END;
$$;

-- ── 3. Schedules ────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname IN ('lot_anchor_snapshots','lot_consistency_check');
    -- Weekly, Sunday 10:00 UTC (~midnight HST / small hours US) — snapshots
    -- are rare by construction (stale + deep only, 5/run cap).
    PERFORM cron.schedule('lot_anchor_snapshots', '0 10 * * 0',
      $cron$SELECT public.snapshot_stale_origin_anchors()$cron$);
    -- Nightly 09:30 UTC drift check → self-healing enqueues.
    PERFORM cron.schedule('lot_consistency_check', '30 9 * * *',
      $cron$SELECT public.enqueue_inconsistent_origins()$cron$);
  ELSE
    RAISE NOTICE 'pg_cron not installed — skipping snapshot/consistency schedules';
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
