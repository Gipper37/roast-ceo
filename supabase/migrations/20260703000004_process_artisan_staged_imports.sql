-- Staged bulk importer for Artisan .alog ROAST HISTORY (Slice 2c).
--
-- Mirrors process_staged_imports (Roastmaster) but for Artisan history roasts,
-- with two differences that matter at scale + for correctness:
--
--   1. TRIGGER SUPPRESSION. Importing ~10k historical roasts one INSERT at a
--      time would fire the roast_log FIFO/inventory recompute per row — an
--      O(n^2) meltdown. These roasts are all PRE-COUNT (history imported before
--      the operator sets counts), so the lot ledger already excludes them and
--      calculate_par reads roast_log directly. So we SET session_replication_role
--      = 'replica' for the batch: no FIFO recompute, no inventory churn. Safe
--      precisely because pre-count roasts must not move current stock.
--
--   2. ATTRIBUTION. Each payload carries a pre-resolved recipe_id (blend) or
--      origin_id (single) so the roast contributes to usage, or attribute=false
--      for history-only (curve kept, no roast_log, no usage). The create/link
--      resolution happens in TypeScript before staging.
--
-- Idempotent (dedup by the "Imported from Artisan (UID: ...)" notes tag) and
-- batched (caller loops until has_more=false). Returns created ids for revert.

CREATE OR REPLACE FUNCTION public.process_artisan_staged_imports(
  p_import_id   text,
  p_facility_id text,
  p_company_id  text,
  p_batch_size  integer DEFAULT 25
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row             RECORD;
  v_payload         jsonb;
  v_uid             text;
  v_session_id      text;
  v_new_log_id      text;
  v_started         timestamptz;
  v_attribute       boolean;
  v_recipe_id       text;
  v_origin_id       text;
  v_imported        int := 0;
  v_skipped         int := 0;
  v_attributed      int := 0;
  v_errors          text[] := '{}';
  v_session_ids     text[] := '{}';
  v_created_log_ids text[] := '{}';
  v_remaining       int;
BEGIN
  -- Suppress inventory/FIFO/audit triggers for this batch. Owner = postgres
  -- (SECURITY DEFINER) so this is permitted. Scoped to the function txn.
  SET LOCAL session_replication_role = 'replica';

  FOR v_row IN
    SELECT id, payload FROM staged_import_sessions
    WHERE import_id = p_import_id AND processed = false
    ORDER BY id
    LIMIT p_batch_size
  LOOP
    v_payload := v_row.payload;
    BEGIN
      v_uid := v_payload->>'artisan_uid';

      -- Dedup: this .alog already imported?
      IF EXISTS (
        SELECT 1 FROM roast_sessions
        WHERE facility_id = p_facility_id
          AND notes LIKE '%Imported from Artisan (UID: ' || v_uid || ')%'
        LIMIT 1
      ) THEN
        v_skipped := v_skipped + 1;
        UPDATE staged_import_sessions SET processed = true WHERE id = v_row.id;
        CONTINUE;
      END IF;

      v_started   := (v_payload->>'started_at')::timestamptz;
      v_attribute := COALESCE((v_payload->>'attribute')::boolean, false);
      v_recipe_id := NULLIF(v_payload->>'recipe_id', '');
      v_origin_id := NULLIF(v_payload->>'origin_id', '');
      v_session_id := gen_random_uuid()::text;

      -- 1) roast_sessions (curve holder + telemetry)
      INSERT INTO roast_sessions (
        session_id, facility_id, company_id, status,
        started_at, ended_at,
        green_weight_lbs, roasted_weight_lbs,
        recipe_id, origin_id, roaster_unit_id, profile_name, notes
      ) VALUES (
        v_session_id, p_facility_id, p_company_id, 'completed',
        v_started,
        COALESCE((v_payload->>'ended_at')::timestamptz, v_started),
        (v_payload->>'charge_weight_lbs')::numeric,
        (v_payload->>'roasted_weight_lbs')::numeric,
        v_recipe_id, v_origin_id,
        NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
        v_payload->>'profile_name',
        CASE
          WHEN COALESCE(v_payload->>'roast_notes','') <> ''
          THEN (v_payload->>'roast_notes') || E'\n\nImported from Artisan (UID: ' || v_uid || ')'
          ELSE 'Imported from Artisan (UID: ' || v_uid || ')'
        END
      );

      -- 2) roast_temp_nodes (the curve)
      IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
        INSERT INTO roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, company_id, recorded_at)
        SELECT v_session_id,
               (n->>'elapsed_secs')::numeric,
               (n->>'bt_temp')::numeric,
               (n->>'et_temp')::numeric,
               p_facility_id, p_company_id,
               v_started + ((n->>'elapsed_secs')::numeric * interval '1 second')
        FROM jsonb_array_elements(v_payload->'nodes') AS n;
      END IF;

      -- 3) roast_events (labels are already STRATA event_type values)
      IF v_payload->'events' IS NOT NULL AND jsonb_array_length(v_payload->'events') > 0 THEN
        INSERT INTO roast_events (session_id, elapsed_secs, event_type, facility_id, company_id)
        SELECT v_session_id, (e->>'elapsed_secs')::numeric, e->>'label', p_facility_id, p_company_id
        FROM jsonb_array_elements(v_payload->'events') AS e;
      END IF;

      -- 4) roast_log — ONLY when attributed (drives usage). History-only roasts
      --    get the curve above but no roast_log, so zero usage + zero stock.
      IF v_attribute AND (v_recipe_id IS NOT NULL OR v_origin_id IS NOT NULL)
         AND COALESCE((v_payload->>'charge_weight_lbs')::numeric, 0) > 0 THEN
        v_new_log_id := gen_random_uuid()::text;
        INSERT INTO roast_log (
          roast_log_id, session_id, recipe_id, origin_id,
          charge_weight_lbs, roasted_weight,
          roast_date, roast_date_utc, "charged?",
          roaster_unit_id, profile_name, external_roast_id,
          facility_id, company_id
        ) VALUES (
          v_new_log_id, v_session_id, v_recipe_id, v_origin_id,
          (v_payload->>'charge_weight_lbs')::numeric,
          (v_payload->>'roasted_weight_lbs')::numeric,
          v_started, v_started, true,
          NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
          v_payload->>'profile_name',
          NULLIF(v_payload->>'external_roast_id', ''),
          p_facility_id, p_company_id
        );
        v_created_log_ids := array_append(v_created_log_ids, v_new_log_id);
        v_attributed := v_attributed + 1;
      END IF;

      v_session_ids := array_append(v_session_ids, v_session_id);
      v_imported := v_imported + 1;

    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'uid=' || COALESCE(v_uid,'?') || ': ' || SQLERRM);
    END;

    UPDATE staged_import_sessions SET processed = true WHERE id = v_row.id;
  END LOOP;

  SELECT COUNT(*) INTO v_remaining
  FROM staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  RETURN jsonb_build_object(
    'has_more',        v_remaining > 0,
    'batch_processed', v_imported + v_skipped,
    'imported',        v_imported,
    'attributed',      v_attributed,
    'skipped',         v_skipped,
    'errors',          v_errors,
    'session_ids',     to_jsonb(v_session_ids),
    'created_log_ids', to_jsonb(v_created_log_ids)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.process_artisan_staged_imports(text, text, text, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.process_artisan_staged_imports(text, text, text, integer) TO authenticated, service_role;
