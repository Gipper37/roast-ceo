-- SMARTroast learning infrastructure — telemetry + per-unit + per-model
-- calibration that the algorithm reads at fire time.
--
-- ── Three-tier resolution chain ──────────────────────────────────
--   1. roaster_unit_smartroast_calibration (≥ 5 fires on this unit)
--      → operator's specific machine + probe placement + style
--   2. roaster_model_smartroast_calibration (≥ 50 fires on this make+model
--      pooled across companies) → typical curve for this hardware
--   3. hardcoded sensitivity tier defaults → cold start
--
-- ── Why pool models across tenants ───────────────────────────────
-- A Probat Probatone 5kg behaves the same regardless of who owns it.
-- Pooling fires across all customers running that model gives us a
-- robust baseline in weeks instead of months per customer. The data
-- being pooled is hardware-level (BT range, drop rate magnitude) —
-- no coffee names, no recipes, no PII. Safe to share.
--
-- ── Why a separate log table ─────────────────────────────────────
-- We log EVERY event (auto fire, manual press, auto-then-cancelled)
-- so we can:
--   - Compute accuracy deltas (auto fired here, operator confirmed at
--     this time → drift = X seconds)
--   - Tune thresholds from real production data, not synthetic spike
--   - A/B sensitivity tiers ("conservative misses fewer roasts than
--     normal on Probatones")
--   - Detect drift over time (probe replaced → calibration shifts)
--
-- ── Trigger updates ──────────────────────────────────────────────
-- After every CONFIRMED event (source='auto' that wasn't cancelled,
-- OR source='manual' that has BT data), update both calibration
-- tables with running averages. Cancelled fires are NOT used for
-- learning (they're the operator saying "you were wrong").

BEGIN;

-- ── 1. Telemetry log ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS roast_smartroast_log (
  log_id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Nullable: SMARTroast fires BEFORE the session row exists (CHARGE
  -- happens before save; DROP happens before save in the current
  -- pipeline). Logging at fire time means session_id is null; an
  -- optional save-time backfill UPDATE can fill it in. The trigger
  -- that updates calibration tables only depends on roaster_unit_id.
  session_id          text        NULL,
  facility_id         text        NOT NULL,
  company_id          text        NOT NULL,
  roaster_unit_id     uuid        NULL,
  event_type          text        NOT NULL,    -- 'charge' | 'drop'
  source              text        NOT NULL,    -- 'auto' | 'manual' | 'auto_cancelled'

  -- Time math (all unix ms relative to nothing; we store deltas)
  fired_at_ms         bigint      NULL,        -- when algorithm said "fire"
  peak_at_ms          bigint      NULL,        -- when peak BT was observed (= committed event time)
  manual_press_at_ms  bigint      NULL,        -- when operator pressed button (if applicable)

  -- Signal stats — what the algorithm "saw" at fire time
  peak_bt             numeric     NULL,        -- BT at peak (the calibration-learning value)
  cliff_rate          numeric     NULL,        -- °F/s drop rate that triggered

  -- Algorithm configuration at fire time (audit trail)
  sensitivity_used    text        NULL,        -- 'conservative'|'normal'|'aggressive'
  thresholds_used     jsonb       NULL,        -- {dropRate, windowMs, minPeakBt, ...}

  -- Where did the thresholds come from? Important for learning loop.
  calibration_source  text        NULL,        -- 'hardcoded'|'model'|'unit'

  created_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT smartroast_log_event_type_check
    CHECK (event_type IN ('charge', 'drop')),
  CONSTRAINT smartroast_log_source_check
    CHECK (source IN ('auto', 'manual', 'auto_cancelled')),
  CONSTRAINT smartroast_log_calibration_source_check
    CHECK (calibration_source IS NULL OR calibration_source IN ('hardcoded', 'model', 'unit')),

  CONSTRAINT smartroast_log_session_fk
    FOREIGN KEY (session_id) REFERENCES roast_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT smartroast_log_unit_fk
    FOREIGN KEY (roaster_unit_id) REFERENCES roaster_units(roaster_unit_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_smartroast_log_unit_event
  ON roast_smartroast_log (roaster_unit_id, event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_smartroast_log_company
  ON roast_smartroast_log (company_id, created_at DESC);

-- ── 2. Per-unit calibration ──────────────────────────────────────
-- Running aggregates by event_type. One row per (unit, event_type).
-- Updated by a trigger on roast_smartroast_log.
CREATE TABLE IF NOT EXISTS roaster_unit_smartroast_calibration (
  roaster_unit_id     uuid        NOT NULL,
  event_type          text        NOT NULL,    -- 'charge' | 'drop'
  company_id          text        NOT NULL,    -- denormalized for RLS later

  sample_count        integer     NOT NULL DEFAULT 0,
  peak_bt_avg         numeric     NULL,        -- mean peak BT seen on this unit
  peak_bt_stddev      numeric     NULL,        -- running stddev (Welford)
  peak_bt_m2          numeric     NULL DEFAULT 0,   -- Welford intermediate (sum of squared diffs)
  cliff_rate_avg      numeric     NULL,        -- mean cliff magnitude
  cliff_rate_m2       numeric     NULL DEFAULT 0,

  last_updated        timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (roaster_unit_id, event_type),
  CONSTRAINT unit_cal_event_check CHECK (event_type IN ('charge', 'drop')),
  CONSTRAINT unit_cal_unit_fk
    FOREIGN KEY (roaster_unit_id) REFERENCES roaster_units(roaster_unit_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_unit_cal_company
  ON roaster_unit_smartroast_calibration (company_id);

-- ── 3. Per-model calibration (pooled across companies) ───────────
-- Keyed by (brand, model, event_type). brand + model come from
-- roaster_units; pooling across tenants is fine because we're only
-- aggregating hardware-level signal statistics, not customer data.
CREATE TABLE IF NOT EXISTS roaster_model_smartroast_calibration (
  brand               text        NOT NULL,
  model               text        NOT NULL,
  event_type          text        NOT NULL,

  sample_count        integer     NOT NULL DEFAULT 0,
  peak_bt_avg         numeric     NULL,
  peak_bt_stddev      numeric     NULL,
  peak_bt_m2          numeric     NULL DEFAULT 0,
  cliff_rate_avg      numeric     NULL,
  cliff_rate_m2       numeric     NULL DEFAULT 0,

  -- How many companies have contributed to this row. Privacy /
  -- diversity signal — a model row dominated by one company isn't
  -- truly "pooled" yet.
  contributing_companies integer  NOT NULL DEFAULT 0,

  last_updated        timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (brand, model, event_type),
  CONSTRAINT model_cal_event_check CHECK (event_type IN ('charge', 'drop'))
);

-- ── 4. Trigger function: update both calibrations on confirmed fire
-- Uses Welford's online algorithm to maintain stable running variance
-- without storing every individual sample. Mean and M2 update in
-- O(1) per row.
CREATE OR REPLACE FUNCTION update_smartroast_calibrations()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_brand text;
  v_model text;
  v_old_count integer;
  v_old_mean numeric;
  v_old_m2 numeric;
  v_delta numeric;
  v_delta2 numeric;
  v_company_already_contributed boolean;
BEGIN
  -- Only confirmed fires teach the model. Cancelled auto-fires are
  -- the operator saying "wrong" — they tune in the OPPOSITE direction
  -- and we don't have a great way to weight that yet.
  IF NEW.source = 'auto_cancelled' THEN RETURN NEW; END IF;
  IF NEW.peak_bt IS NULL OR NEW.cliff_rate IS NULL THEN RETURN NEW; END IF;
  IF NEW.roaster_unit_id IS NULL THEN RETURN NEW; END IF;

  -- ── Per-unit update ───────────────────────────────────────────
  -- Welford: count_new = count + 1; mean_new = mean + delta/count_new
  -- M2_new = M2 + delta * (x - mean_new); stddev = sqrt(M2 / (count-1))
  INSERT INTO roaster_unit_smartroast_calibration (
    roaster_unit_id, event_type, company_id,
    sample_count, peak_bt_avg, peak_bt_m2, cliff_rate_avg, cliff_rate_m2, last_updated
  ) VALUES (
    NEW.roaster_unit_id, NEW.event_type, NEW.company_id,
    1, NEW.peak_bt, 0, NEW.cliff_rate, 0, now()
  )
  ON CONFLICT (roaster_unit_id, event_type) DO UPDATE
  SET
    sample_count   = roaster_unit_smartroast_calibration.sample_count + 1,
    peak_bt_avg    = roaster_unit_smartroast_calibration.peak_bt_avg
                     + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                       / (roaster_unit_smartroast_calibration.sample_count + 1),
    peak_bt_m2     = roaster_unit_smartroast_calibration.peak_bt_m2
                     + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                       * (NEW.peak_bt - (
                           roaster_unit_smartroast_calibration.peak_bt_avg
                           + (NEW.peak_bt - roaster_unit_smartroast_calibration.peak_bt_avg)
                             / (roaster_unit_smartroast_calibration.sample_count + 1)
                         )),
    cliff_rate_avg = roaster_unit_smartroast_calibration.cliff_rate_avg
                     + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                       / (roaster_unit_smartroast_calibration.sample_count + 1),
    cliff_rate_m2  = roaster_unit_smartroast_calibration.cliff_rate_m2
                     + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                       * (NEW.cliff_rate - (
                           roaster_unit_smartroast_calibration.cliff_rate_avg
                           + (NEW.cliff_rate - roaster_unit_smartroast_calibration.cliff_rate_avg)
                             / (roaster_unit_smartroast_calibration.sample_count + 1)
                         )),
    last_updated   = now();

  -- Recompute stddev from M2 (separate update since it depends on the
  -- just-updated count + M2).
  UPDATE roaster_unit_smartroast_calibration
  SET
    peak_bt_stddev = CASE WHEN sample_count > 1
                          THEN sqrt(peak_bt_m2 / (sample_count - 1))
                          ELSE NULL END
  WHERE roaster_unit_id = NEW.roaster_unit_id AND event_type = NEW.event_type;

  -- ── Per-model update ─────────────────────────────────────────
  SELECT brand, model INTO v_brand, v_model
  FROM roaster_units WHERE roaster_unit_id = NEW.roaster_unit_id;

  IF v_brand IS NOT NULL AND v_model IS NOT NULL THEN
    -- Track contributing_companies — only bump when this company isn't
    -- already in the pool for this (brand, model, event_type).
    SELECT EXISTS (
      SELECT 1 FROM roast_smartroast_log al
      JOIN roaster_units ru ON ru.roaster_unit_id = al.roaster_unit_id
      WHERE ru.brand = v_brand AND ru.model = v_model
        AND al.event_type = NEW.event_type
        AND al.company_id = NEW.company_id
        AND al.source IN ('auto', 'manual')
        AND al.log_id <> NEW.log_id
    ) INTO v_company_already_contributed;

    INSERT INTO roaster_model_smartroast_calibration (
      brand, model, event_type,
      sample_count, peak_bt_avg, peak_bt_m2, cliff_rate_avg, cliff_rate_m2,
      contributing_companies, last_updated
    ) VALUES (
      v_brand, v_model, NEW.event_type,
      1, NEW.peak_bt, 0, NEW.cliff_rate, 0,
      1, now()
    )
    ON CONFLICT (brand, model, event_type) DO UPDATE
    SET
      sample_count   = roaster_model_smartroast_calibration.sample_count + 1,
      peak_bt_avg    = roaster_model_smartroast_calibration.peak_bt_avg
                       + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                         / (roaster_model_smartroast_calibration.sample_count + 1),
      peak_bt_m2     = roaster_model_smartroast_calibration.peak_bt_m2
                       + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                         * (NEW.peak_bt - (
                             roaster_model_smartroast_calibration.peak_bt_avg
                             + (NEW.peak_bt - roaster_model_smartroast_calibration.peak_bt_avg)
                               / (roaster_model_smartroast_calibration.sample_count + 1)
                           )),
      cliff_rate_avg = roaster_model_smartroast_calibration.cliff_rate_avg
                       + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                         / (roaster_model_smartroast_calibration.sample_count + 1),
      cliff_rate_m2  = roaster_model_smartroast_calibration.cliff_rate_m2
                       + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                         * (NEW.cliff_rate - (
                             roaster_model_smartroast_calibration.cliff_rate_avg
                             + (NEW.cliff_rate - roaster_model_smartroast_calibration.cliff_rate_avg)
                               / (roaster_model_smartroast_calibration.sample_count + 1)
                           )),
      contributing_companies = roaster_model_smartroast_calibration.contributing_companies
                                + CASE WHEN v_company_already_contributed THEN 0 ELSE 1 END,
      last_updated   = now();

    UPDATE roaster_model_smartroast_calibration
    SET
      peak_bt_stddev = CASE WHEN sample_count > 1
                            THEN sqrt(peak_bt_m2 / (sample_count - 1))
                            ELSE NULL END
    WHERE brand = v_brand AND model = v_model AND event_type = NEW.event_type;
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER trg_smartroast_calibration_update
  AFTER INSERT ON roast_smartroast_log
  FOR EACH ROW
  EXECUTE FUNCTION update_smartroast_calibrations();

-- ── 5. Resolver function: get effective thresholds for a roaster unit
-- Returns a JSON blob with the threshold tuple the algorithm should
-- use, plus which layer supplied them. Read at the start of every
-- streaming session and cached client-side.
--
-- Math for the floor: peak_bt_avg − 1 × stddev gives the "typical
-- lower bound" of peak BT seen on this unit/model. Floor any new
-- detection at that value. For drop rate, use the smaller magnitude
-- threshold: 50% of the avg cliff rate seen (so we still fire on
-- shallower drops than the typical one).
CREATE OR REPLACE FUNCTION get_smartroast_thresholds(
  p_roaster_unit_id uuid,
  p_event_type      text,
  p_sensitivity     text DEFAULT 'normal'
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_unit_row    roaster_unit_smartroast_calibration%ROWTYPE;
  v_model_row   roaster_model_smartroast_calibration%ROWTYPE;
  v_brand       text;
  v_model       text;
  v_unit_min_samples constant integer := 5;
  v_model_min_samples constant integer := 50;
  v_min_peak_bt numeric;
  v_drop_rate   numeric;
BEGIN
  -- Layer 1: per-unit
  SELECT * INTO v_unit_row
  FROM roaster_unit_smartroast_calibration
  WHERE roaster_unit_id = p_roaster_unit_id AND event_type = p_event_type;

  IF FOUND AND v_unit_row.sample_count >= v_unit_min_samples THEN
    v_min_peak_bt := v_unit_row.peak_bt_avg - COALESCE(v_unit_row.peak_bt_stddev, 0);
    v_drop_rate   := abs(v_unit_row.cliff_rate_avg) * 0.5;
    RETURN jsonb_build_object(
      'dropRate', v_drop_rate,
      'minPeakBt', v_min_peak_bt,
      'source', 'unit',
      'sampleCount', v_unit_row.sample_count
    );
  END IF;

  -- Layer 2: per-model
  SELECT brand, model INTO v_brand, v_model
  FROM roaster_units WHERE roaster_unit_id = p_roaster_unit_id;

  IF v_brand IS NOT NULL AND v_model IS NOT NULL THEN
    SELECT * INTO v_model_row
    FROM roaster_model_smartroast_calibration
    WHERE brand = v_brand AND model = v_model AND event_type = p_event_type;

    IF FOUND AND v_model_row.sample_count >= v_model_min_samples THEN
      v_min_peak_bt := v_model_row.peak_bt_avg - COALESCE(v_model_row.peak_bt_stddev, 0);
      v_drop_rate   := abs(v_model_row.cliff_rate_avg) * 0.5;
      RETURN jsonb_build_object(
        'dropRate', v_drop_rate,
        'minPeakBt', v_min_peak_bt,
        'source', 'model',
        'sampleCount', v_model_row.sample_count
      );
    END IF;
  END IF;

  -- Layer 3: hardcoded fallback (mirrors lib/roast/autoDetect.ts tiers)
  RETURN jsonb_build_object(
    'source', 'hardcoded',
    'sensitivity', p_sensitivity
  );
END $$;

COMMIT;
