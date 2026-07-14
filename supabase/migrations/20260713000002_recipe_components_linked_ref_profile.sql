-- recipe_components.reference_profile_session_id — the component's LINKED
-- (standard) reference profile.
--
-- Points at a profile template: roast_sessions row with is_profile_template =
-- true (the rows behind the Roast Profiles page). Loose ON DELETE SET NULL FK
-- so deleting a template never blocks and simply unlinks the components that
-- referenced it.
--
-- The linked profile has THREE jobs (design settled 2026-07-13):
--   1. PLAN/LFP MERGE KEY — future (projected) roasts of the same green merge
--      into one shared roast ONLY when their components carry the SAME linked
--      profile. NULL → standalone (its own roast). Opt-in, explicit — the
--      planner never infers sharing from roast history.
--   2. AUTO-LOAD — pre-fills the roast session's reference profile at charge
--      time (a duplicated roast's carried profile, or a manual change at
--      roast time, overrides it). Whatever is on the session at charge is the
--      truth for that executed roast.
--   3. FALLBACK — profile-of-record only when a session is charged with no
--      reference profile at all.
--
-- Per-component (not per-recipe) because two blends can roast their shared
-- component (e.g. Chocolate) on the same curve — same link, one shared roast —
-- while the rest of each blend differs. A single-origin recipe has exactly one
-- component, so its component link IS the recipe's standard.
--
-- Types: text to match session_id (all STRATA ids are text). No index — the
-- table is small (hundreds of rows) and the column is read via full recipe
-- fetches, never filtered server-side.

ALTER TABLE public.recipe_components
  ADD COLUMN IF NOT EXISTS reference_profile_session_id text
  REFERENCES public.roast_sessions(session_id) ON DELETE SET NULL;
