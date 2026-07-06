-- Universal per-company sequential ORDER NUMBER. Every order (shop or manual)
-- gets a human-facing number on creation — distinct from invoice_number (which
-- only exists once an order is finalized into an invoice). Assigned by a BEFORE
-- INSERT trigger so ALL creation paths (order entry, standing orders, shop,
-- duplicate) get one automatically. Existing orders are backfilled chronologically.

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number bigint;
COMMENT ON COLUMN public.orders.order_number IS 'Per-company sequential order number, assigned on creation. The human-facing order reference (distinct from invoice_number, which only exists once finalized).';

-- Gap-free per-company counter (same ON CONFLICT row-lock idiom as shop_order_ref).
CREATE TABLE IF NOT EXISTS public.order_number_counter (
  company_id text PRIMARY KEY REFERENCES public.companies(company_id) ON DELETE CASCADE,
  next_value bigint NOT NULL DEFAULT 1
);
-- RLS on (deny direct API access, matching shop_order_ref_counter). The allocator
-- is SECURITY DEFINER so it can bump the counter regardless of caller grants.
ALTER TABLE public.order_number_counter ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.allocate_order_number(p_company_id text)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_next bigint;
BEGIN
  INSERT INTO public.order_number_counter (company_id, next_value)
    VALUES (p_company_id, 2)
  ON CONFLICT (company_id) DO UPDATE
    SET next_value = order_number_counter.next_value + 1
  RETURNING next_value - 1 INTO v_next;
  RETURN v_next;
END;
$$;

-- Assign on insert when not already set. NEW.company_id is validated by the order
-- INSERT's own RLS, so numbering the caller's company is safe.
CREATE OR REPLACE FUNCTION public.assign_order_number() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.order_number IS NULL AND NEW.company_id IS NOT NULL THEN
    NEW.order_number := public.allocate_order_number(NEW.company_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_order_number ON public.orders;
CREATE TRIGGER trg_assign_order_number BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.assign_order_number();

-- Backfill existing orders chronologically per company. session_replication_role
-- skips triggers for this bulk UPDATE — order_number affects no trigger logic, and
-- firing the metrics/audit triggers on ~14k rows would be needless churn.
SET session_replication_role = replica;
WITH numbered AS (
  SELECT order_id,
         row_number() OVER (PARTITION BY company_id
                            ORDER BY order_date NULLS FIRST, created_at NULLS FIRST, order_id) AS rn
  FROM public.orders
  WHERE company_id IS NOT NULL
)
UPDATE public.orders o SET order_number = n.rn FROM numbered n WHERE o.order_id = n.order_id;
SET session_replication_role = DEFAULT;

-- Seed each company's counter above its max so new orders continue cleanly.
INSERT INTO public.order_number_counter (company_id, next_value)
SELECT company_id, max(order_number) + 1
  FROM public.orders WHERE order_number IS NOT NULL AND company_id IS NOT NULL
 GROUP BY company_id
ON CONFLICT (company_id) DO UPDATE
  SET next_value = GREATEST(order_number_counter.next_value, EXCLUDED.next_value);

CREATE UNIQUE INDEX IF NOT EXISTS orders_company_order_number_uidx
  ON public.orders (company_id, order_number) WHERE order_number IS NOT NULL;

REVOKE ALL ON FUNCTION public.allocate_order_number(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.allocate_order_number(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
