-- Here-first lots: a count is truth no matter what the paperwork does
-- (owner-confirmed premise 2026-09-05; source-audit passes 2 + 3).
--
-- A lot remembers its origin story. PAPERWORK-FIRST lots (shipment / PO lines)
-- aren't here until delivered: on an unreceived or voided shipment their stock
-- is blank, and a count dated before the delivery day is ignored (the June-30
-- protection — six lots "counted" at 0 while at sea). HERE-FIRST lots (quick
-- add at the roaster, baseline, a count that found them) physically existed
-- before any paperwork: their counts are always their truth, and paperwork
-- recorded later, dated wrong, voided or un-received never blanks them. Today
-- that distinction was erased the moment a receipt was recorded, which is why
-- recording a receipt into an in-transit shipment, or voiding a shipment,
-- could silently wipe counted coffee.
--
-- 1. coffee_inventory_purchased.here_first — stamped true on insert for any
--    lot that isn't a shipment line; never flipped. Backfilled: every lot with
--    no shipment, plus lots whose row predates their shipment header (the
--    receipted quick-adds). Paperwork-first lots stay false.
-- 2. The replay: here-first lots are exempt from the unreceived-shipment blank
--    and use entry order for their count guard; paperwork-first lots keep the
--    delivery-day guard.
-- 3. Recording a receipt INTO an unreceived shipment marks it received (the
--    coffee is demonstrably here), dated with the receipt.
-- 4. Voiding or un-receiving a shipment sends its here-first lots back to
--    "Receipts to record" (detached, counts intact) instead of blanking them.
-- 5. The duplicate-delivery question also fires when a recorded line is
--    EDITED to a lot # already on hand, and also matches lots dismissed from
--    the queue (still here, just not awaiting paperwork). Always confirmable,
--    never a refusal. Recording a pending lot's own receipt is exempt.
-- 6. merge_lot_into_shipment_line: the receipts-queue merge in ONE transaction.
-- 7. roast_detail: the per-origin roasted-stock sums name their stock_type —
--    'origin' rows and 'blend' rows — which the old check constraint implied.
--    Since 20260905000001 a 'component' row carries both ids and would have
--    counted at full value, again at percentage, and leaked into siblings.
--    Output is identical for every existing row.
-- 8. The Sunday replay checkpoint dates its rows in the facility's day.

begin;

-- ── 1. here_first ─────────────────────────────────────────────────────────
alter table public.coffee_inventory_purchased
  add column if not exists here_first boolean not null default false;
comment on column public.coffee_inventory_purchased.here_first is
  'The lot physically existed before any shipment paperwork (quick add, baseline, count-discovered). Its counts are always its truth; paperwork state never blanks it. Set on insert, never flipped.';

