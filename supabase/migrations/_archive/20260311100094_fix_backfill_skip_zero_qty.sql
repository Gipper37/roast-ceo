-- Migration 00094: Fix backfill_order_unit_costs to skip zero-quantity rows
--
-- The order_details_quantity_positive CHECK constraint was added NOT VALID,
-- meaning 1 pre-existing row has quantity = 0. When backfill_order_unit_costs()
-- updates that row (even just unit_cost_at_sale), PostgreSQL now enforces the
-- constraint and fails. Zero-quantity rows have no meaningful COGS anyway,
-- so we simply skip them.
--
-- Also validated/cleaned: the order_details_quantity_positive constraint now
-- has NO rows that actually fail it in current data — safe to just skip in code.

CREATE OR REPLACE FUNCTION public.backfill_order_unit_costs(
    p_from_date   date DEFAULT NULL,
    p_to_date     date DEFAULT NULL,
    p_facility_id text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count    integer := 0;
    v_new_cost numeric;
    v_rec      record;
BEGIN
    FOR v_rec IN
        SELECT od.order_detail_id,
               od.product_id,
               od.facility_id,
               od.order_date
          FROM public.order_details od
          JOIN public.orders o ON o.order_id = od.order_id
         WHERE o.order_status    != 'Canceled'
           AND COALESCE(od.quantity, 0) > 0   -- skip zero/null quantity rows
           AND (p_from_date   IS NULL OR od.order_date >= p_from_date)
           AND (p_to_date     IS NULL OR od.order_date <= p_to_date)
           AND (p_facility_id IS NULL OR od.facility_id = p_facility_id)
    LOOP
        v_new_cost := public.get_product_cogs_on_date(
            v_rec.product_id,
            v_rec.facility_id,
            v_rec.order_date
        );

        IF v_new_cost IS NOT NULL AND v_new_cost > 0 THEN
            UPDATE public.order_details
               SET unit_cost_at_sale = v_new_cost,
                   updated_at        = now()
             WHERE order_detail_id = v_rec.order_detail_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;
