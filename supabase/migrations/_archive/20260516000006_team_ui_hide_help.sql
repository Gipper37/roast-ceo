-- Per-operator preference: hide all in-app help/info tooltips.
-- Site-wide toggle controlled from the Configuration page. Stored
-- on team (per-user) so each operator on the same company can pick
-- their own visibility independently. Defaults to false (tooltips on).

ALTER TABLE public.team
  ADD COLUMN IF NOT EXISTS ui_hide_help boolean NOT NULL DEFAULT false;
