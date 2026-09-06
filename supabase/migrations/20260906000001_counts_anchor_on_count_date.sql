-- Backdated counts deduct from the COUNTED day, not the entry moment
-- (owner-approved 2026-09-05; source-audit pass 3).
--
-- A source count entered at 2pm today for YESTERDAY carried the operator's
-- date in count_date but anchored the replay at count_at — the write instant
-- (recordPerLotCount never set count_at, so the 20260611000004 DEFAULT now()
-- applied). Every roast between end-of-yesterday and the 2pm entry was
-- silently skipped: live-deducted at charge, then preserved as pre-anchor
-- history by the replay without ever coming off the counted value.
--
-- Part 1 — the replay derives an EFFECTIVE ANCHOR per count row, read-side,
-- zero data writes:   LEAST(count_at, end of count_date facility-local)
--   * dated today/future → count_at. The 20260611000004 guarantee is kept
--     byte-identically: count at 2pm, keep roasting at 3pm, only 3pm+ deducts.
--   * backdated          → end of the counted day. Roasts after that boundary
--     (the morning of the entry day included) replay against the count;
--     roasts ON the counted day are presumed inside what was counted.
--   * count_date NULL    → count_at (LEAST ignores NULLs).
-- This is the semantic apply_group_count_to_lots has stamped on the write
-- side since 20260611000006 — both count paths now mean one thing. count_at
-- keeps its honest audit meaning (when the row was written); count_date is
-- the operator's claim; the reader derives the anchor. History and future are
-- fixed by one expression. Three localized diffs in the 20260709000010 body
-- (prod-verified identical before this change), each marked COUNT-DATE ANCHOR.
--
-- Part 2 — record_per_lot_count(): the per-lot count writer moves server-side.
-- A count must be ORIGIN-COMPLETE (the replay treats an uncounted lot as 0),
-- and the frontend completed it with each sibling's CURRENT remaining. Under
-- a backdated anchor that is wrong: current remaining already has the roasts
-- since the counted day taken off, and the replay would take them off again
-- — a double deduction on every sibling. The RPC completes siblings AS OF the
-- anchor by adding back the ledger's post-anchor consumption (exact: the
-- ledger is complete going forward per 20260707000006, prod-verified). For a
-- same-day count the add-back is zero, so behavior is identical to today.
-- One INSERT → the statement trigger replays each origin once. A count dated
-- inside closed books is refused.
--
-- Measured on prod 2026-09-05: 50 backdated rows exist (all MCR, all
-- 2026-06-24); none changes which count wins its lot and none has roasts in
-- its gap, so no existing count replays differently — forward-only on
-- current data. Rehearsed on prod in a rolled-back transaction with per-origin
-- ledger + stock hashes before/after: identical (see pass-3 record).

begin;

