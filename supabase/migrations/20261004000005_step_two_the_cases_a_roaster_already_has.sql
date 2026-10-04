-- STEP 2 OF 2. Converts the case data roasters already have.
--
-- 20261002000002 was step 1: it taught every costing, depletion and reporting
-- path to multiply a per-unit bill of materials by a case's pack count, and set
-- that pack count on NOTHING, so COALESCE(s.units_per_case, 1) stayed 1
-- everywhere and no number moved. Its own header says "Step 2 converts the
-- data." Step 2 was never written, so the columns have sat on production since
-- release-2026-10-02-3 doing nothing: 0 of 38 sizes carry a pack count.
--
-- ── Why both halves have to move together ────────────────────────────────
--
-- A case size today stores the case as the selling unit, so its bill of
-- materials holds CASE TOTALS: "2oz (Case of 40)" lists 40 gold bags and 40
-- labels. Once units_per_case is 40, the engine multiplies a per-unit line by
-- 40, so leaving that 40 in place computes 1,600 bags. Step 1's header names
-- this exactly: "a BOM divided by 40 while the engine still reads it literally
-- understates packaging cost and depletion 40-fold, silently". The same trap
-- runs in reverse, which is the whole reason this file converts the pack count
-- and the lines in one transaction or neither.
--
-- ── What the data actually looks like, measured on prod ───────────────────
--
-- 13 case sizes, 33 products, 55 BOM lines, none marked per_case. Classified
-- against each size's own pack count:
--
--   53 lines  quantity = pack exactly   a per-unit item entered as a case total
--    2 lines  quantity = 1              under-entered, see below
--    0 lines  anything else             no ambiguous line exists
--
-- 🔴 And there is not ONE genuine per-case consumable in the set. No box, no
-- case label, no tape, no shrink wrap. Every line is a bag or a label, and both
-- are per-unit. So `per_case` stays false on everything here, and the column
-- earns its keep later, when somebody adds the box.
--
-- ── What this file converts, and what it refuses to ───────────────────────
--
-- MCR's 7 cases convert, because the arithmetic closes EXACTLY: the base size's
-- weight times the pack count equals the case's stored weight, to six decimal
-- places, for all seven. The base is matched by name where the name agrees and
-- asserted by arithmetic in every case, which is what catches "2lb (Case of
-- 10)" being built from a size named "2lbs". A name is a label; the weight is
-- the fact.
--
-- 🔴 Social Hour UK's 6 cases are deliberately NOT converted. Their pack count
-- is plainly 6, but the base cannot be derived: the size names carry a PRODUCT
-- ("Anglesey Case of 6"), not a size, and the only candidate base is uk-227g at
-- 0.500441 lb, which gives 3.002646 against a stored case weight of 3.042376.
-- That is 3 g per bag out, 18 g per case, 1.3%. Converting on the strength of
-- "it is the only one that is close" would pin 21 products' packaging to a
-- guess, and size_case_fields_agree forbids setting a pack count without a
-- base, so there is no half-measure available. Left alone, COALESCE(...,1)
-- keeps their 31 lines literal and correct, exactly as today. It needs a human
-- to say which unit size a UK case of 6 is built from.
--
-- ── 🔴 TWO NUMBERS DO MOVE, and they are corrections ──────────────────────
--
-- Two lines hold quantity 1 where their siblings hold the full pack count:
--
--   2oz (Case of 40 - labeled, green bags)  2oz Maui Blend Label  qty 1
--   2oz (Case of 40)                        2oz Maui Blend Label  qty 40
--   2oz (Case of 80 - no label)             2oz Gold Bag          qty 1
--   2oz (Case of 80 - labeled)              2oz Gold Bag          qty 80
--
-- Same consumable, same pack size, different quantity. They are not per-case
-- items, they are under-entered, and they have been under-counting packaging
-- since they were typed. Converting the size and LEAVING THESE LINES ALONE
-- makes the engine read 1 x 40 = 40 and 1 x 80 = 80, which is the right answer.
-- So this migration corrects them as a side effect, and that is a real change
-- to production numbers:
--
--   2oz Maui Blend Label on the green-bags case:  1 -> 40 per case
--   2oz Gold Bag on the no-label case:            1 -> 80 per case
--
-- It is said out loud here, and raised as a notice at apply time, because a
-- silent 40-fold increase in a packaging draw is indistinguishable from the bug
-- this feature exists to prevent.
--
-- One thing a migration cannot fix: "2oz (Case of 40 - labeled, green bags)"
-- has NO bag line at all, only the label. Its green bag was never entered. That
-- is a missing row, not a wrong one, and inventing it would be guessing which
-- consumable a roaster buys.
--
-- ── Reversibility ─────────────────────────────────────────────────────────
--
-- Undoing this is: set base_size_id and units_per_case back to null on the
-- seven sizes, and multiply the 22 converted lines by their pack count again.
-- The down path is recorded in the snapshot table this file leaves behind, so
-- it is a join and not an archaeology exercise.

