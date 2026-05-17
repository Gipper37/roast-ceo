-- Remove the open "all authenticated users" policy on product_consumables.
-- This table has RLS enabled; with no policies it behaves like every other
-- tenant table — browser/anon reads return nothing, service_role reads work.
-- The open policy was a vulnerability allowing any authenticated user to
-- read or modify any company's product bill-of-materials.

DROP POLICY IF EXISTS "Enable all access for authenticated users" ON product_consumables;
