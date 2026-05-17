-- Trigger: when a new auth.users row is created (invite accepted, signup, etc.)
-- automatically link it to the matching team record by email.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.team
  SET auth_user_id = NEW.id
  WHERE email = NEW.email
    AND auth_user_id IS NULL;
  RETURN NEW;
END;
$$;

-- Drop if exists (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

-- Backfill: link any existing auth.users rows to team records that are still NULL
UPDATE public.team t
SET auth_user_id = u.id
FROM auth.users u
WHERE u.email = t.email
  AND t.auth_user_id IS NULL;
