-- A helper any member could call now asks who is calling; the Roastmaster import works again.
--
-- The adversarial pass listed the SECURITY DEFINER functions `authenticated`
-- may execute whose bodies never look at the caller. Each falls into one of
-- three bins here:
--
--   1. Called only from other SECURITY DEFINER functions, or from cron. Inside
--      a definer function the caller is the owner, so no grant to
--      `authenticated` was ever needed — it just made the helper reachable by
--      RPC. Revoked: _attribute_unsourced_for_origin, next_recall_reference,
--      terminal_policy, company_has_feature, expire_terminal_sessions,
--      recompute_lot_shortfall_all. Seven trigger bodies likewise; a trigger
--      fires whether or not the invoking role may execute its function
--      (checked on staging before writing this).
--   2. Called by an INVOKER trigger as the person writing the row, or by the
--      app. These keep their grant and get the check: if a JWT is present, the
--      company acted on must be one of the caller's — and for the app-called
--      write, the permission the app requires. allocate_order_number
--      (assign_order_number trigger) advanced Maui Coffee Roasters' invoice
--      counter for a demo-only admin during the pass; set_roast_measured_weight
--      (the post-roast card) rewrote one of their roast weights.
--   3. process_staged_imports — the Roastmaster import. Broken on prod since
--      May: it still UPDATEs roastmaster_imports, renamed to data_imports, so
--      every call rolled back (which is also why its unchecked p_company_id
--      never hurt anyone). Rewritten: the data_imports row decides the tenant,
--      the caller must belong to it and hold config.import_data, the counters
--      land on data_imports. Its sibling process_artisan_staged_imports has no
--      caller and names a table that does not exist; dropped.
--
-- Prod today: 0 rows anywhere that these checks would have refused.

begin;

-- ── 1. helpers nobody outside the database calls ──────────────────────────
revoke execute on function public._attribute_unsourced_for_origin(text, text, text, date) from authenticated;
revoke execute on function public.next_recall_reference(text, text)                          from authenticated;
revoke execute on function public.terminal_policy(text)                                      from authenticated;
revoke execute on function public.company_has_feature(text, text)                            from authenticated;
revoke execute on function public.expire_terminal_sessions()                                 from authenticated;
revoke execute on function public.recompute_lot_shortfall_all(text)                          from authenticated;
-- trigger bodies
revoke execute on function public.config_audit_row()                      from authenticated;
revoke execute on function public.handle_new_auth_user()                  from authenticated;
revoke execute on function public.process_company_signup()                from authenticated;
revoke execute on function public.propagate_price_log_to_orders()         from authenticated;
revoke execute on function public.stamp_trace_start_on_module_enable()    from authenticated;
revoke execute on function public.sync_product_price_from_log()           from authenticated;
revoke execute on function public.trg_roast_log_tombstone()               from authenticated;

-- ── 2. helpers that ask who is calling ────────────────────────────────────
create or replace function public.allocate_order_number(p_company_id text)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_next bigint;
begin
  -- The trigger on orders calls this as the person inserting the order; RLS
  -- has already pinned NEW.company_id to theirs. By RPC it was anyone's.
  if auth.uid() is not null and p_company_id not in (select public.auth_company_ids()) then
    raise exception 'That company is not yours.' using errcode = 'insufficient_privilege';
  end if;
  insert into public.order_number_counter (company_id, next_value)
    values (p_company_id, 2)
  on conflict (company_id) do update
    set next_value = order_number_counter.next_value + 1
  returning next_value - 1 into v_next;
  return v_next;
end;
$$;

