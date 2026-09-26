-- A roast that names its recipe should say so in the join table.
--
-- WHAT IS BROKEN. `roast_log_recipes` carries the recipe attribution that
-- `roast_detail_by_blend` reads for total_roasted and for the roast half of
-- in_stock_roasted. TEN code paths insert into roast_log; exactly ONE of them
-- also writes the join row — the Load-From-Queue insert in stratos
-- app/app/(app)/roast/logger/actions.ts:1539, and even that one swallows its
-- own error with console.error. There is no database-side writer at all.
--
-- The nine silent paths: the impromptu logger charge upsert, saveRoastSession,
-- duplicateRoast, bulkDuplicate, addRoast, the Artisan importer (two sites),
-- the Roastmaster importer, and process_staged_imports.
--
-- So every roast a roaster logs by hand, duplicates, back-dates or imports is
-- unattributed. Charged roasts that name a recipe but have no join row:
--
--     9ShiyDAXhV  1059      <- 100% of them; this tenant has never had one
--     R7CbqHmA1j   248      <- ~10%, the hand-added ones
--     752af3ed-4   106      <- ~10%
--
-- The reason one tenant is at 100% is not pre-blends, and it is not RLS
-- (roast_log_insert and roast_log_recipes_write resolve through the SAME
-- helper, auth_roast_log_company_ids(), so anyone who can insert the parent
-- can insert the child). It is that the one-shot backfill in
-- _archive/20260503000001 ran on 2026-05-03 and that tenant's first roast is
-- 2026-05-05, and it builds its roast day from the logger rather than from
-- Load From Queue. A tenant onboarded after any one-shot backfill gets the
-- same hole, which is why this migration ships a trigger and not a second
-- one-shot.
--
-- WHAT lbs_allocated MEANS. The view computes
--     roasted_weight * (lbs_allocated / charge_weight_lbs)
-- so lbs_allocated is a share of the GREEN charge, not roasted lbs. Measured,
-- not assumed: sum(lbs_allocated) per roast equals charge_weight_lbs on 16,674
-- of 16,686 roasts (99.93%) across every tenant and both eras. The column
-- comment says "Roasted lbs (post-loss)" and has always been wrong; corrected
-- below. For a single-recipe roast the whole charge belongs to the one recipe,
-- so the value is COPIED from charge_weight_lbs, never derived.
--
-- WHY A PROVENANCE COLUMN. The planner inserts its roast_log rows and its join
-- rows in two separate PostgREST requests. A trigger on roast_log therefore
-- fires while the join table is still empty and would leave a duplicate behind
-- when the planner's own rows land a moment later — and no unique key can stop
-- that, because 49 LEGITIMATE duplicate (roast_log_id, recipe_id) pairs already
-- exist on prod (a recipe whose real-demand slice and buffer slice land
-- non-consecutively in one batch). So rows record who wrote them, and the
-- planner's own rows evict the machine-written ones for that roast. This works
-- in either deploy order and needs no frontend change to be correct.
--
-- WHY THE ZERO ANCHORS. in_stock_roasted has no count anchor for most
-- facilities, so the view falls back to accumulating 28 days of attributed
-- roasting minus 28 days of delivered orders. Backfilling history alone would
-- therefore hand one tenant ~9,164 lbs of finished coffee it has never
-- counted, drive roasted_left to zero for nearly every recipe and empty the
-- roast plan for four weeks. Rehearsed on prod: in_stock_roasted 0 -> 9,978.6
-- and roasted_left 220.8 -> 3.5. So each (facility, recipe) that gains
-- backfilled roasting inside that window and has no recent blend anchor gets a
-- zero-baseline anchor dated now. Zero is not a counted number and is not
-- claimed to be one — it is the honest statement that nobody has ever counted
-- that shelf, and it is exactly what these facilities already see today. The
-- anchor lateral only looks back 28 days, so it expires on its own.

begin;

-- ── 1. Who wrote the attribution ────────────────────────────────────────
alter table public.roast_log_recipes
  add column if not exists attributed_by text not null default 'app';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'roast_log_recipes_attributed_by_check') then
    alter table public.roast_log_recipes
      add constraint roast_log_recipes_attributed_by_check
      check (attributed_by in ('app', 'trigger', 'backfill'));
  end if;
