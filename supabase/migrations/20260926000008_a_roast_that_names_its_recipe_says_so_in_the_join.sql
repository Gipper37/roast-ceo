-- A roast that names its recipe should say so in the join table.
--
-- WHAT IS BROKEN. `roast_log_recipes` carries the per-roast recipe attribution.
-- `roast_detail_by_blend` — a view AND an identically-bodied RPC, which is what
-- the app actually calls — INNER JOINs it at four sites, and that join is the
-- only path by which "we roasted this" reaches any roast screen.
--
-- TEN code paths insert into roast_log. Exactly ONE also writes the join row:
-- the Load-From-Queue insert at stratos app/app/(app)/roast/logger/actions.ts
-- :1539, whose error is swallowed with console.error at :1544. There is no
-- database-side writer at all. The nine silent paths are the impromptu logger
-- charge upsert, saveRoastSession, duplicateRoast, bulkDuplicate, addRoast, the
-- Artisan importer (two sites), the Roastmaster importer, and
-- process_staged_imports.
--
-- So every roast logged by hand, duplicated, back-dated or imported is
-- unattributed. Charged roasts naming a recipe with no join row:
--
--     9ShiyDAXhV  1059      <- 100% of them, since 2026-05-05
--     R7CbqHmA1j   248      <- ~10%, the hand-added ones
--     752af3ed-4   106      <- ~10%
--
-- One tenant is at 100% for two reasons, and neither is the one that looks
-- obvious. It is NOT pre-blends — the planner writes the row for single-recipe
-- batches too. It is NOT RLS — roast_log_insert and roast_log_recipes_write
-- resolve through the SAME helper, auth_roast_log_company_ids(), so anyone who
-- can insert the parent can insert the child. It is that the one-shot backfill
-- in _archive/20260503000001 ran on 2026-05-03, that tenant's first roast is
-- 2026-05-05, and it builds its roast day from the logger rather than from Load
-- From Queue. A tenant onboarded after any one-shot gets the same hole, which
-- is why this ships a TRIGGER and not a second one-shot.
--
-- WHAT IT COSTS TODAY. total_roasted has a hand-written fallback in the planner
-- (max(viewRoasted, actualRoasted), reading roast_log directly), so the Left
-- card survives. in_stock_roasted has NO fallback anywhere — not in
-- lib/roast/badgeCount.ts, not in the In Stock tab, not in Roast Progress. So
-- for the unattributed tenant every recipe reads zero, the In Stock column
-- shows "-" on all of them, and Roast Progress sits at 0% for the whole roast
-- day and then flips to "-". It never shows partial or full.
--
-- WHAT lbs_allocated MEANS. The view computes
--     roasted_weight * (lbs_allocated / charge_weight_lbs)
-- so it is a share of the GREEN charge, not roasted lbs. Measured, not assumed:
-- sum(lbs_allocated) per roast equals charge_weight_lbs on 16,674 of 16,686
-- roasts (99.93%) across every tenant and both eras. The column comment says
-- "Roasted lbs (post-loss)" and has always been wrong; corrected below. For a
-- roast that names exactly one recipe the whole charge belongs to it, so the
-- value is COPIED from charge_weight_lbs and never derived.
--
-- WHY A PROVENANCE COLUMN. The planner inserts its roast_log rows and its join
-- rows as two separate PostgREST requests. A trigger on roast_log therefore
-- fires while the join table is still empty and would leave a duplicate behind
-- when the planner's own rows land a moment later. No unique key can stop that:
-- 49 LEGITIMATE duplicate (roast_log_id, recipe_id) pairs already exist on prod,
-- because the bin-packer can place a recipe's real-demand slice and its buffer
-- slice non-consecutively in one batch. So rows record who wrote them, and the
-- planner's honest split evicts the machine's guess. This is correct in either
-- deploy order and needs no frontend change to be safe.
--
-- 🔴 WHAT THIS DELIBERATELY DOES NOT DO: fence in_stock_roasted.
-- An earlier draft wrote zero-baseline rows into roast_stock_log so the newly
-- attributed roasting could not arrive as phantom shelf stock. That was wrong.
-- roast_stock_log is the HUMAN COUNT ledger: it is insert-only across the whole
-- frontend with no delete path, and StockEditorModal asserts "last_logged_at is
-- non-null iff a manual entry exists". A machine row there flips the In-Stock
-- badge from "estimate" to "log · logged today", permanently, and nobody can
-- remove it. A derived cache may not invent a number, and a machine may not
-- sign a count.
--
-- So attribution simply comes on, and in_stock_roasted starts working. For a
-- tenant with no count anchor the view rebuilds it as 28 days of roasting minus
-- 28 days of deliveries, which on incomplete order entry reads high — roughly
-- 5,600 lb at 9ShiyDAXhV, being 9,979 lb roasted against 4,366 lb of recorded
-- deliveries in the window. The honest remedy is the shipped one: log a count.
-- That sets the anchor, replaces the rebuild with a real number, and
-- accumulates forward. logRoastStockBulk does every recipe in one pass.

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
  -- saved, so this has to be the cheapest possible exit. The trigger is
  -- deliberately NOT declared `update of recipe_id, charge_weight_lbs`:
  -- trg_stamp_roasted_weight resolves charge_weight_lbs from the charge_weight
  -- option id in a BEFORE trigger, and a column list keys on the columns NAMED
  -- in the UPDATE statement rather than on what changed — so an update touching
  -- only charge_weight would flip charge_weight_lbs and never reach us.
  if tg_op = 'UPDATE'
     and new.recipe_id is not distinct from old.recipe_id
     and new.charge_weight_lbs is not distinct from old.charge_weight_lbs then
    return null;
  end if;

  -- The planner's own rows are the honest multi-recipe split. Never touch a
  -- roast it has spoken for. Consequence worth knowing: once planner rows
  -- exist, changing roast_log.recipe_id does NOT re-attribute the roast. That
  -- is deliberate — a machine guess must not overwrite a real split — and it
  -- means a corrected multi-recipe roast is fixed by the planner, not here.
  if exists (select 1 from public.roast_log_recipes j
              where j.roast_log_id = new.roast_log_id
                and j.attributed_by = 'app') then
    return null;
  end if;

  delete from public.roast_log_recipes
   where roast_log_id = new.roast_log_id
     and attributed_by in ('trigger', 'backfill');

  -- Three reasons a roast cannot be attributed from anything stored, all of
  -- which leave it honestly unattributed rather than guessed at:
  --   no recipe           - nothing to point at
  --   no charge weight    - lbs_allocated is NOT NULL and any value is invented
  --   a dead recipe_id    - roast_log's FK is NOT VALID while
  --                         roast_log_recipes' is enforced, so 12 legacy roasts
  --                         name a recipe that no longer exists. Without this
  --                         guard, editing one of them would abort the edit
  --                         with a raw FK violation. Same rule the backfill
  --                         below uses, so the two always agree.
  if new.recipe_id is null
     or coalesce(new.charge_weight_lbs, 0) <= 0
     or not exists (select 1 from public.roast_recipes rr where rr.recipe_id = new.recipe_id) then
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

