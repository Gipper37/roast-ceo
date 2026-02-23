--
-- PostgreSQL database dump
--

\restrict 4hCKw1L32v7nR97P48mKbITdFFeYG99Oc5hrGfRAkcI9RjCQd2IwKcpmBacIjJN

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.8 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO supabase_admin;

--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA extensions;


ALTER SCHEMA extensions OWNER TO postgres;

--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql;


ALTER SCHEMA graphql OWNER TO supabase_admin;

--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql_public;


ALTER SCHEMA graphql_public OWNER TO supabase_admin;

--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: pgbouncer
--

CREATE SCHEMA pgbouncer;


ALTER SCHEMA pgbouncer OWNER TO pgbouncer;

--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA realtime;


ALTER SCHEMA realtime OWNER TO supabase_admin;

--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO supabase_admin;

--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA vault;


ALTER SCHEMA vault OWNER TO supabase_admin;

--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;


--
-- Name: EXTENSION pg_graphql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_graphql IS 'pg_graphql: GraphQL support';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE auth.aal_level OWNER TO supabase_auth_admin;

--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


ALTER TYPE auth.code_challenge_method OWNER TO supabase_auth_admin;

--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE auth.factor_status OWNER TO supabase_auth_admin;

--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE auth.factor_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE auth.oauth_authorization_status OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE auth.oauth_client_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE auth.oauth_registration_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


ALTER TYPE auth.oauth_response_type OWNER TO supabase_auth_admin;

--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE auth.one_time_token_type OWNER TO supabase_auth_admin;

--
-- Name: action; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


ALTER TYPE realtime.action OWNER TO supabase_admin;

--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in'
);


ALTER TYPE realtime.equality_op OWNER TO supabase_admin;

--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text
);


ALTER TYPE realtime.user_defined_filter OWNER TO supabase_admin;

--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


ALTER TYPE realtime.wal_column OWNER TO supabase_admin;

--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: supabase_admin
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


ALTER TYPE realtime.wal_rls OWNER TO supabase_admin;

--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE storage.buckettype OWNER TO supabase_storage_admin;

--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION auth.email() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION auth.jwt() OWNER TO supabase_auth_admin;

--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION auth.role() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION auth.uid() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_cron_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


ALTER FUNCTION extensions.grant_pg_graphql_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_net_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_ddl_watch() OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_drop_watch() OWNER TO supabase_admin;

--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


ALTER FUNCTION extensions.set_graphql_placeholder() OWNER TO supabase_admin;

--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: supabase_admin
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


ALTER FUNCTION pgbouncer.get_auth(p_usename text) OWNER TO supabase_admin;

