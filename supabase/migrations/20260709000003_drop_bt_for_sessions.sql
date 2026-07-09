-- drop_bt_for_sessions — the CORRECT drop (end) bean temp per session, for the
-- roast-log / All-Roasts "time @ temp" column.
--
-- For a STREAMING roast, SMARTroast auto-detects the drop AFTER the fact and
-- marks the drop event at the peak TIME (highest BT before the cool-down cliff).
-- The event's TIME is right, but roast_events.bt_at_event is captured at
-- DETECTION time (already sliding down the cliff) → the stored temp is wrong
-- (e.g. real drop 422°F, bt_at_event = 337). The graph already avoids this by
-- reading the BT off the curve at the drop time; this gives the table the same
-- value: bt_temp of the last node at-or-before the drop event's elapsed_secs.
--
-- SECURITY INVOKER (default) + STABLE: RLS on roast_temp_nodes/roast_events
-- applies as the caller, so a user only resolves their own sessions.

CREATE OR REPLACE FUNCTION public.drop_bt_for_sessions(p_session_ids text[])
RETURNS TABLE(session_id text, drop_bt numeric)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT ON (n.session_id)
         n.session_id,
         n.bt_temp::numeric
  FROM public.roast_temp_nodes n
  JOIN public.roast_events e
    ON e.session_id = n.session_id AND e.event_type = 'drop'
  WHERE n.session_id = ANY(p_session_ids)
    AND n.bt_temp IS NOT NULL
    AND n.elapsed_secs <= e.elapsed_secs
  ORDER BY n.session_id, n.elapsed_secs DESC;
$$;

GRANT EXECUTE ON FUNCTION public.drop_bt_for_sessions(text[]) TO authenticated, service_role;
