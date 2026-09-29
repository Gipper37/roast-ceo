-- The lot the roaster chose is the lot that comes off the shelf.
--
-- 20260929000001 gave a coffee group a LOT pin. It recorded which bag was open
-- and nothing read it, because the only channel that reaches
-- _deduct_origin_fifo's p_force_origin_purchase_id is
-- roast_log.borrow_origin_purchase_id, which means "a lot borrowed from ANOTHER
-- group" -- the replay branches on it twice assuming exactly that. Overloading
-- it for a same-group choice would corrupt both branches.
--
-- So the roast carries its own per-group lot choice, shaped like planned_lots:
-- {origin_id: origin_purchase_id}. Without it the roaster could pick a lot, see
-- it recorded, and watch the deduct take the oldest one anyway -- right pounds,
-- wrong bag, which is the whole of traceability.
--
-- ── WHY A GUARD FUNCTION AND NOT A BARE ->> ────────────────────────────
-- _deduct_origin_fifo ranks a forced lot FIRST and exempts it from the
-- roast-time availability guard, on the grounds that a deliberate pick outranks
-- the paperwork. That makes a STALE entry dangerous: a lot left behind after the
-- coffee changed would jump the queue and be exempt from the date check.
-- _chosen_lot_for refuses any lot that does not belong to the coffee actually
-- being drawn, so a stale entry degrades to plain FIFO instead of misfiring.
--
-- ── HOW THE TWO FUNCTION BODIES BELOW WERE PRODUCED ────────────────────
-- 🔴 CREATE OR REPLACE rewrites the ENTIRE body. Retyping the part I was not
-- changing is what broke roast saving for two days. Both bodies here are
-- pg_get_functiondef output from PROD, with a script applying the edits and
-- printing the diff. _recompute_origin_lot_consumption_core: 6 lines changed of
-- 307. deduct_one_roast: 7 of 118. Nothing else moved by a byte.
--
-- The borrow branches are deliberately untouched: a cross-group borrow already
-- names its lot and keeps it. The source-true branch is untouched too -- that is
-- the lender group's own replay and its lot is its business.

begin;

-- ── 1. The roast's own lot choice ──────────────────────────────────────
-- Nullable with no default, unlike planned_lots which is NOT NULL DEFAULT '{}'.
-- That NOT NULL is what made an impromptu roast with no resolved plan INSERT an
-- explicit null and fail the constraint, silently, until aa0b8f3. A column that
-- is simply absent most of the time should be allowed to be absent.
alter table public.roast_log
  add column if not exists planned_lot_ids jsonb;

comment on column public.roast_log.planned_lot_ids is
  'Per coffee group, the exact lot this roast drew from: {origin_id: '
  'origin_purchase_id}. Set only when the roaster chose a lot that was not the '
  'oldest -- otherwise FIFO already agrees and there is nothing to record. '
  'Distinct from borrow_origin_purchase_id, which means a lot borrowed from '
  'ANOTHER group.';

-- ── 2. The guard ───────────────────────────────────────────────────────
create or replace function public._chosen_lot_for(
  p_planned_lot_ids jsonb,
  p_origin_id text,
  p_preferred_source text
) returns text
language plpgsql
stable
as $fn$
declare
  v_lot text;
  v_src text;
  v_origin text;
begin
  if p_planned_lot_ids is null or jsonb_typeof(p_planned_lot_ids) <> 'object' then
    return null;
  end if;
  v_lot := nullif(p_planned_lot_ids ->> p_origin_id, '');
  if v_lot is null then return null; end if;

  select cip.coffee_source_id, cip.origin into v_src, v_origin
    from public.coffee_inventory_purchased cip
   where cip.origin_purchase_id = v_lot;
  if v_src is null and v_origin is null then
    return null;                      -- the lot was deleted; fall back to FIFO
  end if;

  -- A lot of a coffee we are not drawing is a leftover, not a choice. Forcing it
  -- would jump the FIFO queue AND skip the roast-time date guard.
  if p_preferred_source is not null and v_src is distinct from p_preferred_source then
    return null;
  end if;
  -- And a lot that lives in another group belongs to that group's replay.
  if v_origin is distinct from p_origin_id then
    return null;
  end if;
  return v_lot;