--
-- Name: calculate_blend_summary(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_blend_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    final_text text := '';
    comp record;
BEGIN
    -- Loop through components
    FOR comp IN
        SELECT 
            ci.origin, 
            rc.percentage
        FROM recipe_components rc
        LEFT JOIN coffee_inventory ci 
            ON rc.coffee_item = ci.origin_id 
            AND ci.facility_id = NEW.facility_id  -- <--- THIS IS THE FIX
        WHERE rc.recipe_id = NEW.roast_recipe_id
        -- [FIX] Sort by biggest percentage first, then name
        ORDER BY rc.percentage DESC, ci.origin ASC
    LOOP
        -- Build the text safely
        final_text := final_text 
                      || COALESCE(comp.origin, 'Unknown Coffee') 
                      || ' – ' 
                      || COALESCE(ROUND((comp.percentage * NEW.amount_to_blend)::numeric, 2)::text, '0') 
                      || ' lbs, ';
    END LOOP;

    -- Final cleanup
    IF length(final_text) > 0 THEN
        NEW.blend_summary := substring(final_text, 1, length(final_text) - 2);
    ELSE
        NEW.blend_summary := 'No components found for Recipe ID: ' || NEW.roast_recipe_id;
    END IF;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_blend_summary() OWNER TO postgres;

--
-- Name: calculate_current_stock_bags(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_current_stock_bags(p_origin_id text) RETURNS integer
    LANGUAGE plpgsql
    AS $$DECLARE
    v_facility_id TEXT; -- [FIXED] Changed from UUID to TEXT
    v_total_lbs NUMERIC;
    v_bag_size NUMERIC;
BEGIN
    -- 1. Get Facility ID for this specific bean
    SELECT facility_id INTO v_facility_id 
    FROM coffee_inventory 
    WHERE origin_id = p_origin_id 
    LIMIT 1;

    -- 2. Get current weight (Passing both required arguments)
    -- [FIXED] Added v_facility_id as the second argument
    v_total_lbs := public.calculate_current_stock_lbs(p_origin_id, v_facility_id);
    
    -- 3. Get Bag Size (Facility Specific)
    -- ID: 66526a57 (Green Bean Bag Size parameter)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' 
      AND facility_id = v_facility_id;

    -- Fallback to standard 154 lbs if parameter is missing
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN 
        v_bag_size := 154; 
    END IF;

    -- 4. Calculate Bags (Round down to nearest whole bag)
    RETURN FLOOR(v_total_lbs / v_bag_size);
END;$$;


ALTER FUNCTION public.calculate_current_stock_bags(p_origin_id text) OWNER TO postgres;

--
-- Name: calculate_current_stock_consumables(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_last_inventory_date DATE;
    v_inventory_count NUMERIC;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
BEGIN
    -- 1. Get Baseline for THIS facility only
    SELECT last_inventory_date, COALESCE(inventory_count, 0)
    INTO v_last_inventory_date, v_inventory_count
    FROM consumable_inventory
    WHERE consumable_inventory_id = p_consumable_id
      AND facility_id = p_facility_id; -- [FIX] No more guessing

    -- Safety: If never counted, assume start of time
    IF v_last_inventory_date IS NULL THEN 
        v_last_inventory_date := '2000-01-01'; 
    END IF;

    -- 2. Sum Additions (Purchases for THIS facility)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = p_consumable_id
      AND sr.date_received > v_last_inventory_date
      AND cp.facility_id = p_facility_id; -- [FIX]

    -- 3. Sum Subtractions (Usage from Orders at THIS facility)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = p_consumable_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Cancelled'
      AND o.facility_id = p_facility_id; -- [FIX]

    -- 4. Final Calculation
    RETURN GREATEST(0, (v_inventory_count + v_purchased_amount - v_usage_amount));
END;
$$;


ALTER FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) OWNER TO postgres;

--
-- Name: calculate_current_stock_lbs(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_purchased_lbs NUMERIC;
    v_starting_lbs NUMERIC;
    v_bag_size NUMERIC;
    v_inventory_bags NUMERIC;
    v_last_inventory_date DATE;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs NUMERIC;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' 
      AND facility_id = p_facility_id;

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Get Baseline (Physical Count for THIS Facility)
    SELECT last_inventory::DATE, COALESCE(inventory_count_bags, 0)
    INTO v_last_inventory_date, v_inventory_bags
    FROM coffee_inventory
    WHERE origin_id = p_origin_id
      AND facility_id = p_facility_id; -- [FIX] No more guessing

    IF v_last_inventory_date IS NULL THEN v_last_inventory_date := '2000-01-01'; END IF;
    
    v_starting_lbs := v_inventory_bags * v_bag_size;

    -- 3. Inflow: Purchases (Facility Specific)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = p_origin_id 
      AND s.date_received::DATE > v_last_inventory_date
      AND p.facility_id = p_facility_id; -- [FIX]

    -- 4. Outflow A: Direct Roasts (Facility Specific)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id 
      AND rl.roast_date::DATE >= v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = p_facility_id; -- [FIX]

    -- 5. Outflow B: Blend Roasts (Facility Specific)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = p_facility_id; -- [FIX]

    -- 6. Final Result
    RETURN GREATEST(0, (v_starting_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
END;
$$;


ALTER FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) OWNER TO postgres;

--
-- Name: calculate_green_cost(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_green_cost(recipe_id_param text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$DECLARE
    total_cost NUMERIC := 0;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Get the Facility ID for this Recipe
    -- We need to know WHICH facility is roasting this so we grab the right costs.
    SELECT facility_id INTO v_facility_id
    FROM roast_recipes
    WHERE recipe_id = recipe_id_param;

    -- 2. Sum Ingredient Costs (Facility Specific)
    SELECT SUM(
        COALESCE(i.last_cost_lb, 0) * rc.percentage
    ) INTO total_cost
    FROM recipe_components rc
    JOIN coffee_inventory i ON rc.coffee_item = i.origin_id
    WHERE rc.recipe_id = recipe_id_param
      AND i.facility_id = v_facility_id; -- [CHANGED] Lock to Facility Inventory

    RETURN ROUND(total_cost, 2);
END;$$;


ALTER FUNCTION public.calculate_green_cost(recipe_id_param text) OWNER TO postgres;

--
-- Name: calculate_green_purchasing_metrics(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_green_purchasing_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_bag_size NUMERIC;
    v_total_ordered_bags NUMERIC;
    v_total_to_order_bags NUMERIC;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    -- ID: 66526a57
    SELECT value_number INTO v_bag_size
    FROM company_parameters
    WHERE parameter_id = '66526a57' 
      AND facility_id = NEW.facility_id; -- [CHANGED]

    IF v_bag_size IS NULL OR v_bag_size = 0 THEN
        v_bag_size := 154;
    END IF;

    -- 2. Sum up the "Middle Section" (PlmoC2 Only)
    -- [CHANGED] Filter by facility_id to keep locations separate
    SELECT 
        COALESCE(SUM(ci.bags_ordered), 0),
        COALESCE(SUM(ci.to_order_bags), 0)
    INTO 
        v_total_ordered_bags, 
        v_total_to_order_bags
    FROM coffee_inventory ci
    LEFT JOIN supplier s ON ci.supplier_id = s.supplier_id
    LEFT JOIN supplier_category sc ON s.supplier_category = sc.supplier_category_id
    WHERE (s.supplier_category = 'PlmoC2' OR sc.supplier_category = 'PlmoC2')
      AND ci.facility_id = NEW.facility_id; -- [CHANGED]

    -- 3. Push the totals to "Recent Coffee Order"
    -- [CHANGED] Update the specific dashboard row for this facility
    UPDATE recent_coffee_order
    SET 
        lbs_ordered = v_total_ordered_bags * v_bag_size,
        recommended_pallets = CEIL(v_total_to_order_bags / 10.0),
        bags_left = (COALESCE(total_pallets, 0) * 10) - v_total_ordered_bags
    WHERE facility_id = NEW.facility_id; -- [CHANGED]

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_green_purchasing_metrics() OWNER TO postgres;

--
-- Name: calculate_par(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_par(p_origin_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$DECLARE
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
    v_usage_direct NUMERIC;
    v_usage_blend NUMERIC;
    v_monthly_usage NUMERIC;
    v_par_multiple NUMERIC;
    v_buffer NUMERIC;
    v_bag_size NUMERIC;
BEGIN
    -- 1. Get the Facility ID for this Origin
    -- [CHANGED] We need to know which facility we are calculating for
    SELECT facility_id INTO v_facility_id 
    FROM coffee_inventory 
    WHERE origin_id = p_origin_id 
    LIMIT 1;

    -- 2. Direct Usage (Single Origin or Post-Blend)
    -- [CHANGED] Filter by facility_id
    SELECT COALESCE(SUM(rl.charge_weight), 0)
    INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id 
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id; 

    -- 3. Indirect Usage (Pre-Blend via Recipe)
    -- [CHANGED] Filter by facility_id
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0)
    INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (CURRENT_DATE - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id; 

    -- 4. Calculate Average Monthly Usage (92 Days / 3 Months)
    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    -- 5. Get Facility Parameters (Using IDs)
    
    -- Coffee Par Multiple (ID: 3e6f5909)
    SELECT value_number INTO v_par_multiple 
    FROM company_parameters 
    WHERE parameter_id = '3e6f5909' AND facility_id = v_facility_id;

    -- Buffer (ID: 5131610b)
    SELECT value_number INTO v_buffer 
    FROM company_parameters 
    WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Green Bean Bag Size (ID: 66526a57)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' AND facility_id = v_facility_id;

    -- Fallbacks
    IF v_par_multiple IS NULL THEN v_par_multiple := 3; END IF;
    IF v_buffer IS NULL THEN v_buffer := 1.3; END IF;
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 6. Final Calculation
    RETURN FLOOR((v_monthly_usage * v_par_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;$$;


ALTER FUNCTION public.calculate_par(p_origin_id text) OWNER TO postgres;

--
-- Name: calculate_recent_order_totals(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_recent_order_totals() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_bag_size DECIMAL;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    -- ID: 66526a57 (Green Bean Bag Size)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' 
      AND facility_id = NEW.facility_id; -- [CHANGED] company_id -> facility_id
    
    -- Safety Default
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- 2. Calculate LBS Ordered (Filtered by Facility)
    UPDATE recent_coffee_order
    SET lbs_ordered = (
         SELECT COALESCE(SUM(ci.bags_ordered), 0) * v_bag_size
         FROM coffee_inventory ci
         JOIN supplier s ON ci.supplier_id = s.supplier_id
         WHERE s.supplier_category = 'PlmoC2'
           AND ci.facility_id = NEW.facility_id -- [CHANGED] Critical Filter
     )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    -- 3. Calculate Recommended Pallets (Filtered by Facility)
    UPDATE recent_coffee_order
    SET recommended_pallets = (
         SELECT CEILING(COALESCE(SUM(ci.to_order_bags), 0) / 10.0)
         FROM coffee_inventory ci
         JOIN supplier s ON ci.supplier_id = s.supplier_id
         WHERE s.supplier_category = 'PlmoC2'
           AND ci.facility_id = NEW.facility_id -- [CHANGED] Critical Filter
     )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    -- 4. Calculate Bags Left (Filtered by Facility)
    UPDATE recent_coffee_order
    SET bags_left = (COALESCE(total_pallets, 0) * 10) - (
         SELECT COALESCE(SUM(ci.bags_ordered), 0)
         FROM coffee_inventory ci
         JOIN supplier s ON ci.supplier_id = s.supplier_id
         WHERE s.supplier_category = 'PlmoC2'
           AND ci.facility_id = NEW.facility_id -- [CHANGED] Critical Filter
     )
    WHERE recent_coffee_order_id = NEW.recent_coffee_order_id;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_recent_order_totals() OWNER TO postgres;

--
-- Name: calculate_restock_level(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_restock_level(p_origin_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$DECLARE
    v_facility_id TEXT;
    v_usage_direct NUMERIC;
    v_usage_blend NUMERIC;
    v_monthly_usage NUMERIC;
    v_trigger_multiple NUMERIC;
    v_buffer NUMERIC;
    v_bag_size NUMERIC;
    v_current_date DATE;
    v_timezone TEXT;
BEGIN
    -- 1. Get Facility ID from Inventory
    SELECT facility_id INTO v_facility_id 
    FROM coffee_inventory 
    WHERE origin_id = p_origin_id 
    LIMIT 1;

    -- 2. Get Timezone & Date (Directly from Facilities Table)
    -- [CORRECTED] Now pulls from the facility column, not parameters
    SELECT time_zone INTO v_timezone 
    FROM facilities 
    WHERE facility_id = v_facility_id;

    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    -- 3. Direct Usage (Single Origin or Post-Blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_usage_direct
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = p_origin_id 
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = v_facility_id; 

    -- 4. Indirect Usage (Pre-Blend via Recipe)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_usage_blend
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = p_origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= (v_current_date - INTERVAL '92 days')
      AND rl."charged?" = TRUE
      AND rl.facility_id = v_facility_id;

    -- 5. Calculate Average Monthly Usage
    v_monthly_usage := (v_usage_direct + v_usage_blend) / 3.0;

    -- 6. Get Parameters from COMPANY_PARAMETERS (Facility Specific)
    -- These still live in parameters table (Trigger, Buffer, Bag Size)
    
    -- Trigger Multiple (ID: dae6cd4b)
    SELECT value_number INTO v_trigger_multiple 
    FROM company_parameters 
    WHERE parameter_id = 'dae6cd4b' AND facility_id = v_facility_id;

    -- Buffer (ID: 5131610b)
    SELECT value_number INTO v_buffer 
    FROM company_parameters 
    WHERE parameter_id = '5131610b' AND facility_id = v_facility_id;

    -- Bag Size (ID: 66526a57)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' AND facility_id = v_facility_id;

    -- Safety Defaults
    v_trigger_multiple := COALESCE(v_trigger_multiple, 1.5);
    v_buffer := COALESCE(v_buffer, 1.3);
    v_bag_size := COALESCE(v_bag_size, 154);

    -- 7. Final Calculation
    RETURN CEILING((v_monthly_usage * v_trigger_multiple * v_buffer) / NULLIF(v_bag_size, 0));
END;$$;


ALTER FUNCTION public.calculate_restock_level(p_origin_id text) OWNER TO postgres;

--
-- Name: calculate_roast_by_blend(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_roast_by_blend() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_reset_day_target INTEGER;
    v_roast_reset_date DATE;
    v_current_date DATE;
    v_timezone TEXT;
    
    -- Variables for Roasts Remaining Math
    v_charge_weight numeric;
    v_avg_charge_weight numeric;
    v_retention_rate numeric;
BEGIN
    -- 1. Get Timezone (Directly from Facilities Table)
    SELECT time_zone INTO v_timezone 
    FROM facilities 
    WHERE facility_id = NEW.facility_id; -- [CORRECTED]

    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    -- 2. Get Calculation Parameters (These still live in Parameters table)
    SELECT value_number INTO v_reset_day_target FROM company_parameters WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = NEW.facility_id;
    SELECT value_number INTO v_charge_weight FROM company_parameters WHERE parameter_id = '761fd894' AND facility_id = NEW.facility_id;
    SELECT value_number INTO v_retention_rate FROM company_parameters WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id;

    -- 3. Smart Average Logic (By Recipe & Facility)
    SELECT AVG(charge_weight)
    INTO v_avg_charge_weight
    FROM (
        SELECT charge_weight
        FROM roast_log
        WHERE recipe_id = NEW.recipe_id
          AND facility_id = NEW.facility_id
          AND charge_weight > 0
        ORDER BY roast_date DESC
        LIMIT 5
    ) sub;

    -- Apply Fallbacks
    v_charge_weight := COALESCE(v_avg_charge_weight, NULLIF(v_charge_weight, 0), 25);
    v_retention_rate := COALESCE(NULLIF(v_retention_rate, 0), 0.82);
    v_reset_day_target := COALESCE(v_reset_day_target, 4); 

    -- 4. Calculate Start of Roast Week
    v_roast_reset_date := v_current_date - ((EXTRACT(DOW FROM v_current_date)::int - v_reset_day_target + 7) % 7);

    -- 5. Calculate Total Ordered (Facility Specific)
    NEW.total_ordered := COALESCE((
        SELECT SUM(od.roasted_weight)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        JOIN products p ON od.product_id = p.product_id
        WHERE p.recipe_id = NEW.recipe_id
          AND o.order_status = 'Open'
          AND o.facility_id = NEW.facility_id
    ), 0);

    -- 6. Calculate Total Roasted (Facility Specific)
    NEW.total_roasted := COALESCE((
        SELECT SUM(rl.roasted_weight)
        FROM roast_log rl
        WHERE rl.recipe_id = NEW.recipe_id
          AND rl."charged?" = true
          AND rl.roast_date >= v_roast_reset_date
          AND rl.facility_id = NEW.facility_id
    ), 0);

    -- 7. Calculate Roasted Left
    NEW.roasted_left := GREATEST(0, (NEW.total_ordered - COALESCE(NEW.in_stock_roasted, 0) - NEW.total_roasted));

    -- 8. Calculate Roasts Remaining
    NEW.roasts_remaining := (NEW.roasted_left / v_retention_rate) / v_charge_weight;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_roast_by_blend() OWNER TO postgres;

--
-- Name: calculate_roast_detail_origin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_roast_detail_origin() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_charge_weight numeric;
    v_avg_charge_weight numeric;
    v_retention_rate numeric;
    v_reset_day_target integer;
    v_roast_reset_date date;
    v_current_date date;
    v_timezone text;
    
    -- Calculation Variables
    v_total_ordered numeric := 0; 
    v_total_roasted numeric := 0;
    v_direct_roasted numeric := 0;   -- For Single/Post-Blend
    v_indirect_roasted numeric := 0; -- For Pre-Blend portions
BEGIN
    -- 1. Get Timezone (Directly from Facilities Table)
    SELECT time_zone INTO v_timezone 
    FROM facilities 
    WHERE facility_id = NEW.facility_id; -- [CORRECTED]

    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;
    v_current_date := (CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    -- 2. Get Calculation Parameters (Facility Specific)
    -- [CHANGED] company_id -> facility_id
    SELECT value_number INTO v_charge_weight FROM company_parameters WHERE parameter_id = '761fd894' AND facility_id = NEW.facility_id;
    SELECT value_number INTO v_retention_rate FROM company_parameters WHERE parameter_id = '1de271df' AND facility_id = NEW.facility_id;
    SELECT value_number INTO v_reset_day_target FROM company_parameters WHERE parameter_id = 'RF1iFWjOh7' AND facility_id = NEW.facility_id;

    -- [Smart Average Logic]
    -- Learns from THIS facility's roast logs only
    SELECT AVG(charge_weight)
    INTO v_avg_charge_weight
    FROM (
        SELECT charge_weight
        FROM roast_log
        WHERE origin_id = NEW.origin 
          AND facility_id = NEW.facility_id -- [CHANGED]
          AND charge_weight > 0
        ORDER BY roast_date DESC
        LIMIT 5
    ) sub;

    v_charge_weight := COALESCE(v_avg_charge_weight, NULLIF(v_charge_weight, 0), 25);
    v_retention_rate := COALESCE(NULLIF(v_retention_rate, 0), 0.82);
    v_reset_day_target := COALESCE(v_reset_day_target, 4);

    -- 3. Calculate Start of Roast Week
    v_roast_reset_date := v_current_date - ((EXTRACT(DOW FROM v_current_date)::int - v_reset_day_target + 7) % 7);

    -- 4. In Stock Roasted (Facility Specific)
    NEW.in_stock_roasted := COALESCE((
        SELECT SUM(rdb.in_stock_roasted * rc.percentage)
        FROM roast_detail_by_blend rdb
        JOIN recipe_components rc ON rdb.recipe_id = rc.recipe_id
        WHERE rc.coffee_item = NEW.origin
          AND rdb.facility_id = NEW.facility_id -- [CHANGED]
    ), 0);

    -- 5. Calculate Total Ordered (Facility Specific)
    v_total_ordered := COALESCE((
        SELECT SUM(od.quantity * p.weight_lbs * rc.percentage)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        JOIN products p ON od.product_id = p.product_id
        JOIN recipe_components rc ON p.recipe_id = rc.recipe_id
        WHERE rc.coffee_item = NEW.origin
          AND o.order_status = 'Open'
          AND o.facility_id = NEW.facility_id -- [CHANGED]
    ), 0);

    -- 6. Calculate Total Roasted (Split into Direct and Indirect)
    
    -- A. Direct Roasts (Single Origin / Post-Blend)
    -- Logs where the origin_id explicitly matches this row
    SELECT COALESCE(SUM(roasted_weight), 0)
    INTO v_direct_roasted
    FROM roast_log
    WHERE origin_id = NEW.origin
      AND facility_id = NEW.facility_id -- [CHANGED]
      AND roast_date >= v_roast_reset_date
      AND "charged?" = true;

    -- B. Indirect Roasts (Pre-Blend)
    -- Logs for Pre-Blend recipes where this origin is a component
    SELECT COALESCE(SUM(rl.roasted_weight * rc.percentage), 0)
    INTO v_indirect_roasted
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rr.roast_type = 'Pre-Blend'
      AND rc.coffee_item = NEW.origin
      AND rl.facility_id = NEW.facility_id -- [CHANGED]
      AND rl.roast_date >= v_roast_reset_date
      AND rl."charged?" = true;

    -- Combine them for the Total
    v_total_roasted := v_direct_roasted + v_indirect_roasted;

    -- [CRITICAL] Save to column
    NEW.total_roasted := v_total_roasted;

    -- 7. Final Roasted Weight Needed
    NEW.final_roasted_weight := GREATEST(0, v_total_ordered - NEW.in_stock_roasted - v_total_roasted);

    -- 8. Green To Roast & Roasts Remaining
    NEW.green_to_roast := NEW.final_roasted_weight / v_retention_rate;
    NEW.roasts_remaining := NEW.green_to_roast / v_charge_weight;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_roast_detail_origin() OWNER TO postgres;

--
-- Name: calculate_roasted_cost(numeric, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
  retention_factor NUMERIC;
BEGIN
  SELECT value_number
    INTO retention_factor
  FROM company_parameters
  WHERE parameter_id = '1de271df'
    AND facility_id = p_facility_id
  LIMIT 1;

  IF retention_factor IS NULL OR retention_factor = 0 THEN
    SELECT sp.value_number
      INTO retention_factor
    FROM standard_parameters sp
    WHERE sp.parameter_id = '1de271df'
    LIMIT 1;
  END IF;

  IF retention_factor IS NULL OR retention_factor = 0 THEN
    retention_factor := 0.82;
  END IF;

  RETURN ROUND((green_cost / retention_factor), 2);
END;
$$;


ALTER FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text) OWNER TO postgres;

--
-- Name: calculate_shipment_totals(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_shipment_totals() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Calculate Total Weight (Coffee + Consumables)
    -- [FIX] Filter by facility_id to keep facility data separate
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0) 
        FROM coffee_inventory_purchased 
        WHERE shipment_id = NEW.shipment_id 
          AND facility_id = NEW.facility_id -- [CHANGED] company_id -> facility_id
    ) + (
        SELECT COALESCE(SUM(amount), 0) 
        FROM consumable_inventory_purchased 
        WHERE shipment_id = NEW.shipment_id 
          AND facility_id = NEW.facility_id -- [CHANGED] company_id -> facility_id
    );

    -- 2. Update the Shipment Header
    UPDATE shipment_received
    SET 
        shipment_total_weight_units = v_total_weight,
        shipping_cost_unit = CASE 
            WHEN v_total_weight > 0 THEN shipping_cost / v_total_weight 
            ELSE 0 
        END
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id; -- [CHANGED] company_id -> facility_id

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_shipment_totals() OWNER TO postgres;

--
-- Name: calculate_shipping_per_unit(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_shipping_per_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_total_weight NUMERIC;
BEGIN
    -- 1. Anti-Recursion: Stop if we are already inside this trigger
    IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;

    -- 2. Calculate the TRUE Total Weight (Coffee LBS + Consumable UNITS)
    -- [FIX] Filter by facility_id to match your new table structure
    v_total_weight := (
        SELECT COALESCE(SUM(amount), 0) 
        FROM coffee_inventory_purchased 
        WHERE shipment_id = NEW.shipment_id 
          AND facility_id = NEW.facility_id -- [CHANGED]
    ) + (
        SELECT COALESCE(SUM(amount), 0) 
        FROM consumable_inventory_purchased 
        WHERE shipment_id = NEW.shipment_id 
          AND facility_id = NEW.facility_id -- [CHANGED]
    );

    -- 3. Update BOTH the Total Weight and the Cost Per Unit
    -- [FIX] Save totals to the specific facility record
    UPDATE shipment_received
    SET shipping_cost_unit = CASE 
            WHEN v_total_weight > 0 THEN ROUND(NEW.shipping_cost / v_total_weight, 4)
            ELSE 0 
        END,
        shipment_total_weight_units = v_total_weight
    WHERE shipment_id = NEW.shipment_id
      AND facility_id = NEW.facility_id; -- [CHANGED]

    RETURN NEW;
END;$$;


ALTER FUNCTION public.calculate_shipping_per_unit() OWNER TO postgres;

--
-- Name: calculate_totals_columns(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_totals_columns() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_week_start DATE;
    v_timezone TEXT;
BEGIN
    -- 1. Get Facility Timezone (Direct from Facilities Table)
    -- [CHANGED] We now pull the timezone from the facility settings directly
    SELECT time_zone INTO v_timezone 
    FROM facilities 
    WHERE facility_id = NEW.facility_id;

    -- Fallback Default
    IF v_timezone IS NULL OR v_timezone = '' THEN v_timezone := 'Pacific/Honolulu'; END IF;

    -- 2. Calculate Start of Week (Relative to Facility Time)
    -- This resets the "This Week" counter based on the facility's local Monday morning
    v_week_start := date_trunc('week', CURRENT_TIMESTAMP AT TIME ZONE v_timezone)::DATE;

    -- 3. Left To Pack (ALL Open Orders - Date Independent)
    -- [CHANGED] Filter by facility_id to only count orders for THIS location
    NEW.left_to_pack := COALESCE((
        SELECT SUM(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = NEW.product_id
          AND o.order_status = 'Open'
          AND o.facility_id = NEW.facility_id -- [FIX] Facility Scope
    ), 0);

    -- 4. Total (This Week) - Resets on MONDAY
    -- [CHANGED] Filter by facility_id
    NEW.total := COALESCE((
        SELECT SUM(od.quantity)
        FROM order_details od
        JOIN orders o ON od.order_id = o.order_id
        WHERE od.product_id = NEW.product_id
          AND o.order_date >= v_week_start
          AND o.facility_id = NEW.facility_id -- [FIX] Facility Scope
    ), 0);

    -- 5. Recent AVG Week (6-Week Rolling Average)
    -- [CHANGED] Filter by facility_id
    NEW.recent_avg_week := COALESCE((
        SELECT AVG(weekly_sum) FROM (
            SELECT SUM(od2.quantity) as weekly_sum
            FROM order_details od2
            JOIN orders o2 ON od2.order_id = o2.order_id
            WHERE od2.product_id = NEW.product_id
              AND o2.order_date >= (v_week_start - INTERVAL '42 days')
              AND o2.order_date < v_week_start
              AND o2.facility_id = NEW.facility_id -- [FIX] Facility Scope
            GROUP BY date_trunc('week', o2.order_date)
        ) sub
    ), 0);

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_totals_columns() OWNER TO postgres;

--
-- Name: get_param(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_param(p_facility_id text, p_key text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_val_text TEXT;
    v_val_num NUMERIC;
    v_default TEXT;
BEGIN
    -- A. Check Facility Specific Settings
    -- [CHANGED] We now look up parameters by the specific Facility ID
    SELECT value, value_number 
    INTO v_val_text, v_val_num
    FROM company_parameters 
    WHERE facility_id = p_facility_id 
      AND parameter_id = p_key;

    -- Priority: Return Number if it exists, then Text
    IF v_val_num IS NOT NULL THEN RETURN v_val_num::text; END IF;
    IF v_val_text IS NOT NULL THEN RETURN v_val_text; END IF;

    -- B. Fallback to Global Default (Standard Parameters)
    -- This remains the same (System-wide defaults)
    SELECT COALESCE(text_value, amount::text) INTO v_default 
    FROM standard_parameters 
    WHERE parameters_id = p_key;

    RETURN v_default;
END;
$$;


ALTER FUNCTION public.get_param(p_facility_id text, p_key text) OWNER TO postgres;

--
-- Name: handle_manual_inventory_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_manual_inventory_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bag_size NUMERIC;
    v_purchased_lbs NUMERIC;
    v_roasted_direct_lbs NUMERIC;
    v_roasted_blend_lbs NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' 
      AND facility_id = NEW.facility_id;

    -- Default if missing
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- [NEW] 2. Recalculate Rolling Metrics
    -- This runs every time the row is touched (Manual Count OR Nightly Nudge)
    NEW.par := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);

    -- 3. Establish the Baseline (Using your NEW manual count)
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    
    -- Update the hidden "Inventory LBS" column to match your count
    NEW.inventory_lbs := COALESCE(NEW.inventory_count_bags, 0) * v_bag_size;

    -- 4. Calculate "Inflows" (Purchases after this count)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id 
      AND s.date_received::DATE > v_last_inventory_date
      AND p.facility_id = NEW.facility_id;

    -- 5. Calculate "Outflows" (Roasts after this count)
    
    -- A. Direct Roasts (Single Origin / Post-Blend)
    SELECT COALESCE(SUM(rl.charge_weight), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id 
      AND rl.roast_date::DATE >= v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend')
      AND rl.facility_id = NEW.facility_id;

    -- B. Blend Roasts (Pre-Blend)
    SELECT COALESCE(SUM(rl.charge_weight * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id 
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE >= v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    -- 6. UPDATE IN STOCK (LBS & BAGS)
    NEW.in_stock_lbs := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock := NEW.in_stock_lbs / v_bag_size;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_manual_inventory_update() OWNER TO postgres;

--
-- Name: handle_new_record(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- A. Timestamps: Database handles this (UTC)
    -- Only set if not provided, or force it if you prefer DB authority
    IF NEW.created_at IS NULL THEN NEW.created_at := NOW(); END IF;
    IF NEW.updated_at IS NULL THEN NEW.updated_at := NOW(); END IF;

    -- B. PROTECT Company ID (The Fix for the "Wipeout" bug)
    -- If an Update sends a NULL ID, keep the old one.
    IF TG_OP = 'UPDATE' AND NEW.company_id IS NULL THEN
        NEW.company_id := OLD.company_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_new_record() OWNER TO postgres;

--
-- Name: handle_order_detail_logic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_order_detail_logic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_company_id text;
    v_facility_id text; -- [NEW] To hold the facility location
    v_product_weight numeric;
    v_product_price numeric;
    v_recipe_id text;
    v_cogs numeric;
BEGIN
    -- 1. Get Parent Order Info (Company AND Facility)
    -- [CHANGED] Fetch facility_id so we can stamp the line item
    SELECT order_date, customer_id, company_id, facility_id
    INTO NEW.order_date, NEW.customer_id, v_company_id, v_facility_id
    FROM orders 
    WHERE order_id = NEW.order_id;

    -- 2. Get Product Info (Price, Weight, Recipe, AND PRE-CALC COST)
    -- Products are Company-Wide (Shared Catalog), so we keep using company_id here.
    SELECT 
        p.weight_lbs, 
        p.price, 
        p.recipe_id, 
        COALESCE(p.total_unit_cogs, 0)
    INTO 
        v_product_weight, 
        v_product_price, 
        v_recipe_id, 
        v_cogs
    FROM products p
    WHERE p.product_id = NEW.product_id
      AND p.company_id = v_company_id; -- Verified: Catalog is company-wide

    -- 3. Assign Values to the New Row
    
    -- Math: Quantity * Attributes
    NEW.total_price := COALESCE(NEW.quantity, 0) * COALESCE(v_product_price, 0);
    NEW.roasted_weight := COALESCE(NEW.quantity, 0) * COALESCE(v_product_weight, 0);
    NEW.unit_cost_at_sale := COALESCE(NEW.quantity, 0) * v_cogs;

    -- Recipe Fallback
    IF NEW.recipe_id IS NULL THEN
        NEW.recipe_id := v_recipe_id;
    END IF;

    -- [CHANGED] Propagate BOTH Identifiers
    NEW.company_id := v_company_id;
    NEW.facility_id := v_facility_id; -- [FIX] Now the line item knows where it lives

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_order_detail_logic() OWNER TO postgres;

--
-- Name: handle_updated_at_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_updated_at_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_updated_at_timestamp() OWNER TO postgres;

--
-- Name: handle_updated_record(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_updated_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- A. Timestamp: Database ALWAYS forces update time to NOW()
    NEW.updated_at := NOW();
    
    -- B. PROTECT Company ID
    IF NEW.company_id IS NULL THEN
        NEW.company_id := OLD.company_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_updated_record() OWNER TO postgres;

--
-- Name: nudge_all_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.nudge_all_inventory() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 1. Nudge Coffee Inventory based on Facility Time Zone
    -- We only update rows if the current hour in THAT facility is Midnight (0)
    UPDATE public.coffee_inventory ci
    SET updated_at = NOW()
    FROM public.facilities f
    WHERE ci.facility_id = f.facility_id
      -- This check ensures we only nudge if it's currently Midnight at the facility
      AND EXTRACT(HOUR FROM (NOW() AT TIME ZONE f.time_zone)) = 0;

    -- 2. Nudge Consumable Inventory (Bags/Labels) 
    UPDATE public.consumable_inventory c
    SET updated_at = NOW()
    FROM public.facilities f
    WHERE c.facility_id = f.facility_id
      AND EXTRACT(HOUR FROM (NOW() AT TIME ZONE f.time_zone)) = 0;
END;
$$;


ALTER FUNCTION public.nudge_all_inventory() OWNER TO postgres;

--
-- Name: propagate_coffee_cost_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.propagate_coffee_cost_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    -- 1. Performance Check
    IF NEW.latest_cost IS NOT DISTINCT FROM OLD.latest_cost THEN
        RETURN NEW;
    END IF;

    -- 2. "Touch" the Components
    -- We just update 'updated_at'. This is enough to fire the 
    -- 'sync_recipe_component_costs' trigger, which will see the 
    -- new inventory cost and recalculate the math automatically.
    UPDATE recipe_components rc
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE rc.recipe_id = rr.recipe_id
      AND rc.coffee_item = NEW.origin_id
      AND rr.facility_id = NEW.facility_id; -- [FIX] Facility Scope

    -- 3. Touch the Products (to sum up the new component costs)
    UPDATE products p
    SET updated_at = NOW()
    FROM roast_recipes rr
    WHERE p.recipe_id = rr.recipe_id
      AND rr.facility_id = NEW.facility_id
      AND p.company_id = NEW.company_id;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.propagate_coffee_cost_change() OWNER TO postgres;

--
-- Name: propagate_recipe_header_changes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.propagate_recipe_header_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN
    -- Only run if the Roast Type has changed
    IF NEW.roast_type IS DISTINCT FROM OLD.roast_type THEN
        
        -- 1. Loop through all ingredients (components) of this recipe
        FOR r IN SELECT coffee_item 
                 FROM recipe_components 
                 WHERE recipe_id = NEW.recipe_id
        LOOP
            
            -- 2. "Touch" the roast detail for each ingredient
            -- [FIX] Filter by facility_id to only update stats for THIS location
            UPDATE roast_detail 
            SET origin = origin 
            WHERE origin = r.coffee_item 
              AND facility_id = NEW.facility_id; -- Changed from company_id
        END LOOP;

        -- 3. Touch the Blend Detail table as well (just in case)
        -- [FIX] Filter by facility_id
        UPDATE roast_detail_by_blend
        SET recipe_id = recipe_id
        WHERE recipe_id = NEW.recipe_id
          AND facility_id = NEW.facility_id; -- Changed from company_id
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.propagate_recipe_header_changes() OWNER TO postgres;

--
-- Name: push_coffee_history_to_parent(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_coffee_history_to_parent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the Parent Table
    -- This action will FIRE the 'trg_manual_inventory_update' on the parent table,
    -- causing the Weight, Bags, and To Order numbers to recalculate instantly.
    
    UPDATE coffee_inventory
    SET 
        last_inventory = NEW.inventory_date,
        inventory_count_bags = NEW.bag_count,
        updated_at = NOW()
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id; -- [FIX] Link by Facility ID, not Company

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.push_coffee_history_to_parent() OWNER TO postgres;

--
-- Name: push_consumable_history_to_parent(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.push_consumable_history_to_parent() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the Parent Table (Consumables)
    UPDATE consumable_inventory
    SET 
        last_inventory_date = NEW.inventory_date,
        inventory_count = NEW.inventory_count,
        updated_at = NOW()
    WHERE consumable_inventory_id = NEW.consumable_id
      AND facility_id = NEW.facility_id; -- [FIX] Enforce Facility Scope

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.push_consumable_history_to_parent() OWNER TO postgres;

--
-- Name: recalculate_inventory_cost(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_retention numeric;
    v_latest_green_cost numeric;
    v_latest_shipping_cost numeric;
    v_final_landed_cost numeric;
BEGIN
    SELECT value_number
      INTO v_retention 
    FROM company_parameters 
    WHERE parameter_id = '1de271df'
      AND facility_id = p_facility_id
    LIMIT 1;

    IF v_retention IS NULL OR v_retention = 0 THEN
      SELECT sp.value_number
        INTO v_retention
      FROM standard_parameters sp
      WHERE sp.parameter_id = '1de271df'
      LIMIT 1;
    END IF;

    IF v_retention IS NULL OR v_retention = 0 THEN
      v_retention := 0.82;
    END IF;

    SELECT cp.cost_lb
      INTO v_latest_green_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND cp.cost_lb > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    SELECT sr.shipping_cost_unit
      INTO v_latest_shipping_cost
    FROM coffee_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.origin = p_origin_id
      AND sr.shipping_cost_unit > 0
      AND cp.facility_id = p_facility_id
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC NULLS LAST
    LIMIT 1;

    v_latest_green_cost := COALESCE(v_latest_green_cost, 0);
    v_latest_shipping_cost := COALESCE(v_latest_shipping_cost, 0);

    IF v_retention > 0 THEN
      v_final_landed_cost := (v_latest_green_cost + v_latest_shipping_cost) / v_retention;
    ELSE
      v_final_landed_cost := 0;
    END IF;

    UPDATE coffee_inventory
       SET last_cost_lb = v_latest_green_cost,
           last_shipping_cost = v_latest_shipping_cost,
           latest_cost = v_final_landed_cost
     WHERE origin_id = p_origin_id
       AND facility_id = p_facility_id;
END;
$$;


ALTER FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) OWNER TO postgres;

--
-- Name: sync_recipe_component_costs(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_recipe_component_costs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_facility_id text;
BEGIN
    -- 1. Get Facility ID from the Parent Recipe
    -- [CHANGED] We fetch facility_id instead of company_id
    SELECT facility_id INTO v_facility_id
    FROM roast_recipes
    WHERE recipe_id = NEW.recipe_id;

    -- 2. Handle Coffee Costs
    -- [CHANGED] Look up the cost using the facility_id
    -- This ensures we get the 'Waikapu' cost, not the 'Maui' cost
    SELECT latest_cost * NEW.percentage
    INTO NEW.component_cost
    FROM coffee_inventory
    WHERE origin_id = NEW.item_id -- Checks the specific bean ID
      AND facility_id = v_facility_id; -- [FIX] Scope to Facility

    -- 3. Propagate the Facility ID to the component row
    -- This fixes the missing data issue we discussed earlier
    NEW.facility_id := v_facility_id; 

    RETURN NEW;
END;$$;


ALTER FUNCTION public.sync_recipe_component_costs() OWNER TO postgres;

--
-- Name: trg_coffee_purchase_cost_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_coffee_purchase_cost_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- [FIX] Now passes (origin, facility_id) to match your new code
    PERFORM public.recalculate_inventory_cost(
        COALESCE(NEW.origin, OLD.origin),
        COALESCE(NEW.facility_id, OLD.facility_id)
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_coffee_purchase_cost_update() OWNER TO postgres;

--
-- Name: trg_roast_log_inventory_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_roast_log_inventory_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    r RECORD;
    v_bag_size NUMERIC;
    v_facility_id TEXT;
    v_current_lbs NUMERIC;
    v_current_bags NUMERIC;
    v_roast_type TEXT; 
BEGIN
    -- 0. Setup: Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);
    
    -- 1. Get Bag Size (Facility Specific)
    SELECT value_number INTO v_bag_size 
    FROM company_parameters 
    WHERE parameter_id = '66526a57' 
      AND facility_id = v_facility_id;

    -- Safety Default
    IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

    -- -----------------------------------------------------------
    -- HANDLE DELETES or UPDATES (Revert/Fix OLD values)
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        
        v_roast_type := NULL;
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = OLD.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP
                -- [FIX] Added OLD.facility_id as 2nd argument
                v_current_lbs := public.calculate_current_stock_lbs(r.coffee_item, OLD.facility_id);
                v_current_bags := v_current_lbs / v_bag_size;

                UPDATE coffee_inventory
                SET 
                    in_stock_lbs = v_current_lbs,
                    in_stock = v_current_bags,
                    to_order_bags = GREATEST(0, COALESCE(par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item
                  AND facility_id = OLD.facility_id;
            END LOOP;

        -- Case B: Single Origin / Post-Blend
        ELSIF OLD.origin_id IS NOT NULL THEN
            -- [FIX] Added OLD.facility_id as 2nd argument
            v_current_lbs := public.calculate_current_stock_lbs(OLD.origin_id, OLD.facility_id);
            v_current_bags := v_current_lbs / v_bag_size;

            UPDATE coffee_inventory
            SET 
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_bags,
                to_order_bags = GREATEST(0, COALESCE(par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(OLD.origin_id)
            WHERE origin_id = OLD.origin_id
              AND facility_id = OLD.facility_id;
        END IF;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE INSERTS or UPDATES (Apply NEW values)
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        
        v_roast_type := NULL;
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type FROM roast_recipes WHERE recipe_id = NEW.recipe_id;
        END IF;

        -- Case A: Pre-Blend
        IF v_roast_type = 'Pre-Blend' THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP
                -- [FIX] Added NEW.facility_id as 2nd argument
                v_current_lbs := public.calculate_current_stock_lbs(r.coffee_item, NEW.facility_id);
                v_current_bags := v_current_lbs / v_bag_size;

                UPDATE coffee_inventory
                SET 
                    in_stock_lbs = v_current_lbs,
                    in_stock = v_current_bags,
                    to_order_bags = GREATEST(0, COALESCE(par, 0) - v_current_bags),
                    restock_level = public.calculate_restock_level(r.coffee_item)
                WHERE origin_id = r.coffee_item
                  AND facility_id = NEW.facility_id;
            END LOOP;

        -- Case B: Single Origin / Post-Blend
        ELSIF NEW.origin_id IS NOT NULL THEN
            -- [FIX] Added NEW.facility_id as 2nd argument
            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin_id, NEW.facility_id);
            v_current_bags := v_current_lbs / v_bag_size;

            UPDATE coffee_inventory
            SET 
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_bags,
                to_order_bags = GREATEST(0, COALESCE(par, 0) - v_current_bags),
                restock_level = public.calculate_restock_level(NEW.origin_id)
            WHERE origin_id = NEW.origin_id
              AND facility_id = NEW.facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;$$;


ALTER FUNCTION public.trg_roast_log_inventory_update() OWNER TO postgres;

--
-- Name: trg_shipment_cost_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_shipment_cost_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN
    -- Only run if the cost actually changed
    IF OLD.shipping_cost_unit IS DISTINCT FROM NEW.shipping_cost_unit THEN
        
        -- [FIX] Loop through items in this shipment AND get their facility_id
        FOR r IN SELECT DISTINCT origin, facility_id 
                 FROM coffee_inventory_purchased 
                 WHERE shipment_id = NEW.shipment_id 
                   AND facility_id = NEW.facility_id
        LOOP
            -- [FIX] Pass both IDs to the calculator
            PERFORM public.recalculate_inventory_cost(r.origin, r.facility_id);
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_shipment_cost_update() OWNER TO postgres;

--
-- Name: trigger_sync_roasted_cost(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_sync_roasted_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_green_cost NUMERIC;
  v_facility_id TEXT;
BEGIN
  -- 1. Identify the Facility
  -- We use COALESCE to ensure we have the ID during both Inserts and Updates
  v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

  -- 2. Get the Green Cost from the Recipe
  -- We join to ensure we are looking at the recipe that belongs to this facility
  SELECT rr.cost_lb_green
  INTO v_green_cost
  FROM roast_recipes rr
  WHERE rr.recipe_id = NEW.recipe_id
    AND rr.facility_id = v_facility_id; -- [FIX] Facility Isolation

  -- 3. Calculate and Stamp the Roasted Cost
  -- This calls your helper function using the facility-specific retention rate
  NEW.cost_lb_roasted := calculate_roasted_cost(v_green_cost, v_facility_id);

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_sync_roasted_cost() OWNER TO postgres;

--
-- Name: update_actual_ordered_lbs(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_actual_ordered_lbs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bag_size NUMERIC;
BEGIN
    -- OPTIMIZATION: Only run math if it's a NEW row or 'bags_ordered' changed
    IF (TG_OP = 'INSERT') OR (NEW.bags_ordered IS DISTINCT FROM OLD.bags_ordered) THEN
        
        -- 1. Get Bag Size (Facility Specific)
        -- ID: 66526a57 (Green Bean Bag Size)
        SELECT value_number INTO v_bag_size 
        FROM company_parameters 
        WHERE parameter_id = '66526a57' 
          AND facility_id = NEW.facility_id; -- [FIX] Swapped company_id for facility_id

        -- 2. Fallback to Standard/Default if NULL
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN
             v_bag_size := 154; 
        END IF;

        -- 3. Calculate
        NEW.actual_ordered_lbs := COALESCE(NEW.bags_ordered, 0) * v_bag_size;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_actual_ordered_lbs() OWNER TO postgres;

--
-- Name: update_coffee_stock_purchased(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_coffee_stock_purchased() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_bag_size NUMERIC;
    v_current_lbs NUMERIC;
BEGIN
    -- -----------------------------------------------------------
    -- HANDLE DELETES (Revert inventory for the OLD item)
    -- -----------------------------------------------------------
    IF TG_OP = 'DELETE' THEN
        -- 1. Get Bag Size (Facility Specific)
        SELECT value_number INTO v_bag_size 
        FROM company_parameters 
        WHERE parameter_id = '66526a57' AND facility_id = OLD.facility_id;
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

        -- 2. Calculate ONCE (Passing NEW Facility ID)
        v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);

        -- 3. Update Inventory for THIS Facility
        UPDATE coffee_inventory
        SET 
            in_stock_lbs = v_current_lbs,
            in_stock = v_current_lbs / v_bag_size,
            to_order_bags = GREATEST(0, COALESCE(par, 0) - (v_current_lbs / v_bag_size))
        WHERE origin_id = OLD.origin 
          AND facility_id = OLD.facility_id;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE INSERTS
    -- -----------------------------------------------------------
    IF TG_OP = 'INSERT' THEN
        -- 1. Get Bag Size (Facility Specific)
        SELECT value_number INTO v_bag_size 
        FROM company_parameters 
        WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
        IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

        -- 2. Calculate ONCE
        v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);

        -- 3. Update
        UPDATE coffee_inventory
        SET 
            in_stock_lbs = v_current_lbs,
            in_stock = v_current_lbs / v_bag_size,
            to_order_bags = GREATEST(0, COALESCE(par, 0) - (v_current_lbs / v_bag_size))
        WHERE origin_id = NEW.origin 
          AND facility_id = NEW.facility_id;
    END IF;

    -- -----------------------------------------------------------
    -- HANDLE UPDATES
    -- -----------------------------------------------------------
    IF TG_OP = 'UPDATE' THEN
        
        -- Scenario 1: Origin or Facility Changed
        IF OLD.origin IS DISTINCT FROM NEW.origin OR OLD.facility_id IS DISTINCT FROM NEW.facility_id THEN
            
            -- A. Fix OLD
            SELECT value_number INTO v_bag_size 
            FROM company_parameters 
            WHERE parameter_id = '66526a57' AND facility_id = OLD.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(OLD.origin, OLD.facility_id);

            UPDATE coffee_inventory
            SET 
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                to_order_bags = GREATEST(0, COALESCE(par, 0) - (v_current_lbs / v_bag_size))
            WHERE origin_id = OLD.origin 
              AND facility_id = OLD.facility_id;
            
            -- B. Fix NEW
            SELECT value_number INTO v_bag_size 
            FROM company_parameters 
            WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);

            UPDATE coffee_inventory
            SET 
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                to_order_bags = GREATEST(0, COALESCE(par, 0) - (v_current_lbs / v_bag_size))
            WHERE origin_id = NEW.origin 
              AND facility_id = NEW.facility_id;
        
        -- Scenario 2: Simple Update (Same Origin/Facility)
        ELSE
            SELECT value_number INTO v_bag_size 
            FROM company_parameters 
            WHERE parameter_id = '66526a57' AND facility_id = NEW.facility_id;
            IF v_bag_size IS NULL OR v_bag_size = 0 THEN v_bag_size := 154; END IF;

            v_current_lbs := public.calculate_current_stock_lbs(NEW.origin, NEW.facility_id);

            UPDATE coffee_inventory
            SET 
                in_stock_lbs = v_current_lbs,
                in_stock = v_current_lbs / v_bag_size,
                to_order_bags = GREATEST(0, COALESCE(par, 0) - (v_current_lbs / v_bag_size))
            WHERE origin_id = NEW.origin 
              AND facility_id = NEW.facility_id;
        END IF;
    END IF;

    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_coffee_stock_purchased() OWNER TO postgres;

--
-- Name: update_consumable_metrics(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_consumable_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    target_id text;
    v_facility_id text; -- [CHANGED] Shift to Facility scope
    v_last_inventory_date DATE;
    v_purchased_amount NUMERIC;
    v_usage_amount NUMERIC;
    v_par numeric;
    v_restock_level numeric;
BEGIN
    -- Handle both Insert and Update scenarios
    target_id := COALESCE(NEW.consumable_inventory_id, OLD.consumable_inventory_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);
    
    -- 1. Setup Baseline
    v_last_inventory_date := COALESCE(NEW.last_inventory_date::DATE, '2000-01-01');

    -- 2. Sum Additions (Purchases for THIS facility only)
    SELECT COALESCE(SUM(amount), 0)
    INTO v_purchased_amount
    FROM consumable_inventory_purchased cp
    JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = target_id
      AND sr.date_received > v_last_inventory_date
      AND cp.facility_id = v_facility_id; -- [FIX] Facility Isolation

    -- 3. Sum Subtractions (Usage from Orders at THIS facility only)
    SELECT COALESCE(SUM(od.quantity * pc.quantity), 0)
    INTO v_usage_amount
    FROM order_details od
    JOIN orders o ON od.order_id = o.order_id
    JOIN product_consumables pc ON od.product_id = pc.product_id
    WHERE pc.consumable_id = target_id
      AND o.order_date::DATE > v_last_inventory_date
      AND o.order_status != 'Canceled'
      AND o.facility_id = v_facility_id; -- [FIX] Facility Isolation

    -- 4. Calculate Final Stock (Using NEW count)
    NEW.in_stock := GREATEST(0, (COALESCE(NEW.inventory_count, 0) + v_purchased_amount - v_usage_amount));

    -- 5. Calculate "To Order"
    v_par := COALESCE(NEW.par, 0);
    v_restock_level := COALESCE(NEW.restock_level, 0);

    IF NEW.in_stock <= v_restock_level THEN
        NEW.to_order := GREATEST(0, v_par - NEW.in_stock);
    ELSE
        NEW.to_order := 0;
    END IF;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.update_consumable_metrics() OWNER TO postgres;

--
-- Name: update_consumable_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_consumable_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    r RECORD;
    v_product_id TEXT;
    v_facility_id TEXT; -- [CHANGED] Correctly uses TEXT for your IDs
    v_current_stock NUMERIC;
BEGIN
    -- 1. Identify Context (Handle both Inserts and Updates)
    v_product_id := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Loop through consumables linked to this product
    FOR r IN 
        SELECT consumable_id 
        FROM product_consumables 
        WHERE product_id = v_product_id
    LOOP
        -- 3. Calculate the NEW stock level
        -- [FIX] Passing both arguments to the updated helper function
        v_current_stock := public.calculate_current_stock_consumables(r.consumable_id, v_facility_id);

        -- 4. Update the Inventory for THIS Facility
        -- Recalculating here triggers 'update_consumable_metrics' on the target table
        UPDATE consumable_inventory
        SET in_stock = v_current_stock,
            updated_at = NOW()
        WHERE consumable_inventory_id = r.consumable_id
          AND facility_id = v_facility_id; -- [FIX] Facility Isolation
    END LOOP;

    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_consumable_stock() OWNER TO postgres;

--
-- Name: update_consumable_stock_purchased(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_consumable_stock_purchased() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_current_stock NUMERIC;
    v_target_id TEXT;
    v_facility_id TEXT;
BEGIN
    -- 1. Identify Context (Handles INSERT/UPDATE and DELETE)
    v_target_id := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Calculate the NEW stock level
    -- [FIXED] Passing both target_id and facility_id to match the updated helper signature
    v_current_stock := public.calculate_current_stock_consumables(v_target_id, v_facility_id);

    -- 3. Update the Inventory for THIS Facility
    -- Note: This 'touch' will fire 'trg_update_consumable_ordering' 
    -- which handles the Par and To Order math.
    UPDATE consumable_inventory
    SET 
        in_stock = v_current_stock,
        updated_at = NOW()
    WHERE consumable_inventory_id = v_target_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_consumable_stock_purchased() OWNER TO postgres;

--
-- Name: update_customer_metrics_on_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_customer_metrics_on_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_avg_interval NUMERIC;
    v_latest_order_date DATE;
    v_latest_order_id TEXT;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Calculate Average Interval for THIS facility (Last 180 Days)
    SELECT ROUND(CAST(AVG(order_date - prev_date) / 7.0 AS numeric), 1) 
    INTO v_avg_interval
    FROM (
        SELECT order_date, LAG(order_date) OVER (ORDER BY order_date) as prev_date
        FROM orders
        WHERE customer_id = NEW.customer_id
          AND order_status != 'Canceled'
          AND order_date > (CURRENT_DATE - INTERVAL '180 days')
          AND facility_id = v_facility_id -- [FIX] Facility Isolation
    ) sub
    WHERE prev_date IS NOT NULL;

    -- Handle NULLs (No recent orders)
    v_avg_interval := COALESCE(v_avg_interval, 0);

    -- 2. Find the TRUE Latest Order for THIS facility
    SELECT order_date, order_id
    INTO v_latest_order_date, v_latest_order_id
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id -- [FIX] Facility Isolation
    ORDER BY order_date DESC
    LIMIT 1;

    -- 3. Update Customer Metrics for the record matching this facility
    UPDATE customers
    SET
        last_order_id = v_latest_order_id,
        last_order_date = v_latest_order_date,
        
        -- Store raw numbers
        days_since_last_order = (CURRENT_DATE - v_latest_order_date),
        weeks_since_last_order = CEIL((CURRENT_DATE - v_latest_order_date) / 7.0),
        avg_interval_last_180_days = v_avg_interval,
        
        -- THE LOGIC: Manual Override -> OR -> (Floor of Avg, but Min 1)
        effective_interval = COALESCE(
            acct_management_interval_wks, 
            GREATEST(1, FLOOR(v_avg_interval))
        )
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NEW;
END;$$;


ALTER FUNCTION public.update_customer_metrics_on_order() OWNER TO postgres;

--
-- Name: update_effective_interval_on_manual_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_effective_interval_on_manual_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only recalculate if the manual interval OR the average actually changed
    IF (OLD.acct_management_interval_wks IS DISTINCT FROM NEW.acct_management_interval_wks) 
       OR (OLD.avg_interval_last_180_days IS DISTINCT FROM NEW.avg_interval_last_180_days) THEN
       
       -- Apply the EXACT same logic as the Order Trigger
       NEW.effective_interval := COALESCE(
           NEW.acct_management_interval_wks, 
           GREATEST(1, FLOOR(COALESCE(NEW.avg_interval_last_180_days, 0)))
       );
       
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_effective_interval_on_manual_change() OWNER TO postgres;

--
-- Name: update_last_coffee_cost(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_last_coffee_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_origin_id TEXT;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Identify Variables (Handles Insert/Update vs Delete)
    v_origin_id := COALESCE(NEW.origin, OLD.origin);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Call the Calculator (Passing the specific Facility ID)
    -- This matches the 2-argument version we vetted earlier.
    PERFORM public.recalculate_inventory_cost(v_origin_id, v_facility_id);
    
    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_last_coffee_cost() OWNER TO postgres;

--
-- Name: update_last_consumable_cost(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_last_consumable_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    v_item_id TEXT;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
    v_latest_cost NUMERIC;
BEGIN
    -- 1. Handle Context (Support INSERT/UPDATE with NEW, DELETE with OLD)
    v_item_id := COALESCE(NEW.consumable_inventory_item, OLD.consumable_inventory_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Find True Latest Cost (Facility Specific)
    -- We search the history to find the most recent valid price for THIS facility.
    SELECT cp.cost_unit::numeric
    INTO v_latest_cost
    FROM consumable_inventory_purchased cp
    LEFT JOIN shipment_received sr ON cp.shipment_id = sr.shipment_id
    WHERE cp.consumable_inventory_item = v_item_id
      AND cp.facility_id = v_facility_id -- [FIX] Facility Isolation
      AND cp.cost_unit IS NOT NULL
      AND cp.cost_unit::text <> ''
    ORDER BY sr.date_received DESC NULLS LAST, cp.created_at DESC
    LIMIT 1;

    -- 3. Update Parent Record
    -- We only update if we found a valid cost history for this facility.
    IF v_latest_cost IS NOT NULL THEN
        UPDATE consumable_inventory
        SET last_cost_unit = v_latest_cost,
            updated_at = NOW()
        WHERE consumable_inventory_id = v_item_id
          AND facility_id = v_facility_id; -- [FIX] Facility Isolation
    END IF;

    RETURN NULL;
END;$$;


ALTER FUNCTION public.update_last_consumable_cost() OWNER TO postgres;

--
-- Name: update_order_aggregates(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_order_aggregates() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    target_order_id text;
    v_facility_id text; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Identify Context (Handle Insert/Update vs Delete)
    target_order_id := COALESCE(NEW.order_id, OLD.order_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Update Parent Order
    -- We re-sum the details to get the new accurate totals for THIS facility
    UPDATE public.orders
    SET 
        order_total = ( 
             SELECT COALESCE(SUM(total_price), 0) 
             FROM public.order_details 
             WHERE order_id = target_order_id
         ),
        total_weight = ( 
             SELECT COALESCE(SUM(roasted_weight), 0) 
             FROM public.order_details 
             WHERE order_id = target_order_id
         )
    WHERE order_id = target_order_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_order_aggregates() OWNER TO postgres;

--
-- Name: update_order_metrics(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_order_metrics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    prev_date DATE;
    v_cat TEXT;
    v_area TEXT;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Grab from Customer record (Isolated by Facility)
    SELECT customer_category, sales_area 
    INTO v_cat, v_area
    FROM customers
    WHERE customer_id = NEW.customer_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    NEW.customer_category := v_cat;
    NEW.area := v_area;

    -- 2. Sum up totals from "Order Details"
    -- This ensures the header is always in sync with the line items
    SELECT 
        COALESCE(SUM(total_price), 0),
        COALESCE(SUM(roasted_weight), 0)
    INTO NEW.order_total, NEW.total_weight
    FROM order_details
    WHERE order_id = NEW.order_id;

    -- 3. Find previous order date for interval calculation (Isolated by Facility)
    SELECT MAX(order_date) INTO prev_date
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_date < NEW.order_date
      AND order_status != 'Canceled'
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    -- 4. Calculate interval math
    IF prev_date IS NOT NULL THEN
        NEW.interval_days := (NEW.order_date - prev_date);
        -- Weeks rounded to 1 decimal, minimum 1 week for managed account logic
        NEW.interval_wks := GREATEST(1, ROUND(CAST((NEW.order_date - prev_date) AS numeric) / 7.0, 1));
    ELSE
        NEW.interval_days := 0;
        NEW.interval_wks := 0;
    END IF;

    RETURN NEW;
END;$$;


ALTER FUNCTION public.update_order_metrics() OWNER TO postgres;

--
-- Name: update_product_total_cogs(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_product_total_cogs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_coffee_cost_total numeric := 0;
    v_consumable_cost_total numeric := 0;
BEGIN
    -- A. Calculate Coffee Cost (Directly from Inventory * Percentage)
    -- [FIX] Joined using facility_id to prevent double-counting across locations
    SELECT COALESCE(SUM(ci.latest_cost * rc.percentage), 0)
    INTO v_coffee_cost_total
    FROM recipe_components rc
    JOIN coffee_inventory ci ON rc.coffee_item = ci.origin_id
    WHERE rc.recipe_id = NEW.recipe_id
      AND ci.facility_id = NEW.facility_id; -- [FIX] Facility Isolation

    -- B. Calculate Packaging Cost (Directly from Inventory * Quantity)
    -- [FIX] Joined using facility_id
    SELECT COALESCE(SUM(ci.last_cost_unit * pc.quantity), 0)
    INTO v_consumable_cost_total
    FROM product_consumables pc
    JOIN consumable_inventory ci ON pc.consumable_id = ci.consumable_inventory_id
    WHERE pc.product_id = NEW.product_id
      AND ci.facility_id = NEW.facility_id; -- [FIX] Facility Isolation

    -- C. Set Final Cost on the Product Row
    -- COGS = (Coffee Cost/lb * Product Weight) + Sum of Packaging
    NEW.total_unit_cogs := (v_coffee_cost_total * COALESCE(NEW.weight_lbs, 0)) + v_consumable_cost_total;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_product_total_cogs() OWNER TO postgres;

--
-- Name: update_roast_detail_by_components(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_roast_detail_by_components() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
    v_facility_id TEXT; -- [CHANGED]
    v_roast_type TEXT; 
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- -------------------------------------------------------------
    -- 1. IF DELETING or UPDATING (Handle the OLD values first)
    -- -------------------------------------------------------------
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        
        -- Look up roast type for the OLD recipe
        IF OLD.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type 
            FROM roast_recipes 
            WHERE recipe_id = OLD.recipe_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;

        -- A. Update the specific Origin stats
        IF OLD.origin_id IS NOT NULL THEN
            UPDATE roast_detail 
            SET origin = origin -- "Touch" to force recalculation
            WHERE origin = OLD.origin_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;

        -- B. Update Component stats (if it was a Pre-Blend roast)
        IF v_roast_type = 'Pre-Blend' AND OLD.recipe_id IS NOT NULL THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = OLD.recipe_id LOOP
                UPDATE roast_detail 
                SET origin = origin 
                WHERE origin = r.coffee_item
                  AND facility_id = v_facility_id; -- [FIX]
            END LOOP;
        END IF;

        -- C. Update the Recipe/Blend stats
        IF OLD.recipe_id IS NOT NULL THEN
            UPDATE roast_detail_by_blend 
            SET recipe_id = recipe_id 
            WHERE recipe_id = OLD.recipe_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;
    END IF;

    -- -------------------------------------------------------------
    -- 2. IF INSERTING or UPDATING (Handle the NEW values)
    -- -------------------------------------------------------------
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        
        -- Look up roast type for the NEW recipe
        IF NEW.recipe_id IS NOT NULL THEN
            SELECT roast_type INTO v_roast_type 
            FROM roast_recipes 
            WHERE recipe_id = NEW.recipe_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;

        -- A. Update the specific Origin stats
        IF NEW.origin_id IS NOT NULL THEN
            UPDATE roast_detail 
            SET origin = origin 
            WHERE origin = NEW.origin_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;

        -- B. Update Component stats (Pre-Blend)
        IF v_roast_type = 'Pre-Blend' AND NEW.recipe_id IS NOT NULL THEN
            FOR r IN SELECT coffee_item FROM recipe_components WHERE recipe_id = NEW.recipe_id LOOP
                UPDATE roast_detail 
                SET origin = origin 
                WHERE origin = r.coffee_item
                  AND facility_id = v_facility_id; -- [FIX]
            END LOOP;
        END IF;

        -- C. Update the Recipe/Blend stats
        IF NEW.recipe_id IS NOT NULL THEN
            UPDATE roast_detail_by_blend 
            SET recipe_id = recipe_id 
            WHERE recipe_id = NEW.recipe_id
              AND facility_id = v_facility_id; -- [FIX]
        END IF;
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_roast_detail_by_components() OWNER TO postgres;

--
-- Name: update_roast_detail_from_order_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_roast_detail_from_order_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_product_id TEXT;
    v_facility_id TEXT;
    v_recipe_id TEXT;
    r RECORD;
BEGIN
    -- 1. Identify Context
    v_product_id := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. Look up the Recipe ID from the Product
    SELECT recipe_id INTO v_recipe_id 
    FROM products 
    WHERE product_id = v_product_id 
      AND facility_id = v_facility_id;

    -- If no recipe found (e.g., shipping fees, merch), stop
    IF v_recipe_id IS NULL THEN RETURN NULL; END IF;

    -- 3. Loop through Coffee Components
    -- We "touch" the roast detail for every bean in the recipe
    FOR r IN 
        SELECT coffee_item 
        FROM recipe_components 
        WHERE recipe_id = v_recipe_id
    LOOP
        UPDATE roast_detail
        SET origin = origin -- Force recalculation
        WHERE origin = r.coffee_item
          AND facility_id = v_facility_id; -- [FIX] Facility Isolation
    END LOOP;

    -- 4. Update the Blend Summary Table
    UPDATE roast_detail_by_blend
    SET recipe_id = recipe_id
    WHERE recipe_id = v_recipe_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_roast_detail_from_order_trigger() OWNER TO postgres;

--
-- Name: update_roast_detail_from_recipe_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_roast_detail_from_recipe_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_origin_id TEXT;
    v_facility_id TEXT; -- [CHANGED]
BEGIN
    -- 1. Identify Variables (Handles Insert/Update vs Delete)
    -- coffee_item is the column name in the recipe_components table
    v_origin_id := COALESCE(NEW.coffee_item, OLD.coffee_item);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. "Touch" the row in roast_detail for THIS facility only
    -- This forces the 'calculate_roast_detail_origin' trigger to run
    IF v_origin_id IS NOT NULL THEN
        UPDATE roast_detail
        SET origin = origin -- Force recalculation
        WHERE origin = v_origin_id
          AND facility_id = v_facility_id; -- [FIX] Facility Isolation
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_roast_detail_from_recipe_trigger() OWNER TO postgres;

--
-- Name: update_totals_from_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_totals_from_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_product_id TEXT;
    v_facility_id TEXT; -- [CHANGED] company_id -> facility_id
BEGIN
    -- 1. Identify Context (Handle Insert/Update vs Delete)
    v_product_id := COALESCE(NEW.product_id, OLD.product_id);
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 2. The "Nudge" (Facility Specific)
    -- Just update the timestamp. This forces AppSheet to re-sync this specific row
    -- and re-calculate your "Left to Pack" virtual columns for this location only.
    UPDATE totals 
    SET updated_at = NOW()
    WHERE product_id = v_product_id
      AND facility_id = v_facility_id; -- [FIX] Facility Isolation

    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_totals_from_order() OWNER TO postgres;

--
-- Name: update_totals_from_order_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_totals_from_order_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
    v_facility_id TEXT;
BEGIN
    -- 0. Identify Facility
    v_facility_id := COALESCE(NEW.facility_id, OLD.facility_id);

    -- 1. Only run if the status actually changed (e.g., Pending -> Completed)
    IF OLD.order_status IS DISTINCT FROM NEW.order_status THEN
        
        -- 2. Loop through every product in this order
        FOR r IN 
            SELECT product_id 
            FROM order_details 
            WHERE order_id = NEW.order_id 
        LOOP
            
            -- 3. "Nudge" the totals row for THIS facility
            -- This forces AppSheet to recalculate "Left to Pack" for this location
            UPDATE totals
            SET updated_at = NOW()
            WHERE product_id = r.product_id
              AND facility_id = v_facility_id; -- [FIX] Facility Isolation
                
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_totals_from_order_status() OWNER TO postgres;

--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_
        -- Filter by action early - only get subscriptions interested in this action
        -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
        and (subs.action_filter = '*' or subs.action_filter = action::text);

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add "record" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add "old_record" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '"' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$$;


ALTER FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


ALTER FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) OWNER TO supabase_admin;

--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


ALTER FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) OWNER TO supabase_admin;

--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
    declare
      res jsonb;
    begin
      execute format('select to_jsonb(%L::'|| type_::text || ')', val)  into res;
      return res;
    end
    $$;


ALTER FUNCTION realtime."cast"(val text, type_ regtype) OWNER TO supabase_admin;

--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $$;


ALTER FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) OWNER TO supabase_admin;

--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $_$;


ALTER FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) OWNER TO supabase_admin;

--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS SETOF realtime.wal_rls
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
      with pub as (
        select
          concat_ws(
            ',',
            case when bool_or(pubinsert) then 'insert' else null end,
            case when bool_or(pubupdate) then 'update' else null end,
            case when bool_or(pubdelete) then 'delete' else null end
          ) as w2j_actions,
          coalesce(
            string_agg(
              realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
              ','
            ) filter (where ppt.tablename is not null and ppt.tablename not like '% %'),
            ''
          ) w2j_add_tables
        from
          pg_publication pp
          left join pg_publication_tables ppt
            on pp.pubname = ppt.pubname
        where
          pp.pubname = publication
        group by
          pp.pubname
        limit 1
      ),
      w2j as (
        select
          x.*, pub.w2j_add_tables
        from
          pub,
          pg_logical_slot_get_changes(
            slot_name, null, max_changes,
            'include-pk', 'true',
            'include-transaction', 'false',
            'include-timestamp', 'true',
            'include-type-oids', 'true',
            'format-version', '2',
            'actions', pub.w2j_actions,
            'add-tables', pub.w2j_add_tables
          ) x
      )
      select
        xyz.wal,
        xyz.is_rls_enabled,
        xyz.subscription_ids,
        xyz.errors
      from
        w2j,
        realtime.apply_rls(
          wal := w2j.data::jsonb,
          max_record_bytes := max_record_bytes
        ) xyz(wal, is_rls_enabled, subscription_ids, errors)
      where
        w2j.w2j_add_tables <> ''
        and xyz.subscription_ids[1] is not null
    $$;


ALTER FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) OWNER TO supabase_admin;

--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '"')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '"'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $$;


ALTER FUNCTION realtime.quote_wal2json(entity regclass) OWNER TO supabase_admin;

--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    -- Generate a new UUID for the id
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) OWNER TO supabase_admin;

--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $$;


ALTER FUNCTION realtime.subscription_check_filters() OWNER TO supabase_admin;

--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: supabase_admin
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


ALTER FUNCTION realtime.to_regrole(role_name text) OWNER TO supabase_admin;

--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


ALTER FUNCTION realtime.topic() OWNER TO supabase_realtime_admin;

--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) OWNER TO supabase_storage_admin;

--
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


ALTER FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) OWNER TO supabase_storage_admin;

--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION storage.enforce_bucket_name_length() OWNER TO supabase_storage_admin;

--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION storage.extension(name text) OWNER TO supabase_storage_admin;

--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION storage.filename(name text) OWNER TO supabase_storage_admin;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION storage.foldername(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) OWNER TO supabase_storage_admin;

--
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION storage.get_level(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION storage.get_prefix(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION storage.get_prefixes(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION storage.get_size_by_bucket() OWNER TO supabase_storage_admin;

--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) OWNER TO supabase_storage_admin;

--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text, sort_order text) OWNER TO supabase_storage_admin;

--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION storage.operation() OWNER TO supabase_storage_admin;

--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION storage.protect_delete() OWNER TO supabase_storage_admin;

--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION storage.update_updated_at_column() OWNER TO supabase_storage_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE auth.audit_log_entries OWNER TO supabase_auth_admin;

--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


ALTER TABLE auth.flow_state OWNER TO supabase_auth_admin;

--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE auth.identities OWNER TO supabase_auth_admin;

--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE auth.instances OWNER TO supabase_auth_admin;

--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


ALTER TABLE auth.mfa_amr_claims OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


ALTER TABLE auth.mfa_challenges OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


ALTER TABLE auth.mfa_factors OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


ALTER TABLE auth.oauth_authorizations OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


ALTER TABLE auth.oauth_client_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


ALTER TABLE auth.oauth_clients OWNER TO supabase_auth_admin;

--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


ALTER TABLE auth.oauth_consents OWNER TO supabase_auth_admin;

--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


ALTER TABLE auth.one_time_tokens OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


ALTER TABLE auth.refresh_tokens OWNER TO supabase_auth_admin;

--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: supabase_auth_admin
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE auth.refresh_tokens_id_seq OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: supabase_auth_admin
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


ALTER TABLE auth.saml_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


ALTER TABLE auth.saml_relay_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE auth.schema_migrations OWNER TO supabase_auth_admin;

--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


ALTER TABLE auth.sessions OWNER TO supabase_auth_admin;

--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


ALTER TABLE auth.sso_domains OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


ALTER TABLE auth.sso_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


ALTER TABLE auth.users OWNER TO supabase_auth_admin;

--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: blending_worksheet; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blending_worksheet (
    blending_id text NOT NULL,
    roast_recipe_id text,
    amount_to_blend numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    user_email text,
    blend_summary text,
    facility_id text
);


ALTER TABLE public.blending_worksheet OWNER TO postgres;

--
-- Name: charge_weight_options; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.charge_weight_options (
    charge_weight numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.charge_weight_options OWNER TO postgres;

--
-- Name: coffee_inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.coffee_inventory (
    origin_id text NOT NULL,
    origin text,
    supplier_id text,
    last_inventory date,
    inventory_count_bags numeric,
    bags_ordered numeric,
    in_stock numeric,
    par numeric,
    restock_level numeric,
    inventory_lbs numeric,
    to_order numeric,
    to_order_bags numeric,
    actual_ordered_lbs numeric,
    last_cost_lb numeric,
    last_shipping_cost numeric,
    in_stock_lbs numeric,
    latest_cost numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.coffee_inventory OWNER TO postgres;

--
-- Name: coffee_inventory_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.coffee_inventory_history (
    history_id text NOT NULL,
    origin_id text,
    inventory_date date DEFAULT CURRENT_DATE NOT NULL,
    bag_count numeric NOT NULL,
    notes text,
    company_id text,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    updated_by text,
    facility_id text
);


ALTER TABLE public.coffee_inventory_history OWNER TO postgres;

--
-- Name: coffee_inventory_purchased; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.coffee_inventory_purchased (
    origin_purchase_id text NOT NULL,
    shipment_id text,
    origin text,
    coffee_name text,
    lot_id text,
    cost_lb numeric,
    amount numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.coffee_inventory_purchased OWNER TO postgres;

--
-- Name: coffee_usage_by_month; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.coffee_usage_by_month (
    coffee_usage_id text NOT NULL,
    origin text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.coffee_usage_by_month OWNER TO postgres;

--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    company_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    company_name text,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: company_parameters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_parameters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id text NOT NULL,
    parameter_id text,
    value text,
    value_number numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    facility_id text
);


ALTER TABLE public.company_parameters OWNER TO postgres;

--
-- Name: consumable_inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consumable_inventory (
    consumable_inventory_id text NOT NULL,
    consumable_inventory_item text,
    last_inventory_date date,
    inventory_count numeric,
    in_stock numeric DEFAULT 0,
    par numeric DEFAULT 0,
    restock_level numeric DEFAULT 0,
    to_order numeric DEFAULT 0,
    last_cost_unit numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.consumable_inventory OWNER TO postgres;

--
-- Name: consumable_inventory_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consumable_inventory_history (
    history_id text NOT NULL,
    consumable_id text,
    inventory_date date DEFAULT CURRENT_DATE NOT NULL,
    inventory_count numeric NOT NULL,
    notes text,
    company_id text,
    created_by text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    updated_by text,
    facility_id text
);


ALTER TABLE public.consumable_inventory_history OWNER TO postgres;

--
-- Name: consumable_inventory_purchased; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consumable_inventory_purchased (
    consumable_purchase_id text NOT NULL,
    shipment_id text,
    consumable_inventory_item text,
    cost_unit numeric,
    amount bigint,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.consumable_inventory_purchased OWNER TO postgres;

--
-- Name: contact_role; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact_role (
    contact_role_id text NOT NULL,
    contact_role text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.contact_role OWNER TO postgres;

--
-- Name: contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contacts (
    contact_id text NOT NULL,
    contact text,
    company text,
    role text,
    email text,
    phone text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.contacts OWNER TO postgres;

--
-- Name: customer_category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_category (
    customer_category text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


ALTER TABLE public.customer_category OWNER TO postgres;

--
-- Name: customer_notes_detail; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_notes_detail (
    notes_detail_id text NOT NULL,
    customer_id text,
    note text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.customer_notes_detail OWNER TO postgres;

--
-- Name: customer_sales_filter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_sales_filter (
    sales_filter_id text NOT NULL,
    searcher text,
    flagged boolean,
    contact_info text,
    sales_person text,
    sales_status text,
    sales_area text,
    sales_region text,
    sales_state text,
    customer_category text,
    blank_1 text,
    blank_2 text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.customer_sales_filter OWNER TO postgres;

--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    customer_id text NOT NULL,
    customer_category text,
    name_company text,
    contact text,
    acct_management_interval_wks numeric,
    management_type text,
    order_reminders_unsubscribed text,
    deal_open_closed boolean,
    sales_area text,
    sales_person text,
    email text,
    phone text,
    street text,
    city text,
    state text,
    zip text,
    tags text,
    customer_since date,
    flag boolean,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    avg_interval_last_180_days numeric,
    last_order_id text,
    last_order_date date,
    effective_interval numeric,
    days_since_last_order numeric,
    weeks_since_last_order numeric,
    country_id text,
    sales_region text,
    facility_id text
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- Name: facilities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.facilities (
    facility_id text NOT NULL,
    company_id text,
    facility_name text NOT NULL,
    country_code text,
    time_zone text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


ALTER TABLE public.facilities OWNER TO postgres;

--
-- Name: management_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.management_type (
    management_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.management_type OWNER TO postgres;

--
-- Name: open_order_totals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.open_order_totals (
    open_order_total_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.open_order_totals OWNER TO postgres;

--
-- Name: order_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_details (
    order_detail_id text NOT NULL,
    order_id text,
    product_id text,
    coffee_prep text,
    quantity numeric,
    item_status text,
    previous_order_details text,
    next_order_details text,
    company_id text,
    roasted_weight double precision,
    total_price double precision,
    recipe_id text,
    order_date date,
    customer_id text,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    unit_cost_at_sale numeric,
    facility_id text
);


ALTER TABLE public.order_details OWNER TO postgres;

--
-- Name: order_graphs_week; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.order_graphs_week AS
 SELECT (week_start)::date AS week_start
   FROM generate_series('2021-10-02 00:00:00'::timestamp without time zone, '2026-12-26 00:00:00'::timestamp without time zone, '7 days'::interval) week_start(week_start);


ALTER VIEW public.order_graphs_week OWNER TO postgres;

--
-- Name: order_graphs_weekly_avg_by_month; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.order_graphs_weekly_avg_by_month AS
 SELECT (month_start)::date AS month_start
   FROM generate_series('2021-10-01 00:00:00'::timestamp without time zone, '2026-12-01 00:00:00'::timestamp without time zone, '1 mon'::interval) month_start(month_start);


ALTER VIEW public.order_graphs_weekly_avg_by_month OWNER TO postgres;

--
-- Name: order_graphs_weekly_avg_by_year; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.order_graphs_weekly_avg_by_year AS
 SELECT year_start
   FROM generate_series(((EXTRACT(year FROM CURRENT_DATE))::integer - 5), (EXTRACT(year FROM CURRENT_DATE))::integer) year_start(year_start);


ALTER VIEW public.order_graphs_weekly_avg_by_year OWNER TO postgres;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    order_id text NOT NULL,
    customer_id text,
    order_date date,
    order_status text,
    order_notes text,
    previous_order text,
    next_order text,
    delivery_photo text,
    signature text,
    "update column" text,
    order_total numeric,
    total_weight double precision,
    interval_days integer,
    interval_wks real,
    customer_category text,
    area text,
    company_id text,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    facility_id text
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- Name: product_consumables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_consumables (
    product_consumable_id text NOT NULL,
    product_id text,
    consumable_id text,
    quantity numeric DEFAULT 1,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_id text,
    created_by text,
    updated_by text,
    facility_id text
);


ALTER TABLE public.product_consumables OWNER TO postgres;

--
-- Name: product_filter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_filter (
    products_filter_id text NOT NULL,
    product_id text,
    recipe_id text,
    size text,
    order_status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.product_filter OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    product_id text NOT NULL,
    product_name text,
    recipe_id text,
    product_type text,
    size text,
    image text,
    "archived?" boolean,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    weight_lbs numeric,
    price numeric,
    total_unit_cogs numeric,
    facility_id text
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: products_price_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products_price_log (
    price_log_id text NOT NULL,
    product_id text,
    price numeric,
    date_updated date,
    end_date date,
    created_at timestamp without time zone,
    created_by text,
    updated_at timestamp without time zone,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.products_price_log OWNER TO postgres;

--
-- Name: recent_coffee_order; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.recent_coffee_order (
    recent_coffee_order_id text NOT NULL,
    order_date date,
    total_pallets numeric,
    lbs_ordered numeric(10,2) DEFAULT 0,
    recommended_pallets numeric(10,2) DEFAULT 0,
    bags_left numeric(10,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.recent_coffee_order OWNER TO postgres;

--
-- Name: recipe_components; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.recipe_components (
    component_id text NOT NULL,
    recipe_id text,
    item_id text,
    percentage numeric,
    coffee_item text,
    component_cost numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.recipe_components OWNER TO postgres;

--
-- Name: roast_detail; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roast_detail (
    roast_detail_id text NOT NULL,
    origin text,
    final_roasted_weight numeric DEFAULT 0,
    roasts_remaining numeric DEFAULT 0,
    green_to_roast numeric DEFAULT 0,
    total_roasted numeric DEFAULT 0,
    in_stock_roasted numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.roast_detail OWNER TO postgres;

--
-- Name: roast_detail_by_blend; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roast_detail_by_blend (
    roast_blend_id text NOT NULL,
    recipe_id text,
    in_stock_roasted numeric,
    total_ordered numeric DEFAULT 0,
    roasted_left numeric DEFAULT 0,
    total_roasted numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    roasts_remaining numeric DEFAULT 0,
    facility_id text
);


ALTER TABLE public.roast_detail_by_blend OWNER TO postgres;

--
-- Name: roast_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roast_log (
    roast_log_id text NOT NULL,
    roast_date date,
    origin_id text,
    recipe_id text,
    charge_weight numeric,
    roasted_weight numeric,
    "charged?" boolean,
    "chaff_cleaned?" boolean,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.roast_log OWNER TO postgres;

--
-- Name: roast_recipes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roast_recipes (
    recipe_id text NOT NULL,
    recipe_name text,
    image text,
    cost_lb_green numeric,
    cost_lb_roasted numeric,
    shipping_lb numeric,
    created_at timestamp with time zone,
    created_by text,
    updated_at timestamp with time zone,
    updated_by text,
    company_id text,
    roast_type text DEFAULT 'Single Origin/Post-Blend'::text,
    facility_id text
);


ALTER TABLE public.roast_recipes OWNER TO postgres;

--
-- Name: sales_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_activity (
    sales_activity_id text NOT NULL,
    sales_activity_type text,
    activity_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.sales_activity OWNER TO postgres;

--
-- Name: sales_area; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_area (
    area_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    id text NOT NULL,
    state_id text
);


ALTER TABLE public.sales_area OWNER TO postgres;

--
-- Name: sales_category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_category (
    sales_category text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_category OWNER TO postgres;

--
-- Name: sales_city; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_city (
    sales_city_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    city_name text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    state_id text,
    company_id text
);


ALTER TABLE public.sales_city OWNER TO postgres;

--
-- Name: sales_data_filter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_data_filter (
    sales_data_filter_id text NOT NULL,
    start_date date,
    end_date date,
    category text,
    customer text,
    product text,
    recipe text,
    size text,
    order_status text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.sales_data_filter OWNER TO postgres;

--
-- Name: sales_goals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_goals (
    sales_goal_id text NOT NULL,
    sales_person text,
    first_action_daily_goal numeric,
    follow_up_action_daily_goal numeric,
    personal_action_weekly_goal numeric,
    signed_accounts_weekly_goal numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.sales_goals OWNER TO postgres;

--
-- Name: sales_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_notes (
    salesnote_id text NOT NULL,
    customer_id text,
    contact text,
    sales_activity_type text,
    sales_person text,
    sales_note text,
    date date,
    create_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_notes OWNER TO postgres;

--
-- Name: sales_parameters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_parameters (
    sales_parameter_id text NOT NULL,
    sales_person text,
    follow_up_reminder_weeks numeric,
    current_client_follow_up_reminder_weeks numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_parameters OWNER TO postgres;

--
-- Name: sales_region; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_region (
    id text NOT NULL,
    name text NOT NULL,
    country_code text DEFAULT 'US'::text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.sales_region OWNER TO postgres;

--
-- Name: sales_state; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_state (
    id text NOT NULL,
    country_code text NOT NULL,
    state_name text NOT NULL,
    state_abbrev text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    region_id text,
    area_id text
);


ALTER TABLE public.sales_state OWNER TO postgres;

--
-- Name: sales_state_backup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_state_backup (
    sales_state text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_state_backup OWNER TO postgres;

--
-- Name: sales_tasks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_tasks (
    sales_task_id text NOT NULL,
    sales_person text,
    customer_id text,
    contact text,
    sales_activity_type text,
    task text,
    date_due date,
    status boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_tasks OWNER TO postgres;

--
-- Name: sales_tracking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sales_tracking (
    sales_tracking_id text NOT NULL,
    sales_person text,
    period text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.sales_tracking OWNER TO postgres;

--
-- Name: setup_countries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.setup_countries (
    country_name text NOT NULL,
    country_code text NOT NULL
);


ALTER TABLE public.setup_countries OWNER TO postgres;

--
-- Name: setup_timezones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.setup_timezones (
    timezone_name text NOT NULL,
    display_label text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


ALTER TABLE public.setup_timezones OWNER TO postgres;

--
-- Name: shipment_received; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.shipment_received (
    shipment_id text NOT NULL,
    supplier_id text,
    shipping_cost numeric,
    date_received date,
    order_date date,
    shipment_total_weight_units numeric,
    shipping_cost_unit numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.shipment_received OWNER TO postgres;

--
-- Name: size; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.size (
    size_id text NOT NULL,
    size_name text,
    weight numeric,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text
);


ALTER TABLE public.size OWNER TO postgres;

--
-- Name: standard_parameters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.standard_parameters (
    parameters_id text NOT NULL,
    parameter text,
    amount numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    text_value text,
    data_type text,
    company_id text,
    CONSTRAINT standard_parameters_data_type_check CHECK ((data_type = ANY (ARRAY['text'::text, 'number'::text, 'decimal'::text, 'timezone'::text, 'boolean'::text])))
);


ALTER TABLE public.standard_parameters OWNER TO postgres;

--
-- Name: summarized_weight_weekly; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.summarized_weight_weekly AS
 SELECT w.week_start,
    COALESCE(sum(data.roasted_weight), (0)::double precision) AS total_roasted_weight
   FROM (( SELECT ((date_trunc('week'::text, (CURRENT_DATE)::timestamp with time zone) - ((i.i)::double precision * '7 days'::interval)))::date AS week_start
           FROM generate_series(0, 130) i(i)) w
     LEFT JOIN ( SELECT od.roasted_weight,
            o.order_date
           FROM (public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))) data ON (((date_trunc('week'::text, (data.order_date)::timestamp with time zone))::date = w.week_start)))
  GROUP BY w.week_start
  ORDER BY w.week_start DESC;


ALTER VIEW public.summarized_weight_weekly OWNER TO postgres;

--
-- Name: summarized_weight_monthly; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.summarized_weight_monthly AS
 SELECT (date_trunc('month'::text, (week_start)::timestamp with time zone))::date AS month_start,
    sum(total_roasted_weight) AS total_monthly_weight,
    round((avg(total_roasted_weight))::numeric, 2) AS weekly_average_weight
   FROM public.summarized_weight_weekly
  GROUP BY ((date_trunc('month'::text, (week_start)::timestamp with time zone))::date)
  ORDER BY ((date_trunc('month'::text, (week_start)::timestamp with time zone))::date) DESC;


ALTER VIEW public.summarized_weight_monthly OWNER TO postgres;

--
-- Name: summarized_weight_yearly; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.summarized_weight_yearly AS
 SELECT (date_trunc('year'::text, (week_start)::timestamp with time zone))::date AS year_start,
    sum(total_roasted_weight) AS total_yearly_weight,
    round((avg(total_roasted_weight))::numeric, 2) AS weekly_average_weight
   FROM public.summarized_weight_weekly
  GROUP BY ((date_trunc('year'::text, (week_start)::timestamp with time zone))::date)
  ORDER BY ((date_trunc('year'::text, (week_start)::timestamp with time zone))::date) DESC;


ALTER VIEW public.summarized_weight_yearly OWNER TO postgres;

--
-- Name: supplier; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.supplier (
    supplier_id text NOT NULL,
    supplier text,
    supplier_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.supplier OWNER TO postgres;

--
-- Name: supplier_category; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.supplier_category (
    supplier_category_id text NOT NULL,
    supplier_category text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.supplier_category OWNER TO postgres;

--
-- Name: team; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.team (
    team_member_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    name text,
    email text,
    company_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    role text DEFAULT 'Staff'::text,
    facility_id text
);


ALTER TABLE public.team OWNER TO postgres;

--
-- Name: team_member_role; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.team_member_role (
    team_member_role_id text NOT NULL,
    team_member_role text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text
);


ALTER TABLE public.team_member_role OWNER TO postgres;

--
-- Name: totals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.totals (
    totals_id text NOT NULL,
    product_id text,
    amount_packed numeric,
    left_to_pack numeric DEFAULT 0,
    total numeric DEFAULT 0,
    recent_avg_week numeric DEFAULT 0,
    left_to_bag numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by text,
    updated_by text,
    company_id text,
    facility_id text
);


ALTER TABLE public.totals OWNER TO postgres;

--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_roles (
    role_id text NOT NULL,
    role_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_roles OWNER TO postgres;

--
-- Name: weekly_grand_total; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.weekly_grand_total WITH (security_invoker='true') AS
 WITH config AS (
         SELECT standard_parameters.text_value AS timezone,
            ( SELECT (standard_parameters_1.amount)::integer AS amount
                   FROM public.standard_parameters standard_parameters_1
                  WHERE (standard_parameters_1.parameters_id = 'RF1iFWjOh7'::text)) AS roast_target_day,
            ( SELECT standard_parameters_1.amount
                   FROM public.standard_parameters standard_parameters_1
                  WHERE (standard_parameters_1.parameters_id = '1de271df'::text)) AS retention_rate
           FROM public.standard_parameters
          WHERE (standard_parameters.parameters_id = 'TZ_CONFIG'::text)
         LIMIT 1
        ), calc AS (
         SELECT config.timezone,
            config.retention_rate,
            (date_trunc('week'::text, (CURRENT_TIMESTAMP AT TIME ZONE config.timezone)))::date AS order_week_start,
            (((CURRENT_TIMESTAMP AT TIME ZONE config.timezone))::date - ((((EXTRACT(dow FROM ((CURRENT_TIMESTAMP AT TIME ZONE config.timezone))::date))::integer - config.roast_target_day) + 7) % 7)) AS roast_week_start
           FROM config
        )
 SELECT gen_random_uuid() AS open_order_total_id,
    COALESCE(( SELECT sum(od.roasted_weight) AS sum
           FROM ((public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
             CROSS JOIN calc c_1)
          WHERE (o.order_date >= c_1.order_week_start)), (0)::double precision) AS total_ordered_roasted,
    (COALESCE(( SELECT sum(od.roasted_weight) AS sum
           FROM ((public.order_details od
             JOIN public.orders o ON ((od.order_id = o.order_id)))
             CROSS JOIN calc c_1)
          WHERE (o.order_date >= c_1.order_week_start)), (0)::double precision) / (NULLIF(( SELECT calc.retention_rate
           FROM calc), (0)::numeric))::double precision) AS total_ordered_green,
    COALESCE(( SELECT sum(rl.roasted_weight) AS sum
           FROM (public.roast_log rl
             CROSS JOIN calc c_1)
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c_1.roast_week_start))), (0)::numeric) AS total_roasted,
    COALESCE(( SELECT sum(rl.charge_weight) AS sum
           FROM (public.roast_log rl
             CROSS JOIN calc c_1)
          WHERE ((rl."charged?" = true) AND (rl.roast_date >= c_1.roast_week_start))), (0)::numeric) AS total_roasted_green
   FROM calc c;


ALTER VIEW public.weekly_grand_total OWNER TO postgres;

--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL
)
PARTITION BY RANGE (inserted_at);


ALTER TABLE realtime.messages OWNER TO supabase_realtime_admin;

--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE realtime.schema_migrations OWNER TO supabase_admin;

--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE realtime.subscription OWNER TO supabase_admin;

--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


ALTER TABLE storage.buckets OWNER TO supabase_storage_admin;

--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE storage.buckets_analytics OWNER TO supabase_storage_admin;

--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.buckets_vectors OWNER TO supabase_storage_admin;

--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE storage.migrations OWNER TO supabase_storage_admin;

--
-- Name: objects; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb
);


ALTER TABLE storage.objects OWNER TO supabase_storage_admin;

--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


ALTER TABLE storage.s3_multipart_uploads OWNER TO supabase_storage_admin;

--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.s3_multipart_uploads_parts OWNER TO supabase_storage_admin;

--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.vector_indexes OWNER TO supabase_storage_admin;

--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: coffee_inventory_purchased Coffee Inventory Purchased_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT "Coffee Inventory Purchased_pkey" PRIMARY KEY (origin_purchase_id);


--
-- Name: companies Companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT "Companies_pkey" PRIMARY KEY (company_id);


--
-- Name: consumable_inventory_purchased Consumable Inventory Purchased_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT "Consumable Inventory Purchased_pkey" PRIMARY KEY (consumable_purchase_id);


--
-- Name: consumable_inventory Consumable Inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT "Consumable Inventory_pkey" PRIMARY KEY (consumable_inventory_id);


--
-- Name: contacts Contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT "Contacts_pkey" PRIMARY KEY (contact_id);


--
-- Name: customers Customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT "Customers_pkey" PRIMARY KEY (customer_id);


--
-- Name: order_details Order Details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT "Order Details_pkey" PRIMARY KEY (order_detail_id);


--
-- Name: orders Orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT "Orders_pkey" PRIMARY KEY (order_id);


--
-- Name: products_price_log Products Price Log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT "Products Price Log_pkey" PRIMARY KEY (price_log_id);


--
-- Name: products Products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT "Products_pkey" PRIMARY KEY (product_id);


--
-- Name: roast_log Roast Log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT "Roast Log_pkey" PRIMARY KEY (roast_log_id);


--
-- Name: roast_recipes Roast Recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT "Roast Recipes_pkey" PRIMARY KEY (recipe_id);


--
-- Name: sales_notes Sales Notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT "Sales Notes_pkey" PRIMARY KEY (salesnote_id);


--
-- Name: sales_state_backup Sales State_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_state_backup
    ADD CONSTRAINT "Sales State_pkey" PRIMARY KEY (sales_state);


--
-- Name: sales_tasks Sales Tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_tasks
    ADD CONSTRAINT "Sales Tasks_pkey" PRIMARY KEY (sales_task_id);


--
-- Name: size Size_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.size
    ADD CONSTRAINT "Size_pkey" PRIMARY KEY (size_id);


--
-- Name: blending_worksheet blending_worksheet_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_pkey PRIMARY KEY (blending_id);


--
-- Name: charge_weight_options charge_weight_options_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_pkey PRIMARY KEY (charge_weight);


--
-- Name: coffee_inventory_history coffee_inventory_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_pkey PRIMARY KEY (history_id);


--
-- Name: coffee_inventory coffee_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_pkey PRIMARY KEY (origin_id);


--
-- Name: coffee_usage_by_month coffee_usage_by_month_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_pkey PRIMARY KEY (coffee_usage_id);


--
-- Name: company_parameters company_parameters_company_id_parameter_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_company_id_parameter_id_key UNIQUE (company_id, parameter_id);


--
-- Name: company_parameters company_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_pkey PRIMARY KEY (id);


--
-- Name: consumable_inventory_history consumable_inventory_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_pkey PRIMARY KEY (history_id);


--
-- Name: contact_role contact_role_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_role
    ADD CONSTRAINT contact_role_pkey PRIMARY KEY (contact_role_id);


--
-- Name: customer_category customer_category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_category
    ADD CONSTRAINT customer_category_pkey PRIMARY KEY (customer_category);


--
-- Name: customer_notes_detail customer_notes_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_pkey PRIMARY KEY (notes_detail_id);


--
-- Name: customer_sales_filter customer_sales_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_pkey PRIMARY KEY (sales_filter_id);


--
-- Name: facilities facilities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_pkey PRIMARY KEY (facility_id);


--
-- Name: management_type management_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.management_type
    ADD CONSTRAINT management_type_pkey PRIMARY KEY (management_type);


--
-- Name: open_order_totals open_order_totals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.open_order_totals
    ADD CONSTRAINT open_order_totals_pkey PRIMARY KEY (open_order_total_id);


--
-- Name: product_consumables product_consumables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_pkey PRIMARY KEY (product_consumable_id);


--
-- Name: product_filter product_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_pkey PRIMARY KEY (products_filter_id);


--
-- Name: recent_coffee_order recent_coffee_order_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_pkey PRIMARY KEY (recent_coffee_order_id);


--
-- Name: recipe_components recipe_components_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_pkey PRIMARY KEY (component_id);


--
-- Name: roast_detail_by_blend roast_detail_by_blend_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail_by_blend
    ADD CONSTRAINT roast_detail_by_blend_pkey PRIMARY KEY (roast_blend_id);


--
-- Name: roast_detail roast_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail
    ADD CONSTRAINT roast_detail_pkey PRIMARY KEY (roast_detail_id);


--
-- Name: sales_activity sales_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_activity
    ADD CONSTRAINT sales_activity_pkey PRIMARY KEY (sales_activity_id);


--
-- Name: sales_category sales_category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_category
    ADD CONSTRAINT sales_category_pkey PRIMARY KEY (sales_category);


--
-- Name: sales_city sales_city_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_city
    ADD CONSTRAINT sales_city_pkey PRIMARY KEY (sales_city_id);


--
-- Name: sales_data_filter sales_data_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_pkey PRIMARY KEY (sales_data_filter_id);


--
-- Name: sales_goals sales_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_pkey PRIMARY KEY (sales_goal_id);


--
-- Name: sales_parameters sales_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_parameters
    ADD CONSTRAINT sales_parameters_pkey PRIMARY KEY (sales_parameter_id);


--
-- Name: sales_area sales_region_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_region_pkey PRIMARY KEY (id);


--
-- Name: sales_region sales_region_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_region
    ADD CONSTRAINT sales_region_pkey1 PRIMARY KEY (id);


--
-- Name: sales_state sales_state_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_state
    ADD CONSTRAINT sales_state_pkey PRIMARY KEY (id);


--
-- Name: sales_tracking sales_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_tracking
    ADD CONSTRAINT sales_tracking_pkey PRIMARY KEY (sales_tracking_id);


--
-- Name: setup_countries setup_countries_country_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_country_code_key UNIQUE (country_code);


--
-- Name: setup_countries setup_countries_country_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_country_name_key UNIQUE (country_name);


--
-- Name: setup_countries setup_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.setup_countries
    ADD CONSTRAINT setup_countries_pkey PRIMARY KEY (country_code);


--
-- Name: setup_timezones setup_timezones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.setup_timezones
    ADD CONSTRAINT setup_timezones_pkey PRIMARY KEY (timezone_name);


--
-- Name: shipment_received shipment_received_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_pkey PRIMARY KEY (shipment_id);


--
-- Name: standard_parameters standard_parameters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.standard_parameters
    ADD CONSTRAINT standard_parameters_pkey PRIMARY KEY (parameters_id);


--
-- Name: supplier_category supplier_category_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_category
    ADD CONSTRAINT supplier_category_pkey PRIMARY KEY (supplier_category_id);


--
-- Name: supplier supplier_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (supplier_id);


--
-- Name: team_member_role team_member_role_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_member_role
    ADD CONSTRAINT team_member_role_pkey PRIMARY KEY (team_member_role_id);


--
-- Name: team team_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (team_member_id);


--
-- Name: totals totals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.totals
    ADD CONSTRAINT totals_pkey PRIMARY KEY (totals_id);


--
-- Name: setup_timezones unique_tz_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.setup_timezones
    ADD CONSTRAINT unique_tz_name UNIQUE (timezone_name);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (role_id);


--
-- Name: user_roles user_roles_role_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_name_key UNIQUE (role_name);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: idx_coffee_history_origin_facility; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_coffee_history_origin_facility ON public.coffee_inventory_history USING btree (origin_id, facility_id);


--
-- Name: idx_coffee_inv_purchased_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_coffee_inv_purchased_shipment ON public.coffee_inventory_purchased USING btree (shipment_id);


--
-- Name: idx_consumable_history_item_facility; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_consumable_history_item_facility ON public.consumable_inventory_history USING btree (consumable_id, facility_id);


--
-- Name: idx_consumable_inv_purchased_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_consumable_inv_purchased_shipment ON public.consumable_inventory_purchased USING btree (shipment_id);


--
-- Name: idx_order_details_facility; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_details_facility ON public.order_details USING btree (facility_id);


--
-- Name: idx_order_details_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_details_product ON public.order_details USING btree (product_id);


--
-- Name: idx_orders_customer_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_customer_date ON public.orders USING btree (customer_id, order_date DESC);


--
-- Name: idx_orders_date_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_date_status ON public.orders USING btree (order_date, order_status);


--
-- Name: idx_orders_facility; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_facility ON public.orders USING btree (facility_id);


--
-- Name: idx_products_price_log_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_products_price_log_date ON public.products_price_log USING btree (product_id, date_updated DESC);


--
-- Name: idx_products_recipe_facility; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_products_recipe_facility ON public.products USING btree (recipe_id, facility_id);


--
-- Name: idx_recipe_components_recipe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_recipe_components_recipe ON public.recipe_components USING btree (recipe_id);


--
-- Name: idx_roast_log_facility_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_roast_log_facility_date ON public.roast_log USING btree (facility_id, roast_date DESC);


--
-- Name: idx_roast_log_recipe_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_roast_log_recipe_date ON public.roast_log USING btree (recipe_id, roast_date DESC);


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_key; Type: INDEX; Schema: realtime; Owner: supabase_admin
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_key ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter);


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: roast_detail_by_blend tr_calculate_roast_blend; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_calculate_roast_blend BEFORE INSERT OR UPDATE ON public.roast_detail_by_blend FOR EACH ROW EXECUTE FUNCTION public.calculate_roast_by_blend();


--
-- Name: roast_detail tr_calculate_roast_detail; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_calculate_roast_detail BEFORE INSERT OR UPDATE ON public.roast_detail FOR EACH ROW EXECUTE FUNCTION public.calculate_roast_detail_origin();


--
-- Name: totals tr_calculate_totals; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_calculate_totals BEFORE INSERT OR UPDATE ON public.totals FOR EACH ROW EXECUTE FUNCTION public.calculate_totals_columns();


--
-- Name: blending_worksheet trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: charge_weight_options trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.charge_weight_options FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory_history trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_inventory_purchased trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: coffee_usage_by_month trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.coffee_usage_by_month FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: companies trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.companies FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: company_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.company_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory_history trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: consumable_inventory_purchased trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: contact_role trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.contact_role FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: contacts trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_notes_detail trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_notes_detail FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customer_sales_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customer_sales_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: customers trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: management_type trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.management_type FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: open_order_totals trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.open_order_totals FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: order_details trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: orders trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: product_consumables trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_consumables FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: product_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.product_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: products trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: products_price_log trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: recent_coffee_order trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.recent_coffee_order FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: recipe_components trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_detail trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_detail FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_detail_by_blend trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_detail_by_blend FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_log trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: roast_recipes trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_activity trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_activity FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_area trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_area FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_city trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_city FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_data_filter trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_data_filter FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_goals trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_goals FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_notes trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_state_backup trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_state_backup FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_tasks trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_tasks FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: sales_tracking trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.sales_tracking FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: setup_timezones trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.setup_timezones FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: shipment_received trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: size trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.size FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: standard_parameters trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.standard_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: supplier trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: supplier_category trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.supplier_category FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: team trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.team FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: team_member_role trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.team_member_role FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: totals trg_audit_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_insert BEFORE INSERT ON public.totals FOR EACH ROW EXECUTE FUNCTION public.handle_new_record();


--
-- Name: blending_worksheet trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: charge_weight_options trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.charge_weight_options FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory_history trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_inventory_purchased trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: coffee_usage_by_month trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.coffee_usage_by_month FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: companies trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: company_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.company_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory_history trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: consumable_inventory_purchased trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: contact_role trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.contact_role FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: contacts trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_notes_detail trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_notes_detail FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customer_sales_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customer_sales_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: customers trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: management_type trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.management_type FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: open_order_totals trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.open_order_totals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: order_details trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: orders trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: product_consumables trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_consumables FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: product_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.product_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: products trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: products_price_log trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.products_price_log FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: recent_coffee_order trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.recent_coffee_order FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: recipe_components trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_detail trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_detail FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_detail_by_blend trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_detail_by_blend FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_log trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_recipes trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_activity trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_activity FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_area trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_area FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_city trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_city FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_data_filter trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_data_filter FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_goals trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_goals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_notes trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_notes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_state_backup trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_state_backup FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_tasks trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_tasks FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: sales_tracking trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.sales_tracking FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: setup_timezones trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.setup_timezones FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: shipment_received trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: size trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.size FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: standard_parameters trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.standard_parameters FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: supplier trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.supplier FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: supplier_category trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.supplier_category FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: team trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.team FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: team_member_role trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.team_member_role FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: totals trg_audit_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audit_update BEFORE UPDATE ON public.totals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_record();


--
-- Name: roast_detail_by_blend trg_calculate_roast_blend; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_calculate_roast_blend BEFORE INSERT OR UPDATE ON public.roast_detail_by_blend FOR EACH ROW EXECUTE FUNCTION public.calculate_roast_by_blend();


--
-- Name: roast_detail trg_calculate_roast_origin; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_calculate_roast_origin BEFORE INSERT OR UPDATE ON public.roast_detail FOR EACH ROW EXECUTE FUNCTION public.calculate_roast_detail_origin();


--
-- Name: totals trg_calculate_totals; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_calculate_totals BEFORE INSERT OR UPDATE ON public.totals FOR EACH ROW EXECUTE FUNCTION public.calculate_totals_columns();


--
-- Name: coffee_inventory_purchased trg_coffee_purchase_add; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_coffee_purchase_add AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.update_coffee_stock_purchased();


--
-- Name: consumable_inventory_purchased trg_consumable_purchase_add; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_consumable_purchase_add AFTER INSERT OR DELETE OR UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.update_consumable_stock_purchased();


--
-- Name: coffee_inventory_history trg_copy_coffee_history_to_parent; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_copy_coffee_history_to_parent AFTER INSERT ON public.coffee_inventory_history FOR EACH ROW EXECUTE FUNCTION public.push_coffee_history_to_parent();


--
-- Name: consumable_inventory_history trg_copy_consumable_history_to_parent; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_copy_consumable_history_to_parent AFTER INSERT ON public.consumable_inventory_history FOR EACH ROW EXECUTE FUNCTION public.push_consumable_history_to_parent();


--
-- Name: order_details trg_handle_order_details; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_handle_order_details BEFORE INSERT OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.handle_order_detail_logic();


--
-- Name: coffee_inventory trg_manual_inventory_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_manual_inventory_update BEFORE INSERT OR UPDATE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.handle_manual_inventory_update();


--
-- Name: shipment_received trg_propagate_shipping_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_propagate_shipping_cost AFTER INSERT OR UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.trg_shipment_cost_update();


--
-- Name: coffee_inventory_purchased trg_push_last_coffee_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_push_last_coffee_cost AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.trg_coffee_purchase_cost_update();


--
-- Name: roast_recipes trg_recipe_header_changes; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_recipe_header_changes AFTER UPDATE ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.propagate_recipe_header_changes();


--
-- Name: roast_log trg_roast_log_smart_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_roast_log_smart_update AFTER INSERT OR DELETE OR UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.update_roast_detail_by_components();


--
-- Name: order_details trg_sync_consumable_usage; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_consumable_usage AFTER INSERT OR DELETE OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_consumable_stock();


--
-- Name: recipe_components trg_sync_recipe_costs; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_recipe_costs BEFORE INSERT OR UPDATE ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.sync_recipe_component_costs();


--
-- Name: order_details trg_sync_totals_from_order; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_totals_from_order AFTER INSERT OR DELETE OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_totals_from_order();


--
-- Name: orders trg_sync_totals_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_totals_status AFTER UPDATE OF order_status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_totals_from_order_status();


--
-- Name: blending_worksheet trg_update_blend_summary; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_blend_summary BEFORE INSERT OR UPDATE OF roast_recipe_id, amount_to_blend ON public.blending_worksheet FOR EACH ROW EXECUTE FUNCTION public.calculate_blend_summary();


--
-- Name: consumable_inventory trg_update_consumable_ordering; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_consumable_ordering BEFORE INSERT OR UPDATE ON public.consumable_inventory FOR EACH ROW EXECUTE FUNCTION public.update_consumable_metrics();


--
-- Name: coffee_inventory trg_update_green_metrics; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_green_metrics AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.calculate_green_purchasing_metrics();


--
-- Name: order_details trg_update_order_totals; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_order_totals AFTER INSERT OR DELETE OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_order_aggregates();


--
-- Name: roast_recipes trg_update_roasted_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_roasted_cost BEFORE INSERT OR UPDATE OF cost_lb_green ON public.roast_recipes FOR EACH ROW EXECUTE FUNCTION public.trigger_sync_roasted_cost();


--
-- Name: coffee_inventory trigger_calculate_ordered_lbs; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_calculate_ordered_lbs BEFORE INSERT OR UPDATE ON public.coffee_inventory FOR EACH ROW EXECUTE FUNCTION public.update_actual_ordered_lbs();


--
-- Name: customers trigger_manual_interval_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_manual_interval_change BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.update_effective_interval_on_manual_change();


--
-- Name: order_details trigger_order_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_order_update AFTER INSERT OR DELETE OR UPDATE ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_roast_detail_from_order_trigger();


--
-- Name: recipe_components trigger_recipe_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_recipe_update AFTER INSERT OR DELETE OR UPDATE ON public.recipe_components FOR EACH ROW EXECUTE FUNCTION public.update_roast_detail_from_recipe_trigger();


--
-- Name: orders trigger_refresh_customer_stats; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_refresh_customer_stats AFTER INSERT OR DELETE OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_customer_metrics_on_order();


--
-- Name: roast_log trigger_roast_log_update_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_roast_log_update_inventory AFTER INSERT OR DELETE OR UPDATE ON public.roast_log FOR EACH ROW EXECUTE FUNCTION public.trg_roast_log_inventory_update();


--
-- Name: orders trigger_update_order_metrics; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_order_metrics BEFORE INSERT OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_order_metrics();


--
-- Name: shipment_received trigger_update_shipping_unit_cost; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_shipping_unit_cost AFTER INSERT OR UPDATE ON public.shipment_received FOR EACH ROW EXECUTE FUNCTION public.calculate_shipping_per_unit();


--
-- Name: coffee_inventory_purchased update_shipment_on_coffee; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_shipment_on_coffee AFTER INSERT OR DELETE OR UPDATE ON public.coffee_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.calculate_shipment_totals();


--
-- Name: consumable_inventory_purchased update_shipment_on_consumable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_shipment_on_consumable AFTER INSERT OR DELETE OR UPDATE ON public.consumable_inventory_purchased FOR EACH ROW EXECUTE FUNCTION public.calculate_shipment_totals();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: supabase_admin
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: blending_worksheet blending_worksheet_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: blending_worksheet blending_worksheet_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blending_worksheet
    ADD CONSTRAINT blending_worksheet_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: charge_weight_options charge_weight_options_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: charge_weight_options charge_weight_options_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.charge_weight_options
    ADD CONSTRAINT charge_weight_options_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory coffee_inventory_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_inventory coffee_inventory_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory
    ADD CONSTRAINT coffee_inventory_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory_history coffee_inventory_history_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory_history
    ADD CONSTRAINT coffee_inventory_history_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_inventory_purchased coffee_inventory_purchased_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_inventory_purchased
    ADD CONSTRAINT coffee_inventory_purchased_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: coffee_usage_by_month coffee_usage_by_month_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: coffee_usage_by_month coffee_usage_by_month_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coffee_usage_by_month
    ADD CONSTRAINT coffee_usage_by_month_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: company_parameters company_parameters_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: company_parameters company_parameters_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: company_parameters company_parameters_parameter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_parameters
    ADD CONSTRAINT company_parameters_parameter_id_fkey FOREIGN KEY (parameter_id) REFERENCES public.standard_parameters(parameters_id);


--
-- Name: consumable_inventory consumable_inventory_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: consumable_inventory consumable_inventory_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory
    ADD CONSTRAINT consumable_inventory_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: consumable_inventory_history consumable_inventory_history_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory_history
    ADD CONSTRAINT consumable_inventory_history_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: consumable_inventory_purchased consumable_inventory_purchased_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumable_inventory_purchased
    ADD CONSTRAINT consumable_inventory_purchased_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: contact_role contact_role_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_role
    ADD CONSTRAINT contact_role_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: contacts contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: contacts contacts_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customer_notes_detail customer_notes_detail_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customer_notes_detail customer_notes_detail_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE CASCADE;


--
-- Name: customer_notes_detail customer_notes_detail_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_notes_detail
    ADD CONSTRAINT customer_notes_detail_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customer_sales_filter customer_sales_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customer_sales_filter customer_sales_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_sales_filter
    ADD CONSTRAINT customer_sales_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customers customers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: customers customers_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.setup_countries(country_code);


--
-- Name: customers customers_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: customers customers_sales_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_sales_area_fkey FOREIGN KEY (sales_area) REFERENCES public.sales_area(id);


--
-- Name: customers customers_sales_region_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_sales_region_fkey FOREIGN KEY (sales_region) REFERENCES public.sales_region(id);


--
-- Name: facilities facilities_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id) ON DELETE CASCADE;


--
-- Name: facilities facilities_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_country_fkey FOREIGN KEY (country_code) REFERENCES public.setup_countries(country_code);


--
-- Name: customers fk_last_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_last_order FOREIGN KEY (last_order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- Name: management_type management_type_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.management_type
    ADD CONSTRAINT management_type_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: open_order_totals open_order_totals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.open_order_totals
    ADD CONSTRAINT open_order_totals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: order_details order_details_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: order_details order_details_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: orders orders_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: orders orders_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: product_consumables product_consumables_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: product_consumables product_consumables_consumable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_consumable_id_fkey FOREIGN KEY (consumable_id) REFERENCES public.consumable_inventory(consumable_inventory_id) ON DELETE CASCADE;


--
-- Name: product_consumables product_consumables_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: product_consumables product_consumables_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_consumables
    ADD CONSTRAINT product_consumables_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- Name: product_filter product_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: product_filter product_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_filter
    ADD CONSTRAINT product_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: products products_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: products products_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: products_price_log products_price_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT products_price_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: products_price_log products_price_log_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products_price_log
    ADD CONSTRAINT products_price_log_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: recent_coffee_order recent_coffee_order_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: recent_coffee_order recent_coffee_order_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recent_coffee_order
    ADD CONSTRAINT recent_coffee_order_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: recipe_components recipe_components_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: recipe_components recipe_components_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recipe_components
    ADD CONSTRAINT recipe_components_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_detail_by_blend roast_detail_by_blend_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail_by_blend
    ADD CONSTRAINT roast_detail_by_blend_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_detail_by_blend roast_detail_by_blend_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail_by_blend
    ADD CONSTRAINT roast_detail_by_blend_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_detail roast_detail_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail
    ADD CONSTRAINT roast_detail_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_detail roast_detail_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_detail
    ADD CONSTRAINT roast_detail_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_log roast_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_log roast_log_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_log
    ADD CONSTRAINT roast_log_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: roast_recipes roast_recipes_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT roast_recipes_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: roast_recipes roast_recipes_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roast_recipes
    ADD CONSTRAINT roast_recipes_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_activity sales_activity_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_activity
    ADD CONSTRAINT sales_activity_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_activity sales_activity_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_activity
    ADD CONSTRAINT sales_activity_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_area sales_area_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_area_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.sales_state(id);


--
-- Name: sales_category sales_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_category
    ADD CONSTRAINT sales_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_city sales_city_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_city
    ADD CONSTRAINT sales_city_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.sales_state(id);


--
-- Name: sales_data_filter sales_data_filter_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_data_filter sales_data_filter_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_data_filter
    ADD CONSTRAINT sales_data_filter_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_goals sales_goals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_goals sales_goals_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_goals
    ADD CONSTRAINT sales_goals_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: sales_notes sales_notes_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_notes
    ADD CONSTRAINT sales_notes_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_parameters sales_parameters_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_parameters
    ADD CONSTRAINT sales_parameters_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_area sales_region_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_area
    ADD CONSTRAINT sales_region_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_state sales_state_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_state
    ADD CONSTRAINT sales_state_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.sales_area(id);


--
-- Name: sales_state_backup sales_state_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_state_backup
    ADD CONSTRAINT sales_state_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_state sales_state_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_state
    ADD CONSTRAINT sales_state_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.sales_region(id);


--
-- Name: sales_tasks sales_tasks_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_tasks
    ADD CONSTRAINT sales_tasks_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: sales_tracking sales_tracking_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sales_tracking
    ADD CONSTRAINT sales_tracking_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: shipment_received shipment_received_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: shipment_received shipment_received_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shipment_received
    ADD CONSTRAINT shipment_received_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: size size_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.size
    ADD CONSTRAINT size_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: standard_parameters standard_parameters_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.standard_parameters
    ADD CONSTRAINT standard_parameters_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: supplier_category supplier_category_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier_category
    ADD CONSTRAINT supplier_category_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: supplier supplier_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: supplier supplier_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.supplier
    ADD CONSTRAINT supplier_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: team team_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: team team_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: team_member_role team_member_role_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team_member_role
    ADD CONSTRAINT team_member_role_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: totals totals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.totals
    ADD CONSTRAINT totals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(company_id);


--
-- Name: totals totals_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.totals
    ADD CONSTRAINT totals_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facilities(facility_id);


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: product_consumables Enable all access for authenticated users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable all access for authenticated users" ON public.product_consumables USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: sales_state Global Read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Global Read" ON public.sales_state FOR SELECT USING (true);


--
-- Name: setup_countries Public Read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read" ON public.setup_countries FOR SELECT USING (true);


--
-- Name: customer_category Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.customer_category FOR SELECT USING (true);


--
-- Name: sales_region Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.sales_region FOR SELECT USING (true);


--
-- Name: sales_state Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.sales_state FOR SELECT USING (true);


--
-- Name: setup_countries Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.setup_countries FOR SELECT USING (true);


--
-- Name: setup_timezones Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.setup_timezones FOR SELECT USING (true);


--
-- Name: user_roles Public Read Access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Access" ON public.user_roles FOR SELECT USING (true);


--
-- Name: blending_worksheet; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.blending_worksheet ENABLE ROW LEVEL SECURITY;

--
-- Name: charge_weight_options; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.charge_weight_options ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.coffee_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory_history; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.coffee_inventory_history ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_inventory_purchased; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.coffee_inventory_purchased ENABLE ROW LEVEL SECURITY;

--
-- Name: coffee_usage_by_month; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.coffee_usage_by_month ENABLE ROW LEVEL SECURITY;

--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: company_parameters; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.consumable_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory_history; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.consumable_inventory_history ENABLE ROW LEVEL SECURITY;

--
-- Name: consumable_inventory_purchased; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.consumable_inventory_purchased ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_role; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.contact_role ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_category; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customer_category ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_notes_detail; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customer_notes_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_sales_filter; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customer_sales_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: facilities; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.facilities ENABLE ROW LEVEL SECURITY;

--
-- Name: management_type; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.management_type ENABLE ROW LEVEL SECURITY;

--
-- Name: open_order_totals; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.open_order_totals ENABLE ROW LEVEL SECURITY;

--
-- Name: order_details; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.order_details ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: product_consumables; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_consumables ENABLE ROW LEVEL SECURITY;

--
-- Name: product_filter; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products_price_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products_price_log ENABLE ROW LEVEL SECURITY;

--
-- Name: recent_coffee_order; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.recent_coffee_order ENABLE ROW LEVEL SECURITY;

--
-- Name: recipe_components; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.recipe_components ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_detail; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roast_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_detail_by_blend; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roast_detail_by_blend ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roast_log ENABLE ROW LEVEL SECURITY;

--
-- Name: roast_recipes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.roast_recipes ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_activity; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_area; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_area ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_category; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_category ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_city; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_city ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_data_filter; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_data_filter ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_goals; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_goals ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_notes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_parameters; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_region; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_region ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_state; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_state ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_state_backup; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_state_backup ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_tasks; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_tracking; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sales_tracking ENABLE ROW LEVEL SECURITY;

--
-- Name: setup_countries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.setup_countries ENABLE ROW LEVEL SECURITY;

--
-- Name: setup_timezones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.setup_timezones ENABLE ROW LEVEL SECURITY;

--
-- Name: shipment_received; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.shipment_received ENABLE ROW LEVEL SECURITY;

--
-- Name: size; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.size ENABLE ROW LEVEL SECURITY;

--
-- Name: standard_parameters; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.standard_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.supplier ENABLE ROW LEVEL SECURITY;

--
-- Name: supplier_category; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.supplier_category ENABLE ROW LEVEL SECURITY;

--
-- Name: team; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.team ENABLE ROW LEVEL SECURITY;

--
-- Name: team_member_role; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.team_member_role ENABLE ROW LEVEL SECURITY;

--
-- Name: totals; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.totals ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: postgres
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION supabase_realtime OWNER TO postgres;

--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA auth TO dashboard_user;
GRANT USAGE ON SCHEMA auth TO postgres;


--
-- Name: SCHEMA cron; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA cron TO postgres WITH GRANT OPTION;


--
-- Name: SCHEMA extensions; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA extensions TO anon;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA extensions TO service_role;
GRANT ALL ON SCHEMA extensions TO dashboard_user;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA realtime; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA realtime TO postgres;
GRANT USAGE ON SCHEMA realtime TO anon;
GRANT USAGE ON SCHEMA realtime TO authenticated;
GRANT USAGE ON SCHEMA realtime TO service_role;
GRANT ALL ON SCHEMA realtime TO supabase_realtime_admin;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA storage TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON SCHEMA storage TO dashboard_user;


--
-- Name: SCHEMA vault; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA vault TO service_role;


--
-- Name: FUNCTION email(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.email() TO dashboard_user;


--
-- Name: FUNCTION jwt(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.jwt() TO postgres;
GRANT ALL ON FUNCTION auth.jwt() TO dashboard_user;


--
-- Name: FUNCTION role(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.role() TO dashboard_user;


--
-- Name: FUNCTION uid(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.uid() TO dashboard_user;


--
-- Name: FUNCTION alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION job_cache_invalidate(); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.job_cache_invalidate() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(job_name text, schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(job_name text, schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_id bigint); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_id bigint) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_name text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_name text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION armor(bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.armor(bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.armor(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea) TO dashboard_user;


--
-- Name: FUNCTION armor(bytea, text[], text[]); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.armor(bytea, text[], text[]) FROM postgres;
GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO dashboard_user;


--
-- Name: FUNCTION crypt(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.crypt(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.crypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.crypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION dearmor(text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.dearmor(text) FROM postgres;
GRANT ALL ON FUNCTION extensions.dearmor(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.dearmor(text) TO dashboard_user;


--
-- Name: FUNCTION decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION decrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.digest(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.digest(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.digest(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(text, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION gen_random_bytes(integer); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_random_bytes(integer) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO dashboard_user;


--
-- Name: FUNCTION gen_random_uuid(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_random_uuid() FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_salt(text) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_salt(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text) TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text, integer); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_salt(text, integer) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO dashboard_user;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_cron_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO dashboard_user;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.grant_pg_graphql_access() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION grant_pg_net_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_net_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO dashboard_user;


--
-- Name: FUNCTION hmac(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.hmac(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION hmac(text, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.hmac(text, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO dashboard_user;


--
-- Name: FUNCTION pgp_armor_headers(text, OUT key text, OUT value text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO dashboard_user;


--
-- Name: FUNCTION pgp_key_id(bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_key_id(bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgrst_ddl_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_ddl_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION pgrst_drop_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_drop_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.set_graphql_placeholder() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION uuid_generate_v1(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v1() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v1mc(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v1mc() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v3(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v4(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v4() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v5(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_nil(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_nil() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_nil() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_nil() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_dns(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_dns() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_oid(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_oid() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_url(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_url() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_x500(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_x500() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO dashboard_user;


--
-- Name: FUNCTION graphql("operationName" text, query text, variables jsonb, extensions jsonb); Type: ACL; Schema: graphql_public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO postgres;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO anon;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO authenticated;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO service_role;


--
-- Name: FUNCTION pg_reload_conf(); Type: ACL; Schema: pg_catalog; Owner: supabase_admin
--

GRANT ALL ON FUNCTION pg_catalog.pg_reload_conf() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION get_auth(p_usename text); Type: ACL; Schema: pgbouncer; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION pgbouncer.get_auth(p_usename text) FROM PUBLIC;
GRANT ALL ON FUNCTION pgbouncer.get_auth(p_usename text) TO pgbouncer;


--
-- Name: FUNCTION calculate_blend_summary(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_blend_summary() TO anon;
GRANT ALL ON FUNCTION public.calculate_blend_summary() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_blend_summary() TO service_role;


--
-- Name: FUNCTION calculate_current_stock_bags(p_origin_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_current_stock_bags(p_origin_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_current_stock_bags(p_origin_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_current_stock_bags(p_origin_id text) TO service_role;


--
-- Name: FUNCTION calculate_current_stock_consumables(p_consumable_id text, p_facility_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_current_stock_consumables(p_consumable_id text, p_facility_id text) TO service_role;


--
-- Name: FUNCTION calculate_current_stock_lbs(p_origin_id text, p_facility_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_current_stock_lbs(p_origin_id text, p_facility_id text) TO service_role;


--
-- Name: FUNCTION calculate_green_cost(recipe_id_param text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_green_cost(recipe_id_param text) TO anon;
GRANT ALL ON FUNCTION public.calculate_green_cost(recipe_id_param text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_green_cost(recipe_id_param text) TO service_role;


--
-- Name: FUNCTION calculate_green_purchasing_metrics(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_green_purchasing_metrics() TO anon;
GRANT ALL ON FUNCTION public.calculate_green_purchasing_metrics() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_green_purchasing_metrics() TO service_role;


--
-- Name: FUNCTION calculate_par(p_origin_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_par(p_origin_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_par(p_origin_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_par(p_origin_id text) TO service_role;


--
-- Name: FUNCTION calculate_recent_order_totals(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_recent_order_totals() TO anon;
GRANT ALL ON FUNCTION public.calculate_recent_order_totals() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_recent_order_totals() TO service_role;


--
-- Name: FUNCTION calculate_restock_level(p_origin_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_restock_level(p_origin_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_restock_level(p_origin_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_restock_level(p_origin_id text) TO service_role;


--
-- Name: FUNCTION calculate_roast_by_blend(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_roast_by_blend() TO anon;
GRANT ALL ON FUNCTION public.calculate_roast_by_blend() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_roast_by_blend() TO service_role;


--
-- Name: FUNCTION calculate_roast_detail_origin(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_roast_detail_origin() TO anon;
GRANT ALL ON FUNCTION public.calculate_roast_detail_origin() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_roast_detail_origin() TO service_role;


--
-- Name: FUNCTION calculate_roasted_cost(green_cost numeric, p_facility_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text) TO anon;
GRANT ALL ON FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_roasted_cost(green_cost numeric, p_facility_id text) TO service_role;


--
-- Name: FUNCTION calculate_shipment_totals(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_shipment_totals() TO anon;
GRANT ALL ON FUNCTION public.calculate_shipment_totals() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_shipment_totals() TO service_role;


--
-- Name: FUNCTION calculate_shipping_per_unit(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_shipping_per_unit() TO anon;
GRANT ALL ON FUNCTION public.calculate_shipping_per_unit() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_shipping_per_unit() TO service_role;


--
-- Name: FUNCTION calculate_totals_columns(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_totals_columns() TO anon;
GRANT ALL ON FUNCTION public.calculate_totals_columns() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_totals_columns() TO service_role;


--
-- Name: FUNCTION get_param(p_facility_id text, p_key text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_param(p_facility_id text, p_key text) TO anon;
GRANT ALL ON FUNCTION public.get_param(p_facility_id text, p_key text) TO authenticated;
GRANT ALL ON FUNCTION public.get_param(p_facility_id text, p_key text) TO service_role;


--
-- Name: FUNCTION handle_manual_inventory_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.handle_manual_inventory_update() TO anon;
GRANT ALL ON FUNCTION public.handle_manual_inventory_update() TO authenticated;
GRANT ALL ON FUNCTION public.handle_manual_inventory_update() TO service_role;


--
-- Name: FUNCTION handle_new_record(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.handle_new_record() TO anon;
GRANT ALL ON FUNCTION public.handle_new_record() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_record() TO service_role;


--
-- Name: FUNCTION handle_order_detail_logic(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.handle_order_detail_logic() TO anon;
GRANT ALL ON FUNCTION public.handle_order_detail_logic() TO authenticated;
GRANT ALL ON FUNCTION public.handle_order_detail_logic() TO service_role;


--
-- Name: FUNCTION handle_updated_at_timestamp(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.handle_updated_at_timestamp() TO anon;
GRANT ALL ON FUNCTION public.handle_updated_at_timestamp() TO authenticated;
GRANT ALL ON FUNCTION public.handle_updated_at_timestamp() TO service_role;


--
-- Name: FUNCTION handle_updated_record(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.handle_updated_record() TO anon;
GRANT ALL ON FUNCTION public.handle_updated_record() TO authenticated;
GRANT ALL ON FUNCTION public.handle_updated_record() TO service_role;


--
-- Name: FUNCTION nudge_all_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.nudge_all_inventory() TO anon;
GRANT ALL ON FUNCTION public.nudge_all_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.nudge_all_inventory() TO service_role;


--
-- Name: FUNCTION propagate_coffee_cost_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.propagate_coffee_cost_change() TO anon;
GRANT ALL ON FUNCTION public.propagate_coffee_cost_change() TO authenticated;
GRANT ALL ON FUNCTION public.propagate_coffee_cost_change() TO service_role;


--
-- Name: FUNCTION propagate_recipe_header_changes(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.propagate_recipe_header_changes() TO anon;
GRANT ALL ON FUNCTION public.propagate_recipe_header_changes() TO authenticated;
GRANT ALL ON FUNCTION public.propagate_recipe_header_changes() TO service_role;


--
-- Name: FUNCTION push_coffee_history_to_parent(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.push_coffee_history_to_parent() TO anon;
GRANT ALL ON FUNCTION public.push_coffee_history_to_parent() TO authenticated;
GRANT ALL ON FUNCTION public.push_coffee_history_to_parent() TO service_role;


--
-- Name: FUNCTION push_consumable_history_to_parent(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.push_consumable_history_to_parent() TO anon;
GRANT ALL ON FUNCTION public.push_consumable_history_to_parent() TO authenticated;
GRANT ALL ON FUNCTION public.push_consumable_history_to_parent() TO service_role;


--
-- Name: FUNCTION recalculate_inventory_cost(p_origin_id text, p_facility_id text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) TO anon;
GRANT ALL ON FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) TO authenticated;
GRANT ALL ON FUNCTION public.recalculate_inventory_cost(p_origin_id text, p_facility_id text) TO service_role;


--
-- Name: FUNCTION sync_recipe_component_costs(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.sync_recipe_component_costs() TO anon;
GRANT ALL ON FUNCTION public.sync_recipe_component_costs() TO authenticated;
GRANT ALL ON FUNCTION public.sync_recipe_component_costs() TO service_role;


--
-- Name: FUNCTION trg_coffee_purchase_cost_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_coffee_purchase_cost_update() TO anon;
GRANT ALL ON FUNCTION public.trg_coffee_purchase_cost_update() TO authenticated;
GRANT ALL ON FUNCTION public.trg_coffee_purchase_cost_update() TO service_role;


--
-- Name: FUNCTION trg_roast_log_inventory_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_roast_log_inventory_update() TO anon;
GRANT ALL ON FUNCTION public.trg_roast_log_inventory_update() TO authenticated;
GRANT ALL ON FUNCTION public.trg_roast_log_inventory_update() TO service_role;


--
-- Name: FUNCTION trg_shipment_cost_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_shipment_cost_update() TO anon;
GRANT ALL ON FUNCTION public.trg_shipment_cost_update() TO authenticated;
GRANT ALL ON FUNCTION public.trg_shipment_cost_update() TO service_role;


--
-- Name: FUNCTION trigger_sync_roasted_cost(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trigger_sync_roasted_cost() TO anon;
GRANT ALL ON FUNCTION public.trigger_sync_roasted_cost() TO authenticated;
GRANT ALL ON FUNCTION public.trigger_sync_roasted_cost() TO service_role;


--
-- Name: FUNCTION update_actual_ordered_lbs(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_actual_ordered_lbs() TO anon;
GRANT ALL ON FUNCTION public.update_actual_ordered_lbs() TO authenticated;
GRANT ALL ON FUNCTION public.update_actual_ordered_lbs() TO service_role;


--
-- Name: FUNCTION update_coffee_stock_purchased(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_coffee_stock_purchased() TO anon;
GRANT ALL ON FUNCTION public.update_coffee_stock_purchased() TO authenticated;
GRANT ALL ON FUNCTION public.update_coffee_stock_purchased() TO service_role;


--
-- Name: FUNCTION update_consumable_metrics(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_consumable_metrics() TO anon;
GRANT ALL ON FUNCTION public.update_consumable_metrics() TO authenticated;
GRANT ALL ON FUNCTION public.update_consumable_metrics() TO service_role;


--
-- Name: FUNCTION update_consumable_stock(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_consumable_stock() TO anon;
GRANT ALL ON FUNCTION public.update_consumable_stock() TO authenticated;
GRANT ALL ON FUNCTION public.update_consumable_stock() TO service_role;


--
-- Name: FUNCTION update_consumable_stock_purchased(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_consumable_stock_purchased() TO anon;
GRANT ALL ON FUNCTION public.update_consumable_stock_purchased() TO authenticated;
GRANT ALL ON FUNCTION public.update_consumable_stock_purchased() TO service_role;


--
-- Name: FUNCTION update_customer_metrics_on_order(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_customer_metrics_on_order() TO anon;
GRANT ALL ON FUNCTION public.update_customer_metrics_on_order() TO authenticated;
GRANT ALL ON FUNCTION public.update_customer_metrics_on_order() TO service_role;


--
-- Name: FUNCTION update_effective_interval_on_manual_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_effective_interval_on_manual_change() TO anon;
GRANT ALL ON FUNCTION public.update_effective_interval_on_manual_change() TO authenticated;
GRANT ALL ON FUNCTION public.update_effective_interval_on_manual_change() TO service_role;


--
-- Name: FUNCTION update_last_coffee_cost(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_last_coffee_cost() TO anon;
GRANT ALL ON FUNCTION public.update_last_coffee_cost() TO authenticated;
GRANT ALL ON FUNCTION public.update_last_coffee_cost() TO service_role;


--
-- Name: FUNCTION update_last_consumable_cost(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_last_consumable_cost() TO anon;
GRANT ALL ON FUNCTION public.update_last_consumable_cost() TO authenticated;
GRANT ALL ON FUNCTION public.update_last_consumable_cost() TO service_role;


--
-- Name: FUNCTION update_order_aggregates(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_order_aggregates() TO anon;
GRANT ALL ON FUNCTION public.update_order_aggregates() TO authenticated;
GRANT ALL ON FUNCTION public.update_order_aggregates() TO service_role;


--
-- Name: FUNCTION update_order_metrics(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_order_metrics() TO anon;
GRANT ALL ON FUNCTION public.update_order_metrics() TO authenticated;
GRANT ALL ON FUNCTION public.update_order_metrics() TO service_role;


--
-- Name: FUNCTION update_product_total_cogs(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_product_total_cogs() TO anon;
GRANT ALL ON FUNCTION public.update_product_total_cogs() TO authenticated;
GRANT ALL ON FUNCTION public.update_product_total_cogs() TO service_role;


--
-- Name: FUNCTION update_roast_detail_by_components(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_roast_detail_by_components() TO anon;
GRANT ALL ON FUNCTION public.update_roast_detail_by_components() TO authenticated;
GRANT ALL ON FUNCTION public.update_roast_detail_by_components() TO service_role;


--
-- Name: FUNCTION update_roast_detail_from_order_trigger(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_roast_detail_from_order_trigger() TO anon;
GRANT ALL ON FUNCTION public.update_roast_detail_from_order_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.update_roast_detail_from_order_trigger() TO service_role;


--
-- Name: FUNCTION update_roast_detail_from_recipe_trigger(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_roast_detail_from_recipe_trigger() TO anon;
GRANT ALL ON FUNCTION public.update_roast_detail_from_recipe_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.update_roast_detail_from_recipe_trigger() TO service_role;


--
-- Name: FUNCTION update_totals_from_order(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_totals_from_order() TO anon;
GRANT ALL ON FUNCTION public.update_totals_from_order() TO authenticated;
GRANT ALL ON FUNCTION public.update_totals_from_order() TO service_role;


--
-- Name: FUNCTION update_totals_from_order_status(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_totals_from_order_status() TO anon;
GRANT ALL ON FUNCTION public.update_totals_from_order_status() TO authenticated;
GRANT ALL ON FUNCTION public.update_totals_from_order_status() TO service_role;


--
-- Name: FUNCTION apply_rls(wal jsonb, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO anon;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO authenticated;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO service_role;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO supabase_realtime_admin;


--
-- Name: FUNCTION broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO postgres;
GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO dashboard_user;


--
-- Name: FUNCTION build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO postgres;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO anon;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO service_role;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO supabase_realtime_admin;


--
-- Name: FUNCTION "cast"(val text, type_ regtype); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO postgres;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO dashboard_user;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO anon;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO authenticated;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO service_role;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO supabase_realtime_admin;


--
-- Name: FUNCTION check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO postgres;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO anon;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO authenticated;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO service_role;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO supabase_realtime_admin;


--
-- Name: FUNCTION is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO postgres;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO anon;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO service_role;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO supabase_realtime_admin;


--
-- Name: FUNCTION list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO anon;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO authenticated;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO service_role;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO supabase_realtime_admin;


--
-- Name: FUNCTION quote_wal2json(entity regclass); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO postgres;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO anon;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO authenticated;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO service_role;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO supabase_realtime_admin;


--
-- Name: FUNCTION send(payload jsonb, event text, topic text, private boolean); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO postgres;
GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO dashboard_user;


--
-- Name: FUNCTION subscription_check_filters(); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO postgres;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO dashboard_user;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO anon;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO authenticated;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO service_role;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO supabase_realtime_admin;


--
-- Name: FUNCTION to_regrole(role_name text); Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO postgres;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO anon;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO authenticated;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO service_role;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO supabase_realtime_admin;


--
-- Name: FUNCTION topic(); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.topic() TO postgres;
GRANT ALL ON FUNCTION realtime.topic() TO dashboard_user;


--
-- Name: FUNCTION _crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO service_role;


--
-- Name: FUNCTION create_secret(new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: FUNCTION update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: TABLE audit_log_entries; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.audit_log_entries TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.audit_log_entries TO postgres;
GRANT SELECT ON TABLE auth.audit_log_entries TO postgres WITH GRANT OPTION;


--
-- Name: TABLE flow_state; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.flow_state TO postgres;
GRANT SELECT ON TABLE auth.flow_state TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.flow_state TO dashboard_user;


--
-- Name: TABLE identities; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.identities TO postgres;
GRANT SELECT ON TABLE auth.identities TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.identities TO dashboard_user;


--
-- Name: TABLE instances; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.instances TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.instances TO postgres;
GRANT SELECT ON TABLE auth.instances TO postgres WITH GRANT OPTION;


--
-- Name: TABLE mfa_amr_claims; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_amr_claims TO postgres;
GRANT SELECT ON TABLE auth.mfa_amr_claims TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_amr_claims TO dashboard_user;


--
-- Name: TABLE mfa_challenges; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_challenges TO postgres;
GRANT SELECT ON TABLE auth.mfa_challenges TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_challenges TO dashboard_user;


--
-- Name: TABLE mfa_factors; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_factors TO postgres;
GRANT SELECT ON TABLE auth.mfa_factors TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_factors TO dashboard_user;


--
-- Name: TABLE oauth_authorizations; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_authorizations TO postgres;
GRANT ALL ON TABLE auth.oauth_authorizations TO dashboard_user;


--
-- Name: TABLE oauth_client_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_client_states TO postgres;
GRANT ALL ON TABLE auth.oauth_client_states TO dashboard_user;


--
-- Name: TABLE oauth_clients; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_clients TO postgres;
GRANT ALL ON TABLE auth.oauth_clients TO dashboard_user;


--
-- Name: TABLE oauth_consents; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_consents TO postgres;
GRANT ALL ON TABLE auth.oauth_consents TO dashboard_user;


--
-- Name: TABLE one_time_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.one_time_tokens TO postgres;
GRANT SELECT ON TABLE auth.one_time_tokens TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.one_time_tokens TO dashboard_user;


--
-- Name: TABLE refresh_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.refresh_tokens TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.refresh_tokens TO postgres;
GRANT SELECT ON TABLE auth.refresh_tokens TO postgres WITH GRANT OPTION;


--
-- Name: SEQUENCE refresh_tokens_id_seq; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO dashboard_user;
GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO postgres;


--
-- Name: TABLE saml_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_providers TO postgres;
GRANT SELECT ON TABLE auth.saml_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_providers TO dashboard_user;


--
-- Name: TABLE saml_relay_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_relay_states TO postgres;
GRANT SELECT ON TABLE auth.saml_relay_states TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_relay_states TO dashboard_user;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT SELECT ON TABLE auth.schema_migrations TO postgres WITH GRANT OPTION;


--
-- Name: TABLE sessions; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sessions TO postgres;
GRANT SELECT ON TABLE auth.sessions TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sessions TO dashboard_user;


--
-- Name: TABLE sso_domains; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_domains TO postgres;
GRANT SELECT ON TABLE auth.sso_domains TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_domains TO dashboard_user;


--
-- Name: TABLE sso_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_providers TO postgres;
GRANT SELECT ON TABLE auth.sso_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_providers TO dashboard_user;


--
-- Name: TABLE users; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.users TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.users TO postgres;
GRANT SELECT ON TABLE auth.users TO postgres WITH GRANT OPTION;


--
-- Name: TABLE job; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT SELECT ON TABLE cron.job TO postgres WITH GRANT OPTION;


--
-- Name: TABLE job_run_details; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON TABLE cron.job_run_details TO postgres WITH GRANT OPTION;


--
-- Name: TABLE pg_stat_statements; Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON TABLE extensions.pg_stat_statements FROM postgres;
GRANT ALL ON TABLE extensions.pg_stat_statements TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements TO dashboard_user;


--
-- Name: TABLE pg_stat_statements_info; Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON TABLE extensions.pg_stat_statements_info FROM postgres;
GRANT ALL ON TABLE extensions.pg_stat_statements_info TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements_info TO dashboard_user;


--
-- Name: TABLE blending_worksheet; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.blending_worksheet TO anon;
GRANT ALL ON TABLE public.blending_worksheet TO authenticated;
GRANT ALL ON TABLE public.blending_worksheet TO service_role;


--
-- Name: TABLE charge_weight_options; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.charge_weight_options TO anon;
GRANT ALL ON TABLE public.charge_weight_options TO authenticated;
GRANT ALL ON TABLE public.charge_weight_options TO service_role;


--
-- Name: TABLE coffee_inventory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.coffee_inventory TO anon;
GRANT ALL ON TABLE public.coffee_inventory TO authenticated;
GRANT ALL ON TABLE public.coffee_inventory TO service_role;


--
-- Name: TABLE coffee_inventory_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.coffee_inventory_history TO anon;
GRANT ALL ON TABLE public.coffee_inventory_history TO authenticated;
GRANT ALL ON TABLE public.coffee_inventory_history TO service_role;


--
-- Name: TABLE coffee_inventory_purchased; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.coffee_inventory_purchased TO anon;
GRANT ALL ON TABLE public.coffee_inventory_purchased TO authenticated;
GRANT ALL ON TABLE public.coffee_inventory_purchased TO service_role;


--
-- Name: TABLE coffee_usage_by_month; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.coffee_usage_by_month TO anon;
GRANT ALL ON TABLE public.coffee_usage_by_month TO authenticated;
GRANT ALL ON TABLE public.coffee_usage_by_month TO service_role;


--
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.companies TO anon;
GRANT ALL ON TABLE public.companies TO authenticated;
GRANT ALL ON TABLE public.companies TO service_role;


--
-- Name: TABLE company_parameters; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.company_parameters TO anon;
GRANT ALL ON TABLE public.company_parameters TO authenticated;
GRANT ALL ON TABLE public.company_parameters TO service_role;


--
-- Name: TABLE consumable_inventory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.consumable_inventory TO anon;
GRANT ALL ON TABLE public.consumable_inventory TO authenticated;
GRANT ALL ON TABLE public.consumable_inventory TO service_role;


--
-- Name: TABLE consumable_inventory_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.consumable_inventory_history TO anon;
GRANT ALL ON TABLE public.consumable_inventory_history TO authenticated;
GRANT ALL ON TABLE public.consumable_inventory_history TO service_role;


--
-- Name: TABLE consumable_inventory_purchased; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.consumable_inventory_purchased TO anon;
GRANT ALL ON TABLE public.consumable_inventory_purchased TO authenticated;
GRANT ALL ON TABLE public.consumable_inventory_purchased TO service_role;


--
-- Name: TABLE contact_role; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contact_role TO anon;
GRANT ALL ON TABLE public.contact_role TO authenticated;
GRANT ALL ON TABLE public.contact_role TO service_role;


--
-- Name: TABLE contacts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contacts TO anon;
GRANT ALL ON TABLE public.contacts TO authenticated;
GRANT ALL ON TABLE public.contacts TO service_role;


--
-- Name: TABLE customer_category; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customer_category TO anon;
GRANT ALL ON TABLE public.customer_category TO authenticated;
GRANT ALL ON TABLE public.customer_category TO service_role;


--
-- Name: TABLE customer_notes_detail; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customer_notes_detail TO anon;
GRANT ALL ON TABLE public.customer_notes_detail TO authenticated;
GRANT ALL ON TABLE public.customer_notes_detail TO service_role;


--
-- Name: TABLE customer_sales_filter; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customer_sales_filter TO anon;
GRANT ALL ON TABLE public.customer_sales_filter TO authenticated;
GRANT ALL ON TABLE public.customer_sales_filter TO service_role;


--
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO anon;
GRANT ALL ON TABLE public.customers TO authenticated;
GRANT ALL ON TABLE public.customers TO service_role;


--
-- Name: TABLE facilities; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.facilities TO anon;
GRANT ALL ON TABLE public.facilities TO authenticated;
GRANT ALL ON TABLE public.facilities TO service_role;


--
-- Name: TABLE management_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.management_type TO anon;
GRANT ALL ON TABLE public.management_type TO authenticated;
GRANT ALL ON TABLE public.management_type TO service_role;


--
-- Name: TABLE open_order_totals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.open_order_totals TO anon;
GRANT ALL ON TABLE public.open_order_totals TO authenticated;
GRANT ALL ON TABLE public.open_order_totals TO service_role;


--
-- Name: TABLE order_details; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_details TO anon;
GRANT ALL ON TABLE public.order_details TO authenticated;
GRANT ALL ON TABLE public.order_details TO service_role;


--
-- Name: TABLE order_graphs_week; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_graphs_week TO anon;
GRANT ALL ON TABLE public.order_graphs_week TO authenticated;
GRANT ALL ON TABLE public.order_graphs_week TO service_role;


--
-- Name: TABLE order_graphs_weekly_avg_by_month; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_month TO anon;
GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_month TO authenticated;
GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_month TO service_role;


--
-- Name: TABLE order_graphs_weekly_avg_by_year; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_year TO anon;
GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_year TO authenticated;
GRANT ALL ON TABLE public.order_graphs_weekly_avg_by_year TO service_role;


--
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO anon;
GRANT ALL ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.orders TO service_role;


--
-- Name: TABLE product_consumables; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_consumables TO anon;
GRANT ALL ON TABLE public.product_consumables TO authenticated;
GRANT ALL ON TABLE public.product_consumables TO service_role;


--
-- Name: TABLE product_filter; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_filter TO anon;
GRANT ALL ON TABLE public.product_filter TO authenticated;
GRANT ALL ON TABLE public.product_filter TO service_role;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO anon;
GRANT ALL ON TABLE public.products TO authenticated;
GRANT ALL ON TABLE public.products TO service_role;


--
-- Name: TABLE products_price_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products_price_log TO anon;
GRANT ALL ON TABLE public.products_price_log TO authenticated;
GRANT ALL ON TABLE public.products_price_log TO service_role;


--
-- Name: TABLE recent_coffee_order; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.recent_coffee_order TO anon;
GRANT ALL ON TABLE public.recent_coffee_order TO authenticated;
GRANT ALL ON TABLE public.recent_coffee_order TO service_role;


--
-- Name: TABLE recipe_components; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.recipe_components TO anon;
GRANT ALL ON TABLE public.recipe_components TO authenticated;
GRANT ALL ON TABLE public.recipe_components TO service_role;


--
-- Name: TABLE roast_detail; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roast_detail TO anon;
GRANT ALL ON TABLE public.roast_detail TO authenticated;
GRANT ALL ON TABLE public.roast_detail TO service_role;


--
-- Name: TABLE roast_detail_by_blend; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roast_detail_by_blend TO anon;
GRANT ALL ON TABLE public.roast_detail_by_blend TO authenticated;
GRANT ALL ON TABLE public.roast_detail_by_blend TO service_role;


--
-- Name: TABLE roast_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roast_log TO anon;
GRANT ALL ON TABLE public.roast_log TO authenticated;
GRANT ALL ON TABLE public.roast_log TO service_role;


--
-- Name: TABLE roast_recipes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roast_recipes TO anon;
GRANT ALL ON TABLE public.roast_recipes TO authenticated;
GRANT ALL ON TABLE public.roast_recipes TO service_role;


--
-- Name: TABLE sales_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_activity TO anon;
GRANT ALL ON TABLE public.sales_activity TO authenticated;
GRANT ALL ON TABLE public.sales_activity TO service_role;


--
-- Name: TABLE sales_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_area TO anon;
GRANT ALL ON TABLE public.sales_area TO authenticated;
GRANT ALL ON TABLE public.sales_area TO service_role;


--
-- Name: TABLE sales_category; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_category TO anon;
GRANT ALL ON TABLE public.sales_category TO authenticated;
GRANT ALL ON TABLE public.sales_category TO service_role;


--
-- Name: TABLE sales_city; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_city TO anon;
GRANT ALL ON TABLE public.sales_city TO authenticated;
GRANT ALL ON TABLE public.sales_city TO service_role;


--
-- Name: TABLE sales_data_filter; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_data_filter TO anon;
GRANT ALL ON TABLE public.sales_data_filter TO authenticated;
GRANT ALL ON TABLE public.sales_data_filter TO service_role;


--
-- Name: TABLE sales_goals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_goals TO anon;
GRANT ALL ON TABLE public.sales_goals TO authenticated;
GRANT ALL ON TABLE public.sales_goals TO service_role;


--
-- Name: TABLE sales_notes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_notes TO anon;
GRANT ALL ON TABLE public.sales_notes TO authenticated;
GRANT ALL ON TABLE public.sales_notes TO service_role;


--
-- Name: TABLE sales_parameters; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_parameters TO anon;
GRANT ALL ON TABLE public.sales_parameters TO authenticated;
GRANT ALL ON TABLE public.sales_parameters TO service_role;


--
-- Name: TABLE sales_region; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_region TO anon;
GRANT ALL ON TABLE public.sales_region TO authenticated;
GRANT ALL ON TABLE public.sales_region TO service_role;


--
-- Name: TABLE sales_state; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_state TO anon;
GRANT ALL ON TABLE public.sales_state TO authenticated;
GRANT ALL ON TABLE public.sales_state TO service_role;


--
-- Name: TABLE sales_state_backup; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_state_backup TO anon;
GRANT ALL ON TABLE public.sales_state_backup TO authenticated;
GRANT ALL ON TABLE public.sales_state_backup TO service_role;


--
-- Name: TABLE sales_tasks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_tasks TO anon;
GRANT ALL ON TABLE public.sales_tasks TO authenticated;
GRANT ALL ON TABLE public.sales_tasks TO service_role;


--
-- Name: TABLE sales_tracking; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sales_tracking TO anon;
GRANT ALL ON TABLE public.sales_tracking TO authenticated;
GRANT ALL ON TABLE public.sales_tracking TO service_role;


--
-- Name: TABLE setup_countries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.setup_countries TO anon;
GRANT ALL ON TABLE public.setup_countries TO authenticated;
GRANT ALL ON TABLE public.setup_countries TO service_role;


--
-- Name: TABLE setup_timezones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.setup_timezones TO anon;
GRANT ALL ON TABLE public.setup_timezones TO authenticated;
GRANT ALL ON TABLE public.setup_timezones TO service_role;


--
-- Name: TABLE shipment_received; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.shipment_received TO anon;
GRANT ALL ON TABLE public.shipment_received TO authenticated;
GRANT ALL ON TABLE public.shipment_received TO service_role;


--
-- Name: TABLE size; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.size TO anon;
GRANT ALL ON TABLE public.size TO authenticated;
GRANT ALL ON TABLE public.size TO service_role;


--
-- Name: TABLE standard_parameters; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.standard_parameters TO anon;
GRANT ALL ON TABLE public.standard_parameters TO authenticated;
GRANT ALL ON TABLE public.standard_parameters TO service_role;


--
-- Name: TABLE summarized_weight_weekly; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.summarized_weight_weekly TO anon;
GRANT ALL ON TABLE public.summarized_weight_weekly TO authenticated;
GRANT ALL ON TABLE public.summarized_weight_weekly TO service_role;


--
-- Name: TABLE summarized_weight_monthly; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.summarized_weight_monthly TO anon;
GRANT ALL ON TABLE public.summarized_weight_monthly TO authenticated;
GRANT ALL ON TABLE public.summarized_weight_monthly TO service_role;


--
-- Name: TABLE summarized_weight_yearly; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.summarized_weight_yearly TO anon;
GRANT ALL ON TABLE public.summarized_weight_yearly TO authenticated;
GRANT ALL ON TABLE public.summarized_weight_yearly TO service_role;


--
-- Name: TABLE supplier; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.supplier TO anon;
GRANT ALL ON TABLE public.supplier TO authenticated;
GRANT ALL ON TABLE public.supplier TO service_role;


--
-- Name: TABLE supplier_category; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.supplier_category TO anon;
GRANT ALL ON TABLE public.supplier_category TO authenticated;
GRANT ALL ON TABLE public.supplier_category TO service_role;


--
-- Name: TABLE team; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.team TO anon;
GRANT ALL ON TABLE public.team TO authenticated;
GRANT ALL ON TABLE public.team TO service_role;


--
-- Name: TABLE team_member_role; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.team_member_role TO anon;
GRANT ALL ON TABLE public.team_member_role TO authenticated;
GRANT ALL ON TABLE public.team_member_role TO service_role;


--
-- Name: TABLE totals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.totals TO anon;
GRANT ALL ON TABLE public.totals TO authenticated;
GRANT ALL ON TABLE public.totals TO service_role;


--
-- Name: TABLE user_roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_roles TO anon;
GRANT ALL ON TABLE public.user_roles TO authenticated;
GRANT ALL ON TABLE public.user_roles TO service_role;


--
-- Name: TABLE weekly_grand_total; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.weekly_grand_total TO anon;
GRANT ALL ON TABLE public.weekly_grand_total TO authenticated;
GRANT ALL ON TABLE public.weekly_grand_total TO service_role;


--
-- Name: TABLE messages; Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON TABLE realtime.messages TO postgres;
GRANT ALL ON TABLE realtime.messages TO dashboard_user;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO service_role;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.schema_migrations TO postgres;
GRANT ALL ON TABLE realtime.schema_migrations TO dashboard_user;
GRANT SELECT ON TABLE realtime.schema_migrations TO anon;
GRANT SELECT ON TABLE realtime.schema_migrations TO authenticated;
GRANT SELECT ON TABLE realtime.schema_migrations TO service_role;
GRANT ALL ON TABLE realtime.schema_migrations TO supabase_realtime_admin;


--
-- Name: TABLE subscription; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON TABLE realtime.subscription TO postgres;
GRANT ALL ON TABLE realtime.subscription TO dashboard_user;
GRANT SELECT ON TABLE realtime.subscription TO anon;
GRANT SELECT ON TABLE realtime.subscription TO authenticated;
GRANT SELECT ON TABLE realtime.subscription TO service_role;
GRANT ALL ON TABLE realtime.subscription TO supabase_realtime_admin;


--
-- Name: SEQUENCE subscription_id_seq; Type: ACL; Schema: realtime; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO postgres;
GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO dashboard_user;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO anon;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO service_role;
GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO supabase_realtime_admin;


--
-- Name: TABLE buckets; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.buckets FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.buckets TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.buckets TO service_role;
GRANT ALL ON TABLE storage.buckets TO authenticated;
GRANT ALL ON TABLE storage.buckets TO anon;
GRANT ALL ON TABLE storage.buckets TO postgres WITH GRANT OPTION;


--
-- Name: TABLE buckets_analytics; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.buckets_analytics TO service_role;
GRANT ALL ON TABLE storage.buckets_analytics TO authenticated;
GRANT ALL ON TABLE storage.buckets_analytics TO anon;


--
-- Name: TABLE buckets_vectors; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.buckets_vectors TO service_role;
GRANT SELECT ON TABLE storage.buckets_vectors TO authenticated;
GRANT SELECT ON TABLE storage.buckets_vectors TO anon;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.objects FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.objects TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.objects TO service_role;
GRANT ALL ON TABLE storage.objects TO authenticated;
GRANT ALL ON TABLE storage.objects TO anon;
GRANT ALL ON TABLE storage.objects TO postgres WITH GRANT OPTION;


--
-- Name: TABLE s3_multipart_uploads; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO anon;


--
-- Name: TABLE s3_multipart_uploads_parts; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads_parts TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO anon;


--
-- Name: TABLE vector_indexes; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.vector_indexes TO service_role;
GRANT SELECT ON TABLE storage.vector_indexes TO authenticated;
GRANT SELECT ON TABLE storage.vector_indexes TO anon;


--
-- Name: TABLE secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.secrets TO service_role;


--
-- Name: TABLE decrypted_secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.decrypted_secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.decrypted_secrets TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO service_role;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


ALTER EVENT TRIGGER issue_graphql_placeholder OWNER TO supabase_admin;

--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


ALTER EVENT TRIGGER issue_pg_cron_access OWNER TO supabase_admin;

--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE FUNCTION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


ALTER EVENT TRIGGER issue_pg_graphql_access OWNER TO supabase_admin;

--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


ALTER EVENT TRIGGER issue_pg_net_access OWNER TO supabase_admin;

--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


ALTER EVENT TRIGGER pgrst_ddl_watch OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


ALTER EVENT TRIGGER pgrst_drop_watch OWNER TO supabase_admin;

--
-- PostgreSQL database dump complete
--

\unrestrict 4hCKw1L32v7nR97P48mKbITdFFeYG99Oc5hrGfRAkcI9RjCQd2IwKcpmBacIjJN

