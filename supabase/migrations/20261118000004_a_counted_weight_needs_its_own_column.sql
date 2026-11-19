-- A count in pounds has nowhere to land.
--
-- Owner, 2026-11-18, on a coffee group holding sacks of more than one size:
-- "Ask for pounds". This migration builds the place the pounds go. It adds no
-- way to enter them -- that is the next migration and the UI change -- so on
-- its own it changes nothing. That is deliberate and it is PROVABLE: the new
-- column is NULL on every existing row, and every reader below falls through
-- to exactly the arithmetic it does today when it is NULL.
--
-- WHY A NEW COLUMN AND NOT A UNIT FLAG.
-- The whole family of bugs this closes comes from converting bags to pounds on
-- one side of a comparison with a different denominator than the other. A
-- column called `bag_count` that sometimes holds pounds would be that bug with
-- a flag bolted on. Pounds get their own name.
--
-- 🔴 WHAT I MEASURED FIRST, because it decided the shape.
--  - `coffee_inventory_history.bag_count` is NOT NULL with no default, and the
--    count's only legal entry point is an INSERT there: trg_guard_coffee_baseline
--    REFUSES a direct write to inventory_count_bags / last_inventory unless the
--    history trigger's flag is set. So the unit question lands on that column.
--  - It stays NOT NULL here. Nothing in the app ever SELECTs that table (three
--    INSERT sites, zero reads), so its one reader is push_coffee_history_to_parent,
--    and `weekly_coffee_stock_by_origin` -- which the Reports page DOES read --
--    anchors on `inventory_count_bags * bag_size`. A pounds count that left bags
--    NULL would COALESCE that anchor to 0. Keeping bags populated with the
--    canonical per-lot figure keeps that reader whole without rebuilding a
--    materialized view and the RLS wrapper view on top of it.
--  - `coffee_inventory.inventory_lbs` is NOT write-only, which is what I thought
--    when I started. handle_manual_inventory_update reads it two statements later
--    to produce `in_stock_lbs`, and `in_stock` from that. It is the count anchor
--    for the whole stock figure, which is why the counted weight has to reach it.
--  - And the numbers the app actually SHOWS are already safe on mixed groups:
--    `in_stock_lbs` matches the sum of the lots on 43 of 43 origins that hold
--    stock, all 4 mixed-size ones included, because the coffee_lot_count
--    statement trigger recomputes them from the lots after the fact. So this
--    change is not repairing a displayed number. It is removing the one place
--    where an invented denominator reaches STORED truth.
--  - Both tables carry TABLE-level INSERT/UPDATE for `authenticated`, so a new
--    column inherits the privilege and needs no GRANT. Checked, not assumed:
--    `customers` is the counter-example where 65 columns are granted one by one
--    and a new column would have been silently unwritable.
--
-- WHAT THIS DELIBERATELY DOES NOT DO.
-- It does not touch mv_weekly_coffee_stock_by_origin. Its anchor recomputes
-- bags x the origin's one size, which for a group holding two sizes is not the
-- counted weight -- but that is true of every count already recorded, nothing
-- refreshes the view, and making it read the counted weight means dropping a
-- materialized view, its two indexes and the RLS wrapper view the Reports page
-- selects from. One change at a time; recorded in project_open_list.md.
--
-- One line I hardened while rewriting handle_manual_inventory_update: its
-- `NEW.bag_size::numeric` throws on an empty string. Prod holds no empty
-- strings in that column today (0 rows), so it is latent, but the same cast
-- crashed the local rehearsal of 20261118000001 and the counted-weight path
-- would now fail the same way. NULLIF, as the sibling functions already do.
--
-- PROVENANCE. Both bodies below are prod's own pg_get_functiondef output with
-- the stated edits. Not retyped: CREATE OR REPLACE rewrites the whole body.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 1. THE COLUMN, on the audit row and on the group row it pushes to.
alter table public.coffee_inventory_history add column if not exists counted_lbs numeric;
alter table public.coffee_inventory         add column if not exists counted_lbs numeric;

comment on column public.coffee_inventory_history.counted_lbs is
  'The weight the operator counted, when they counted in pounds rather than bags. NULL for a bag count, where the weight is bag_count x the size in force. A group holding sacks of more than one size has no single size to multiply by, so pounds are the only answerable unit there.';
comment on column public.coffee_inventory.counted_lbs is
  'The counted weight in force for this origin at this facility, pushed from the latest coffee_inventory_history row by trg_copy_coffee_history_to_parent. NULL means the count in force was taken in bags. handle_manual_inventory_update prefers it over inventory_count_bags x bag_size when deriving inventory_lbs.';