CREATE OR REPLACE FUNCTION public.recompute_origin_lot_consumption(p_origin_id text, p_facility_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_roast record;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_last_count_at timestamptz;
    v_tz text;
    v_pre_ids text[];
    v_post_ids text[];
    v_all_ids text[];
    v_bc record;              -- borrowed-INTO-p_origin_id component (source-true)
    v_native_source text;     -- planned source of the native component of p_origin_id
    v_native_xgroup boolean;  -- is that native component's planned source cross-group?
BEGIN
    IF p_origin_id IS NULL OR p_facility_id IS NULL THEN RETURN; END IF;

    -- Serialize allocation writers per (origin, facility) — see 20260707000003.
    PERFORM pg_advisory_xact_lock(hashtext(p_origin_id), hashtext(p_facility_id));

    SELECT COALESCE(NULLIF(time_zone, ''), 'UTC') INTO v_tz
      FROM public.facilities WHERE facility_id = p_facility_id;
    v_tz := COALESCE(v_tz, 'UTC');

    -- ── COUNT-DATE ANCHOR (D1) ── the group anchor is the latest EFFECTIVE
    -- anchor: a count claims its own day. Entered same-day that is count_at
    -- (2pm/3pm ordering preserved); backdated it is the end of the counted
    -- day, facility-local — the rule apply_group_count_to_lots has stamped on
    -- the write side since 20260611000006. LEAST ignores a NULL count_date.
    SELECT MAX(LEAST(clc.count_at, ((clc.count_date + 1)::timestamp AT TIME ZONE v_tz))) INTO v_last_count_at
      FROM public.coffee_lot_count clc
      JOIN public.coffee_inventory_purchased cip2 ON cip2.origin_purchase_id = clc.origin_purchase_id
     WHERE cip2.origin = p_origin_id AND cip2.facility_id = p_facility_id;

    -- Roasts currently consuming this origin's lots — they lose rows in the
    -- wipe, so their cost rollups must be refreshed in the final reconcile.
    SELECT COALESCE(array_agg(DISTINCT rlc.roast_log_id), ARRAY[]::text[]) INTO v_pre_ids
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    -- Silence the per-row valuation + origin-total triggers for the duration of
    -- the rewrite; this function reconciles both once at the end. ALSO set the
    -- shipment-side defer flag: three cip triggers with no column list
    -- (trg_push_last_coffee_cost → recalculate_inventory_cost,
    -- trg_update_green_metrics_from_purchased → green metrics,
    -- update_shipment_on_coffee → shipment totals) fire on EVERY remaining_lbs
    -- touch during the replay; they already honor app.defer_shipment_recompute
    -- (20260703000003). Cost + green metrics are reconciled once below; shipment
    -- totals need no reconcile (they sum cip.amount, which the replay never
    -- changes — the per-row firings were pure no-op recomputes).
    PERFORM set_config('app.defer_lot_valuation', 'true', true);
    PERFORM set_config('app.defer_shipment_recompute', 'true', true);

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.shipment_received sr
          WHERE sr.shipment_id = cip.shipment_id
            AND sr.date_received IS NOT NULL
            AND COALESCE(sr.voided, false) = false);

    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = CASE
            WHEN v_last_count_at IS NULL THEN cip.amount
            ELSE COALESCE(
              -- this lot's OWN latest count, but ONLY if taken on/after the lot's
              -- receipt (a pre-receipt count can't be the lot's truth).
              (SELECT clc.counted_remaining_lbs
                 FROM public.coffee_lot_count clc
                WHERE clc.origin_purchase_id = cip.origin_purchase_id
                  -- ── COUNT-DATE ANCHOR (D2) ── judged and ordered by the
                  -- EFFECTIVE anchor (the count's claimed moment): a count
                  -- backdated to before the receipt is excluded, and
                  -- latest-count-wins means latest-DATED.
                  AND LEAST(clc.count_at, ((clc.count_date + 1)::timestamp AT TIME ZONE v_tz)) >= COALESCE(
                        (SELECT sr.date_received::timestamptz
                           FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                        cip.created_at)
                ORDER BY LEAST(clc.count_at, ((clc.count_date + 1)::timestamp AT TIME ZONE v_tz)) DESC, clc.created_at DESC LIMIT 1),
              -- fallback: received ON/AFTER the group's last count → fresh stock
              -- (full amount); strictly earlier uncounted lots stay 0 (assumed
              -- captured by that comprehensive count).
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     cip.created_at::date) >= v_last_count_at::date
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       AND (cip.shipment_id IS NULL
          OR EXISTS (SELECT 1 FROM public.shipment_received sr
                      WHERE sr.shipment_id = cip.shipment_id
                        AND sr.date_received IS NOT NULL
                        AND COALESCE(sr.voided, false) = false));

    -- Wipe ONLY what the replay re-derives: consumption of roasts AFTER the
    -- anchor. Pre-anchor rows are preserved as history — deleting them (the
    -- old behavior) permanently erased pre-count lot attribution AND degraded
    -- those roasts' stamped costs on EVERY count (measured: a June-30 blend
    -- dropped green_cost $178.20 -> $92.88 when a count landed on one of its
    -- components). remaining_lbs is re-seeded from counts above (physical
    -- truth), so preserved history never affects the arithmetic — the replay
    -- only allocates post-anchor roasts from the re-seeded values.
    DELETE FROM public.roast_log_lot_consumption rlc
     USING public.coffee_inventory_purchased cip, public.roast_log rl
     WHERE rlc.origin_purchase_id = cip.origin_purchase_id
       AND cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND rl.roast_log_id = rlc.roast_log_id
       AND (v_last_count_at IS NULL
            OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at);

    <<roast_loop>>
    FOR v_roast IN
        SELECT rl.roast_log_id, rl.charge_weight_lbs, rl.coffee_source_id,
               rl.recipe_id, rl.origin_id, rl.roast_date, rl.created_at,
               rl.borrow_origin_purchase_id, rl.planned_lots, rr.roast_type,
               COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) AS roast_utc
          FROM public.roast_log rl
          LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl.recipe_id
         WHERE rl.facility_id = p_facility_id
           AND rl."charged?" = true
           AND COALESCE(rl.charge_weight_lbs, 0) > 0
           AND (rl.external_roast_id IS NOT NULL
                OR rl.roast_date >= (rl.created_at::date - interval '1 day'))
           AND (v_last_count_at IS NULL
                OR COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) > v_last_count_at)
           AND (
              (rl.borrow_origin_purchase_id IS NULL AND (
                  (rr.roast_type = 'Pre-Blend'
                     AND (
                       -- native: a component of THIS origin (unchanged membership)
                       EXISTS (SELECT 1 FROM public.recipe_components rc
                                WHERE rc.recipe_id = rl.recipe_id
                                  AND rc.coffee_item = p_origin_id
                                  AND COALESCE(rc.percentage, 0) > 0)
                       -- source-true: a component BORROWED into this origin (its
                       -- planned source is homed in p_origin_id but the component
                       -- itself is a different group)
                       OR EXISTS (
                            SELECT 1
                              FROM jsonb_each_text(rl.planned_lots) pl
                              JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                              JOIN public.recipe_components rc2 ON rc2.recipe_id = rl.recipe_id
                                                              AND rc2.coffee_item = pl.key
                             WHERE jsonb_typeof(rl.planned_lots) = 'object'
                               AND cs.origin_id = p_origin_id
                               AND cs.origin_id IS DISTINCT FROM pl.key
                               AND COALESCE(rc2.percentage, 0) > 0)
                     ))
                  OR ((rr.roast_type IS NULL OR rr.roast_type <> 'Pre-Blend')
                        AND rl.origin_id = p_origin_id)))
              OR
              (rl.borrow_origin_purchase_id IS NOT NULL
                 AND EXISTS (SELECT 1 FROM public.coffee_inventory_purchased b
                              WHERE b.origin_purchase_id = rl.borrow_origin_purchase_id
                                AND b.origin = p_origin_id))
           )
         ORDER BY COALESCE(rl.roast_date_utc, (rl.roast_date AT TIME ZONE v_tz)) ASC, rl.created_at ASC
    LOOP
        v_force := NULL;
        IF v_roast.borrow_origin_purchase_id IS NOT NULL THEN
            v_needed := v_roast.charge_weight_lbs;
            v_force  := v_roast.borrow_origin_purchase_id;
            v_pref   := NULL;
            PERFORM public._deduct_origin_fifo(
                v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force, NULL);
        ELSIF v_roast.roast_type = 'Pre-Blend' THEN
            -- (a) NATIVE component of p_origin_id. This is the byte-identical
            -- same-group path — UNLESS this component's own planned source is
            -- cross-group, in which case it is owned by the lender group's replay
            -- and must be skipped here (else it would double-count).
            SELECT v_roast.charge_weight_lbs * COALESCE(rc.percentage, 0)
              INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = v_roast.recipe_id AND rc.coffee_item = p_origin_id
             ORDER BY rc.percentage DESC LIMIT 1;

            v_native_source := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            v_native_xgroup := false;
            IF v_native_source IS NOT NULL THEN
                SELECT (cs.origin_id IS DISTINCT FROM p_origin_id)
                  INTO v_native_xgroup
                  FROM public.coffee_source cs WHERE cs.coffee_source_id = v_native_source;
                v_native_xgroup := COALESCE(v_native_xgroup, false);
            END IF;

            IF COALESCE(v_needed, 0) > 0 AND NOT v_native_xgroup THEN
                -- Per-component planned source (Edit Roast / Add Roast picker) wins:
                -- it's how a blend's individual components get re-attributed.
                -- (Restores 20260625000002, silently dropped by the 20260703000005 rewrite.)
                v_pref := v_native_source;
                IF v_pref IS NULL AND v_roast.coffee_source_id IS NOT NULL THEN
                    SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                      INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
                END IF;
                PERFORM public._deduct_origin_fifo(
                    v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, NULL, NULL);
            END IF;

            -- (b) SOURCE-TRUE: every component BORROWED into p_origin_id. Each
            -- draws its own component percentage, forcing its planned source
            -- (whose lots live here in p_origin_id). One roast can borrow more
            -- than one component into the same lender group.
            -- One row per planned-lots component (jsonb_each_text is already
            -- one-per-key); percentage is a scalar subquery taking the MAX row,
            -- exactly like deduct_one_roast (ORDER BY percentage DESC LIMIT 1). A
            -- plain JOIN to recipe_components would multiply the draw if a recipe
            -- ever carried duplicate (recipe_id, coffee_item) rows.
            FOR v_bc IN
                SELECT pl.key AS component_origin, pl.value AS source_id,
                       v_roast.charge_weight_lbs * (
                         SELECT COALESCE(rc2.percentage, 0)
                           FROM public.recipe_components rc2
                          WHERE rc2.recipe_id = v_roast.recipe_id
                            AND rc2.coffee_item = pl.key
                          ORDER BY rc2.percentage DESC LIMIT 1) AS needed
                  FROM jsonb_each_text(v_roast.planned_lots) pl
                  JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
                 WHERE jsonb_typeof(v_roast.planned_lots) = 'object'
                   AND cs.origin_id = p_origin_id
                   AND cs.origin_id IS DISTINCT FROM pl.key
                   AND EXISTS (SELECT 1 FROM public.recipe_components rc3
                                WHERE rc3.recipe_id = v_roast.recipe_id
                                  AND rc3.coffee_item = pl.key
                                  AND COALESCE(rc3.percentage, 0) > 0)
            LOOP
                IF COALESCE(v_bc.needed, 0) <= 0 THEN CONTINUE; END IF;
                PERFORM public._deduct_origin_fifo(
                    v_roast.roast_log_id, v_bc.component_origin, p_facility_id,
                    v_bc.needed, NULL, v_roast.roast_date, NULL, v_bc.source_id);
            END LOOP;

            -- (a) and (b) already issued every _deduct_origin_fifo for this roast;
            -- skip the common tail call below (advance the OUTER roast loop).
            CONTINUE roast_loop;
        ELSE
            v_needed := v_roast.charge_weight_lbs;
            v_pref := NULL;
            IF v_roast.coffee_source_id IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id = p_origin_id THEN v_roast.coffee_source_id ELSE NULL END
                  INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = v_roast.coffee_source_id;
            END IF;
            -- Single-origin fallback: honor planned_lots[origin] only when there
            -- is no coffee_source_id pick (coffee_source_id stays authoritative).
            IF v_pref IS NULL THEN
                v_pref := NULLIF(v_roast.planned_lots ->> p_origin_id, '');
            END IF;
            PERFORM public._deduct_origin_fifo(
                v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force, NULL);
        END IF;
    END LOOP;

    -- ── Reconcile once (owner-must-reconcile) ──
    -- Valuation runs with the defer flags STILL SET so its roast_log cost
    -- updates don't fire the per-roast par/stock trigger (no-ops here anyway).
    SELECT COALESCE(array_agg(DISTINCT rlc.roast_log_id), ARRAY[]::text[]) INTO v_post_ids
      FROM public.roast_log_lot_consumption rlc
      JOIN public.coffee_inventory_purchased cip ON cip.origin_purchase_id = rlc.origin_purchase_id
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id;

    SELECT COALESCE(array_agg(DISTINCT x), ARRAY[]::text[]) INTO v_all_ids
      FROM unnest(v_pre_ids || v_post_ids) AS x;

    PERFORM public.value_roasts_lot_consumption(v_all_ids);

    PERFORM set_config('app.defer_lot_valuation', 'false', true);
    PERFORM set_config('app.defer_shipment_recompute', 'false', true);

    -- Once-per-origin versions of everything the deferred triggers would have
    -- recomputed row-by-row (each a pure recompute of final committed state):
    -- lot totals, par/stock caches, latest cost, green purchasing metrics.
    PERFORM public.recalculate_origin_total_stock(p_origin_id, p_facility_id);
    PERFORM public.refresh_coffee_stock_par(p_origin_id, p_facility_id);
    PERFORM public.recalculate_inventory_cost(p_origin_id, p_facility_id);
    PERFORM public.recalculate_green_purchasing_metrics(p_facility_id);