end $$;

comment on column public.roast_log_recipes.lbs_allocated is
  'GREEN lbs of this roast''s charge belonging to this recipe. The share, not '
  'the yield: roast_detail_by_blend reads it as lbs_allocated / charge_weight_lbs. '
  'Per roast these sum to charge_weight_lbs.';
comment on column public.roast_log_recipes.attributed_by is
  'app = written by the Load-From-Queue planner, which knows the real '
  'multi-recipe split. trigger/backfill = written by the database from '
  'roast_log.recipe_id for a roast that names exactly one recipe. An app row '
  'always wins and evicts the machine-written rows for its roast.';

-- ── 2. The database attributes any roast that names one recipe ──────────
create or replace function public.attribute_single_recipe_roast()
returns trigger
language plpgsql
as $fn$
begin
  -- Nothing relevant moved. Roast rows are updated constantly while a curve is
  -- being saved, so this has to be the cheapest possible exit. The trigger is
  -- deliberately NOT declared `update of recipe_id, charge_weight_lbs`:
  -- trg_stamp_roasted_weight resolves charge_weight_lbs from the charge_weight
  -- option id in a BEFORE trigger, and a column list keys on the columns named
  -- in the UPDATE statement rather than on what actually changed, so an update
  -- that touched only charge_weight would never reach us.
  if tg_op = 'UPDATE'
     and new.recipe_id is not distinct from old.recipe_id
     and new.charge_weight_lbs is not distinct from old.charge_weight_lbs then
    return null;
  end if;

  -- The planner's own rows are the honest multi-recipe split. Never touch a
  -- roast it has spoken for.
  if exists (select 1 from public.roast_log_recipes j
              where j.roast_log_id = new.roast_log_id
                and j.attributed_by = 'app') then
    return null;
  end if;

  delete from public.roast_log_recipes
   where roast_log_id = new.roast_log_id
     and attributed_by in ('trigger', 'backfill');

  -- A roast with no recipe, or no charge weight, cannot be attributed from
  -- anything stored. lbs_allocated is NOT NULL and any value would be invented,
  -- so it stays unattributed and visible as such.
  if new.recipe_id is null or coalesce(new.charge_weight_lbs, 0) <= 0 then
    return null;
  end if;

  insert into public.roast_log_recipes (roast_log_id, recipe_id, lbs_allocated, attributed_by)
  values (new.roast_log_id, new.recipe_id, new.charge_weight_lbs, 'trigger');

  return null;
end;
$fn$;

drop trigger if exists trg_attribute_single_recipe_roast on public.roast_log;
create trigger trg_attribute_single_recipe_roast
  after insert or update on public.roast_log
  for each row execute function public.attribute_single_recipe_roast();

-- ── 3. The planner's split evicts the machine's guess ───────────────────
create or replace function public.planner_attribution_wins()
returns trigger
language plpgsql
as $fn$
begin
  if new.attributed_by = 'app' then
    delete from public.roast_log_recipes
     where roast_log_id = new.roast_log_id
       and attributed_by in ('trigger', 'backfill');
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_planner_attribution_wins on public.roast_log_recipes;
create trigger trg_planner_attribution_wins
  before insert on public.roast_log_recipes
  for each row execute function public.planner_attribution_wins();

-- ── 4. Zero-baseline anchors, BEFORE the backfill can accumulate ────────
-- Written first so that no window ever sees the backfilled roasting without
-- the anchor that fences it off.
insert into public.roast_stock_log
  (stock_type, blend_id, facility_id, company_id, lbs_in_stock, created_by, updated_by)
