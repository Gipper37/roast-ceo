-- PL/pgSQL function to process staged Roastmaster import sessions.
-- Runs entirely inside Postgres — no HTTP, no Vercel, no timeout issues.
-- Called via supabase.rpc('process_staged_imports', { p_import_id, p_facility_id, ... })

CREATE OR REPLACE FUNCTION process_staged_imports(
  p_import_id text,
  p_facility_id text,
  p_company_id text,
  p_create_roast_log_entries boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SET statement_timeout TO '600s'  -- 10 minutes
AS $$
DECLARE
  v_row RECORD;
  v_payload jsonb;
  v_session_id text;
  v_imported int := 0;
  v_linked int := 0;
  v_skipped int := 0;
  v_profiles_imported int := 0;
  v_profiles_skipped int := 0;
  v_errors text[] := '{}';
  v_total int := 0;
  v_node RECORD;
  v_event RECORD;
  v_log_id text;
  v_existing_count int;
BEGIN
  -- Count total to process
  SELECT COUNT(*) INTO v_total
  FROM staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  IF v_total = 0 THEN
    -- Nothing to process — mark complete
    UPDATE roastmaster_imports SET
      status = 'completed', completed_at = now()
    WHERE import_id = p_import_id;
    RETURN jsonb_build_object('imported', 0, 'skipped', 0, 'linked', 0, 'profiles_imported', 0);
  END IF;

  -- Process each staged row
  FOR v_row IN
    SELECT id, payload FROM staged_import_sessions
    WHERE import_id = p_import_id AND processed = false
    ORDER BY id
  LOOP
    v_payload := v_row.payload;

    BEGIN  -- exception block per row

      IF v_payload->>'type' = 'profile_template' THEN
        -- ═══ Profile Template ═══
        -- Duplicate check
        SELECT COUNT(*) INTO v_existing_count
        FROM roast_sessions
        WHERE facility_id = p_facility_id
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_profiles_skipped := v_profiles_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at, roaster_unit_id, profile_name,
            is_profile_template, notes
          ) VALUES (
            v_session_id, p_facility_id, p_company_id, 'completed',
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            (v_payload->>'roaster_unit_id')::uuid,
            v_payload->>'name',
            true,
            'Profile template imported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
          );

          -- Insert temp nodes
          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              p_facility_id,
              now()
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          v_profiles_imported := v_profiles_imported + 1;
        END IF;

      ELSE
        -- ═══ Regular Session ═══
        -- Duplicate check
        SELECT COUNT(*) INTO v_existing_count
        FROM roast_sessions
        WHERE facility_id = p_facility_id
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_skipped := v_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at,
            green_weight_lbs, roasted_weight_lbs,
            charge_weight_id, origin_id, roaster_unit_id, profile_name,
            agtron_color, ambient_temp, ambient_humidity,
            post_moisture, post_density, roast_degree, rating,
            notes
          ) VALUES (
            v_session_id, p_facility_id, p_company_id, 'completed',
            (v_payload->>'started_at')::timestamptz,
            COALESCE((v_payload->>'ended_at')::timestamptz, (v_payload->>'started_at')::timestamptz),
            (v_payload->>'charge_weight_lbs')::numeric,
            (v_payload->>'roasted_weight_lbs')::numeric,
            v_payload->>'charge_weight_id',
            v_payload->>'origin_id',
            (v_payload->>'roaster_unit_id')::uuid,
            v_payload->>'profile_name',
            (v_payload->>'agtron_color')::numeric,
            (v_payload->>'ambient_temp')::numeric,
            (v_payload->>'ambient_humidity')::numeric,
            (v_payload->>'post_moisture')::numeric,
            (v_payload->>'post_density')::numeric,
            v_payload->>'roast_degree',
            (v_payload->>'rating')::integer,
            CASE
              WHEN v_payload->>'roast_notes' IS NOT NULL AND v_payload->>'roast_notes' != ''
              THEN (v_payload->>'roast_notes') || E'\n\nImported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
              ELSE 'Imported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
            END
          );

          -- Insert temp nodes (bulk from JSONB array)
          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              p_facility_id,
              (v_payload->>'started_at')::timestamptz + ((n->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          -- Insert events
          IF v_payload->'events' IS NOT NULL AND jsonb_array_length(v_payload->'events') > 0 THEN
            INSERT INTO roast_events (session_id, elapsed_secs, event_type, label, facility_id, recorded_at)
            SELECT
              v_session_id,
              (e->>'elapsed_secs')::numeric,
              CASE lower(trim(e->>'label'))
                WHEN 'first crack' THEN 'first_crack_start'
                WHEN '1c start' THEN 'first_crack_start'
                WHEN 'first crack start' THEN 'first_crack_start'
                WHEN 'first crack end' THEN 'first_crack_end'
                WHEN '1c end' THEN 'first_crack_end'
                WHEN 'second crack' THEN 'second_crack_start'
                WHEN '2c start' THEN 'second_crack_start'
                WHEN 'second crack start' THEN 'second_crack_start'
                WHEN 'second crack end' THEN 'second_crack_end'
                WHEN 'turning point' THEN 'turning_point'
                WHEN 'charge' THEN 'charge'
                WHEN 'drop' THEN 'drop'
                WHEN 'yellowing' THEN 'yellowing'
                WHEN 'maillard' THEN 'maillard'
                ELSE 'custom'
              END,
              e->>'label',
              p_facility_id,
              (v_payload->>'started_at')::timestamptz + ((e->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'events') AS e;
          END IF;

          -- Roast log linkage
          IF v_payload->>'roast_log_id' IS NOT NULL AND v_payload->>'roast_log_id' != '' THEN
            UPDATE roast_log SET session_id = v_session_id
            WHERE roast_log_id = v_payload->>'roast_log_id';
            IF v_payload->>'coffee_source_id' IS NOT NULL AND v_payload->>'coffee_source_id' != '' THEN
              UPDATE roast_log SET coffee_source_id = v_payload->>'coffee_source_id'
              WHERE roast_log_id = v_payload->>'roast_log_id';
            END IF;
            v_linked := v_linked + 1;
          ELSIF p_create_roast_log_entries AND COALESCE((v_payload->>'create_log_entry')::boolean, true) THEN
            INSERT INTO roast_log (
              roast_log_id, origin_id, coffee_source_id,
              charge_weight, charge_weight_lbs,
              roast_date, "charged?", roaster_unit_id, session_id,
              measured_roasted_weight, profile_name,
              facility_id, company_id
            ) VALUES (
              gen_random_uuid()::text,
              v_payload->>'origin_id',
              NULLIF(v_payload->>'coffee_source_id', ''),
              v_payload->>'charge_weight_id',
              (v_payload->>'charge_weight_lbs')::numeric,
              ((v_payload->>'started_at')::timestamptz)::date,
              true,
              (v_payload->>'roaster_unit_id')::uuid,
              v_session_id,
              (v_payload->>'roasted_weight_lbs')::numeric,
              v_payload->>'profile_name',
              p_facility_id,
              p_company_id
            );
          END IF;

          v_imported := v_imported + 1;
        END IF;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'rm_pk=' || COALESCE(v_payload->>'rm_pk', '?') || ': ' || SQLERRM);
    END;

    -- Mark row as processed
    UPDATE staged_import_sessions SET processed = true WHERE id = v_row.id;

    -- Progress is written on completion (function runs in single transaction)

  END LOOP;

  -- Final update
  UPDATE roastmaster_imports SET
    status = 'completed',
    completed_at = now(),
    sessions_imported = v_imported,
    sessions_linked = v_linked,
    sessions_skipped = v_skipped,
    profiles_imported = v_profiles_imported,
    profiles_skipped = v_profiles_skipped,
    error_count = COALESCE(array_length(v_errors, 1), 0),
    errors = to_jsonb(v_errors[1:50])
  WHERE import_id = p_import_id;

  -- Clean up staging table
  DELETE FROM staged_import_sessions WHERE import_id = p_import_id;

  RETURN jsonb_build_object(
    'imported', v_imported,
    'linked', v_linked,
    'skipped', v_skipped,
    'profiles_imported', v_profiles_imported,
    'profiles_skipped', v_profiles_skipped,
    'errors', array_length(v_errors, 1)
  );
END;
$$;
