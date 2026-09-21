-- ALREADY WRITTEN AND UNAPPLIED, in the backend repo: 20260920000010_per_tenant_gateway_credentials, 20260920000011_a_key_to_connect_your_own_gateway, 20260920000012_a_webhook_delivery_knows_whose_it_is. These create provider_credentials. I confirmed on prod that to_regclass('public.provider_credentials') is null, so none of them has landed.
--
-- ORDER: 1 of 4. Migrations 2 and 3 below, and the frontend deploy. Migration 3 ALTERs the table 20260920000010 creates and will fail without it.

begin;

-- Nothing new to write. These three files exist in supabase/migrations/ and
-- are committed and unapplied. Apply them first: migration 3 below alters a
-- table 20260920000010 creates, and every gateway surface reads it.

commit;
