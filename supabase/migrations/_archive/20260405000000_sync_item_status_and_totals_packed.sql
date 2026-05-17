-- Trigger: when orders.order_status changes, sync order_details.item_status
CREATE OR REPLACE FUNCTION sync_item_status_on_order_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.order_status = 'Packed' AND OLD.order_status <> 'Packed' THEN
    UPDATE order_details
    SET item_status = 'Packed'
    WHERE order_id = NEW.order_id;
  ELSIF NEW.order_status IN ('Open', 'Delivered', 'Canceled') AND OLD.order_status = 'Packed' THEN
    UPDATE order_details
    SET item_status = 'Open'
    WHERE order_id = NEW.order_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_item_status_on_order_status
  AFTER UPDATE OF order_status ON orders
  FOR EACH ROW
  WHEN (OLD.order_status IS DISTINCT FROM NEW.order_status)
  EXECUTE FUNCTION sync_item_status_on_order_status_change();

-- Update totals view: packed_qty now uses item_status instead of order_status
-- so partial packing shows up
CREATE OR REPLACE VIEW totals AS
  WITH facility_params AS (
      SELECT f.facility_id,
         f.company_id,
         COALESCE(NULLIF(f.time_zone, ''), 'Pacific/Honolulu') AS timezone,
         COALESCE(
           (SELECT cp.value_number::integer FROM company_parameters cp
            WHERE cp.parameter_id = 'orders_reset_day' AND cp.facility_id = f.facility_id LIMIT 1),
           (SELECT sp.amount::integer FROM standard_parameters sp
            WHERE sp.parameters_id = 'orders_reset_day' LIMIT 1),
           6
         ) AS orders_reset_day
      FROM facilities f
  ), calc AS (
      SELECT fp.facility_id, fp.company_id, fp.timezone,
         (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date
           - ((EXTRACT(dow FROM (CURRENT_TIMESTAMP AT TIME ZONE fp.timezone)::date)::integer
               - fp.orders_reset_day + 7) % 7) AS orders_week_start
      FROM facility_params fp
  ), product_facility AS (
      SELECT p.product_id, f.facility_id, f.company_id
      FROM products p
      JOIN facilities f ON p.company_id = f.company_id
        AND (p.facility_id IS NULL OR p.facility_id = f.facility_id)
  )
  SELECT
    (pf.product_id || '-') || pf.facility_id AS totals_id,
    pf.product_id, pf.facility_id, pf.company_id,
    -- This Week: non-canceled orders placed since week reset
    COALESCE((
      SELECT sum(od.quantity) FROM order_details od
      JOIN orders o ON od.order_id = o.order_id
      WHERE od.product_id = pf.product_id
        AND o.order_date >= c.orders_week_start
        AND o.facility_id = pf.facility_id
        AND o.order_status <> 'Canceled'
    ), 0) AS total,
    -- Left to Pack: all open orders, any date
    COALESCE((
      SELECT sum(od.quantity) FROM order_details od
      JOIN orders o ON od.order_id = o.order_id
      WHERE od.product_id = pf.product_id
        AND o.order_status = 'Open'
        AND o.facility_id = pf.facility_id
    ), 0) AS left_to_pack,
    -- Backlog: open orders before this week
    COALESCE((
      SELECT sum(od.quantity) FROM order_details od
      JOIN orders o ON od.order_id = o.order_id
      WHERE od.product_id = pf.product_id
        AND o.order_date < c.orders_week_start
        AND o.order_status = 'Open'
        AND o.facility_id = pf.facility_id
    ), 0) AS open_backlog,
    -- Packed: uses item_status so partial packing counts
    COALESCE((
      SELECT sum(od.quantity) FROM order_details od
      JOIN orders o ON od.order_id = o.order_id
      WHERE od.product_id = pf.product_id
        AND od.item_status = 'Packed'
        AND o.order_date >= c.orders_week_start
        AND o.facility_id = pf.facility_id
        AND o.order_status <> 'Canceled'
    ), 0) AS packed_qty,
    -- Delivered: order_status = Delivered, this week
    COALESCE((
      SELECT sum(od.quantity) FROM order_details od
      JOIN orders o ON od.order_id = o.order_id
      WHERE od.product_id = pf.product_id
        AND o.order_status = 'Delivered'
        AND o.order_date >= c.orders_week_start
        AND o.facility_id = pf.facility_id
    ), 0) AS delivered_qty,
    -- Avg/Week: 6-week rolling average before this week
    COALESCE((
      SELECT avg(sub.weekly_sum) FROM (
        SELECT sum(od2.quantity) AS weekly_sum
        FROM order_details od2
        JOIN orders o2 ON od2.order_id = o2.order_id
        WHERE od2.product_id = pf.product_id
          AND o2.order_date >= (c.orders_week_start - interval '42 days')
          AND o2.order_date < c.orders_week_start
          AND o2.facility_id = pf.facility_id
          AND o2.order_status <> 'Canceled'
        GROUP BY date_trunc('week', o2.order_date::timestamptz)
      ) sub
    ), 0) AS recent_avg_week
  FROM product_facility pf
  JOIN calc c ON c.facility_id = pf.facility_id;
