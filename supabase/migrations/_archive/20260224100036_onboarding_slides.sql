-- Migration 00036: Create onboarding_slides table for the AppSheet Onboarding view
--
-- The AppSheet Onboarding view type maps its visual slots (title, body, detail)
-- to columns in a data table — one row per slide. This table provides that content.
--
-- Column → AppSheet slot mapping:
--   title       → Main header / slide title
--   short_text  → Short text (primary body)
--   detail_text → Short text 2 (secondary detail)
--   sort_order  → Row sort (controls slide sequence)
--
-- Global table (no company_id) — all companies see the same intro slides.

CREATE TABLE IF NOT EXISTS public.onboarding_slides (
    id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
    sort_order   INTEGER     NOT NULL,
    title        TEXT        NOT NULL,
    short_text   TEXT,
    detail_text  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.onboarding_slides IS
    'Content rows for the AppSheet Onboarding view. One row = one slide. Global — no company scope.';

-- Seed the three intro slides
INSERT INTO public.onboarding_slides (sort_order, title, short_text, detail_text) VALUES
    (1,
     'Welcome to Roast CEO',
     'Manage your inventory, recipes, roasts, and orders — all in one place.',
     'This quick tour will get you set up in minutes.'),
    (2,
     'Start with your inventory',
     'Add your green coffee inventory first. Then build a roast recipe from those beans.',
     'Everything downstream — roast batches, costs, orders — flows from your inventory.'),
    (3,
     'You''re ready to roast',
     'Tap Get Started to open the app.',
     'You can revisit this guide any time from the Settings menu.');