begin;

-- A snapshot first, so the conversion is reversible by join rather than by
-- reading this comment. Dropped and rebuilt so a re-run is idempotent.
drop table if exists public._case_conversion_20261004;
create table public._case_conversion_20261004 (
  kind                  text not null,
  size_id               text,
  product_consumable_id text,
  old_base_size_id      text,
  old_units_per_case    integer,
  old_quantity          numeric,
  old_per_case          boolean,
  pack                  integer,
  noted_at              timestamptz not null default now()
);
comment on table public._case_conversion_20261004 is
  'Pre-conversion state for 20261004000005. Keep until the case UI has been exercised against this data, then drop.';

-- ── The cases we can prove ────────────────────────────────────────────────
--
-- A row qualifies only when: the name carries "Case of N", a base size exists
-- in the SAME company, and base.weight * N equals the case weight to six
-- decimals. Everything else is left for a human, by construction rather than by
-- an exclusion list.
create temporary table _case_map on commit drop as
with cases as (
  select s.size_id, s.company_id, s.size_name, s.weight,
         (regexp_match(s.size_name, 'Case of ([0-9]+)'))[1]::int as pack,
         trim(regexp_replace(s.size_name, '\s*\(?Case of [0-9]+.*$', ''))     as prefix
    from public.size s
   where s.size_name ~* 'case of [0-9]+'
     and s.units_per_case is null
)
select c.size_id, c.company_id, c.size_name, c.pack, b.size_id as base_size_id
  from cases c
  join public.size b
    on b.company_id = c.company_id
   and b.size_id <> c.size_id
   and b.units_per_case is null                       -- a case is never built from a case
   and round((b.weight * c.pack)::numeric, 6) = round(c.weight::numeric, 6)
   -- The name must not contradict the arithmetic. '2lb' vs '2lbs' agrees;
   -- a coincidental weight match on an unrelated size does not.
   and (c.prefix = '' or b.size_name ilike c.prefix || '%' or c.prefix ilike b.size_name || '%')
 where c.pack > 1;

do $pre$
declare v_n int; v_amb int;
begin
  select count(*) into v_n from _case_map;
  -- A case that resolved to more than one base is not resolved at all.
  select count(*) into v_amb from (
    select size_id from _case_map group by size_id having count(*) > 1) t;
  if v_amb > 0 then
    raise exception '% case size(s) matched more than one base size; refusing to guess', v_amb;
  end if;
  raise notice 'converting % case size(s); every one verified by base weight x pack = case weight', v_n;
end $pre$;

insert into public._case_conversion_20261004 (kind, size_id, old_base_size_id, old_units_per_case, pack)
select 'size', m.size_id, s.base_size_id, s.units_per_case, m.pack
  from _case_map m join public.size s on s.size_id = m.size_id;

update public.size s
   set base_size_id   = m.base_size_id,
       units_per_case = m.pack
  from _case_map m
 where s.size_id = m.size_id;

-- ── The bill of materials, divided only where it is provably a case total ──
--
-- quantity = pack is the only shape converted. The quantity-1 lines are left
-- untouched on purpose (see the header): the multiplication corrects them.
create temporary table _bom_convert on commit drop as
select pc.product_consumable_id, pc.quantity, pc.per_case, m.pack
  from _case_map m
  join public.products p on p.size = m.size_id
  join public.product_consumables pc on pc.product_id = p.product_id
 where pc.quantity = m.pack
   and not pc.per_case;

