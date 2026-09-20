-- roast_recipes.roast_type defaults to a value its own CHECK forbids.
--
-- Migration 20260502000002 split the single 'Single Origin/Post-Blend' value
-- into three -- 'Single Origin', 'Post-Blend', 'Pre-Blend' -- backfilled the
-- rows, and added
--
--     CHECK (roast_type = ANY (ARRAY['Single Origin','Post-Blend','Pre-Blend']))
--
-- but never touched the column DEFAULT, which is still the pre-split string.
-- So any INSERT that omits roast_type evaluates the default to a value the
-- CHECK rejects and fails outright:
--
--     column_default: 'Single Origin/Post-Blend'::text
--
-- Nothing hits it today. All three app writers -- createRecipe, addRecipe in
-- company/actions and addRecipe in roast/actions -- pass roast_type
-- explicitly. But `authenticated` holds INSERT on this table through
-- PostgREST, so the trap is one omitted field away for any integration, and
-- the failure would read as a mystifying constraint violation rather than a
-- missing column.
--
-- 'Single Origin' is the right default: it is what all three writers already
-- fall back to, and it is the only one of the three that is meaningful for a
-- recipe with no components yet.

begin;

alter table public.roast_recipes alter column roast_type set default 'Single Origin';

commit;
