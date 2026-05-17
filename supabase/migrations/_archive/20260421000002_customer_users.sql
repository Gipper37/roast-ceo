-- ─────────────────────────────────────────────────────────────────────────────
-- customer_users — many PEOPLE per customer (business)
--
-- Replaces the prior 1:1 customers.auth_user_id model. A wholesale customer
-- (a business like Broth Bar Elixir) may now have multiple people who can
-- log in and place orders on its behalf.
--
-- Shape also degenerates cleanly to:
--   • B2C retail later (one row per shopper)
--   • per-user role-based perms ('admin' can invite colleagues, 'buyer' just
--     places orders) — not enforced yet but the column is here.
--
-- Lookups in the storefront change from
--     customers WHERE auth_user_id = $logged_in_user
-- to
--     customer_users WHERE auth_user_id = $logged_in_user → JOIN customers.
--
-- Greeting ("Hi, Tiffany") reads from customer_users.shop_display_name —
-- the personal name the user typed on the invite-accept form. The roaster's
-- customers.name_company stays as the business label and is no longer used
-- for the personal greeting.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.customer_users (
  customer_user_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id        text NOT NULL REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  auth_user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email              text NOT NULL,
  shop_display_name  text,
  role               text NOT NULL DEFAULT 'buyer',  -- 'admin' | 'buyer' (not enforced yet)
  invited_by         uuid,                           -- auth.users.id of who sent the invite
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         text,
  UNIQUE (customer_id, auth_user_id)
);

CREATE INDEX IF NOT EXISTS idx_customer_users_customer  ON public.customer_users (customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_users_auth_user ON public.customer_users (auth_user_id);
CREATE INDEX IF NOT EXISTS idx_customer_users_email     ON public.customer_users (lower(email));

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_updated_record') THEN
    EXECUTE 'CREATE TRIGGER trg_customer_users_updated
             BEFORE INSERT OR UPDATE ON public.customer_users
             FOR EACH ROW EXECUTE FUNCTION handle_updated_record()';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Migrate existing customers.auth_user_id rows into customer_users.
--
-- INNER JOIN auth.users so an orphan auth_user_id (deleted user, FK ghost)
-- doesn't violate the new FK. shop_display_name pulled from the prior auth
-- user metadata if it was set by the previous invite flow, else null.
-- All migrated users get role='admin' since they were the sole user on their
-- customer up to this point.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.customer_users (customer_id, auth_user_id, email, shop_display_name, role)
SELECT
  c.customer_id,
  c.auth_user_id,
  COALESCE(au.email, c.email, 'unknown@unknown')             AS email,
  au.raw_user_meta_data->>'display_name'                     AS shop_display_name,
  'admin'                                                     AS role
FROM public.customers c
JOIN auth.users au ON au.id = c.auth_user_id
WHERE c.auth_user_id IS NOT NULL
ON CONFLICT (customer_id, auth_user_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Add target_role to shop_invitations so the roaster can pre-pick the role
-- for the user being invited. App-side logic decides the default (admin if
-- this is the first invite for the customer, else buyer).
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.shop_invitations
  ADD COLUMN IF NOT EXISTS target_role text NOT NULL DEFAULT 'buyer';

-- ─────────────────────────────────────────────────────────────────────────────
-- Drop customers.auth_user_id — no longer the source of truth.
--
-- Safe within this migration's transaction: if the INSERT above failed for
-- any reason, this DROP also rolls back, so we never lose the link. Once
-- this commits, the only place auth_user_id lives for shop users is
-- customer_users.
-- ─────────────────────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_customers_auth_user_id;
ALTER TABLE public.customers DROP COLUMN IF EXISTS auth_user_id;
