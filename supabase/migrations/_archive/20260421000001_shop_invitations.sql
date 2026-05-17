-- ─────────────────────────────────────────────────────────────────────────────
-- shop_invitations — wholesale shop invite tokens (our own table, mirrors the
-- employee `invitations` flow).
--
-- Why a new table instead of reusing `invitations`: the employee invitations
-- table joins to `team` semantics (role_id, facility_id) that don't apply to
-- shop customers. Cleaner to keep them separate than overload one table.
--
-- Workflow:
--   1. Roaster clicks "Invite" → sendShopInvite() inserts a row here with a
--      fresh UUID token, then sends a Resend email with link
--      https://www.strataroast.com/<slug>/invite/<token>
--   2. Customer clicks the link → public page at /<slug>/invite/[token]/page.tsx
--      collects name + password.
--   3. POST /api/shop-invite/accept validates token, calls
--      auth.admin.createUser({email, password, email_confirm: true}), links
--      the new auth_user_id onto customers, marks accepted_at.
--   4. Customer logs in normally at /<slug>/login.
--
-- Critically: NO auth.users row is created at invite time. That eliminates
-- the entire class of "stale half-created user" bugs we kept hitting with
-- supabase.auth.admin.generateLink({type:'invite'}).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.shop_invitations (
  invitation_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token           uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  customer_id     text NOT NULL REFERENCES public.customers(customer_id) ON DELETE CASCADE,
  company_id      text NOT NULL,
  slug            text NOT NULL,
  invited_email   text NOT NULL,
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  accepted_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      text
);

CREATE INDEX IF NOT EXISTS idx_shop_invitations_token       ON public.shop_invitations (token);
CREATE INDEX IF NOT EXISTS idx_shop_invitations_customer    ON public.shop_invitations (customer_id);
CREATE INDEX IF NOT EXISTS idx_shop_invitations_company     ON public.shop_invitations (company_id);
CREATE INDEX IF NOT EXISTS idx_shop_invitations_email_open  ON public.shop_invitations (invited_email) WHERE accepted_at IS NULL;

-- Standard updated_at trigger if your project has one (mirror existing pattern).
-- Most tables in this DB use handle_updated_record() — wire it up here too.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_updated_record') THEN
    EXECUTE 'CREATE TRIGGER trg_shop_invitations_updated
             BEFORE INSERT OR UPDATE ON public.shop_invitations
             FOR EACH ROW EXECUTE FUNCTION handle_updated_record()';
  END IF;
END $$;
