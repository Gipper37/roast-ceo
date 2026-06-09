-- ============================================================
-- Phase 2: lot-aware deduction triggers + receive-shipment lot stock init
-- ============================================================
-- Cutover is system-wide: every charged roast inserted after this
-- migration ships deducts from FIFO lot(s); every shipment receive
-- initializes the new lot's remaining_lbs. No per-facility switch.
--
-- What the trigger does on roast_log INSERT (deduct_from_lot_on_roast):
--   - Skips if not charged or charge_weight_lbs is null/0
--   - Skips if historical (roast_date < created_at - 1 hour) — catches
--     importer paths that backfill old roast data without deducting
--     from CURRENT stock
--   - Skips if external_roast_id IS NOT NULL — catches Artisan imports
--     specifically (their lot history already lives in
--     coffee_inventory_purchased rows from the same import)
--   - For blends: walks recipe_components, computes lbs per component
--     via percentage, FIFO-deducts each component's lbs from its
--     origin's oldest active lot. If coffee_source_id is set on the
--     roast_log row AND that source belongs to one of the components'
--     origins, that source's lots get drained first before falling
--     through to FIFO across the rest.
--   - For single-origin roasts (no recipe or no components): full
--     charge_weight_lbs comes from roast_log.origin_id.
--   - Writes one roast_log_lot_consumption row per (lot, lbs).
--     Cross-lot deductions produce multiple rows.
--
-- What the trigger does on shipment_received UPDATE
-- (initialize_lot_remaining_lbs_on_receive):
--   - When date_received transitions from NULL to non-NULL, every
--     coffee_inventory_purchased line in the shipment gets its
--     remaining_lbs initialized to its amount (the lbs received).
--
-- What the trigger does on coffee_inventory_purchased UPDATE
-- (refresh_origin_total_on_lot_change):
--   - When remaining_lbs changes, refreshes the origin's cached
--     total_stock_lbs via recalculate_origin_total_stock.
-- ============================================================


-- ── deduct_from_lot_on_roast ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.deduct_from_lot_on_roast()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_component record;
    v_lot record;
    v_lbs_to_deduct numeric;
    v_lbs_alloc numeric;
    v_alloc_total numeric;
    v_origin_id text;
    v_component_count int;
    v_picked_source_origin text;
BEGIN
    -- Skip non-charge rows
    IF NEW."charged?" IS NOT TRUE OR COALESCE(NEW.charge_weight_lbs, 0) <= 0 THEN
        RETURN NEW;
    END IF;

    -- Skip historical inserts (importers + manual backfill paths)
    IF NEW.roast_date < NEW.created_at - interval '1 hour' THEN
        RETURN NEW;
    END IF;

    -- Skip Artisan imports specifically
    IF NEW.external_roast_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Resolve the origin of the picked source (if any) so we can prefer
    -- it during FIFO walk below.
    IF NEW.coffee_source_id IS NOT NULL THEN
        SELECT origin_id INTO v_picked_source_origin
          FROM public.coffee_source
         WHERE coffee_source_id = NEW.coffee_source_id;
    END IF;

    -- Build the list of (origin, lbs_to_deduct) to walk. For a blend
    -- (recipe with components), walk each component's share. For a
    -- single-origin roast (no recipe components), use roast_log.origin_id.
    SELECT count(*) INTO v_component_count
      FROM public.recipe_components rc
     WHERE rc.recipe_id = NEW.recipe_id;

    IF v_component_count > 0 THEN
        -- Blend roast: iterate components
        FOR v_component IN
            SELECT rc.coffee_item AS origin_id,
                   COALESCE(rc.percentage, 0) AS pct
              FROM public.recipe_components rc
             WHERE rc.recipe_id = NEW.recipe_id
               AND rc.coffee_item IS NOT NULL
               AND COALESCE(rc.percentage, 0) > 0
        LOOP
            v_lbs_to_deduct := NEW.charge_weight_lbs * (v_component.pct / 100.0);
            IF v_lbs_to_deduct <= 0 THEN CONTINUE; END IF;

            -- For this component's origin: deduct FIFO. If the picked
            -- source belongs to this origin, drain its lots first.
            v_alloc_total := 0;
            FOR v_lot IN
                SELECT cip.origin_purchase_id, cip.remaining_lbs, cip.coffee_source_id,
                       COALESCE(sr.date_received, cip.created_at::date) AS sort_date
                  FROM public.coffee_inventory_purchased cip
                  LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
                 WHERE cip.origin = v_component.origin_id
                   AND cip.facility_id = NEW.facility_id
                   AND COALESCE(cip.remaining_lbs, 0) > 0
                 ORDER BY
                   -- Picked source's lots first (if this origin matches)
                   CASE WHEN v_picked_source_origin = v_component.origin_id
                             AND cip.coffee_source_id = NEW.coffee_source_id
                        THEN 0 ELSE 1 END,
                   -- Then FIFO by received date (oldest first)
                   COALESCE(sr.date_received, cip.created_at::date) ASC,
                   cip.created_at ASC
            LOOP
                IF v_alloc_total >= v_lbs_to_deduct THEN EXIT; END IF;
                v_lbs_alloc := LEAST(v_lot.remaining_lbs, v_lbs_to_deduct - v_alloc_total);
                IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;

                UPDATE public.coffee_inventory_purchased
                   SET remaining_lbs = remaining_lbs - v_lbs_alloc
                 WHERE origin_purchase_id = v_lot.origin_purchase_id;

                INSERT INTO public.roast_log_lot_consumption
                    (roast_log_id, origin_purchase_id, lbs_consumed)
                  VALUES (NEW.roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);

                v_alloc_total := v_alloc_total + v_lbs_alloc;
            END LOOP;

            PERFORM public.recalculate_origin_total_stock(v_component.origin_id, NEW.facility_id);
        END LOOP;
    ELSE
        -- Single-origin roast: use roast_log.origin_id
        v_origin_id := NEW.origin_id;
        IF v_origin_id IS NULL THEN
            RETURN NEW;
        END IF;

        v_lbs_to_deduct := NEW.charge_weight_lbs;
        v_alloc_total := 0;
        FOR v_lot IN
            SELECT cip.origin_purchase_id, cip.remaining_lbs, cip.coffee_source_id,
                   COALESCE(sr.date_received, cip.created_at::date) AS sort_date
              FROM public.coffee_inventory_purchased cip
              LEFT JOIN public.shipment_received sr ON sr.shipment_id = cip.shipment_id
             WHERE cip.origin = v_origin_id
               AND cip.facility_id = NEW.facility_id
               AND COALESCE(cip.remaining_lbs, 0) > 0
             ORDER BY
               CASE WHEN cip.coffee_source_id = NEW.coffee_source_id THEN 0 ELSE 1 END,
               COALESCE(sr.date_received, cip.created_at::date) ASC,
               cip.created_at ASC
        LOOP
            IF v_alloc_total >= v_lbs_to_deduct THEN EXIT; END IF;
            v_lbs_alloc := LEAST(v_lot.remaining_lbs, v_lbs_to_deduct - v_alloc_total);
            IF v_lbs_alloc <= 0 THEN CONTINUE; END IF;

            UPDATE public.coffee_inventory_purchased
               SET remaining_lbs = remaining_lbs - v_lbs_alloc
             WHERE origin_purchase_id = v_lot.origin_purchase_id;

            INSERT INTO public.roast_log_lot_consumption
                (roast_log_id, origin_purchase_id, lbs_consumed)
              VALUES (NEW.roast_log_id, v_lot.origin_purchase_id, v_lbs_alloc);

            v_alloc_total := v_alloc_total + v_lbs_alloc;
        END LOOP;

        PERFORM public.recalculate_origin_total_stock(v_origin_id, NEW.facility_id);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduct_from_lot_on_roast ON public.roast_log;
