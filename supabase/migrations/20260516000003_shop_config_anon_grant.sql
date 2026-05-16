-- Fix: my prior public_read_enabled RLS policy on shop_config was
-- a no-op because the anon role has no base SELECT grant on the
-- table. RLS only runs AFTER Postgres-level grants — without GRANT
-- SELECT TO anon, the query returns "permission denied for table
-- shop_config" before RLS even evaluates.
--
-- Granting SELECT to anon (alongside the existing public_read_enabled
-- policy from 20260516000002) gives anon visitors read access to
-- enabled shops. Write privileges (INSERT/UPDATE/DELETE) are still
-- anon-blocked because anon has no grant for those, AND the
-- tenant_company_access policy gates them anyway.

GRANT SELECT ON public.shop_config TO anon;
