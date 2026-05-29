-- ============================================================
-- channel: allow read of global rows (company_id IS NULL)
-- ============================================================
-- The existing tenant_company_access policy on `channel` is
--   USING (company_id IN (SELECT auth_company_ids()))
-- which hides every global row (NULL company_id) because NULL never
-- satisfies IN. Result: channelMap on the orders page renders empty
-- of globals, and lines fall back to showing raw channel UUIDs in
-- the dropdown.
--
-- The 4 globals (wholesale / retail / vip / sample) are intentionally
-- visible to every tenant, same model as customer_category. Add a
-- separate SELECT-only policy mirroring what we already do on
-- parts_catalog and maintenance_template — anyone authenticated can
-- read NULL-scoped rows, writes still require tenant ownership.
-- ============================================================

-- Idempotent: the policy was applied directly to prod when the
-- UUID-in-channel-dropdown bug was first surfaced, before this
-- migration existed. Guard the CREATE so re-running on prod is a no-op.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'catalog_read_global'
      AND polrelid = 'public.channel'::regclass
  ) THEN
    CREATE POLICY catalog_read_global ON public.channel
      FOR SELECT TO authenticated
      USING (company_id IS NULL);
  END IF;
END $$;
