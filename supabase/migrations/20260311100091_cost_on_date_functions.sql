-- Migration 00091: Point-in-time cost lookup functions
--
-- Three functions that reconstruct what a cost WOULD HAVE BEEN on a
-- given date, using the shipment history already in the database.
--
-- Used by:
--   - backfill_order_unit_costs()     (migration 00092) — on-demand backfill
--   - propagate_coffee_purchase_to_orders()   (00092) — auto-sweep on cost change
--   - propagate_consumable_purchase_to_orders() (00092) — same for consumables
--
-- Cost lookup priority (applied for both coffee and consumables):
--   1. Most recent received shipment WHERE date_received <= order_date
--      (exact historical match — the cost in effect when the order was placed)
--   2. Earliest received shipment (date_received IS NOT NULL)
--      (forward fallback — best approximation for pre-history orders)
--   3. fallback_cost / fallback_unit_cost on the inventory row
--      (user-entered baseline for origins/consumables with no shipment history)
--   4. Returns NULL → caller skips the update (never overwrites with 0)

-- ---------------------------------------------------------------------------
-- get_coffee_cost_on_date
--   Returns the roasting-loss-adjusted cost per lb for a given coffee origin
--   on a given date. Mirrors the recalculate_inventory_cost() formula.
--
--   Formula: (cost_lb + shipping_cost_unit) / retention_factor
--   Retention factor: company_parameters (facility-scoped) → standard_parameters → 0.82
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_coffee_cost_on_date(
    p_origin_id   text,
    p_facility_id text,
    p_order_date  date
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_retention     numeric;
    v_cost_lb       numeric;
    v_shipping_cost numeric;
BEGIN
    -- Retention factor (3-tier, mirrors recalculate_inventory_cost)
    SELECT value_number
      INTO v_retention
      FROM public.company_parameters
     WHERE parameter_id = '1de271df'
       AND facility_id  = p_facility_id
     LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
        SELECT amount
          INTO v_retention
          FROM public.standard_parameters
         WHERE parameters_id = '1de271df'
         LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
        v_retention := 0.82;
    END IF;

    -- Priority 1: Most recent received shipment on or before order date
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received <= p_order_date
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 2: Earliest received shipment (forward fallback for pre-history)
    SELECT cp.cost_lb, COALESCE(sr.shipping_cost_unit, 0)
      INTO v_cost_lb, v_shipping_cost
      FROM public.coffee_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.origin        = p_origin_id
       AND cp.facility_id   = p_facility_id
       AND cp.cost_lb        > 0
       AND sr.date_received IS NOT NULL
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost_lb IS NOT NULL THEN
        RETURN (v_cost_lb + v_shipping_cost) / v_retention;
    END IF;

    -- Priority 3: User-entered fallback cost
    -- NOTE: fallback_cost is already expected to be in roasted $/lb (loss-adjusted),
    -- matching what latest_cost stores. We do NOT divide by retention_factor here.
    RETURN (
        SELECT fallback_cost
          FROM public.coffee_inventory
         WHERE origin_id   = p_origin_id
           AND facility_id = p_facility_id
         LIMIT 1
    );
    -- Returns NULL if no fallback — caller will skip the update
END;
$$;


-- ---------------------------------------------------------------------------
-- get_consumable_cost_on_date
--   Returns the cost per unit for a given consumable on a given date.
--
--   p_consumable_id = consumable_inventory.consumable_inventory_id
--   (consumable_inventory_purchased.consumable_inventory_item stores this ID)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_consumable_cost_on_date(
    p_consumable_id text,
    p_facility_id   text,
    p_order_date    date
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_cost numeric;
BEGIN
    -- Priority 1: Most recent received shipment on or before order date
    SELECT cp.cost_unit
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
       AND sr.date_received             <= p_order_date
     ORDER BY sr.date_received DESC, cp.created_at DESC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN
        RETURN v_cost;
    END IF;

    -- Priority 2: Earliest received shipment (forward fallback for pre-history)
    SELECT cp.cost_unit
      INTO v_cost
      FROM public.consumable_inventory_purchased cp
      JOIN public.shipment_received sr ON sr.shipment_id = cp.shipment_id
     WHERE cp.consumable_inventory_item = p_consumable_id
       AND cp.facility_id               = p_facility_id
       AND cp.cost_unit                  > 0
       AND sr.date_received IS NOT NULL
     ORDER BY sr.date_received ASC, cp.created_at ASC
     LIMIT 1;

    IF v_cost IS NOT NULL THEN
        RETURN v_cost;
    END IF;

    -- Priority 3: User-entered fallback cost
    RETURN (
        SELECT fallback_unit_cost
          FROM public.consumable_inventory
         WHERE consumable_inventory_id = p_consumable_id
         LIMIT 1
    );
    -- Returns NULL if no fallback — caller will skip the update
END;
$$;


-- ---------------------------------------------------------------------------
-- get_product_cogs_on_date
--   Reconstructs the full unit COGS for a product as of a given date.
--
--   Formula mirrors update_product_total_cogs():
--     total = SUM(coffee_cost_on_date × percentage) × weight_lbs
--           + SUM(consumable_cost_on_date × quantity)
--
--   If a component returns NULL (no cost data at all, no fallback),
--   that component contributes 0 — a partial result is still better than
--   leaving the order at 0. Returns NULL only if weight_lbs is missing
--   AND there are no consumables with costs (nothing to compute).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_product_cogs_on_date(
    p_product_id  text,
    p_facility_id text,
    p_order_date  date
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_recipe_id       text;
    v_weight_lbs      numeric;
    v_coffee_cost     numeric := 0;
    v_consumable_cost numeric := 0;
    v_component_cost  numeric;
    v_rec             record;
    v_has_any_cost    boolean := false;
BEGIN
    -- Get recipe and weight for this product
    SELECT recipe_id, weight_lbs
      INTO v_recipe_id, v_weight_lbs
      FROM public.products
     WHERE product_id = p_product_id
     LIMIT 1;

    -- Coffee cost: SUM(cost_on_date × percentage) × weight_lbs
    IF v_recipe_id IS NOT NULL AND COALESCE(v_weight_lbs, 0) > 0 THEN
        FOR v_rec IN
            SELECT rc.coffee_item, rc.percentage
              FROM public.recipe_components rc
             WHERE rc.recipe_id   = v_recipe_id
               AND rc.facility_id = p_facility_id
        LOOP
            v_component_cost := public.get_coffee_cost_on_date(
                v_rec.coffee_item, p_facility_id, p_order_date
            );
            IF v_component_cost IS NOT NULL THEN
                v_coffee_cost  := v_coffee_cost + (v_component_cost * COALESCE(v_rec.percentage, 0));
                v_has_any_cost := true;
            END IF;
        END LOOP;
    END IF;

    -- Consumable cost: SUM(cost_on_date × quantity)
    FOR v_rec IN
        SELECT pc.consumable_id, pc.quantity
          FROM public.product_consumables pc
         WHERE pc.product_id   = p_product_id
           AND pc.facility_id  = p_facility_id
    LOOP
        v_component_cost := public.get_consumable_cost_on_date(
            v_rec.consumable_id, p_facility_id, p_order_date
        );
        IF v_component_cost IS NOT NULL THEN
            v_consumable_cost := v_consumable_cost + (v_component_cost * COALESCE(v_rec.quantity, 1));
            v_has_any_cost    := true;
        END IF;
    END LOOP;

    -- Return NULL if we found no cost data at all (nothing to update)
    IF NOT v_has_any_cost THEN
        RETURN NULL;
    END IF;

    RETURN (v_coffee_cost * COALESCE(v_weight_lbs, 0)) + v_consumable_cost;
END;
$$;