end;
$fn$;

-- ── 3. The two deduct paths, byte-identical but for the edits above ────
CREATE OR REPLACE FUNCTION public._recompute_origin_lot_consumption_core(p_origin_id text, p_facility_id text)
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
    -- AT TIME ZONE v_tz is evaluated unconditionally below; an unrecognized
    -- facility time_zone must degrade to UTC, never fail every replay.
    BEGIN
        PERFORM now() AT TIME ZONE v_tz;
    EXCEPTION WHEN OTHERS THEN
        v_tz := 'UTC';
    END;

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

    -- Paperwork-first lots on an unreceived/voided shipment aren't here yet.
    -- ── HERE-FIRST ── a lot that physically existed before its paperwork is
    -- never blanked by that paperwork's state: its count is its truth.
    UPDATE public.coffee_inventory_purchased cip
       SET remaining_lbs = NULL
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.shipment_id IS NOT NULL
       AND NOT cip.here_first
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
                  -- ── COUNT-DATE ANCHOR (D2) ── the receipt guard judges the
                  -- count's CLAIM: for a shipment lot the counted day must be on
                  -- or after the receipt day (local calendar dates — no more UTC
                  -- midnight = 2pm-yesterday HST); a baseline lot has no receipt,
                  -- so entry order decides as before (its creation count may
                  -- carry an as-of date just before the row was written).
                  -- Ordering: latest-count-wins means latest-DATED.
                  -- ── HERE-FIRST ── a here-first lot's counts are always its
                  -- truth (entry order only); a paperwork-first lot's count
                  -- must be dated on/after its delivery day.
                  AND CASE WHEN cip.here_first THEN clc.count_at >= cip.created_at
                           ELSE COALESCE(
                                  clc.count_date >= (SELECT sr.date_received
                                                       FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                                  clc.count_at >= cip.created_at) END
                ORDER BY LEAST(clc.count_at, ((clc.count_date + 1)::timestamp AT TIME ZONE v_tz)) DESC, clc.created_at DESC LIMIT 1),
              -- fallback: received ON/AFTER the group's last count → fresh stock
              -- (full amount); strictly earlier uncounted lots stay 0 (assumed
              -- captured by that comprehensive count).
              CASE WHEN COALESCE(
                     (SELECT sr.date_received FROM public.shipment_received sr WHERE sr.shipment_id = cip.shipment_id),
                     (cip.created_at AT TIME ZONE v_tz)::date) >= (v_last_count_at AT TIME ZONE v_tz)::date
                   THEN cip.amount ELSE 0 END
            )
           END
     WHERE cip.origin = p_origin_id AND cip.facility_id = p_facility_id
       AND cip.amount IS NOT NULL
       -- ── HERE-FIRST ── re-seeded from its counts whatever its paperwork
       -- says (exempt from the blank above, so it must be re-seeded here or
       -- the replay would take its post-anchor roasts off twice).
       AND (cip.here_first
          OR cip.shipment_id IS NULL
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
               rl.borrow_origin_purchase_id, rl.planned_lots, rl.planned_lot_ids, rr.roast_type,
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
                v_force := public._chosen_lot_for(v_roast.planned_lot_ids, p_origin_id, v_pref);
                PERFORM public._deduct_origin_fifo(
                    v_roast.roast_log_id, p_origin_id, p_facility_id, v_needed, v_pref, v_roast.roast_date, v_force, NULL);
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
            v_force := public._chosen_lot_for(v_roast.planned_lot_ids, p_origin_id, v_pref);
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

CREATE OR REPLACE FUNCTION public.deduct_one_roast(p_roast_log_id text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    rl record;
    o text;
    v_needed numeric;
    v_pref text;
    v_force text;
    v_force_source text;
    v_borrow_home text;
BEGIN
    SELECT rl2.roast_log_id, rl2.facility_id, rl2.charge_weight_lbs, rl2.coffee_source_id,
           rl2.recipe_id, rl2.origin_id, rl2.roast_date, rl2.created_at,
           rl2."charged?" AS charged, rl2.external_roast_id, rl2.borrow_origin_purchase_id,
           rl2.planned_lots, rl2.planned_lot_ids, rr.roast_type
      INTO rl
      FROM public.roast_log rl2
      LEFT JOIN public.roast_recipes rr ON rr.recipe_id = rl2.recipe_id
     WHERE rl2.roast_log_id = p_roast_log_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF rl.charged IS NOT TRUE OR COALESCE(rl.charge_weight_lbs, 0) <= 0 THEN RETURN; END IF;
    IF rl.external_roast_id IS NULL
       AND rl.roast_date < (rl.created_at::date - interval '1 day') THEN RETURN; END IF;
    IF rl.facility_id IS NULL THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.roast_log_lot_consumption WHERE roast_log_id = p_roast_log_id) THEN RETURN; END IF;

    -- Same per-origin serialization as recompute (see there) — a charge waits
    -- out any in-flight replay on its origins instead of interleaving. Affected
    -- origins now include cross-group lender homes (planned_lots passed in).
    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id, rl.planned_lots) LOOP
        PERFORM pg_advisory_xact_lock(hashtext(o), hashtext(rl.facility_id));
    END LOOP;

    FOREACH o IN ARRAY public._roast_affected_origins(rl.recipe_id, rl.origin_id, rl.planned_lots) LOOP
        IF rl.roast_type = 'Pre-Blend' THEN
            SELECT rl.charge_weight_lbs * COALESCE(rc.percentage, 0) INTO v_needed
              FROM public.recipe_components rc
             WHERE rc.recipe_id = rl.recipe_id AND rc.coffee_item = o
             ORDER BY rc.percentage DESC LIMIT 1;
        ELSE
            v_needed := rl.charge_weight_lbs;
        END IF;
        IF COALESCE(v_needed, 0) <= 0 THEN CONTINUE; END IF;

        -- Preferred source: blend components take their planned_lots pick first
        -- (the Add/Edit per-component picker), then the single coffee_source_id;
        -- single-origin keeps coffee_source_id authoritative with planned_lots
        -- as the fallback. Mirrors recompute_origin_lot_consumption.
        --
        -- Source-true: if a pre-blend component's planned source is cross-group
        -- (its home origin_id <> the component origin o), FORCE that source so
        -- the deduct draws the source's own lots (which live in another group),
        -- not this component group's native FIFO. v_pref stays NULL in that case.
        v_pref := NULL;
        v_force_source := NULL;
        IF rl.roast_type = 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
            IF v_pref IS NOT NULL THEN
                SELECT CASE WHEN cs.origin_id IS DISTINCT FROM o THEN v_pref ELSE NULL END
                  INTO v_force_source
                  FROM public.coffee_source cs WHERE cs.coffee_source_id = v_pref;
                -- Cross-group: the planned source becomes a forced source, and the
                -- in-group preference no longer applies (its lots aren't in o).
                IF v_force_source IS NOT NULL THEN
                    v_pref := NULL;
                END IF;
            END IF;
        END IF;
        IF v_pref IS NULL AND v_force_source IS NULL AND rl.coffee_source_id IS NOT NULL THEN
            SELECT CASE WHEN cs.origin_id = o THEN rl.coffee_source_id ELSE NULL END
              INTO v_pref FROM public.coffee_source cs WHERE cs.coffee_source_id = rl.coffee_source_id;
        END IF;
        IF v_pref IS NULL AND v_force_source IS NULL AND rl.roast_type IS DISTINCT FROM 'Pre-Blend' THEN
            v_pref := NULLIF(rl.planned_lots ->> o, '');
        END IF;

        -- Borrow applies to single-origin / post-blend only (one affected origin).
        v_force := NULL;
        IF rl.roast_type IS DISTINCT FROM 'Pre-Blend'
           AND o = rl.origin_id AND rl.borrow_origin_purchase_id IS NOT NULL THEN
            v_force := rl.borrow_origin_purchase_id;
        END IF;
        -- A lot the roaster deliberately chose for THIS group. A cross-group
        -- borrow already named its lot above and keeps it.
        IF v_force IS NULL THEN
            v_force := public._chosen_lot_for(rl.planned_lot_ids, o, v_pref);
        END IF;

        PERFORM public._deduct_origin_fifo(rl.roast_log_id, o, rl.facility_id, v_needed, v_pref, rl.roast_date, v_force, v_force_source);
        PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
    END LOOP;

    -- Source-true parity with the replay's per-origin reconcile: a cross-group
    -- component drew from a LENDER group's lots, but the FOREACH iteration for that
    -- lender computed v_needed=0 (it is not a recipe component) and skipped its
    -- recalculate_origin_total_stock. Refresh each cross-group lender home so its
    -- in_stock/total_stock cache is not left stale-high on the first-deduct path.
    IF rl.roast_type = 'Pre-Blend' AND jsonb_typeof(rl.planned_lots) = 'object' THEN
        FOR o IN
            SELECT DISTINCT cs.origin_id
              FROM jsonb_each_text(rl.planned_lots) pl
              JOIN public.coffee_source cs ON cs.coffee_source_id = pl.value
             WHERE cs.origin_id IS DISTINCT FROM pl.key
        LOOP
            PERFORM public.recalculate_origin_total_stock(o, rl.facility_id);
        END LOOP;
    END IF;

    -- Refresh the lender lot's home group (the bean physically left it).
    IF rl.borrow_origin_purchase_id IS NOT NULL THEN
        SELECT cip.origin INTO v_borrow_home
          FROM public.coffee_inventory_purchased cip
         WHERE cip.origin_purchase_id = rl.borrow_origin_purchase_id;
        IF v_borrow_home IS NOT NULL THEN
            PERFORM public.recalculate_origin_total_stock(v_borrow_home, rl.facility_id);
        END IF;
    END IF;
END;
$function$;

do $verify$
declare v_bad int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='roast_log'
                    and column_name='planned_lot_ids') then
    raise exception 'planned_lot_ids is missing';
  end if;

  -- The guard refuses a lot that is not the coffee being drawn. Proved against
  -- real rows rather than asserted: take any lot, ask for it under a coffee it
  -- does not belong to, and it must come back null.
  select count(*) into v_bad from (
    select cip.origin_purchase_id, cip.origin, cip.coffee_source_id
      from public.coffee_inventory_purchased cip
     where cip.coffee_source_id is not null and cip.origin is not null
     limit 50) x
   where public._chosen_lot_for(
           jsonb_build_object(x.origin, x.origin_purchase_id),
           x.origin,
           '__a_coffee_that_is_not_this_one__') is not null;
  if v_bad > 0 then raise exception '_chosen_lot_for honoured % lot(s) of the wrong coffee', v_bad; end if;

  -- And it ACCEPTS the lot when the coffee does match, or the column is inert.
  select count(*) into v_bad from (
    select cip.origin_purchase_id, cip.origin, cip.coffee_source_id
      from public.coffee_inventory_purchased cip
     where cip.coffee_source_id is not null and cip.origin is not null
     limit 50) x
   where public._chosen_lot_for(
           jsonb_build_object(x.origin, x.origin_purchase_id),
           x.origin, x.coffee_source_id) is distinct from x.origin_purchase_id;
  if v_bad > 0 then raise exception '_chosen_lot_for refused % lot(s) of the RIGHT coffee', v_bad; end if;

  -- A null/absent choice must be inert, which is every roast that exists today.
  if public._chosen_lot_for(null, 'anything', null) is not null
     or public._chosen_lot_for('{}'::jsonb, 'anything', null) is not null then
    raise exception '_chosen_lot_for invented a lot from nothing';
  end if;

  raise notice 'lot forcing is live; % roast(s) carry a lot choice so far',
    (select count(*) from public.roast_log where planned_lot_ids is not null);
end;
$verify$;

commit;