select distinct 'blend', rl.recipe_id, rl.facility_id, rl.company_id, 0,
       'migration:20260926000004', 'migration:20260926000004'
  from public.roast_log rl
 where rl.recipe_id is not null
   and rl."charged?"
   and coalesce(rl.charge_weight_lbs, 0) > 0
   -- 35, not 28. The view accumulates from `roast_week_start - 28 days`, and
   -- roast_week_start can sit up to 6 days behind today, so a 28-day window
   -- measured from today misses up to six days of roasting that the view still
   -- counts. Rehearsed at 28 and it leaked 29.5 lbs through. Widening only ever
   -- writes more zero anchors, and a zero anchor claims nothing that is not
   -- already true: nobody has counted that shelf.
   and rl.roast_date >= current_date - 35
   and not exists (select 1 from public.roast_log_recipes j
                    where j.roast_log_id = rl.roast_log_id)
   and not exists (select 1 from public.roast_stock_log s
                    where s.stock_type = 'blend'
                      and s.blend_id = rl.recipe_id
                      and s.facility_id = rl.facility_id
                      and s.created_at >= current_date - 35);

-- ── 5. The backfill ─────────────────────────────────────────────────────
-- Every roast that names a recipe and carries a charge weight, and has no
-- attribution at all. Expressed as that rule and not as a tenant, so it is
-- correct on staging, on any future database, and for the next tenant.
insert into public.roast_log_recipes (roast_log_id, recipe_id, lbs_allocated, attributed_by)
select rl.roast_log_id, rl.recipe_id, rl.charge_weight_lbs, 'backfill'
  from public.roast_log rl
  join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
 where rl.recipe_id is not null
   and coalesce(rl.charge_weight_lbs, 0) > 0
   and not exists (select 1 from public.roast_log_recipes j
                    where j.roast_log_id = rl.roast_log_id);

do $verify$
declare
  v_gap int; v_bad int; v_rows int; v_anchors int; v_skipped int;
begin
  -- THE INVARIANT this migration exists to establish. Stated as a rule, never
  -- as a tenant's count: tenant-specific probes have failed four times here.
  select count(*) into v_gap
    from public.roast_log rl
    join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
   where rl.recipe_id is not null
     and coalesce(rl.charge_weight_lbs, 0) > 0
     and not exists (select 1 from public.roast_log_recipes j
                      where j.roast_log_id = rl.roast_log_id);
  if v_gap > 0 then
    raise exception '% roast(s) name a recipe and carry a charge weight but have no attribution', v_gap;
  end if;

  -- No roast may be attributed more green than it was charged. This is the
  -- guard against a backfill landing on top of a partial app split.
  select count(*) into v_bad
    from public.roast_log rl
    join (select roast_log_id, sum(lbs_allocated) alloc
            from public.roast_log_recipes group by 1) j
      on j.roast_log_id = rl.roast_log_id
   where coalesce(rl.charge_weight_lbs, 0) > 0
     and j.alloc > rl.charge_weight_lbs + 0.01;
  if v_bad > 12 then
    raise exception '% roast(s) are attributed more green than they were charged (12 predate this migration)', v_bad;
  end if;

  -- A roast never carries both kinds of attribution.
  select count(*) into v_bad from (
    select roast_log_id from public.roast_log_recipes
     group by roast_log_id
    having count(*) filter (where attributed_by = 'app') > 0
       and count(*) filter (where attributed_by in ('trigger','backfill')) > 0) x;
  if v_bad > 0 then
    raise exception '% roast(s) mix planner and machine attribution', v_bad;
  end if;

  -- Nothing was attributed that could only have been guessed.
  select count(*) into v_bad
    from public.roast_log_recipes j
    join public.roast_log rl on rl.roast_log_id = j.roast_log_id
   where j.attributed_by = 'backfill'
     and (rl.recipe_id is null or j.lbs_allocated is distinct from rl.charge_weight_lbs);
  if v_bad > 0 then
    raise exception '% backfilled row(s) hold a value that was not copied from the roast', v_bad;
  end if;

  select count(*) into v_rows from public.roast_log_recipes where attributed_by = 'backfill';
  select count(*) into v_anchors from public.roast_stock_log where created_by = 'migration:20260926000004';
  select count(*) into v_skipped
    from public.roast_log rl
   where rl.recipe_id is not null
     and not exists (select 1 from public.roast_log_recipes j where j.roast_log_id = rl.roast_log_id);
  raise notice 'attribution: % row(s) backfilled, % zero anchor(s) written, % roast(s) left unattributed (no charge weight, or a recipe that no longer exists)',
    v_rows, v_anchors, v_skipped;
end $verify$;

commit;
