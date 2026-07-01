-- Performance indexes for hot query paths (perf audit 2026-06-30).
-- coffee_inventory_purchased is filtered by coffee_source_id (source enrichment)
-- and (company_id, facility_id); customers list scans by (company_id, facility_id).
CREATE INDEX IF NOT EXISTS idx_cip_coffee_source
  ON public.coffee_inventory_purchased (coffee_source_id);
CREATE INDEX IF NOT EXISTS idx_cip_company_facility
  ON public.coffee_inventory_purchased (company_id, facility_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_facility
  ON public.customers (company_id, facility_id);
