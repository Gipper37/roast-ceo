-- Reference-profile target anchors: add Second Crack (SC).
--
-- roast_sessions already carries the STRATA-owned target anchors for a
-- reference profile: fc_time_secs/fc_temp (first crack), dry_end_time_secs/
-- dry_end_temp, tp_time_secs/tp_temp (turning point). SC was missing — add it
-- so a profile can specify a target second-crack time + temp, matching the
-- other anchors' numeric type. Nullable (not every profile hits SC).

ALTER TABLE public.roast_sessions
  ADD COLUMN IF NOT EXISTS sc_time_secs numeric,
  ADD COLUMN IF NOT EXISTS sc_temp numeric;