-- ── 4. Baseline, captured BEFORE the backfill ───────────────────────────
-- Over-attribution has 12 pre-existing cases on prod. Asserting "<= 12" would
-- bake today's count into an invariant and abort a future tag the moment the
-- planner produces a 13th — it does so at roughly 2.4/month. Measure instead,
-- and assert that THIS migration adds none.
create temporary table _attr_baseline on commit drop as
select count(*)::int as over_allocated
  from public.roast_log rl
  join (select roast_log_id, sum(lbs_allocated) alloc
          from public.roast_log_recipes group by 1) j
    on j.roast_log_id = rl.roast_log_id
 where coalesce(rl.charge_weight_lbs, 0) > 0
   and j.alloc > rl.charge_weight_lbs + 0.01;

-- ── 5. The backfill ─────────────────────────────────────────────────────
-- Every roast that names a live recipe and carries a charge weight, and has no
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
declare v_gap int; v_bad int; v_pre int; v_rows int; v_skipped int;
begin
  -- THE INVARIANT this migration exists to establish, stated as a rule.
  select count(*) into v_gap
    from public.roast_log rl
    join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
   where rl.recipe_id is not null
     and coalesce(rl.charge_weight_lbs, 0) > 0
     and not exists (select 1 from public.roast_log_recipes j
                      where j.roast_log_id = rl.roast_log_id);
  if v_gap > 0 then
    raise exception '% roast(s) name a live recipe and carry a charge weight but have no attribution', v_gap;
  end if;

  -- No roast may be attributed more green than it was charged, and this
  -- migration may not add a single new case.
  select over_allocated into v_pre from _attr_baseline;
  select count(*) into v_bad
    from public.roast_log rl
    join (select roast_log_id, sum(lbs_allocated) alloc
            from public.roast_log_recipes group by 1) j
      on j.roast_log_id = rl.roast_log_id
   where coalesce(rl.charge_weight_lbs, 0) > 0
     and j.alloc > rl.charge_weight_lbs + 0.01;
  if v_bad > v_pre then
    raise exception 'over-attributed roasts went from % to % — this migration added %', v_pre, v_bad, v_bad - v_pre;
  end if;

  -- A roast never carries both kinds of attribution.
  select count(*) into v_bad from (
    select roast_log_id from public.roast_log_recipes
     group by roast_log_id
    having count(*) filter (where attributed_by = 'app') > 0
       and count(*) filter (where attributed_by in ('trigger','backfill')) > 0) x;
  if v_bad > 0 then raise exception '% roast(s) mix planner and machine attribution', v_bad; end if;

  -- Nothing was attributed that could only have been guessed.
  select count(*) into v_bad
    from public.roast_log_recipes j
    join public.roast_log rl on rl.roast_log_id = j.roast_log_id
   where j.attributed_by = 'backfill'
     and (rl.recipe_id is null or j.lbs_allocated is distinct from rl.charge_weight_lbs);
  if v_bad > 0 then
    raise exception '% backfilled row(s) hold a value that was not copied from the roast', v_bad;
  end if;

  -- Nothing was written into the count ledger. This migration must never sign
  -- a count on a human's behalf.
  select count(*) into v_bad from public.roast_stock_log
   where created_by like 'migration:%';
  if v_bad > 0 then
    raise exception '% machine-written row(s) are sitting in the count ledger', v_bad;
  end if;

  select count(*) into v_rows from public.roast_log_recipes where attributed_by = 'backfill';
  select count(*) into v_skipped
    from public.roast_log rl
   where rl.recipe_id is not null
     and not exists (select 1 from public.roast_log_recipes j where j.roast_log_id = rl.roast_log_id);
  raise notice 'attribution: % row(s) backfilled; % roast(s) left unattributed (no charge weight, or a recipe that no longer exists)',
    v_rows, v_skipped;
end $verify$;

commit;