create or replace function public.attribute_after_stock_event(p_company_id text, p_facility_id text, p_origin_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and p_company_id not in (select public.auth_company_ids()) then
    raise exception 'That company is not yours.' using errcode = 'insufficient_privilege';
  end if;
  -- Cheap guard: almost every stock event touches an origin with nothing open.
  if not exists (
    select 1 from public.roast_lot_shortfall
     where company_id = p_company_id and facility_id = p_facility_id
       and origin_id = p_origin_id and waived_at is null
     limit 1) then
    return;
  end if;
  perform public._attribute_unsourced_for_origin(p_company_id, p_facility_id, p_origin_id, null);
end;
$$;

create or replace function public.set_roast_measured_weight(p_roast_log_id text, p_measured_weight numeric)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company    text;
  v_session_id text;
begin
  select company_id into v_company from public.roast_log where roast_log_id = p_roast_log_id;
  if not found then
    raise exception 'That roast does not exist.' using errcode = 'no_data_found';
  end if;
  -- Weighing a roast is part of logging it: the same key the logger holds.
  if auth.uid() is not null and (
       v_company not in (select public.auth_company_ids())
    or not public.auth_has_permission('roast.log', v_company)) then
    raise exception 'You may not record a weight for that roast.' using errcode = 'insufficient_privilege';
  end if;

  update public.roast_log
     set measured_roasted_weight = p_measured_weight
   where roast_log_id = p_roast_log_id
  returning session_id into v_session_id;

  -- Mirror onto the linked session so downstream queries that read from
  -- roast_sessions (reports, AppSheet, etc.) see the same value.
  if v_session_id is not null then
    update public.roast_sessions
       set roasted_weight_lbs = p_measured_weight
     where session_id = v_session_id;
  end if;
end;
$$;

-- ── 3. the Roastmaster import ─────────────────────────────────────────────
drop function if exists public.process_staged_imports(text, text, text, boolean, integer);
drop function if exists public.process_artisan_staged_imports(text, text, text, integer);

create or replace function public.process_staged_imports(p_import_id text, p_create_roast_log_entries boolean default true, p_batch_size integer default 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_import            public.data_imports%ROWTYPE;
  v_company           text;
  v_facility          text;
  v_row               RECORD;
  v_payload           jsonb;
  v_session_id        text;
  v_imported          int := 0;
  v_linked            int := 0;
  v_skipped           int := 0;
  v_profiles_imported int := 0;
  v_profiles_skipped  int := 0;
  v_errors            text[] := '{}';
  v_existing_count    int;
  v_session_ids       text[] := '{}';
  v_created_log_ids   text[] := '{}';
  v_new_log_id        text;
  v_remaining         int;
BEGIN
  -- The import row decides the tenant, never the caller's arguments. Before
  -- this the browser passed p_company_id / p_facility_id straight into every
  -- INSERT, and the function ran as its owner.
  SELECT * INTO v_import FROM public.data_imports WHERE import_id = p_import_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That import does not exist.' USING ERRCODE = 'no_data_found';
  END IF;
  v_company  := v_import.company_id;
  v_facility := v_import.facility_id;
  IF auth.uid() IS NOT NULL AND (
       v_company NOT IN (SELECT public.auth_company_ids())
    OR NOT public.auth_has_permission('config.import_data', v_company)) THEN
    RAISE EXCEPTION 'You may not import data for this company.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_import.status IN ('completed', 'reverted') THEN
    RAISE EXCEPTION 'That import is already %.', v_import.status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Count rows still to process BEFORE we pick this batch (including the batch
  -- itself — we'll subtract after to decide whether there are more).
  SELECT COUNT(*) INTO v_remaining
  FROM public.staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  IF v_remaining = 0 THEN
    -- Nothing left — mark completed (idempotent finish).
    UPDATE public.data_imports SET
      status = 'completed',
      completed_at = COALESCE(completed_at, now())
    WHERE import_id = p_import_id AND status <> 'completed';

    RETURN jsonb_build_object(
      'has_more',           false,
      'batch_processed',    0,
      'imported',           0,
      'linked',             0,
      'skipped',            0,
      'profiles_imported',  0,
      'profiles_skipped',   0,
      'errors',             0
    );
  END IF;

  FOR v_row IN
    SELECT id, payload FROM public.staged_import_sessions
    WHERE import_id = p_import_id AND processed = false
    ORDER BY id
    LIMIT p_batch_size
  LOOP
    v_payload := v_row.payload;

    BEGIN

      IF v_payload->>'type' = 'profile_template' THEN
        SELECT COUNT(*) INTO v_existing_count
        FROM public.roast_sessions
        WHERE facility_id = v_facility
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_profiles_skipped := v_profiles_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO public.roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at, roaster_unit_id, profile_name,
            is_profile_template, notes
          ) VALUES (
            v_session_id, v_facility, v_company, 'completed',
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            COALESCE((v_payload->>'created_at')::timestamptz, now()),
            NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
            v_payload->>'name',
            true,
            'Profile template imported from Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')'
          );

          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO public.roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              v_facility,
              now()
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          v_session_ids := array_append(v_session_ids, v_session_id);
          v_profiles_imported := v_profiles_imported + 1;
        END IF;

      ELSE
        SELECT COUNT(*) INTO v_existing_count
        FROM public.roast_sessions
        WHERE facility_id = v_facility
          AND notes LIKE '%Roastmaster (ID: ' || (v_payload->>'rm_pk') || ')%'
        LIMIT 1;

        IF v_existing_count > 0 THEN
          v_skipped := v_skipped + 1;
        ELSE
          v_session_id := gen_random_uuid()::text;

          INSERT INTO public.roast_sessions (
            session_id, facility_id, company_id, status,
            started_at, ended_at,
            green_weight_lbs, roasted_weight_lbs,
            charge_weight_id, origin_id, roaster_unit_id, profile_name,
            agtron_color, ambient_temp, ambient_humidity,
            post_moisture, post_density, roast_degree, rating,
            notes
          ) VALUES (
            v_session_id, v_facility, v_company, 'completed',
            (v_payload->>'started_at')::timestamptz,
            COALESCE((v_payload->>'ended_at')::timestamptz, (v_payload->>'started_at')::timestamptz),
            (v_payload->>'charge_weight_lbs')::numeric,
            (v_payload->>'roasted_weight_lbs')::numeric,
            v_payload->>'charge_weight_id',
            v_payload->>'origin_id',
            NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
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

          IF v_payload->'nodes' IS NOT NULL AND jsonb_array_length(v_payload->'nodes') > 0 THEN
            INSERT INTO public.roast_temp_nodes (session_id, elapsed_secs, bt_temp, et_temp, facility_id, recorded_at)
            SELECT
              v_session_id,
              (n->>'elapsed_secs')::numeric,
              (n->>'bt_temp')::numeric,
              (n->>'et_temp')::numeric,
              v_facility,
              (v_payload->>'started_at')::timestamptz + ((n->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'nodes') AS n;
          END IF;

          IF v_payload->'events' IS NOT NULL AND jsonb_array_length(v_payload->'events') > 0 THEN
            INSERT INTO public.roast_events (session_id, elapsed_secs, event_type, label, facility_id, recorded_at)
            SELECT
              v_session_id,
              (e->>'elapsed_secs')::numeric,
              CASE lower(trim(e->>'label'))
                WHEN 'first crack'       THEN 'first_crack_start'
                WHEN '1c start'          THEN 'first_crack_start'
                WHEN 'first crack start' THEN 'first_crack_start'
                WHEN 'first crack end'   THEN 'first_crack_end'
                WHEN '1c end'            THEN 'first_crack_end'
                WHEN 'second crack'      THEN 'second_crack_start'
                WHEN '2c start'          THEN 'second_crack_start'
                WHEN 'second crack start' THEN 'second_crack_start'
                WHEN 'second crack end'  THEN 'second_crack_end'
                WHEN '2c end'            THEN 'second_crack_end'
                WHEN 'turning point'     THEN 'turning_point'
                WHEN 'charge'            THEN 'charge'
                WHEN 'drop'              THEN 'drop'
                WHEN 'yellowing'         THEN 'yellowing'
                WHEN 'maillard'          THEN 'maillard'
                ELSE 'custom'
              END,
              e->>'label',
              v_facility,
              (v_payload->>'started_at')::timestamptz + ((e->>'elapsed_secs')::numeric * interval '1 second')
            FROM jsonb_array_elements(v_payload->'events') AS e;
          END IF;

          IF v_payload->>'roast_log_id' IS NOT NULL AND v_payload->>'roast_log_id' != '' THEN
            UPDATE public.roast_log SET session_id = v_session_id
            WHERE roast_log_id = v_payload->>'roast_log_id';
            IF v_payload->>'coffee_source_id' IS NOT NULL AND v_payload->>'coffee_source_id' != '' THEN
              UPDATE public.roast_log SET coffee_source_id = v_payload->>'coffee_source_id'
              WHERE roast_log_id = v_payload->>'roast_log_id';
            END IF;
            v_linked := v_linked + 1;
          ELSIF p_create_roast_log_entries AND COALESCE((v_payload->>'create_log_entry')::boolean, true) THEN
            v_new_log_id := gen_random_uuid()::text;
            INSERT INTO public.roast_log (
              roast_log_id, origin_id, coffee_source_id,
              charge_weight, charge_weight_lbs,
              roast_date, "charged?", roaster_unit_id, session_id,
              measured_roasted_weight, profile_name,
              facility_id, company_id
            ) VALUES (
              v_new_log_id,
              v_payload->>'origin_id',
              NULLIF(v_payload->>'coffee_source_id', ''),
              v_payload->>'charge_weight_id',
              (v_payload->>'charge_weight_lbs')::numeric,
              ((v_payload->>'started_at')::timestamptz)::date,
              true,
              NULLIF(v_payload->>'roaster_unit_id', '')::uuid,
              v_session_id,
              (v_payload->>'roasted_weight_lbs')::numeric,
              v_payload->>'profile_name',
              v_facility,
              v_company
            );
            v_created_log_ids := array_append(v_created_log_ids, v_new_log_id);
          END IF;

          v_session_ids := array_append(v_session_ids, v_session_id);
          v_imported := v_imported + 1;
        END IF;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'rm_pk=' || COALESCE(v_payload->>'rm_pk', '?') || ': ' || SQLERRM);
    END;

    UPDATE public.staged_import_sessions SET processed = true WHERE id = v_row.id;
  END LOOP;

  -- How many unprocessed rows remain after this batch?
  SELECT COUNT(*) INTO v_remaining
  FROM public.staged_import_sessions
  WHERE import_id = p_import_id AND processed = false;

  -- Accumulate counts and arrays into public.data_imports.
  -- If this is the last batch (v_remaining = 0), mark completed and clean up.
  UPDATE public.data_imports SET
    sessions_imported   = COALESCE(sessions_imported,   0) + v_imported,
    sessions_linked     = COALESCE(sessions_linked,     0) + v_linked,
    sessions_skipped    = COALESCE(sessions_skipped,    0) + v_skipped,
    profiles_imported   = COALESCE(profiles_imported,   0) + v_profiles_imported,
    profiles_skipped    = COALESCE(profiles_skipped,    0) + v_profiles_skipped,
    error_count         = COALESCE(error_count,         0) + COALESCE(array_length(v_errors, 1), 0),
    errors              = CASE
                            WHEN array_length(v_errors, 1) > 0
                            THEN to_jsonb((
                              SELECT array_agg(e) FROM (
                                SELECT jsonb_array_elements_text(COALESCE(errors, '[]'::jsonb))
                                UNION ALL
                                SELECT unnest(v_errors)
                              ) t(e)
                              LIMIT 50
                            ))
                            ELSE COALESCE(errors, '[]'::jsonb)
                          END,
    session_ids         = CASE
                            WHEN array_length(v_session_ids, 1) > 0
                            THEN COALESCE(session_ids, ARRAY[]::text[]) || v_session_ids
                            ELSE session_ids
                          END,
    created_log_ids     = CASE
                            WHEN array_length(v_created_log_ids, 1) > 0
                            THEN COALESCE(created_log_ids, ARRAY[]::text[]) || v_created_log_ids
                            ELSE created_log_ids
                          END,
    status              = CASE WHEN v_remaining = 0 THEN 'completed' ELSE status END,
    completed_at        = CASE WHEN v_remaining = 0 THEN now() ELSE completed_at END
  WHERE import_id = p_import_id;

  -- Clean up staged rows only when fully done.
  IF v_remaining = 0 THEN
    DELETE FROM public.staged_import_sessions WHERE import_id = p_import_id;
  END IF;

  RETURN jsonb_build_object(
    'has_more',          v_remaining > 0,
    'batch_processed',   v_imported + v_skipped + v_profiles_imported + v_profiles_skipped,
    'imported',          v_imported,
    'linked',            v_linked,
    'skipped',           v_skipped,
    'profiles_imported', v_profiles_imported,
    'profiles_skipped',  v_profiles_skipped,
    'errors',            COALESCE(array_length(v_errors, 1), 0)
  );
END;
$function$;

revoke all on function public.process_staged_imports(text, boolean, integer) from public, anon;
grant execute on function public.process_staged_imports(text, boolean, integer) to authenticated, service_role;

comment on function public.process_staged_imports(text, boolean, integer) is
  'Processes one batch of a staged Roastmaster import. The data_imports row decides company and facility; the caller must belong to that company and hold config.import_data. Counters accumulate on data_imports.';

commit;