insert into public._case_conversion_20261004 (kind, product_consumable_id, old_quantity, old_per_case, pack)
select 'bom', product_consumable_id, quantity, per_case, pack from _bom_convert;

update public.product_consumables pc
   set quantity = 1,
       updated_at = now(),
       updated_by = 'migration-20261004000005'
  from _bom_convert b
 where pc.product_consumable_id = b.product_consumable_id;

do $verify$
declare
  v_sizes int; v_bom int; v_bad int; v_rec record;
begin
  select count(*) into v_sizes from public._case_conversion_20261004 where kind = 'size';
  select count(*) into v_bom   from public._case_conversion_20261004 where kind = 'bom';
  raise notice 'converted % size(s) and divided % bill-of-materials line(s)', v_sizes, v_bom;

  -- 1. Both case columns agree on every row, which the CHECK enforces, asserted
  --    anyway so a future edit to this file cannot quietly drop one.
  select count(*) into v_bad from public.size
   where (base_size_id is null) <> (units_per_case is null);
  if v_bad > 0 then raise exception '% size(s) have one case column set and not the other', v_bad; end if;

  -- 2. No case is built from a case, and no case is built from itself.
  select count(*) into v_bad from public.size s
    join public.size b on b.size_id = s.base_size_id
   where b.units_per_case is not null or b.size_id = s.size_id;
  if v_bad > 0 then raise exception '% case(s) point at a base that is itself a case', v_bad; end if;

  -- 3. Every base lives in the same company as its case. A cross-tenant base
  --    would price one roaster's packaging off another's size.
  select count(*) into v_bad from public.size s
    join public.size b on b.size_id = s.base_size_id
   where b.company_id <> s.company_id;
  if v_bad > 0 then raise exception '% case(s) point at another company''s size', v_bad; end if;

  -- 4. 🔴 THE ONE THAT MATTERS: the effective per-case draw must be unchanged
  --    for every line this file divided. quantity 1 x pack must equal the old
  --    quantity. If this fails, packaging consumption moved and the whole point
  --    of splitting the migration in two was lost.
  select count(*) into v_bad
    from public._case_conversion_20261004 c
    join public.product_consumables pc on pc.product_consumable_id = c.product_consumable_id
   where c.kind = 'bom'
     and (pc.quantity * c.pack) <> c.old_quantity;
  if v_bad > 0 then
    raise exception '% converted line(s) changed the per-case draw; this migration must be net zero on them', v_bad;
  end if;

  -- 5. Nothing still holds a raw case total. A line left equal to its pack
  --    count would now be multiplied by it.
  select count(*) into v_bad
    from public.size s
    join public.products p on p.size = s.size_id
    join public.product_consumables pc on pc.product_id = p.product_id
   where s.units_per_case is not null and not pc.per_case
     and pc.quantity = s.units_per_case and s.units_per_case > 1;
  if v_bad > 0 then
    raise exception '% line(s) still hold a case total and would now be multiplied by it', v_bad;
  end if;

  -- 6. Say out loud which numbers moved, and which cases were left behind.
  for v_rec in
    select s.size_name, ci.consumable_inventory_item as item,
           pc.quantity as per_unit, s.units_per_case as pack,
           pc.quantity * s.units_per_case as now_draws
      from public.size s
      join public.products p on p.size = s.size_id
      join public.product_consumables pc on pc.product_id = p.product_id
      join public.consumable_inventory ci on ci.consumable_inventory_id = pc.consumable_id
     where s.units_per_case is not null and not pc.per_case
       and not exists (select 1 from public._case_conversion_20261004 c
                        where c.kind = 'bom' and c.product_consumable_id = pc.product_consumable_id)
     order by 1, 2
  loop
    raise notice 'CORRECTED: % / % was under-entered and now draws % per case', v_rec.size_name, v_rec.item, v_rec.now_draws;
  end loop;

  for v_rec in
    select s.company_id, s.size_name from public.size s
     where s.size_name ~* 'case of [0-9]+' and s.units_per_case is null
     order by 1, 2
  loop
    raise notice 'LEFT ALONE: % / % could not be converted; its base size is not derivable from the data', v_rec.company_id, v_rec.size_name;
  end loop;
end $verify$;

commit;