-- 2. The push trigger carries the weight to the group row. It must write the
--    column on EVERY push, including a bag count's NULL: otherwise a pounds
--    count followed by a bag count would leave the stale weight in place and
--    inventory_lbs would keep preferring it.
create or replace function public.push_coffee_history_to_parent()
 returns trigger
 language plpgsql
as $function$
BEGIN
    -- Set flag so the guard trigger allows this write
    PERFORM set_config('app.from_history_trigger', 'true', true);

    UPDATE coffee_inventory
    SET
        last_inventory = NEW.inventory_date,
        inventory_count_bags = NEW.bag_count,
        counted_lbs = NEW.counted_lbs,
        updated_at = NOW()
    WHERE origin_id = NEW.origin_id
      AND facility_id = NEW.facility_id;

    RETURN NEW;
END;
$function$;

-- 3. inventory_lbs prefers the counted weight. With counted_lbs NULL -- every
--    row today -- this is the old expression, character for character.
create or replace function public.handle_manual_inventory_update()
 returns trigger
 language plpgsql
as $function$
DECLARE
    v_bag_size            NUMERIC;
    v_purchased_lbs       NUMERIC;
    v_roasted_direct_lbs  NUMERIC;
    v_roasted_blend_lbs   NUMERIC;
    v_last_inventory_date DATE;
BEGIN
    v_bag_size := COALESCE(NULLIF(NEW.bag_size, '')::numeric, 154);
    NEW.par           := public.calculate_par(NEW.origin_id);
    NEW.restock_level := public.calculate_restock_level(NEW.origin_id);
    v_last_inventory_date := COALESCE(NEW.last_inventory::DATE, '2000-01-01');
    -- A weight the operator actually counted outranks bags x one size. On a
    -- group holding more than one sack size there IS no one size, which is the
    -- whole reason this column exists.
    NEW.inventory_lbs     := COALESCE(NEW.counted_lbs,
                                      COALESCE(NEW.inventory_count_bags, 0) * v_bag_size);

    SELECT COALESCE(SUM(p.amount), 0) INTO v_purchased_lbs
    FROM coffee_inventory_purchased p
    JOIN shipment_received s ON p.shipment_id = s.shipment_id
    WHERE p.origin = NEW.origin_id
      AND s.date_received IS NOT NULL
      AND s.date_received::DATE > v_last_inventory_date
      AND COALESCE(s.voided, false) = false
      AND p.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs), 0) INTO v_roasted_direct_lbs
    FROM roast_log rl
    LEFT JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    WHERE rl.origin_id = NEW.origin_id
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND (rr.roast_type IS DISTINCT FROM 'Pre-Blend' OR rr.roast_type IS NULL)
      AND rl.facility_id = NEW.facility_id;

    SELECT COALESCE(SUM(rl.charge_weight_lbs * rc.percentage), 0) INTO v_roasted_blend_lbs
    FROM roast_log rl
    JOIN roast_recipes rr ON rl.recipe_id = rr.recipe_id
    JOIN recipe_components rc ON rl.recipe_id = rc.recipe_id
    WHERE rc.coffee_item = NEW.origin_id
      AND rr.roast_type = 'Pre-Blend'
      AND rl.roast_date::DATE > v_last_inventory_date
      AND rl."charged?" = TRUE
      AND rl.facility_id = NEW.facility_id;

    NEW.in_stock_lbs  := GREATEST(0, (NEW.inventory_lbs + v_purchased_lbs - v_roasted_direct_lbs - v_roasted_blend_lbs));
    NEW.in_stock      := NEW.in_stock_lbs / NULLIF(v_bag_size, 0);
    NEW.to_order_bags := GREATEST(0, COALESCE(NEW.par, 0) - NEW.in_stock);

    RETURN NEW;
END;
$function$;

-- 4. Both triggers must SEE the new column. `UPDATE OF <cols>` fires only when
--    one of those columns is in the statement's SET list, so without this a
--    push that moved only the weight would re-derive nothing, and a direct edit
--    of the weight would slip past the baseline guard.
--
--    🔴 The names are unchanged on purpose. Postgres fires BEFORE row triggers
--    in alphabetical order by name, and this table's order is load-bearing:
--    trg_zzz_sync_in_stock_bags runs after trg_manual_inventory_update and
--    overwrites its `in_stock` with the exact per-lot figure. Recreating these
--    under the same names keeps that order. The verify block asserts it.
drop trigger if exists trg_manual_inventory_update on public.coffee_inventory;
create trigger trg_manual_inventory_update
  before insert or update of origin_id, facility_id, last_inventory,
                             inventory_count_bags, bag_size, counted_lbs
  on public.coffee_inventory
  for each row execute function handle_manual_inventory_update();