CREATE TRIGGER trg_deduct_from_lot_on_roast
  AFTER INSERT ON public.roast_log
  FOR EACH ROW
  EXECUTE FUNCTION public.deduct_from_lot_on_roast();


-- ── initialize_lot_remaining_lbs_on_receive ─────────────────────
CREATE OR REPLACE FUNCTION public.initialize_lot_remaining_lbs_on_receive()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_line record;
BEGIN
    -- Only fires when date_received transitions NULL → non-NULL.
    IF OLD.date_received IS NOT NULL OR NEW.date_received IS NULL THEN
        RETURN NEW;
    END IF;
    IF COALESCE(NEW.voided, false) = true THEN
        RETURN NEW;
    END IF;

    FOR v_line IN
        SELECT origin_purchase_id, origin, facility_id, amount
          FROM public.coffee_inventory_purchased
         WHERE shipment_id = NEW.shipment_id
           AND remaining_lbs IS NULL
    LOOP
        UPDATE public.coffee_inventory_purchased
           SET remaining_lbs = v_line.amount
         WHERE origin_purchase_id = v_line.origin_purchase_id;

        IF v_line.origin IS NOT NULL AND v_line.facility_id IS NOT NULL THEN
            PERFORM public.recalculate_origin_total_stock(v_line.origin, v_line.facility_id);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_init_lot_remaining_on_receive ON public.shipment_received;
CREATE TRIGGER trg_init_lot_remaining_on_receive
  AFTER UPDATE OF date_received ON public.shipment_received
  FOR EACH ROW
  EXECUTE FUNCTION public.initialize_lot_remaining_lbs_on_receive();


-- ── refresh_origin_total_on_lot_change ──────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_origin_total_on_lot_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.origin IS NOT NULL AND NEW.facility_id IS NOT NULL THEN
        PERFORM public.recalculate_origin_total_stock(NEW.origin, NEW.facility_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_origin_total_on_lot_change ON public.coffee_inventory_purchased;
CREATE TRIGGER trg_refresh_origin_total_on_lot_change
  AFTER UPDATE OF remaining_lbs ON public.coffee_inventory_purchased
  FOR EACH ROW
  WHEN (OLD.remaining_lbs IS DISTINCT FROM NEW.remaining_lbs)
  EXECUTE FUNCTION public.refresh_origin_total_on_lot_change();


-- ── Default require_coffee_source to 'on' for new tenants ───────
-- standard_parameters drives signup defaults. Existing tenants are
-- untouched (their company_parameters override stays in place).
UPDATE public.standard_parameters
   SET text_value = 'on'
 WHERE parameters_id = 'require_coffee_source'
   AND COALESCE(text_value, 'off') = 'off';

NOTIFY pgrst, 'reload schema';
