-- Migration 00035: Add onboarding tracking columns to the team table
-- These enable AppSheet to detect new users and show a welcome/onboarding screen.
--
--   onboarding_completed  — AppSheet reads this to decide whether to show the Welcome view
--   first_app_open_at     — set when the user clicks "Get Started" in AppSheet; useful for analytics

ALTER TABLE public.team
  ADD COLUMN IF NOT EXISTS onboarding_completed  BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS first_app_open_at     TIMESTAMPTZ;

COMMENT ON COLUMN public.team.onboarding_completed IS
  'Set to TRUE when the user dismisses the AppSheet welcome/onboarding screen via the Get Started action.';
COMMENT ON COLUMN public.team.first_app_open_at IS
  'Timestamp of first Get Started action in AppSheet. NULL means the user has never completed onboarding.';