create or replace function public.guard_coffee_inventory_baseline()
 returns trigger
 language plpgsql
as $function$
BEGIN
    -- Allow writes from the history-to-parent trigger function
    IF current_setting('app.from_history_trigger', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.last_inventory IS DISTINCT FROM NEW.last_inventory
       OR OLD.inventory_count_bags IS DISTINCT FROM NEW.inventory_count_bags
       OR OLD.counted_lbs IS DISTINCT FROM NEW.counted_lbs THEN
        RAISE EXCEPTION 'Direct edits to last_inventory / inventory_count_bags / counted_lbs are not allowed. Insert into coffee_inventory_history instead.';
    END IF;

    RETURN NEW;
END;
$function$;

drop trigger if exists trg_guard_coffee_baseline on public.coffee_inventory;
create trigger trg_guard_coffee_baseline
  before update of last_inventory, inventory_count_bags, counted_lbs
  on public.coffee_inventory
  for each row execute function guard_coffee_inventory_baseline();

do $$
declare
  v_src text; v_code text; v_def text; v_names text;
  v_leftover bigint;
begin
  -- 🔴 Strip the comments before matching. prosrc is the whole body, so a grep
  -- for a pattern the body DOCUMENTS matches the documentation. That is how
  -- 20261118000003's verify block first failed and rolled its own migration back.
  create temp table _vb(name text, code text) on commit drop;
  insert into _vb
  select p.proname, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('push_coffee_history_to_parent','handle_manual_inventory_update',
                      'guard_coffee_inventory_baseline');
  if (select count(*) from _vb) <> 3 then
    raise exception 'one of the three rewritten functions is missing';
  end if;

  -- 1. THE COLUMNS EXIST, numeric, and nullable.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='coffee_inventory_history'
                    and column_name='counted_lbs' and data_type='numeric' and is_nullable='YES') then
    raise exception 'coffee_inventory_history.counted_lbs is missing or not a nullable numeric';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='coffee_inventory'
                    and column_name='counted_lbs' and data_type='numeric' and is_nullable='YES') then
    raise exception 'coffee_inventory.counted_lbs is missing or not a nullable numeric';
  end if;

  -- 2. 🔴 THE NO-OP PROOF. Nothing can enter the new column yet, so every row
  --    must still be NULL -- which is what makes every COALESCE below fall
  --    through to the old arithmetic. If this ever fails, the migration is no
  --    longer the behaviour-free change its header claims to be.
  select count(*) into v_leftover from public.coffee_inventory where counted_lbs is not null;
  if v_leftover <> 0 then
    raise exception 'coffee_inventory.counted_lbs is already set on % row(s); this migration is not a no-op', v_leftover;
  end if;
  select count(*) into v_leftover from public.coffee_inventory_history where counted_lbs is not null;
  if v_leftover <> 0 then
    raise exception 'coffee_inventory_history.counted_lbs is already set on % row(s)', v_leftover;
  end if;

  -- 3. bag_count STAYS NOT NULL. The Reports page's weekly view anchors on
  --    inventory_count_bags, so bags must keep arriving.
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='coffee_inventory_history'
                and column_name='bag_count' and is_nullable='YES') then
    raise exception 'coffee_inventory_history.bag_count lost its NOT NULL; the weekly stock view would COALESCE its anchor to 0';
  end if;

  -- 4. The push trigger carries the weight.
  select code into v_code from _vb where name='push_coffee_history_to_parent';
  if v_code !~ 'counted_lbs\s*=\s*NEW\.counted_lbs' then
    raise exception 'push_coffee_history_to_parent does not push counted_lbs, so a pounds count would never reach the group row';
  end if;
  -- control: it still does what it did before.
  if v_code !~ 'inventory_count_bags\s*=\s*NEW\.bag_count' then
    raise exception 'push_coffee_history_to_parent stopped pushing bag_count';
  end if;
  if v_code !~ 'app\.from_history_trigger' then
    raise exception 'push_coffee_history_to_parent lost the guard flag, so its own UPDATE would be refused';
  end if;

  -- 5. inventory_lbs prefers the counted weight.
  select code into v_code from _vb where name='handle_manual_inventory_update';
  if v_code !~ 'COALESCE\(NEW\.counted_lbs' then
    raise exception 'handle_manual_inventory_update still derives inventory_lbs from bags alone';
  end if;
  -- controls: the rest of a function CREATE OR REPLACE rewrote wholesale.
  if v_code !~ 'NEW\.in_stock_lbs\s*:=\s*GREATEST\(0' then
    raise exception 'the in_stock_lbs derivation is gone';
  end if;
  if v_code !~ 'v_roasted_blend_lbs' or v_code !~ 'rr\.roast_type = ''Pre-Blend''' then
    raise exception 'the pre-blend roast subtraction is gone';
  end if;
  if v_code !~ 'COALESCE\(s\.voided, false\) = false' then
    raise exception 'the voided-shipment filter in the purchases term is gone';
  end if;
  if v_code !~ 'calculate_par' or v_code !~ 'calculate_restock_level' then
    raise exception 'the par / restock derivation is gone';
  end if;
  if v_code ~ 'COALESCE\(NEW\.bag_size::numeric' then
    raise exception 'the bare bag_size cast is back; an empty string would crash every count on this origin';
  end if;

  -- 6. The baseline guard covers the new column, and still refuses.
  select code into v_code from _vb where name='guard_coffee_inventory_baseline';
  if v_code !~ 'OLD\.counted_lbs IS DISTINCT FROM NEW\.counted_lbs' then
    raise exception 'the baseline guard does not cover counted_lbs, so it could be edited directly';
  end if;
  if v_code !~ 'RAISE EXCEPTION' or v_code !~ 'from_history_trigger' then
    raise exception 'the baseline guard no longer refuses, or no longer admits the history trigger';
  end if;

  -- 7. BOTH TRIGGERS SEE THE COLUMN.
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where c.relname='coffee_inventory' and t.tgname='trg_manual_inventory_update' and not t.tgisinternal;
  if v_def is null then raise exception 'trg_manual_inventory_update is missing'; end if;
  if v_def !~ 'counted_lbs' then
    raise exception 'trg_manual_inventory_update does not fire on counted_lbs: %', v_def;
  end if;
  if v_def !~ 'inventory_count_bags' or v_def !~ 'bag_size' then
    raise exception 'trg_manual_inventory_update lost a column it used to fire on: %', v_def;
  end if;

  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where c.relname='coffee_inventory' and t.tgname='trg_guard_coffee_baseline' and not t.tgisinternal;
  if v_def is null then raise exception 'trg_guard_coffee_baseline is missing'; end if;
  if v_def !~ 'counted_lbs' then
    raise exception 'trg_guard_coffee_baseline does not fire on counted_lbs: %', v_def;
  end if;

  -- 8. 🔴 TRIGGER ORDER. BEFORE row triggers fire alphabetically, and
  --    trg_zzz_sync_in_stock_bags must still come after
  --    trg_manual_inventory_update or `in_stock` keeps the one-size division
  --    instead of the exact per-lot figure. Dropping and recreating under the
  --    same names is what preserves this; assert it rather than trust it.
  select string_agg(t.tgname, ',' order by t.tgname) into v_names
    from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where c.relname='coffee_inventory' and not t.tgisinternal
     and (t.tgtype & 2) <> 0;   -- BEFORE
  if v_names is null or position('trg_manual_inventory_update' in v_names) = 0
     or position('trg_zzz_sync_in_stock_bags' in v_names) = 0
     or position('trg_manual_inventory_update' in v_names) > position('trg_zzz_sync_in_stock_bags' in v_names) then
    raise exception 'BEFORE trigger order on coffee_inventory is wrong; sync_in_stock_bags must still follow handle_manual_inventory_update: %', v_names;
  end if;
  if position('trg_guard_coffee_baseline' in v_names) = 0 then
    raise exception 'trg_guard_coffee_baseline vanished from coffee_inventory: %', v_names;
  end if;

  -- 9. The new columns are writable WITHOUT a per-column grant, because both
  --    tables carry table-level privileges. If that ever changes, a count
  --    would be refused silently.
  if not has_table_privilege('authenticated', 'public.coffee_inventory', 'UPDATE') then
    raise exception 'authenticated lost table-level UPDATE on coffee_inventory';
  end if;
  if not has_table_privilege('authenticated', 'public.coffee_inventory_history', 'INSERT') then
    raise exception 'authenticated lost table-level INSERT on coffee_inventory_history';
  end if;
  if not has_column_privilege('authenticated', 'public.coffee_inventory_history', 'counted_lbs', 'INSERT') then
    raise exception 'authenticated cannot INSERT coffee_inventory_history.counted_lbs';
  end if;
end $$;

commit;