-- Dismissing a receipt is an explicit state, not a shape ("no shipment, no
-- cost" also describes a baseline import that was never in the queue).
alter table public.coffee_inventory_purchased
  add column if not exists receipt_dismissed_at timestamptz;
comment on column public.coffee_inventory_purchased.receipt_dismissed_at is
  'Set when the operator dismisses this lot from "Receipts to record" (last resort). Cleared by un-dismiss. The duplicate-delivery question still matches a dismissed lot by exact lot #.';
update public.coffee_inventory_purchased
   set receipt_dismissed_at = coalesce(updated_at, now())
 where receipt_dismissed_at is null and updated_by = 'cleanup_pass1_20260905'
   and not receipt_pending and shipment_id is null;

create or replace function public.cip_stamp_here_first() returns trigger
language plpgsql as $function$
begin
  if new.entry_method is distinct from 'shipment' or coalesce(new.receipt_pending, false) then
    new.here_first := true;
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_cip_here_first on public.coffee_inventory_purchased;
create trigger trg_cip_here_first before insert on public.coffee_inventory_purchased
  for each row execute function public.cip_stamp_here_first();

-- Backfill. The per-row cost/metrics/shipment-total triggers honor these
-- defer flags (they'd otherwise recompute once per touched row for nothing).
select set_config('app.defer_lot_valuation', 'true', true);
select set_config('app.defer_shipment_recompute', 'true', true);
update public.coffee_inventory_purchased cip
   set here_first = true
 where not cip.here_first
   and (cip.shipment_id is null
        or exists (select 1 from public.shipment_received sr
                    where sr.shipment_id = cip.shipment_id and cip.created_at < sr.created_at));

-- ── 2. replay ─────────────────────────────────────────────────────────────
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

-- ── 5. duplicate-delivery guard: on edit too, dismissed lots too ──────────
CREATE OR REPLACE FUNCTION public.guard_duplicate_pending_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_pending text;
BEGIN
  -- The operator was shown the clash and said these are separate deliveries.
  -- Transaction-local; see save_shipment_lines.
  IF COALESCE(current_setting('app.allow_duplicate_lot', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  -- Recording the receipt for a lot that was already here (pending → recorded,
  -- or the merge keeper) is not a new line — never a duplicate of itself.
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.receipt_pending, false) THEN
    RETURN NEW;
  END IF;
  -- UPDATE OF fires whenever a column is in SET, changed or not: a saved
  -- shipment re-asserts every line. Only a real change of the key asks.
  IF TG_OP = 'UPDATE'
     AND NEW.coffee_source_id IS NOT DISTINCT FROM OLD.coffee_source_id
     AND lower(btrim(COALESCE(NEW.lot_id, ''))) = lower(btrim(COALESCE(OLD.lot_id, '')))
     AND NEW.shipment_id IS NOT DISTINCT FROM OLD.shipment_id THEN
    RETURN NEW;
  END IF;

  -- Guard real recorded-shipment lots (not pending-count rows) that carry a source.
  IF NEW.entry_method = 'shipment'
     AND NEW.coffee_source_id IS NOT NULL
     AND NOT COALESCE(NEW.receipt_pending, false) THEN

    IF NULLIF(btrim(NEW.lot_id), '') IS NOT NULL THEN
      -- Non-blank lot: match a pending receipt by (facility, source, lot #).
      SELECT origin_purchase_id INTO v_pending
        FROM public.coffee_inventory_purchased
       WHERE facility_id = NEW.facility_id
         AND coffee_source_id = NEW.coffee_source_id
         AND lower(btrim(lot_id)) = lower(btrim(NEW.lot_id))
         AND (receipt_pending = true OR receipt_dismissed_at IS NOT NULL)
         AND origin_purchase_id <> NEW.origin_purchase_id
       LIMIT 1;
    ELSE
      -- Blank lot: no lot # to match on, so fall back to matching a pending receipt
      -- for the SAME (facility, source). A blank-lot recorded line for a source that
      -- already has a counted-pending receipt is the exact double-count the
      -- source-count design prevents.
      SELECT origin_purchase_id INTO v_pending
        FROM public.coffee_inventory_purchased
       WHERE facility_id = NEW.facility_id
         AND coffee_source_id = NEW.coffee_source_id
         AND receipt_pending = true
         AND origin_purchase_id <> NEW.origin_purchase_id
       LIMIT 1;
    END IF;

    IF v_pending IS NOT NULL THEN
      -- Message unchanged in substance, but it now names the way out rather than
      -- presenting one reading as the only one.
      -- The frontend recognizes this refusal by the phrase 'waiting in "Receipts to record"'.
      RAISE EXCEPTION 'This coffee + lot # (%) is already on hand and waiting in "Receipts to record" (or was dismissed from it). If it is the same coffee, record that receipt instead of adding a new line. If this is a separate delivery that happens to share a lot number, confirm to add it anyway.',
        COALESCE(NULLIF(btrim(NEW.lot_id), ''), '(no lot #)')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
drop trigger if exists trg_guard_dup_pending_receipt on public.coffee_inventory_purchased;
create trigger trg_guard_dup_pending_receipt
  before insert or update of coffee_source_id, lot_id, receipt_pending, shipment_id
  on public.coffee_inventory_purchased
  for each row execute function public.guard_duplicate_pending_receipt();

-- ── 6. merge in one transaction ───────────────────────────────────────────
drop function if exists public.merge_lot_into_shipment_line(text, text);
create function public.merge_lot_into_shipment_line(p_keep_purchase_id text, p_duplicate_purchase_id text)
returns jsonb language plpgsql as $function$
declare
  v_dup record; v_keep record; v_roasts int; v_ship record; v_arrived date; v_tz text;
begin
  select origin_purchase_id, shipment_id, coffee_source_id, lot_id, cost_lb, target_cost_lb, supplier_id,
         remaining_lbs, company_id, facility_id
    into v_dup from public.coffee_inventory_purchased where origin_purchase_id = p_duplicate_purchase_id;
  if not found then raise exception 'That shipment line no longer exists.'; end if;
  if v_dup.shipment_id is null then raise exception 'That line is not on a shipment.'; end if;
  -- A line holding stock or roasts of its own is a second real delivery, not a duplicate.
  if coalesce(v_dup.remaining_lbs, 0) > 0 then
    raise exception 'That shipment line holds stock of its own, so it is not a duplicate. Edit the lines directly instead.';
  end if;
  select count(*) into v_roasts from public.roast_log_lot_consumption where origin_purchase_id = p_duplicate_purchase_id;
  if v_roasts > 0 then raise exception 'That shipment line has roasts against it, so it cannot be removed.'; end if;

  select origin_purchase_id, shipment_id, cost_lb, company_id
    into v_keep from public.coffee_inventory_purchased where origin_purchase_id = p_keep_purchase_id;
  if not found then raise exception 'That lot no longer exists.'; end if;
  if v_keep.company_id is distinct from v_dup.company_id then raise exception 'Those lots belong to different companies.'; end if;
  if v_keep.shipment_id is not null then raise exception 'That lot is already on a shipment.'; end if;

  -- The keeper moves onto the shipment and inherits what the line knew; it is a
  -- recorded purchase now so it leaves "Receipts to record". remaining_lbs is
  -- untouched: the roasts stay where they are. Setting cost_lb reprices roasts
  -- booked at zero (trg_revalue_roasts_on_cost_change).
  update public.coffee_inventory_purchased
     set shipment_id = v_dup.shipment_id,
         cost_lb = coalesce(v_dup.cost_lb, v_keep.cost_lb),
         target_cost_lb = v_dup.target_cost_lb,
         supplier_id = v_dup.supplier_id,
         entry_method = 'shipment',
         receipt_pending = false,
         updated_at = now()
   where origin_purchase_id = p_keep_purchase_id;

  delete from public.coffee_inventory_purchased where origin_purchase_id = p_duplicate_purchase_id;

  -- Merging says "this coffee came from this order", so the order arrived. Date
  -- it from the lot's own count (when the roaster said it turned up), not today.
  select date_received, voided into v_ship from public.shipment_received where shipment_id = v_dup.shipment_id;
  if coalesce(v_ship.voided, false) then raise exception 'That shipment was voided.'; end if;
  if v_ship.date_received is null then
    select coalesce(nullif(time_zone, ''), 'UTC') into v_tz from public.facilities where facility_id = v_dup.facility_id;
    select count_date into v_arrived from public.coffee_lot_count
     where origin_purchase_id = p_keep_purchase_id order by count_at asc limit 1;
    v_arrived := coalesce(v_arrived, (now() at time zone coalesce(v_tz, 'UTC'))::date);
    update public.shipment_received set date_received = v_arrived, status = 'received', updated_at = now()
     where shipment_id = v_dup.shipment_id;
  end if;
  return jsonb_build_object('ok', true, 'shipment_id', v_dup.shipment_id);
end;
$function$;
revoke all on function public.merge_lot_into_shipment_line(text, text) from public;
grant execute on function public.merge_lot_into_shipment_line(text, text) to authenticated;

-- ── 7. roast_detail: name the stock types the constraint used to imply ────
create or replace view public.roast_detail as
WITH facility_params AS (
         SELECT f.facility_id,
            f.company_id,
            COALESCE(NULLIF(f.time_zone, ''::text), 'Pacific/Honolulu'::text) AS timezone,
            COALESCE(( SELECT cp.value_number::integer AS value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = 'RF1iFWjOh7'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), 4) AS roast_reset_day,
            COALESCE(( SELECT cp.value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = '761fd894'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), 25::numeric) AS charge_weight,
            COALESCE(( SELECT cp.value_number
                   FROM company_parameters cp
                  WHERE cp.parameter_id = '1de271df'::text AND cp.facility_id = f.facility_id
                 LIMIT 1), 0.82) AS retention_rate
           FROM facilities f
        ), calc AS (
         SELECT fp.facility_id,
            fp.company_id,
            fp.timezone,
            fp.charge_weight,
            fp.retention_rate,
            (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date - (EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer - fp.roast_reset_day + 7) % 7 AS roast_week_start
           FROM facility_params fp
        ), origin_facility AS (
         SELECT DISTINCT rc.coffee_item AS origin,
            f.facility_id,
            f.company_id
           FROM recipe_components rc
             JOIN roast_recipes rr ON rc.recipe_id = rr.recipe_id
             JOIN facilities f ON f.company_id = rr.company_id AND (rr.facility_id IS NULL OR rr.facility_id = f.facility_id)
        ), per_origin AS (
         SELECT of2.origin,
            of2.facility_id,
            of2.company_id,
            COALESCE(( SELECT sum(rsl.lbs_in_stock) AS sum
                   FROM roast_stock_log rsl
                  WHERE rsl.stock_type = 'origin' AND rsl.origin_id = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0::numeric) + COALESCE(( SELECT sum(rsl.lbs_in_stock * rc.percentage) AS sum
                   FROM roast_stock_log rsl
                     JOIN recipe_components rc ON rsl.blend_id = rc.recipe_id
                  WHERE rsl.stock_type = 'blend' AND rc.coffee_item = of2.origin AND rsl.facility_id = of2.facility_id AND (rsl.created_at AT TIME ZONE c.timezone)::date >= c.roast_week_start), 0::numeric) AS in_stock_roasted,
            COALESCE(( SELECT sum(od.quantity * p.weight_lbs * rc.percentage) AS sum
                   FROM order_details od
                     JOIN orders o ON od.order_id = o.order_id
                     JOIN products p ON od.product_id = p.product_id
                     JOIN recipe_components rc ON p.recipe_id = rc.recipe_id
                  WHERE rc.coffee_item = of2.origin AND o.order_status = 'Open'::text AND o.facility_id = of2.facility_id), 0::numeric) AS total_ordered,
            COALESCE(( SELECT sum(rl.roasted_weight) AS sum
                   FROM roast_log rl
                  WHERE rl.origin_id = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0::numeric) + COALESCE(( SELECT sum(rl.roasted_weight * rc.percentage) AS sum
                   FROM roast_log rl
                     JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
                     JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
                  WHERE rr.roast_type = 'Pre-Blend'::text AND rc.coffee_item = of2.origin AND rl."charged?" = true AND rl.roast_date >= c.roast_week_start AND rl.facility_id = of2.facility_id), 0::numeric) AS total_roasted,
            c.retention_rate,
            COALESCE(( SELECT avg(rl.charge_weight_lbs) AS avg
                   FROM ( SELECT roast_log.charge_weight_lbs
                           FROM roast_log
                          WHERE roast_log.origin_id = of2.origin AND roast_log.facility_id = of2.facility_id AND roast_log.charge_weight_lbs > 0::numeric
                          ORDER BY roast_log.roast_date DESC
                         LIMIT 5) rl), c.charge_weight, 25::numeric) AS effective_charge_weight
           FROM origin_facility of2
             JOIN calc c ON c.facility_id = of2.facility_id
        )
 SELECT (origin || '-'::text) || facility_id AS roast_detail_id,
    origin,
    facility_id,
    company_id,
    in_stock_roasted,
    total_roasted,
    total_ordered,
    GREATEST(0::numeric, total_ordered - in_stock_roasted - total_roasted) AS final_roasted_weight,
    GREATEST(0::numeric, total_ordered - in_stock_roasted - total_roasted) / NULLIF(retention_rate, 0::numeric) AS green_to_roast,
    GREATEST(0::numeric, total_ordered - in_stock_roasted - total_roasted) / NULLIF(retention_rate, 0::numeric) / NULLIF(effective_charge_weight, 0::numeric) AS roasts_remaining
   FROM per_origin;


-- ── 3. receipts: a count is truth; attaching to an order means it arrived ─
create or replace function public.record_lot_receipt(
  p_origin_purchase_id text,
  p_cost_lb numeric,
  p_supplier_id text,
  p_received_date date,
  p_shipping_cost numeric default 0,
  p_shipment_id text default null,
  p_confirm_past_count boolean default false,
  p_bags_ordered numeric default null)
returns jsonb
language plpgsql
as $function$
declare
  v_lot record; v_count_date date; v_ship text;
begin
  select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = p_origin_purchase_id;
  if not found then raise exception 'lot % not found', p_origin_purchase_id; end if;
  if not coalesce(v_lot.receipt_pending, false) then raise exception 'lot has no pending receipt to record'; end if;
  if p_cost_lb is null or p_cost_lb < 0 then raise exception 'cost per lb is required'; end if;
  if p_received_date is null then raise exception 'received date is required'; end if;
  if p_bags_ordered is not null and p_bags_ordered <= 0 then raise exception 'bag count must be > 0'; end if;
  select max(count_date) into v_count_date
    from public.coffee_lot_count where origin_purchase_id = p_origin_purchase_id;
  if v_count_date is not null and p_received_date > v_count_date and not p_confirm_past_count then
    return jsonb_build_object(
      'warning', 'received_after_count',
      'count_date', v_count_date, 'received_date', p_received_date,
      'message', format('This lot was counted on %s but the receipt is dated %s (later). Check the date — the count stays as this lot''s stock either way.', v_count_date, p_received_date));
  end if;
  if p_shipment_id is not null then
    v_ship := p_shipment_id;
    -- ── HERE-FIRST ── recording a counted lot INTO an order says the coffee is
    -- here, so an unreceived order becomes received (dated with this receipt).
    -- Attaching to "not here yet" paperwork used to blank the lot's stock.
    perform 1 from public.shipment_received where shipment_id = v_ship and coalesce(voided, false) = false;
    if not found then raise exception 'that shipment was voided or does not exist'; end if;
    -- If the order already carries a stock-less line for this coffee, this lot
    -- is almost certainly THAT line: receiving the order would seed the line to
    -- its amount on top of this counted lot. Steer to Combine; confirmable.
    if not p_confirm_past_count and exists (
         select 1 from public.coffee_inventory_purchased o
          where o.shipment_id = v_ship and o.origin_purchase_id <> p_origin_purchase_id
            and o.coffee_source_id is not distinct from v_lot.coffee_source_id
            and coalesce(o.remaining_lbs, 0) = 0
            and not exists (select 1 from public.roast_log_lot_consumption r where r.origin_purchase_id = o.origin_purchase_id)) then
      return jsonb_build_object(
        'warning', 'same_coffee_on_order',
        'message', 'That order already has a line for this coffee with nothing received against it. If this is that coffee, combine it with that line instead (Edit shipment → Combine). Confirm to record it as a separate lot anyway.');
    end if;
    update public.shipment_received
       set date_received = p_received_date, status = 'received', updated_at = now()
     where shipment_id = v_ship and date_received is null;
  else
    v_ship := 'rcpt-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 18);
    insert into public.shipment_received
      (shipment_id, company_id, facility_id, supplier_id, order_date, date_received, shipping_cost, status, voided, created_at, updated_at)
    values
      (v_ship, v_lot.company_id, v_lot.facility_id, p_supplier_id, p_received_date, p_received_date, coalesce(p_shipping_cost, 0), 'received', false, now(), now());
  end if;
  update public.coffee_inventory_purchased
     set shipment_id = v_ship, cost_lb = p_cost_lb, entry_method = 'shipment',
         bags_ordered = coalesce(p_bags_ordered, bags_ordered),
         receipt_pending = false, updated_at = now()
   where origin_purchase_id = p_origin_purchase_id;
  -- Trigger-overwrite guard: restore the counted bag_size/amount (BEFORE
  -- trigger rewrote them when bags_ordered changed). These columns are not
  -- in the trigger's OF list, so this sticks without re-firing it.
  update public.coffee_inventory_purchased
     set bag_size = v_lot.bag_size, amount = v_lot.amount
   where origin_purchase_id = p_origin_purchase_id
     and (bag_size is distinct from v_lot.bag_size or amount is distinct from v_lot.amount);
  return jsonb_build_object('ok', true, 'shipment_id', v_ship);
end;
$function$;
revoke all on function public.record_lot_receipt(text, numeric, text, date, numeric, text, boolean, numeric) from public;
grant execute on function public.record_lot_receipt(text, numeric, text, date, numeric, text, boolean, numeric) to authenticated;

create or replace function public.record_lot_receipts(
  p_receipts jsonb,
  p_supplier_id text,
  p_received_date date,
  p_shipping_cost numeric default 0,
  p_confirm_past_count boolean default false)
returns jsonb
language plpgsql
as $function$
declare
  v_item jsonb; v_lot record; v_count_date date; v_ship text;
  v_id text; v_cost numeric; v_bags numeric;
  v_company text; v_facility text;
  v_seen text[] := '{}'; v_warn jsonb := '[]'::jsonb; v_n int := 0;
begin
  if p_receipts is null or jsonb_typeof(p_receipts) <> 'array' or jsonb_array_length(p_receipts) = 0 then
    raise exception 'no lots to record';
  end if;
  if p_received_date is null then raise exception 'received date is required'; end if;

  -- Pass 1: validate every lot before writing anything.
  for v_item in select * from jsonb_array_elements(p_receipts) loop
    v_id := v_item->>'origin_purchase_id';
    v_cost := (v_item->>'cost_lb')::numeric;
    v_bags := (v_item->>'bags_ordered')::numeric;
    if v_id is null then raise exception 'lot id missing'; end if;
    if v_id = any(v_seen) then raise exception 'lot % appears twice in this delivery', v_id; end if;
    v_seen := v_seen || v_id;
    select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = v_id;
    if not found then raise exception 'lot % not found', v_id; end if;
    if not coalesce(v_lot.receipt_pending, false) then raise exception 'lot % has no pending receipt to record', v_id; end if;
    if v_cost is null or v_cost < 0 then raise exception 'cost per lb is required for every lot'; end if;
    if v_bags is null or v_bags <= 0 then raise exception 'bag count is required for every lot'; end if;
    if v_company is null then
      v_company := v_lot.company_id; v_facility := v_lot.facility_id;
    elsif v_lot.company_id is distinct from v_company or v_lot.facility_id is distinct from v_facility then
      raise exception 'these lots belong to different facilities — record them separately';
    end if;
    select max(count_date) into v_count_date
      from public.coffee_lot_count where origin_purchase_id = v_id;
    if v_count_date is not null and p_received_date > v_count_date then
      v_warn := v_warn || jsonb_build_object(
        'origin_purchase_id', v_id, 'lot_id', v_lot.lot_id,
        'count_date', v_count_date, 'received_date', p_received_date);
    end if;
  end loop;

  -- One aggregate confirm for the whole delivery; nothing written yet.
  if jsonb_array_length(v_warn) > 0 and not p_confirm_past_count then
    return jsonb_build_object(
      'warning', 'received_after_count',
      'lots', v_warn,
      'message', format('%s of these lots were counted before this received date. Check the date — the counts stay as their stock either way.', jsonb_array_length(v_warn)));
  end if;

  -- Write: one delivery header, then every lot onto it.
  v_ship := 'rcpt-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 18);
  insert into public.shipment_received
    (shipment_id, company_id, facility_id, supplier_id, order_date, date_received, shipping_cost, status, voided, created_at, updated_at)
  values
    (v_ship, v_company, v_facility, p_supplier_id, p_received_date, p_received_date, coalesce(p_shipping_cost, 0), 'received', false, now(), now());

  for v_item in select * from jsonb_array_elements(p_receipts) loop
    v_id := v_item->>'origin_purchase_id';
    v_cost := (v_item->>'cost_lb')::numeric;
    v_bags := (v_item->>'bags_ordered')::numeric;
    select * into v_lot from public.coffee_inventory_purchased where origin_purchase_id = v_id;
    update public.coffee_inventory_purchased
       set shipment_id = v_ship, cost_lb = v_cost, entry_method = 'shipment',
           bags_ordered = v_bags,
           receipt_pending = false, updated_at = now()
     where origin_purchase_id = v_id;
    update public.coffee_inventory_purchased
       set bag_size = v_lot.bag_size, amount = v_lot.amount
     where origin_purchase_id = v_id
       and (bag_size is distinct from v_lot.bag_size or amount is distinct from v_lot.amount);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'shipment_id', v_ship, 'count', v_n);
end;
$function$;
revoke all on function public.record_lot_receipts(jsonb, text, date, numeric, boolean) from public;
grant execute on function public.record_lot_receipts(jsonb, text, date, numeric, boolean) to authenticated;

-- ── 4. voided / un-received paperwork releases its here-first lots ────────
-- The coffee was counted on the floor; only its paperwork changed. The lots
-- go back to "Receipts to record" with their counts intact (the replay never
-- blanks a here-first lot, so stock is unaffected either way).
create or replace function public.shipment_release_here_first_lots() returns trigger
language plpgsql as $function$
begin
  if (coalesce(new.voided, false) and not coalesce(old.voided, false))
     or (new.date_received is null and old.date_received is not null) then
    update public.coffee_inventory_purchased
       set shipment_id = null, receipt_pending = true, updated_at = now()
     where shipment_id = new.shipment_id and here_first;
    -- update_shipment_on_coffee recomputes totals for the NEW (null) header only
    perform public.calculate_shipment_totals_for(new.shipment_id, new.facility_id);
  end if;
  return null;
end;
$function$;
drop trigger if exists trg_shipment_release_here_first on public.shipment_received;
create trigger trg_shipment_release_here_first
  after update of voided, date_received on public.shipment_received
  for each row execute function public.shipment_release_here_first_lots();

-- ── 8. the Sunday checkpoint is dated in the facility's day ─────────────
CREATE OR REPLACE FUNCTION public.snapshot_stale_origin_anchors(p_min_anchor_age interval DEFAULT '30 days'::interval, p_min_depth integer DEFAULT 300, p_max_origins integer DEFAULT 5, p_only_origin text DEFAULT NULL::text, p_only_facility text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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
               -- the checkpoint claims the FACILITY's day (its anchor is derived
               -- from count_date now); CURRENT_DATE is the server's UTC day
               (now() AT TIME ZONE COALESCE((SELECT NULLIF(f.time_zone, '') FROM public.facilities f
                                               WHERE f.facility_id = v_o.facility_id), 'UTC'))::date,
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
$function$;

notify pgrst, 'reload schema';

commit;
