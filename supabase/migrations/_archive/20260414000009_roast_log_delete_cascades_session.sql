-- When a roast_log row is deleted, also delete its associated roast_session.
-- roast_temp_nodes and roast_events already CASCADE from roast_sessions,
-- so this one trigger gives us the full chain:
--   roast_log DELETE → roast_sessions DELETE → roast_temp_nodes + roast_events DELETE

CREATE OR REPLACE FUNCTION trg_delete_session_on_log_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.session_id IS NOT NULL THEN
    DELETE FROM public.roast_sessions WHERE session_id = OLD.session_id;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_cascade_delete_session ON public.roast_log;

CREATE TRIGGER trg_cascade_delete_session
  AFTER DELETE ON public.roast_log
  FOR EACH ROW
  EXECUTE FUNCTION trg_delete_session_on_log_delete();
