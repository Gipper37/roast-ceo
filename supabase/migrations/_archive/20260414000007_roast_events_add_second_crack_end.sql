-- Add second_crack_end to roast_events_event_type_check constraint.
-- The Roastmaster importer maps "Second Crack End" / "2C End" labels to
-- 'second_crack_end', but this value was missing from the allowed list,
-- causing those roasts to error during import.

ALTER TABLE roast_events
  DROP CONSTRAINT roast_events_event_type_check;

ALTER TABLE roast_events
  ADD CONSTRAINT roast_events_event_type_check CHECK (
    event_type = ANY (ARRAY[
      'charge'::text,
      'turning_point'::text,
      'yellowing'::text,
      'maillard'::text,
      'first_crack_start'::text,
      'first_crack_end'::text,
      'second_crack_start'::text,
      'second_crack_end'::text,
      'drop'::text,
      'cool_end'::text,
      'custom'::text
    ])
  );