END;
$function$;

-- ── Part 2: server-side per-lot count writer ──────────────────────────────
drop function if exists public.record_per_lot_count(text, text, date, jsonb, text);

create function public.record_per_lot_count(
  p_facility_id text,
  p_company_id  text,
  p_count_date  date,
  p_updates     jsonb,           -- [{"origin_purchase_id": ..., "counted_remaining_lbs": ...}]
  p_reason      text default null
) returns integer
language plpgsql
as $function$
declare
  v_tz      text;
  v_anchor  timestamptz;
  v_closed  date;
  v_changed integer;
  v_rows    integer;
begin
  if p_facility_id is null or p_company_id is null or p_count_date is null then
    raise exception 'facility, company and count date are required';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'array' or jsonb_array_length(p_updates) = 0 then
    return 0;
  end if;

  select coalesce(nullif(time_zone, ''), 'UTC') into v_tz
    from public.facilities where facility_id = p_facility_id;
  v_tz := coalesce(v_tz, 'UTC');

  -- The same effective anchor the replay derives (Part 1).
  v_anchor := least(now(), ((p_count_date + 1)::timestamp at time zone v_tz));

  select books_closed_through into v_closed from public.companies where company_id = p_company_id;
  if v_closed is not null and p_count_date <= v_closed then
    raise exception 'A count dated % falls inside the closed books (through %). Pick a later date.', p_count_date, v_closed;
  end if;

  -- Valid updates = lots of this facility/company; anything else in the
  -- payload is ignored. Inline (no temp table) so the RPC is safe to call
  -- more than once in one transaction.
  select count(*) into v_changed
    from jsonb_to_recordset(p_updates) as u(origin_purchase_id text, counted_remaining_lbs numeric)
    join public.coffee_inventory_purchased cip on cip.origin_purchase_id = u.origin_purchase_id
   where cip.facility_id = p_facility_id and cip.company_id = p_company_id;
  if v_changed = 0 then return 0; end if;

  -- Origin-complete snapshot: changed lots at the operator's value; every
  -- other available lot of each touched origin at its remaining AS OF the
  -- anchor (current remaining + whatever the ledger took off after the
  -- anchor). Same-day count → anchor = now() → add-back 0 → today's value.
  insert into public.coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id, reason)
  select cip.origin_purchase_id,
         p_count_date,
         case when u.origin_purchase_id is not null
              then greatest(0, u.counted_remaining_lbs)
              else greatest(0, coalesce(cip.remaining_lbs, 0) + coalesce((
                     select sum(rlc.lbs_consumed)
                       from public.roast_log_lot_consumption rlc
                       join public.roast_log rl on rl.roast_log_id = rlc.roast_log_id
                      where rlc.origin_purchase_id = cip.origin_purchase_id
                        and coalesce(rl.roast_date_utc, (rl.roast_date at time zone v_tz)) > v_anchor), 0))
         end,
         p_company_id,
         case when u.origin_purchase_id is not null then p_reason else null end
    from public.coffee_inventory_purchased cip
    left join jsonb_to_recordset(p_updates) as u(origin_purchase_id text, counted_remaining_lbs numeric)
           on u.origin_purchase_id = cip.origin_purchase_id
   where cip.facility_id = p_facility_id
     and cip.company_id  = p_company_id
     and cip.origin in (select cip2.origin
                          from jsonb_to_recordset(p_updates) as u2(origin_purchase_id text, counted_remaining_lbs numeric)
                          join public.coffee_inventory_purchased cip2 on cip2.origin_purchase_id = u2.origin_purchase_id
                         where cip2.facility_id = p_facility_id and cip2.company_id = p_company_id)
     and (u.origin_purchase_id is not null or cip.remaining_lbs is not null);
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return 0; end if;

  return v_changed;
end;
$function$;

-- New signature = fresh PUBLIC EXECUTE (lesson 20260905000004): revoke, then grant.
revoke all on function public.record_per_lot_count(text, text, date, jsonb, text) from public;
grant execute on function public.record_per_lot_count(text, text, date, jsonb, text) to authenticated;

notify pgrst, 'reload schema';

commit;
