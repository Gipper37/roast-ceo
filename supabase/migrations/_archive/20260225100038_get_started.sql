-- Migration 00038: get_started table
-- Pre-signup "Get Started" dashboard content for users not yet in team

CREATE TABLE IF NOT EXISTS public.get_started (
    id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
    sort_order   INTEGER     NOT NULL,
    title        TEXT        NOT NULL,
    short_text   TEXT,
    detail_text  TEXT,
    image_url    TEXT,
    action_url   TEXT,
    action_label TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.get_started TO anon, authenticated, service_role;

INSERT INTO public.get_started (sort_order, title, short_text, detail_text, image_url, action_url, action_label) VALUES
    (1,
     'Welcome to RoastOS',
     'Manage your inventory, recipes, roasts, and orders — all in one place.',
     'Set up your roastery in minutes.',
     NULL,
     'https://pwpslalerytymorcodlv.supabase.co/functions/v1/company-signup',
     'Get Started');
