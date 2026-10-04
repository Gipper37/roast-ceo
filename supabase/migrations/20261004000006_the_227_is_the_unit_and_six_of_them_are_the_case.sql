-- The 227 g bag is the unit, and six of them are the case.
--
-- STEP 2, PART TWO. 20261004000005 converted Maui Coffee Roasters' 7 case sizes
-- and deliberately REFUSED Social Hour UK's, because the arithmetic did not
-- close: the only candidate base was `uk-227g` at 0.500441 lb, 6 x that is
-- 3.002646, and the stored case weight was 3.042376, which is "3 g per bag out,
-- 18 g per case, 1.3%", so "it needs a human to say which unit size a UK case of
-- 6 is built from."
--
-- The human said it, 2026-10-04:
--
--     "why would uk store 226.996. they didn't input that they input 227."
--
-- That makes the refusal correct rather than timid, and this file is the answer.
-- It does two things in one transaction, in this order, because the second
-- depends on the first:
--
--   PART ONE   `uk-227g` is made to hold 227 g exactly.
--   PART TWO   `uk-case6` is made to hold six of them, and its bill of
--              materials is divided by six so the engine multiplies it back.
--
-- ── 🔴 WHERE 226.996 CAME FROM. IT IS A ROUNDED POUND, NOT A ROUNDED GRAM ──
--
-- The stored 0.500441 is not a truncation of the right answer. It is the right
-- arithmetic done with the wrong constant:
--
--   227 / 453.6        = 0.5004409...  -> 0.500441   THE STORED VALUE
--   227 / 453.59237    = 0.5004493...  -> 0.500449   six decimals of the truth
--
-- Somebody converted 227 g with a pound rounded to 453.6, and the row has been
-- 4 mg light ever since: 226.99621923517 g against a typed 227. Worth knowing
-- because it says which rows are suspect and which are not. `uk-1kg`
-- (2.20462) and `100g` (0.220462) are 453.59237 rounded to five and six
-- decimals, 1.2 mg and 0.1 mg light; they used the right constant. `uk-227g`
-- is the only UK size converted with the wrong one. Said once, acted on once.
--
-- This file stores the division, never its decimal expansion. `size.weight` is
-- unconstrained `numeric`, so `227 / 453.59237` lands exact to the precision
-- numeric division yields (20 places, which reads back as 227.0000000000000000
-- grams), and the expression in the SQL is its own documentation. That is also
-- what the app itself does: size `98c41c0e` ("50g") holds
-- 0.11023122100918888, the unrounded conversion of 50 g, and the 27 products on
-- it carry the same 17 places. A full-precision weight is the house behaviour
-- on a row created by the current code, not a novelty introduced here.
--
-- ── 🔴 PART ONE MOVES 73 PRODUCTS, AND NOT ALL FOR THE SAME REASON ────────
--
-- Measured on prod, and the headline sum is misleading unless it is split.
-- 73 products sit on `uk-227g`, 46 active, and their cached `weight_lbs` falls
-- into THREE buckets, not one:
--
--   67 products  hold 0.500441, the 453.6 conversion   46 active, 21 inactive
--    4 products  hold NULL                             all inactive
--    2 products  hold 0.75                             both inactive
--
-- Only the first bucket is the 227 g correction, and it is tiny: +0.0000083 lb
-- a bag, +0.00055846 lb across all 67. The other six rows dominate the total
-- (+2.00179734 and -0.49910133 lb) and have nothing to do with 227 g. So every
-- figure below is reported BY BUCKET and each of those six rows is named
-- individually at apply time. A single "sum moved by 1.5 lb" would hide a 0.75
-- -> 0.50 move inside a 4 mg fix, and that is the shape of defect this file
-- exists to correct.
--
-- WHY THE SIX ARE CORRECTED AND NOT LEFT ALONE. `weight_lbs` is not an
-- independent field. `update_product_total_cogs` assigns
-- `NEW.weight_lbs := v_weight` from the product's size on every insert and
-- update where the size has a weight, and there is no path in the app that sets
-- it to anything else. So a product on a 227 g size holding 0.75 lb (340 g) is
-- not somebody's decision, it is a cache that went stale and then stopped being
-- refreshed, and all six are inactive, which is exactly why: see the early
-- return below. Their names say it out loud ("Brazil - 227g - Wholesale" at
-- 0.75 lb). Correcting them is the schema's own rule applied, and it is what
-- makes the post-condition assertable: EVERY product on the 227 g size weighs
-- 227 g. Nothing financial moves on them, measured, and asserted below: all six
-- are inactive and carry NULL on all four cost columns.
--
-- 🔴 THE INACTIVE EARLY RETURN IS WHY THE WEIGHT IS ASSIGNED BY HAND. The
-- trigger's first statement is
--   `IF COALESCE(NEW.is_active,true)=false AND COALESCE(OLD.is_active,true)=false
--    THEN RETURN NEW; END IF;`
-- which returns BEFORE `NEW.weight_lbs := v_weight`. 27 of the 73 are inactive,
-- so a bare `set updated_at = now()` would leave exactly those 27 on the old
-- weight. Proved by doing it on a throwaway cluster loaded with these rows: 46
-- moved, 27 did not. Both UPDATEs below therefore assign `weight_lbs`
-- EXPLICITLY. It is the only thing that lands on an archived row.
--
-- WHAT MOVES IN PART ONE, measured on prod's rows in that cluster:
--   weight            0.500441 -> 227 / 453.59237, which is 226.99621923517 g
--                     -> 227.000000 g. One size row.
--   weight_lbs        73 products, 35.02954700 -> 36.53280147 lb in total,
--                     of which the 227 g correction is +0.00055846 across 67.
--   total_coffee_cost 61.020578 -> 61.021594 across the 46 active rows
--                     (+0.001016, +0.0017%), non-zero on 32 of them.
--                     total_unit_cogs follows it exactly, because
--                     total_consumable_cost is 0 on every one of the 73.
--   gross_profit_per_unit  -31.210578 -> -31.211594, which is minus the COGS
--                     move and nothing else. 8 of the 73 carry a price.
--   cogs_pct,         did not move, measured, because the trigger rounds them
--   margin_pct        to a tenth of a percent and 0.0017% does not reach it.
--                     Asserted unchanged only on the rows with no price, where
--                     the trigger leaves them NULL by construction; a priced
--                     row that DOES move is reported, not refused.
--   the 27 inactive   take the weight and keep their frozen `last_active_*`
--                     figures, which were costed at the old weight. Rewriting
--                     what a product cost when it was last on sale is not a
--                     weight fix. The 46 active rows are different: the trigger
--                     rewrites their `last_active_*` mirror on every touch, by
--                     design, so theirs follow.
--
-- ── 🔴 PART TWO CONVERTS ONE SIZE. THE OTHER FIVE ARE ARCHIVED ────────────
--
-- 20261004000005 named six UK case sizes. Only ONE of them is converted here,
-- because the owner already dealt with the other five, 2026-10-04:
--
--     "for shuk aren't those hendrix case of 6 archived. didn't i change that in
--      their system by just adding a case of 6 variant and archive the ones they
--      had created that were at the product group level."
--
-- Verified on prod. `uk-case6` ("Case of 6") is `is_active = true` and carries
-- all 21 case products. The five named after a product are `is_active = false`
-- and carry ZERO products between them:
--
--   637f51ad  Anglesey Case of 6        inactive, 0 products
--   89f62c10  Hendrix Case of 6         inactive, 0 products
--   17ee9018  Nova Case of 6            inactive, 0 products
--   27c76630  Sunset Decaf Case of 6    inactive, 0 products
--   caac333c  Vinyl Case of 6           inactive, 0 products
--
-- They are the product-group-level sizes the owner replaced with one generic
-- variant. Converting a dead size sets a 6x packaging multiplier on a row
-- nothing reads, in exchange for widening the blast radius of a money
-- migration by five rows. They are reported by notice, with what this file
-- observed about each, and skipped. They keep their wrong 1380 g, which costs
-- nothing while no product sits on them.
--
-- WHAT MOVES IN PART TWO, measured:
--   weight            3.042376 -> 6 x the corrected bag = 3.00269601095803264944
--                     (1379.99854 g -> 1362.000000 g, -0.039680 lb, -17.99854 g,
--                     -1.3043%). This is production shipping weight and the
--                     roasted-coffee draw per case.
--   base_size_id      NULL -> uk-227g, units_per_case NULL -> 6.
--   31 BOM lines      quantity 6 -> 1, per_case stays false. The effective draw
--                     stays 6 on every one, asserted line by line.
--   weight_lbs        21 products, 63.88989600 -> 63.05661623 lb.
--   total_coffee_cost 114.317582 -> 112.826602 (-1.490980, -1.3043%), and
--                     total_unit_cogs with it, because total_consumable_cost is
--                     0 on all 21 (every consumable on those 31 lines has
--                     last_cost_unit 0).
--   gross_profit_per_unit  -114.317582 -> -112.826602. None of the 21 is
--                     priced, so that is minus the COGS and nothing else.
--   last_active_*     -114.970684 -> -113.479704 on the 14 active rows, by the
--                     same trigger-by-design mirror as above.
--
-- It is a CORRECTION, not a reduction: the coffee in six 227 g bags IS 1362 g,
-- and 1380 g was six 230 g bags, a weight no product in the system has.
--
-- ── 🔴 WHY THE CASE WEIGHT IS NEVER A LITERAL ─────────────────────────────
--
-- Every case figure is computed as `6 x (the bag row as it stands after part
-- one)`, read back from the table rather than carried in a variable. So the
-- case cannot drift from the bag it is built from, the two halves cannot
-- disagree, and `base weight x pack = case weight` is asserted EXACTLY rather
-- than within a tolerance. It also means the file is correct on a database
-- where somebody already hand-corrected the bag: part one no-ops, part two
-- still builds the case from whatever the bag now holds. An earlier draft
-- hardcoded `round(p.weight_lbs,6) <> round(3.002646,6)`, which would have
-- aborted the moment the bag was corrected first.
--
-- ── 🔴 THIS FILE IS A NO-OP ON A DATABASE THAT DOES NOT HOLD ITS SUBJECT ──
--
-- An earlier draft asserted one tenant's DATA: that `uk-227g` exists, that
-- exactly 6 name-matched sizes exist, that there are exactly 31 bill-of-
-- materials lines and exactly 21 products. Staging holds none of that, so it
-- raised and stopped every migration queued behind it. That was the THIRD time
-- in one day: 20261003000001 required at least 2 shop_access_request rows
-- because prod happened to have two, and 20261003000003 asserted anon held zero
-- grants because prod happened to hold none. Both were fixed the same way, and
-- so is this one.
--
--   A MIGRATION ASSERTS ITS OWN CHANGE. A RELEASE CHECK ASSERTS THE POSTURE.
--
-- So: absent subject, nothing happens and a notice says why. Every count below
-- (73, 67, 31, 21, five archived) is an OBSERVATION raised as a notice, never a
-- precondition. Every guard is on SHAPE. The two parts degrade independently:
-- no `uk-227g` means the whole file is a notice, and a corrected bag with no
-- `uk-case6` is a complete, correct part one.
--
-- WHY BY ID, AND NOT BY A NAME MATCH. An earlier draft selected with
-- `size_name ~* 'case of 6'` and required the result to number exactly 6, which
-- makes ordinary owner activity unappliable: adding one more "Blend X Case of 6"
-- raises "expected 6, found 7", and renaming "Vinyl Case of 6" raises "expected
-- 6, found 5". A size_id is immutable; a size_name is a label the owner edits.
-- The pack count is the owner's sentence, not a parse: it is 6, declared once.
-- The name is used only as a CONTRADICTION check, because a row whose name says
-- "Case of 12" is not a row this file was adjudicated for.
--
-- And a size added tomorrow SHOULD be out of scope. Step 1 shipped the case
-- fields; a case created after today is created with them set. This file exists
-- to correct known rows a human ruled on, not to stand as a rule.
--
-- ── 🔴 WHAT A BAD ROW COSTS, AND WHY IT IS SKIPPED AND NOT AN EXCEPTION ───
--
-- 20261004000005 aborts on an ambiguous bill-of-materials line. This file
-- disqualifies the SIZE instead, loudly, and leaves it exactly as it is today,
-- where `COALESCE(units_per_case, 1) = 1` keeps its lines literal and correct.
-- Nothing is guessed either way, and a queue of migrations does not stop over
-- one roaster's typo. A size is skipped, with its reason named at apply time,
-- when any of these is true:
--
--   * its weight is NULL. The column is nullable, and an earlier draft wrote
--     its two "base weight x pack = case weight" assertions as
--     `count(*) where s.weight <> b.weight * s.units_per_case`, which counts
--     NOTHING for a NULL, so a NULL-weight case passed every check and came out
--     with `base_size_id` and `units_per_case = 6` set and its weight still
--     NULL: rehearsed, exit 0, silently wrong. A case whose weight is unknown
--     cannot be shown to be six bags, and putting a 6x multiplier on it is
--     precisely the silent 6-fold packaging error this feature prevents. Every
--     such comparison is now IS DISTINCT FROM.
--   * its weight is neither the wrong 1380 g nor already 6 x the bag. A third
--     value is somebody's decision and this file does not stamp over it.
--   * its case columns are already set to something else. A base that is not
--     `uk-227g`, or a pack that is not 6, is a configuration, not a gap.
--   * its name states a pack count that is not 6.
--   * any bill-of-materials line on its products is neither 1 nor 6, or holds a
--     NULL quantity. An earlier draft's ambiguity check read
--     `pc.quantity not in (1, u.pack)`, which is NULL for a NULL quantity and
--     so counted nothing: rehearsed, a NULL-quantity line was neither converted
--     nor flagged, the file exited 0, and that line's draw became NULL x 6. The
--     header claimed it would stop the migration. It did not.
--
-- The same shape applies to the bag: `uk-227g` is corrected only if the row
-- already claims to be a 227 g bag (to the nearest hundredth of a gram) and is
-- not itself a case. A size that claims some other weight is not a size this
-- file was told about, so it is reported and left alone.
--
-- ── THE BILL OF MATERIALS ─────────────────────────────────────────────────
--
-- 31 lines across the 21 case products, every one quantity 6 and per_case
-- false: a white retail bag and a product label, both per BAG, entered as the
-- case total. Once `units_per_case` is 6, `product_consumables_effective`
-- multiplies by 6, so 6 would become 36. They become quantity 1 and the
-- effective draw stays 6, asserted against the view itself and not against a
-- cost, because every consumable here has `last_cost_unit` 0: a money
-- comparison would pass on account of one tenant's zeroes. There is still not
-- one genuine per-case consumable in the set, no box and no case label, so
-- `per_case` stays false on all 31.
--
-- The 100 lines on the BAG's products are not touched and must not be: 96 hold
-- quantity 1, two hold 2 and two hold 4, and `uk-227g` keeps
-- `units_per_case IS NULL`, so `COALESCE(...,1) = 1` leaves every one of them
-- literal, exactly as today.
--
-- ── 🔴 THE PRODUCT NAMES ARE NOT TOUCHED HERE ─────────────────────────────
--
-- `trg_build_product_name` is BEFORE INSERT OR UPDATE **OF group_id, size,
-- channel**, and this file updates none of those three, so it does not fire.
-- That is deliberate. Five of the 21 case products are already STALE against
-- their size ("Anglesey Sunrise - Anglesey Case of 6 - Wholesale" sits on the
-- size named "Case of 6", compiled before the owner archived the
-- product-named sizes), and putting the pack count into the compiled name is
-- the owner's other instruction and 20261004000007's job. A weight fix must not
-- rename a roaster's products as a side effect, so `product_name` is asserted
-- byte-identical below for EVERY product in the database, not only these.
--
-- Proved by breaking it, and it takes TWO changes rather than one, which is
-- worth knowing because the single-change version looks safe and is not:
--   * `size` added to the CASE products' UPDATE alone renames NOTHING. The five
--     stale-named rows are active and carry a bill-of-materials line, so the
--     propagation has already corrected their weight and the statement's
--     `is distinct from` guard skips them.
--   * `size` added AND the guard dropped renames exactly those five,
--     "Anglesey Sunrise - Anglesey Case of 6 - Wholesale" to "Anglesey Sunrise
--     - Case of 6 - Wholesale" and so on, and the assertion stops the
--     migration: "5 product name(s) changed".
--   * `size` added to the BAG products' UPDATE renames 19 of the 73, because
--     their compiled names are stale against their group or channel too, and
--     the assertion stops that as well.
-- The assertion does not care which statement did it, which is why it holds in
-- all three cases.
--
-- ── 🔴 LINES ALREADY ON ORDERS. READ THIS BEFORE BELIEVING THEY ARE FROZEN ─
--
-- `handle_order_detail_logic` does NOT simply leave written lines alone.
--   * Its main block is guarded by `IF NOT v_is_legacy AND (TG_OP = 'INSERT' OR
--     quantity / product_id / amount_override / discount_kind / discount_value
--     IS DISTINCT FROM OLD...)`. Inside it BOTH
--     `NEW.roasted_weight := quantity * products.weight_lbs` AND
--     `NEW.unit_cost_at_sale := quantity * COALESCE(products.total_unit_cogs,0)`
--     are rewritten. Editing a line's QUANTITY on an order written last year
--     re-stamps that line's weight AND its COGS from the corrected figures.
--     There is no edit that picks up one and not the other.
--   * `unit_price_at_sale` is the only exception: repriced on INSERT, on a
--     product change, or when the snapshot is NULL, so an edit does not move
--     what the customer was quoted.
--   * A tail block outside that guard fills `roasted_weight` on ANY update of a
--     line whose roasted_weight is 0 or NULL, from the current weight_lbs.
--   * Lines on orders flagged `is_legacy_import` never enter the main block.
-- Measured on prod: 1495 order_details lines across 487 orders reference the 73
-- bag products, none legacy, 1442 carrying a roasted_weight and 1112 a
-- unit_cost_at_sale, all computed at 226.996 g; and 37 lines across 8 orders
-- reference the 21 case products, none legacy, all 37 carrying a roasted_weight
-- computed at 1380 g and all 37 carrying a NULL unit_cost_at_sale. This file
-- overwrites none of them. The first touch of any of those five fields on a
-- line is what moves it, which for a bag line is 0.0017% and for a case line is
-- -1.3%.
--
-- ── Reversibility ─────────────────────────────────────────────────────────
--
-- `_case_conversion_20261004_uk` holds, per row: the bag's and the case's old
-- weight, base and pack; the 31 lines' old quantity and per_case; and all 94
-- products' weight_lbs and four cost columns both BEFORE and AFTER. Undoing
-- this is a join against that table, not archaeology. It is a SEPARATE table
-- from 20261004000005's `_case_conversion_20261004`, which that file drops and
-- recreates: writing into the same name would destroy MCR's down path.
--
-- 🔴 AND THIS FILE DOES NOT DROP ITS OWN. An earlier draft opened with
-- `drop table if exists`, so a second apply deleted the undo path it calls the
-- undo path: rehearsed, run 2 left 0 'bom' rows (the lines are 1 now, so nothing
-- re-qualifies) and rewrote the product rows with old = new. It also made the
-- net-zero assertion vacuous, because an assertion over an empty snapshot
-- passes. The table is now `create table if not exists`, a row is recorded only
-- the FIRST time it is touched, and the after-state is filled only for rows this
-- run recorded. A second apply converts nothing, records nothing, and re-checks
-- run 1's own rows against the live data. On a database that never held the
-- subject the table is dropped again at the end rather than left behind empty.
--
-- ── How this was rehearsed, and what the rehearsal changed ───────────────
--
-- A throwaway Postgres 17 cluster loaded with prod's real DDL, real function
-- bodies and prod's real rows for size, products, product_consumables,
-- consumable_inventory, coffee_inventory, recipe_components, roast_recipes,
-- product_groups, product_type, companies and facilities, then torn down. Every
-- number in this header came off that cluster. What it caught:
--
--   APPLIED TWICE   run 2 writes 0 rows on all eight UPDATEs and all five
--                   INSERTs, and says so instead of reprinting the money as if
--                   it had moved again.
--   NO SUBJECT      a schema-only database, and a loaded database holding the
--                   other tenants with Social Hour UK removed: both skip with
--                   one notice and leave no snapshot table behind.
--   SKIPPED         a NULL case weight, a case weight of 0.55 lb, a case named
--                   "Case of 12", a bill-of-materials line at NULL and one at
--                   3, and a bag that is itself marked a case: each reported by
--                   name and left exactly as it was, with the rest of the file
--                   still doing its job where the two halves are independent.
--   BROKEN ON PURPOSE, and each assertion fired:
--     drop the explicit weight_lbs on the bag   -> "27 product(s) on the 227 g
--                                                   bag do not hold its weight"
--     drop it on the case                       -> "7 case product(s) do not
--                                                   hold six bags' worth"
--     divide the bill of materials to 2         -> "31 converted line(s)
--                                                   changed the per-case draw"
--     flip per_case true with quantity 1        -> the draw assertion read off
--                                                   product_consumables_
--                                                   effective, which the
--                                                   arithmetic one passes
--     hardcode the case weight to 3.002646      -> "base weight x pack = case
--                                                   weight" fails
--     rename as a side effect                   -> "5 product name(s) changed"
--     remove the RLS line                       -> `authenticated` reads 127
--                                                   rows and 175.3382 of one
--                                                   roaster's COGS, and can
--                                                   UPDATE them. With the line:
--                                                   0 rows.
--
-- Two defects in this file were found that way rather than by reasoning, and
-- both are noted where they live: the product buckets were classified against
-- the defect alone, so a second apply reported all 73 rows as stale caches; and
-- the bag assertion demanded 227 g to six decimals on every database, which
-- would have aborted on the hand-corrected row the header promises is a no-op.
--
-- 🔴 AND IT IS NOT WORLD-READABLE. `pg_default_acl` on prod hands
-- `authenticated` every privilege on a new table in `public`, and RLS defaults
-- off, so without the line below this table would be readable AND WRITABLE
-- through PostgREST by any logged-in user of any tenant, carrying one roaster's
-- COGS. That is the hole 20261004000008 closed on five existing snapshot
-- tables, and its reasoning is followed here rather than re-litigated: the
-- grant is the schema's convention and is left in place, RLS with no policy is
-- the fence. It denies every role except the owner and service_role, which is
-- exactly what a snapshot wants, and this migration still reads and writes the
-- table because it runs as the owner.

begin;

-- ── The snapshot, written before anything moves ───────────────────────────
--
-- NOT dropped first: see the header. It is the down path, and a second apply
-- must not be the thing that deletes it.
create table if not exists public._case_conversion_20261004_uk (
  kind                      text not null,   -- bag_size | case_size | bom | bag_product | case_product
  size_id                   text,
  product_id                text,
  product_consumable_id     text,
  label                     text,
  pack                      integer,
  old_weight                numeric,
  new_weight                numeric,
  old_base_size_id          text,
  old_units_per_case        integer,
  old_quantity              numeric,
  old_per_case              boolean,
  old_weight_lbs            numeric,
  new_weight_lbs            numeric,
  old_total_coffee_cost     numeric,
  new_total_coffee_cost     numeric,
  old_total_consumable_cost numeric,
  new_total_consumable_cost numeric,
  old_total_unit_cogs       numeric,
  new_total_unit_cogs       numeric,
  old_gross_profit_per_unit numeric,
  new_gross_profit_per_unit numeric,
  old_product_name          text,
  noted_at                  timestamptz not null default now()
);
comment on table public._case_conversion_20261004_uk is
  'Pre- and post-change state for 20261004000006 (Social Hour UK: the 227 g bag corrected from a 453.6 conversion, and uk-case6 made six of them). Append-only across re-applies: a row is recorded the first time it moves and never rewritten, because this table IS the down path. Keep until the case UI has been exercised against this data, then drop.';

-- 🔴 A NEW TABLE IN `public` IS NOT PRIVATE. See the header: the grant stays,
-- because that is this schema's convention and 20261004000008 settled it, and
-- RLS with no policy is the fence that makes the convention safe.
alter table public._case_conversion_20261004_uk enable row level security;

-- Every size and every product as they stand right now, so "nothing else moved"
-- is a comparison against THIS database and not a promise.
create temporary table _size_before on commit drop as
  select size_id, company_id, weight, base_size_id, units_per_case from public.size;

create temporary table _product_before on commit drop as
  select product_id, size, weight_lbs, total_coffee_cost, total_consumable_cost,
         total_unit_cogs, gross_profit_per_unit, cogs_pct, margin_pct,
         last_active_unit_cogs, last_active_gross_profit_per_unit,
         product_name, is_active, price
    from public.products;

-- ══ PART ONE: 227 g means 227 g ═══════════════════════════════════════════
--
-- The premise, as a WHERE clause. If there is no `uk-227g`, or it does not
-- claim to be a 227 g bag, or it is itself a case, this table comes out EMPTY
-- and every statement in the file touches nothing. That is the whole no-op
-- path, and it is one condition per sentence of the reasoning:
--
--   weight is not null       a bag of unknown weight is not a bag of 227 g
--   units_per_case is null   a case is never the base of a case
--   227.00 g to a hundredth  the row must ALREADY say it is a 227 g bag. This
--                            file sharpens a conversion; it never redefines a
--                            size. 226.99621923517 and 227.000000 both pass,
--                            which is what makes a re-run and a hand-corrected
--                            row behave the same.
create temporary table _bag on commit drop as
with raw as (
  select s.size_id,
         s.company_id,
         s.size_name,
         s.weight                                             as old_weight,
         -- The owner typed 227 grams. This is 227 grams, written as the division
         -- so the row documents itself and never as its decimal expansion.
         227::numeric / 453.59237                             as new_weight,
         -- The defect, named exactly: 227 divided by a pound rounded to 453.6.
         -- Guarding on the WRONG value is what makes a re-run and a row somebody
         -- already fixed by hand both no-ops.
         round(s.weight, 6) = round(227::numeric / 453.6, 6)   as holds_the_defect
    from public.size s
   where s.size_id = 'uk-227g'
     and s.weight is not null
     and s.units_per_case is null
     and round(s.weight * 453.59237, 2) = 227.00
)
-- What the bag will hold once this file is done with it, which on a re-apply
-- and on a hand-corrected row is simply what it holds now. The notices classify
-- the products against THIS and not against the defect: an earlier draft
-- compared each cached weight to the 453.6 value alone, so after a successful
-- apply every one of the 73 rows was reported as "a third value: stale cache".
-- 73 false alarms on the second run, found by running it twice.
select r.*, case when r.holds_the_defect then r.new_weight else r.old_weight end as will_hold
  from raw r;

do $bag_pre$
declare
  v_w numeric; v_u int; v_n int; v_rec record;
begin
  if not exists (select 1 from public.size where size_id = 'uk-227g') then
    raise notice 'SKIPPING ENTIRELY: size uk-227g is not in this database, so there is no Social Hour UK bag to correct and no case built from it. Nothing was changed.';
    return;
  end if;

  if not exists (select 1 from _bag) then
    select weight, units_per_case into v_w, v_u from public.size where size_id = 'uk-227g';
    raise notice 'SKIPPING ENTIRELY: uk-227g weighs % lb (% g) and units_per_case is %. This file corrects a row that already claims to be a 227 g bag and is not itself a case; it does not redefine a size. Nothing was changed.',
      coalesce(v_w::text, 'NULL'),
      coalesce(round(v_w * 453.59237, 5)::text, 'NULL'),
      coalesce(v_u::text, 'NULL');
    return;
  end if;

  select old_weight into v_w from _bag;
  if exists (select 1 from _bag where holds_the_defect) then
    raise notice 'CORRECTING THE BAG: uk-227g holds % lb (% g), which is 227 / 453.6. It becomes 227 / 453.59237 = % lb (% g).',
      v_w, round(v_w * 453.59237, 11),
      (select new_weight from _bag), (select round(new_weight * 453.59237, 6) from _bag);
  else
    raise notice 'THE BAG IS ALREADY CORRECT: uk-227g holds % lb (% g), which is not the 453.6 conversion this file replaces. Its weight is left exactly as it is, and the case below is built from it as it stands.',
      v_w, round(v_w * 453.59237, 11);
  end if;

  -- Observations. Prod holds 73 products on this size in three buckets on a
  -- first apply and one bucket on a re-apply; a database holding a different
  -- number is not a database with a problem.
  for v_rec in
    select case
             when b.weight_lbs is not distinct from g.will_hold
               then 'the corrected weight already, so it does not move'
             when b.weight_lbs is null then 'nothing at all (NULL)'
             when round(b.weight_lbs, 6) = round(227::numeric / 453.6, 6)
               then 'the 453.6 conversion, which is this file''s subject'
             else 'a third value: ' || b.weight_lbs::text
           end                                   as bucket,
           count(*)                              as n,
           count(*) filter (where b.is_active)   as active
      from _bag g
      join _product_before b on b.size = g.size_id
     group by 1 order by 2 desc
  loop
    raise notice 'OBSERVED: % product(s) on the bag (% active) cached %',
      v_rec.n, v_rec.active, v_rec.bucket;
  end loop;

  -- Each row that cached neither the defect nor the right answer is named,
  -- because a 0.75 -> 0.50 move must not hide inside a 4 mg fix. See the header
  -- for why they are corrected rather than left: weight_lbs is a cache of the
  -- size's weight and no app path sets it to anything else.
  for v_rec in
    select b.product_id, b.product_name, b.is_active, b.weight_lbs
      from _bag g
      join _product_before b on b.size = g.size_id
     where b.weight_lbs is distinct from g.will_hold
       and (b.weight_lbs is null
            or round(b.weight_lbs, 6) <> round(227::numeric / 453.6, 6))
     order by b.product_name
  loop
    raise notice 'STALE CACHE, NOT A 227 g CONVERSION: % (%, %) cached weight_lbs %, and takes the size''s weight like every other row on it',
      v_rec.product_name, v_rec.product_id,
      case when v_rec.is_active then 'active' else 'inactive' end,
      coalesce(v_rec.weight_lbs::text, 'NULL');
  end loop;

  select count(*) into v_n
    from _bag g
    join _product_before b on b.size = g.size_id
   where b.weight_lbs is distinct from g.will_hold
     and (b.weight_lbs is null or round(b.weight_lbs, 6) <> round(227::numeric / 453.6, 6))
     and (b.is_active or b.total_coffee_cost is not null or b.total_unit_cogs is not null);
  if v_n > 0 then
    raise notice '  of those, % is/are active or carry a cost, so the money columns below move for a reason other than the 227 g correction', v_n;
  end if;
end $bag_pre$;

-- Record the bag's before-state, and every product on it, BEFORE anything
-- moves. All of them, not only the ones that will change, so the report can say
-- "73 products, this sum before and this sum after" rather than a subset.
insert into public._case_conversion_20261004_uk
  (kind, size_id, label, pack, old_weight, new_weight)
select 'bag_size', b.size_id, b.size_name, 1, b.old_weight, b.new_weight
  from _bag b
 where not exists (select 1 from public._case_conversion_20261004_uk c
                    where c.kind = 'bag_size' and c.size_id = b.size_id);

insert into public._case_conversion_20261004_uk
  (kind, product_id, size_id, label, pack, old_weight_lbs, old_total_coffee_cost,
   old_total_consumable_cost, old_total_unit_cogs, old_gross_profit_per_unit,
   old_product_name)
select 'bag_product', o.product_id, b.size_id, b.size_name, 1,
       o.weight_lbs, o.total_coffee_cost, o.total_consumable_cost,
       o.total_unit_cogs, o.gross_profit_per_unit, o.product_name
  from _bag b
  join _product_before o on o.size = b.size_id
 where not exists (select 1 from public._case_conversion_20261004_uk c
                    where c.kind = 'bag_product' and c.product_id = o.product_id);

-- 1. The bag itself. Guarded on the DEFECT, so a re-run touches nothing and a
--    row somebody already fixed by hand is left exactly as they left it.
update public.size s
   set weight     = b.new_weight,
       updated_by = 'migration-20261004000006'
  from _bag b
 where s.size_id = b.size_id
   and b.holds_the_defect
   and round(s.weight, 6) = round(227::numeric / 453.6, 6);

-- 2. Everything downstream reads the bag back FROM THE TABLE, never from the
--    temp row that wrote it. On a database where the bag was hand-corrected the
--    UPDATE above was a no-op, and the products and the case must still agree
--    with whatever the row actually holds.
create temporary table _bag_now on commit drop as
  select s.size_id, s.company_id, s.size_name, s.weight as target_weight
    from public.size s
   where s.size_id in (select size_id from _bag);

-- 3. The 73. weight_lbs is assigned EXPLICITLY, because the trigger early-
--    returns on a row that is inactive on both sides and 27 of these are. The
--    column list is weight_lbs/updated_at/updated_by only, so
--    trg_build_product_name (OF group_id, size, channel) does not fire and no
--    product is renamed by a weight fix. The IS DISTINCT FROM is what makes a
--    second apply touch zero rows.
update public.products p
   set weight_lbs = b.target_weight,
       updated_at = now(),
       updated_by = 'migration-20261004000006'
  from _bag_now b
 where p.size = b.size_id
   and p.weight_lbs is distinct from b.target_weight;

-- The after-state, for the rows THIS run recorded. A row already carrying a
-- new_weight_lbs was recorded by an earlier apply and is left alone, because the
-- down path is the state before the FIRST change.
update public._case_conversion_20261004_uk c
   set new_weight_lbs            = p.weight_lbs,
       new_total_coffee_cost     = p.total_coffee_cost,
       new_total_consumable_cost = p.total_consumable_cost,
       new_total_unit_cogs       = p.total_unit_cogs,
       new_gross_profit_per_unit = p.gross_profit_per_unit
  from public.products p
 where c.kind = 'bag_product'
   and c.product_id = p.product_id
   and c.new_weight_lbs is null;

-- ══ PART TWO: and a case is six of them ═══════════════════════════════════
--
-- ONLY uk-case6. The other five are archived with zero products: see the
-- header. The base is pinned by the owner's sentence, not by a weight search,
-- and the pack is 6 for the same reason. Joining through _bag_now is what keeps
-- Social Hour US (R7CbqHmA1j) out: the case must live in the company that owns
-- the bag it is built from.
create temporary table _uk_case on commit drop as
select s.size_id,
       s.company_id,
       s.size_name,
       s.weight                                                     as old_weight,
       s.base_size_id                                               as old_base_size_id,
       s.units_per_case                                             as old_units_per_case,
       b.size_id                                                    as base_size_id,
       b.target_weight                                              as base_weight,
       6                                                            as pack,
       b.target_weight * 6                                          as new_weight,
       -- The name is not the selector, only a contradiction check.
       (regexp_match(s.size_name, 'case of ([0-9]+)', 'i'))[1]::int  as name_pack
  from _bag_now b
  join public.size s on s.size_id    = 'uk-case6'
                    and s.company_id = b.company_id
                    and s.size_id   <> b.size_id;

-- Which of them this file may convert, and which it must leave alone. Every
-- condition is about SHAPE, never about how many rows there are. A size that
-- fails any of them keeps COALESCE(units_per_case, 1) = 1, which leaves its
-- lines literal and correct, exactly as they are today.
create temporary table _uk_skip on commit drop as
select u.size_id, u.size_name,
       case
         when u.old_weight is null
           then 'its weight is NULL, so it cannot be shown to be six bags'
         when round(u.old_weight * 453.59237, 1) <> 1380.0
          and round(u.old_weight, 6) is distinct from round(u.new_weight, 6)
           then 'its weight is neither the wrong 1380 g nor 6 x the corrected bag; refusing to overwrite a deliberate value'
         when u.old_units_per_case is not null
          and (u.old_units_per_case <> u.pack or u.old_base_size_id is distinct from u.base_size_id)
           then 'its case columns are already set to a different base or pack'
         when u.name_pack is not null and u.name_pack <> u.pack
           then 'its name states a pack count that is not 6'
         when exists (
           select 1
             from public.products p
             join public.product_consumables pc on pc.product_id = p.product_id
            where p.size = u.size_id
              and not pc.per_case
              and (pc.quantity is null or pc.quantity not in (1, u.pack)))
           then 'a bill-of-materials line on its products is NULL or is neither 1 nor 6'
       end as reason
  from _uk_case u;

delete from _uk_skip where reason is null;

create temporary table _uk_convert on commit drop as
  select * from _uk_case u
   where not exists (select 1 from _uk_skip k where k.size_id = u.size_id);

do $case_pre$
declare v_rec record; v_n int;
begin
  if not exists (select 1 from _bag_now) then return; end if;

  -- The five the owner archived. Reported with what this file OBSERVED about
  -- each, not with what it expects, so a database where one of them is live
  -- says so instead of being described from this header.
  for v_rec in
    select s.size_id, s.size_name, s.is_active,
           (select count(*) from public.products p where p.size = s.size_id) as products
      from public.size s
      join (values ('637f51ad'), ('89f62c10'), ('17ee9018'), ('27c76630'), ('caac333c')) v(size_id)
        on v.size_id = s.size_id
      join _bag_now b on b.company_id = s.company_id
     order by s.size_name
  loop
    raise notice 'ARCHIVED, NOT CONVERTED: % (%) is_active=%, % product(s). The owner replaced the product-group-level case sizes with one generic variant and archived these; converting a dead size would widen the blast radius for nothing.',
      v_rec.size_name, v_rec.size_id, v_rec.is_active, v_rec.products;
  end loop;

  if not exists (select 1 from _uk_case) then
    raise notice 'NO CASE TO CONVERT: uk-case6 is not in this database, or not in the bag''s company. Part one stands on its own and part two did nothing.';
    return;
  end if;

  for v_rec in select size_id, size_name, reason from _uk_skip order by 2 loop
    raise notice 'LEFT ALONE: % (%) %', v_rec.size_name, v_rec.size_id, v_rec.reason;
  end loop;

  if not exists (select 1 from _uk_convert) then
    raise notice 'NO CASE TO CONVERT: uk-case6 was disqualified above. Nothing in part two was changed.';
    return;
  end if;

  -- Split so a re-apply reads as a re-apply and not as a conversion. Both
  -- figures are counted, never typed.
  select count(*) into v_n from _uk_convert where round(old_weight, 6) = round(new_weight, 6);
  if v_n > 0 then
    raise notice 'THE CASE IS ALREADY SIX BAGS: % holds % lb (% g), which is 6 x the bag at % lb. Its weight is left exactly as it is; only its case columns are filled if they are empty.',
      (select size_name from _uk_convert),
      (select round(old_weight, 11) from _uk_convert),
      (select round(old_weight * 453.59237, 6) from _uk_convert),
      (select round(base_weight, 11) from _uk_convert);
  else
    raise notice 'CONVERTING THE CASE: % to % lb (% g), which is 6 x the bag at % lb',
      (select size_name from _uk_convert),
      (select round(new_weight, 11) from _uk_convert),
      (select round(new_weight * 453.59237, 6) from _uk_convert),
      (select round(base_weight, 11) from _uk_convert);
    select count(*) into v_n from _uk_convert where round(old_weight * 453.59237, 1) = 1380.0;
    if v_n > 0 then
      raise notice '  it still holds the wrong 1380.0 g (six 230 g bags, a weight no product in the system has) and has its weight corrected';
    end if;
  end if;
end $case_pre$;

insert into public._case_conversion_20261004_uk
  (kind, size_id, label, pack, old_weight, new_weight, old_base_size_id, old_units_per_case)
select 'case_size', u.size_id, u.size_name, u.pack, u.old_weight, u.new_weight,
       u.old_base_size_id, u.old_units_per_case
  from _uk_convert u
 where not exists (select 1 from public._case_conversion_20261004_uk c
                    where c.kind = 'case_size' and c.size_id = u.size_id);

-- 4. The case weight. 1380.0 is a literal on purpose: it is the defect being
--    corrected, not the target. The target is always 6 x the bag row.
update public.size s
   set weight     = u.new_weight,
       updated_by = 'migration-20261004000006'
  from _uk_convert u
 where s.size_id = u.size_id
   and round(s.weight * 453.59237, 1) = 1380.0;

-- 5. The case columns. size_case_fields_agree forbids setting one without the
--    other, which is why they move in one statement.
update public.size s
   set base_size_id   = u.base_size_id,
       units_per_case = u.pack,
       updated_by     = 'migration-20261004000006'
  from _uk_convert u
 where s.size_id = u.size_id
   and s.units_per_case is null;

do $mid$
declare v_bad int;
begin
  if not exists (select 1 from _uk_convert) then return; end if;

  -- The arithmetic 20261004000005 could not make close. It closes now, exactly,
  -- because the case weight was computed from the base ROW. IS DISTINCT FROM,
  -- not <>: a NULL on either side is a FAILURE here, and `<>` would have counted
  -- it as a pass. That was an earlier draft's bug.
  select count(*) into v_bad
    from public.size s
    join _uk_convert u on u.size_id = s.size_id
    left join public.size b on b.size_id = s.base_size_id
   where s.weight is null
      or s.units_per_case is distinct from u.pack
      or s.base_size_id  is distinct from u.base_size_id
      or s.weight is distinct from b.weight * s.units_per_case;
  if v_bad > 0 then
    raise exception '% converted case(s) do not satisfy base weight x pack = case weight on a non-NULL weight', v_bad;
  end if;
end $mid$;

-- ── 6. The bill of materials ──────────────────────────────────────────────
--
-- quantity = pack is a per-unit item entered as a case total: it becomes 1 and
-- the engine multiplies it back. quantity = 1 is already per-unit and is left
-- alone. Anything else, NULL included, disqualified the size above, so nothing
-- here is a guess.
create temporary table _bom_convert on commit drop as
select pc.product_consumable_id, pc.product_id, pc.quantity, pc.per_case, u.pack,
       ci.consumable_inventory_item as item
  from _uk_convert u
  join public.products p  on p.size = u.size_id
  join public.product_consumables pc on pc.product_id = p.product_id
  left join public.consumable_inventory ci on ci.consumable_inventory_id = pc.consumable_id
 where pc.quantity = u.pack
   and not pc.per_case;

do $bom$
declare v_total int; v_conv int; v_ones int;
begin
  if not exists (select 1 from _uk_convert) then return; end if;

  select count(*) into v_total
    from _uk_convert u
    join public.products p on p.size = u.size_id
    join public.product_consumables pc on pc.product_id = p.product_id;
  select count(*) into v_conv from _bom_convert;
  select count(*) into v_ones
    from _uk_convert u
    join public.products p on p.size = u.size_id
    join public.product_consumables pc on pc.product_id = p.product_id
   where pc.quantity = 1 and not pc.per_case;

  -- Observations, not preconditions. Prod holds 31.
  raise notice 'OBSERVED: % bill-of-materials line(s) on the case''s products', v_total;
  raise notice 'dividing % of them; % already read as per-unit', v_conv, v_ones;
end $bom$;

insert into public._case_conversion_20261004_uk
  (kind, product_consumable_id, product_id, label, pack, old_quantity, old_per_case)
select 'bom', b.product_consumable_id, b.product_id, b.item, b.pack, b.quantity, b.per_case
  from _bom_convert b
 where not exists (select 1 from public._case_conversion_20261004_uk c
                    where c.kind = 'bom'
                      and c.product_consumable_id = b.product_consumable_id);

-- This UPDATE fires trg_propagate_consumable_bom, which touches the ACTIVE
-- parent products and so recomputes them against the already-corrected size.
-- That is why the weight moved first: a recompute against the old 1380 g would
-- have to be undone by the product touch below.
update public.product_consumables pc
   set quantity   = 1,
       updated_at = now(),
       updated_by = 'migration-20261004000006'
  from _bom_convert b
 where pc.product_consumable_id = b.product_consumable_id;

-- ── 7. The case's products, including the ones that early-return ──────────
--
-- Recorded from the state captured at the top of this transaction, NOT from the
-- live row: the UPDATE above has already fired trg_propagate_consumable_bom,
-- which recomputed the ACTIVE products that carry a line, so 12 of prod's 21 are
-- at the corrected weight before this statement runs. Reading the live row here
-- would record old = new for those 12 and lose the down path for them. Found by
-- rehearsing: the snapshot came out with 9 rows and the COGS notices vanished.
insert into public._case_conversion_20261004_uk
  (kind, product_id, size_id, label, pack, old_weight_lbs, old_total_coffee_cost,
   old_total_consumable_cost, old_total_unit_cogs, old_gross_profit_per_unit,
   old_product_name)
select 'case_product', o.product_id, u.size_id, u.size_name, u.pack,
       o.weight_lbs, o.total_coffee_cost, o.total_consumable_cost,
       o.total_unit_cogs, o.gross_profit_per_unit, o.product_name
  from _uk_convert u
  join _product_before o on o.size = u.size_id
 where not exists (select 1 from public._case_conversion_20261004_uk c
                    where c.kind = 'case_product' and c.product_id = o.product_id);

-- Same explicit-assignment care as the 73, and for the same reason: 7 of prod's
-- 21 are inactive and the trigger returns before it would assign the weight.
update public.products p
   set weight_lbs = u.new_weight,
       updated_at = now(),
       updated_by = 'migration-20261004000006'
  from _uk_convert u
 where p.size = u.size_id
   and p.weight_lbs is distinct from u.new_weight;

update public._case_conversion_20261004_uk c
   set new_weight_lbs            = p.weight_lbs,
       new_total_coffee_cost     = p.total_coffee_cost,
       new_total_consumable_cost = p.total_consumable_cost,
       new_total_unit_cogs       = p.total_unit_cogs,
       new_gross_profit_per_unit = p.gross_profit_per_unit
  from public.products p
 where c.kind = 'case_product'
   and c.product_id = p.product_id
   and c.new_weight_lbs is null;

-- ══ What this file wrote, asserted and said out loud ══════════════════════

do $verify$
declare
  v_bad int; v_n int; v_rec record;
  v_ow numeric; v_nw numeric;
  v_oc numeric; v_nc numeric;
  v_ocg numeric; v_ncg numeric;
  v_ogp numeric; v_ngp numeric;
  v_defect numeric := round(227::numeric / 453.6, 6);
begin
  -- ── Assertions about rows OUTSIDE the changed set run ALWAYS, because a file
  --    that did nothing still has to prove it did nothing.

  -- A. BLAST RADIUS: no size outside the changed set moved, and none appeared.
  --    Compared against this database's own before-state, so it is as strong on
  --    an empty database as on prod.
  select count(*) into v_bad
    from _size_before o
    join public.size s on s.size_id = o.size_id
   where (o.weight, o.base_size_id, o.units_per_case)
      is distinct from (s.weight, s.base_size_id, s.units_per_case)
     and o.size_id not in (select size_id from _bag)
     and o.size_id not in (select size_id from _uk_convert);
  if v_bad > 0 then
    raise exception '% size(s) outside the bag and the one converted case changed; the selection was too wide', v_bad;
  end if;

  select count(*) into v_n from public.size where size_id not in (select size_id from _size_before);
  if v_n > 0 then raise exception '% size row(s) appeared from nowhere', v_n; end if;

  -- B. BLAST RADIUS: no product outside those two sizes moved, on ANY of the
  --    columns the before-snapshot captured. An earlier draft checked weight_lbs
  --    alone and captured four, which left the money columns unguarded outside
  --    the set.
  select count(*) into v_bad
    from _product_before o
    join public.products p on p.product_id = o.product_id
   where (o.weight_lbs, o.total_coffee_cost, o.total_consumable_cost,
          o.total_unit_cogs, o.gross_profit_per_unit, o.cogs_pct, o.margin_pct)
      is distinct from
         (p.weight_lbs, p.total_coffee_cost, p.total_consumable_cost,
          p.total_unit_cogs, p.gross_profit_per_unit, p.cogs_pct, p.margin_pct)
     and p.size is distinct from (select size_id from _bag)
     and not exists (select 1 from _uk_convert u where u.size_id = p.size);
  if v_bad > 0 then
    raise exception '% product(s) outside the bag and the converted case changed weight or cost', v_bad;
  end if;

  -- C. No product was renamed, ANYWHERE. trg_build_product_name must not have
  --    fired. Five of the case products' names are stale against their size, so
  --    a rename is visible, and it is 20261004000007's change to make.
  select count(*) into v_bad
    from _product_before o
    join public.products p on p.product_id = o.product_id
   where o.product_name is distinct from p.product_name;
  if v_bad > 0 then
    raise exception '% product name(s) changed; a weight fix does not rename products', v_bad;
  end if;

  -- D. 🔴 THE ONE 20261004000005 CALLED THE ONE THAT MATTERS: every line this
  --    file has EVER divided, and that still exists, draws exactly what it drew
  --    before. The snapshot survives a re-run now, so this is not vacuous on
  --    apply two. A line somebody has since deleted is out of scope: the join
  --    drops it, and a deleted line is not this file's change.
  select count(*) into v_bad
    from public._case_conversion_20261004_uk c
    join public.product_consumables pc on pc.product_consumable_id = c.product_consumable_id
   where c.kind = 'bom'
     and (pc.quantity * c.pack) is distinct from c.old_quantity;
  if v_bad > 0 then
    raise exception '% converted line(s) changed the per-case draw; this file must be net zero on them', v_bad;
  end if;

  -- E. And the same claim read off the VIEW that actually feeds costing and
  --    depletion, rather than off the arithmetic this file just did. Asserted
  --    against the stated quantity, not against a cost, because every
  --    consumable here has last_cost_unit 0 and a money comparison would pass
  --    on account of one tenant's zeroes.
  select count(*) into v_bad
    from public._case_conversion_20261004_uk c
    join public.product_consumables_effective e
      on e.product_consumable_id = c.product_consumable_id
   where c.kind = 'bom'
     and e.quantity is distinct from c.old_quantity;
  if v_bad > 0 then
    raise exception '% converted line(s) draw a different effective quantity than before; product_consumables_effective disagrees with the net-zero claim', v_bad;
  end if;

  if not exists (select 1 from _bag) then
    -- Nothing happened. Leave no empty table behind on a database that does not
    -- hold this file's subject.
    if not exists (select 1 from public._case_conversion_20261004_uk) then
      execute 'drop table public._case_conversion_20261004_uk';
      raise notice 'no subject here, no snapshot table left behind';
    end if;
    raise notice '20261004000006 changed nothing in this database and asserted that nothing moved';
    return;
  end if;

  -- ── Assertions about what this file WROTE. Strict, every one.

  -- 1. The bag holds what this file said it would leave it holding, which is
  --    the exact conversion where the row held the defect and the row's own
  --    value where it did not.
  --
  --    🔴 THIS IS TWO ASSERTIONS AND NOT ONE, and an earlier draft wrote only
  --    the second half: `round(s.weight * 453.59237, 6) is distinct from
  --    227.000000` for every database. That aborts on a row somebody already
  --    corrected by hand to six decimals (0.500449 reads back as 226.999848 g),
  --    which the header promises is a no-op. Found by reading the no-op path
  --    against the assertion rather than by running the happy case again.
  select count(*) into v_bad
    from public.size s join _bag b on b.size_id = s.size_id
   where s.weight is distinct from b.will_hold;
  if v_bad > 0 then
    raise exception 'uk-227g does not hold the weight this file was going to leave it at';
  end if;

  --    And where this file DID correct it, the result is 227 g exactly, to six
  --    decimal places of a gram. Not "close to": a row left at the 453.6
  --    conversion reads 226.996219 and fails here, which is the whole point.
  if exists (select 1 from _bag where holds_the_defect) then
    select count(*) into v_bad
      from public.size s join _bag b on b.size_id = s.size_id
     where s.weight is null
        or round(s.weight * 453.59237, 6) is distinct from 227.000000;
    if v_bad > 0 then
      raise exception 'uk-227g was corrected and still does not weigh 227 g';
    end if;
  end if;

  -- 2. EVERY product on the bag carries the bag's weight, read back from the
  --    size table and not from the temp row that wrote it. This is what the
  --    explicit assignment buys: without it the inactive rows fail here.
  select count(*) into v_bad
    from public.products p
    join _bag_now b on b.size_id = p.size
    join public.size s on s.size_id = p.size
   where p.weight_lbs is distinct from s.weight;
  if v_bad > 0 then
    raise exception '% product(s) on the 227 g bag do not hold its weight; the inactive early return is back', v_bad;
  end if;

  -- 3. The six stale-cache rows moved their WEIGHT and no money. They are
  --    inactive and carry NULL on every cost column, so the trigger's early
  --    return means a weight assignment cannot have touched a figure. Asserted
  --    rather than described, because it is the justification for correcting
  --    them at all.
  select count(*) into v_bad
    from public._case_conversion_20261004_uk c
   where c.kind = 'bag_product'
     and (c.old_weight_lbs is null or round(c.old_weight_lbs, 6) <> v_defect)
     and ((c.old_total_coffee_cost, c.old_total_consumable_cost,
           c.old_total_unit_cogs, c.old_gross_profit_per_unit)
       is distinct from
          (c.new_total_coffee_cost, c.new_total_consumable_cost,
           c.new_total_unit_cogs, c.new_gross_profit_per_unit));
  if v_bad > 0 then
    raise exception '% product(s) whose cached weight was not the 453.6 conversion moved a cost column; this file corrects their weight only', v_bad;
  end if;

  -- 4. The consumable term did not move on anything, which is what "net zero on
  --    the packaging draw" is worth in money. NULL on the inactive rows, so
  --    compare distinctly.
  select count(*) into v_bad from public._case_conversion_20261004_uk
   where kind in ('bag_product', 'case_product')
     and old_total_consumable_cost is distinct from new_total_consumable_cost;
  if v_bad > 0 then
    raise exception '% product(s) moved their consumable cost; only the weight was supposed to move', v_bad;
  end if;

  -- 5. The coffee term moved by the weight and by NOTHING else. Cross
  --    multiplied, so this is exact numeric equality and not a tolerance:
  --    total_coffee_cost = cost_per_lb x weight_lbs, and cost_per_lb did not
  --    change inside this transaction. A NULL weight on either side is a
  --    FAILURE, not a pass: `<>` on a NULL counts nothing, which is the hole
  --    this file was rewritten to close.
  select count(*) into v_bad from public._case_conversion_20261004_uk
   where kind in ('bag_product', 'case_product')
     and old_total_coffee_cost is not null and new_total_coffee_cost is not null
     and (old_weight_lbs is null or new_weight_lbs is null
          or new_total_coffee_cost * old_weight_lbs
             is distinct from old_total_coffee_cost * new_weight_lbs);
  --
  -- 🔴 REPORTED, NOT RAISED, and the reason is in this file's own measurements.
  --
  -- The COGS trigger recomputes total_coffee_cost from coffee_inventory on any
  -- update, so this comparison only holds for a row whose cached cost was in
  -- sync with that price BEFORE the transaction. A row whose cache was stale is
  -- refreshed by the update, the cross multiplication fails, and a correct
  -- migration aborts over data it did not create.
  --
  -- That is not hypothetical here. This file measured 2 products on the 227 g
  -- size cached at 0.75 lb and 4 cached at NULL, so the WEIGHT cache is
  -- demonstrably stale on this tenant; there is no reason to assume the COST
  -- cache is cleaner. Raising would be the fourth instance in one day of a
  -- migration that asserts a database's DATA rather than its own change and
  -- stops every migration queued behind it.
  --
  -- So each one is named and the count is reported. A row listed here is a real
  -- finding worth chasing: either its cached cost was stale going in, which this
  -- transaction has now corrected as a side effect, or something other than the
  -- weight moved it, which would be a defect in this file. The log says which
  -- rows to look at; it no longer decides that the release cannot ship.
  if v_bad > 0 then
    raise notice '% product(s) changed their coffee cost by something other than the weight; '
                 'their cached cost was stale going in, or this file moved something it should not have',
                 v_bad;
    for v_rec in
      select c.product_id, c.old_weight_lbs, c.new_weight_lbs,
             c.old_total_coffee_cost, c.new_total_coffee_cost
        from public._case_conversion_20261004_uk c
       where c.kind in ('bag_product', 'case_product')
         and c.old_total_coffee_cost is not null and c.new_total_coffee_cost is not null
         and (c.old_weight_lbs is null or c.new_weight_lbs is null
              or c.new_total_coffee_cost * c.old_weight_lbs
                 is distinct from c.old_total_coffee_cost * c.new_weight_lbs)
       order by c.product_id
    loop
      raise notice '  not proportional: % weight % -> %, coffee cost % -> %',
        v_rec.product_id, v_rec.old_weight_lbs, v_rec.new_weight_lbs,
        v_rec.old_total_coffee_cost, v_rec.new_total_coffee_cost;
    end loop;
  else
    raise notice 'every product that carries a coffee cost moved it in exact proportion to its weight';
  end if;

  -- 6. total_unit_cogs is the sum of its two terms. Deliberately NOT asserted
  --    as proportional to the weight: it is, here, only because the consumable
  --    term is 0 on all 94 rows, and an assertion that holds on account of one
  --    tenant's zeroes is the bug at the top of this header.
  select count(*) into v_bad
    from public.products p
   where (p.size = (select size_id from _bag)
          or exists (select 1 from _uk_convert u where u.size_id = p.size))
     and p.total_coffee_cost is not null
     and p.total_consumable_cost is not null
     and p.total_unit_cogs is distinct from p.total_coffee_cost + p.total_consumable_cost;
  if v_bad > 0 then
    raise exception '% product(s) hold a total_unit_cogs that is not coffee + consumable', v_bad;
  end if;

  -- 7. Gross profit moved because COGS moved, and for no other reason. This is
  --    update_product_total_cogs' own identity: price is PER SELLING UNIT and
  --    COGS is per CASE, so the comparison happens on the case side. The bag's
  --    pack is 1 by COALESCE, the case's is 6.
  select count(*) into v_bad
    from public.products p
    join public.size s on s.size_id = p.size
   where (p.size = (select size_id from _bag)
          or exists (select 1 from _uk_convert u where u.size_id = p.size))
     and p.gross_profit_per_unit is not null
     and p.gross_profit_per_unit
         is distinct from coalesce(p.price, 0) * coalesce(s.units_per_case, 1) - p.total_unit_cogs;
  if v_bad > 0 then
    raise exception '% product(s) hold a gross profit that is not price x pack minus COGS', v_bad;
  end if;

  -- 8. The ratios. With no price the trigger leaves them NULL, so on every
  --    unpriced row they must be exactly what they were. A priced row WOULD
  --    move, correctly, so it is reported instead of asserted.
  select count(*) into v_bad
    from _product_before o
    join public.products p on p.product_id = o.product_id
   where (o.size = (select size_id from _bag)
          or exists (select 1 from _uk_convert u where u.size_id = o.size))
     and coalesce(o.price, p.price) is null
     and (o.cogs_pct, o.margin_pct) is distinct from (p.cogs_pct, p.margin_pct);
  if v_bad > 0 then
    raise exception '% unpriced product(s) moved cogs_pct or margin_pct', v_bad;
  end if;

  for v_rec in
    select p.product_id, p.product_name, o.cogs_pct as was, p.cogs_pct as now_is,
           o.margin_pct as was_m, p.margin_pct as now_m
      from _product_before o
      join public.products p on p.product_id = o.product_id
     where (o.size = (select size_id from _bag)
            or exists (select 1 from _uk_convert u where u.size_id = o.size))
       and p.price is not null
       and (o.cogs_pct, o.margin_pct) is distinct from (p.cogs_pct, p.margin_pct)
     order by 2
  loop
    raise notice 'RATIO MOVED: % carries a price, so cogs_pct % -> % and margin_pct % -> % followed the corrected COGS',
      v_rec.product_name, coalesce(v_rec.was::text, 'NULL'), coalesce(v_rec.now_is::text, 'NULL'),
      coalesce(v_rec.was_m::text, 'NULL'), coalesce(v_rec.now_m::text, 'NULL');
  end loop;

  -- 9. The invariants 20261004000005 asserts, SCOPED to the rows this file
  --    touched. Table-wide they would abort on a database carrying an unrelated
  --    inconsistency, which is not this file's change to assert. The whole-table
  --    posture belongs in a release check.
  select count(*) into v_bad from public.size s
    join _uk_convert u on u.size_id = s.size_id
   where (s.base_size_id is null) <> (s.units_per_case is null);
  if v_bad > 0 then raise exception '% converted size(s) have one case column set and not the other', v_bad; end if;

  select count(*) into v_bad from public.size s
    join _uk_convert u on u.size_id = s.size_id
    join public.size b on b.size_id = s.base_size_id
   where b.units_per_case is not null or b.size_id = s.size_id;
  if v_bad > 0 then raise exception '% converted case(s) point at a base that is itself a case', v_bad; end if;

  select count(*) into v_bad from public.size s
    join _uk_convert u on u.size_id = s.size_id
    join public.size b on b.size_id = s.base_size_id
   where b.company_id is distinct from s.company_id;
  if v_bad > 0 then raise exception '% converted case(s) point at another company''s size', v_bad; end if;

  -- 10. Every product on the converted case carries the case weight, and the
  --     case weight IS six bags. Read back from the tables, no literal.
  select count(*) into v_bad
    from public.products p
    join _uk_convert u on u.size_id = p.size
    join public.size s on s.size_id = p.size
   where p.weight_lbs is distinct from s.weight
      or s.weight is distinct from u.base_weight * u.pack;
  if v_bad > 0 then
    raise exception '% case product(s) do not hold six bags'' worth of weight', v_bad;
  end if;

  -- 11. Nothing on these products still holds a raw case total that would now be
  --     multiplied by the pack count.
  select count(*) into v_bad
    from public.size s
    join _uk_convert u on u.size_id = s.size_id
    join public.products p on p.size = s.size_id
    join public.product_consumables pc on pc.product_id = p.product_id
   where s.units_per_case is not null and not pc.per_case
     and pc.quantity = s.units_per_case and s.units_per_case > 1;
  if v_bad > 0 then
    raise exception '% line(s) still hold a case total and would now be multiplied by it', v_bad;
  end if;

  -- ── Say out loud what moved. Every figure is computed; none is typed. ─────

  -- Rows recorded by THIS transaction. now() is the transaction timestamp, so
  -- anything older was recorded by an earlier apply and the figures below are a
  -- replay of what that apply did, re-checked against the live data. Said out
  -- loud, because a report that reads identically on run 1 and run 2 invites
  -- somebody to conclude the money moved twice. It did not: every write in this
  -- file reports 0 rows on a second apply, measured.
  select count(*) into v_n from public._case_conversion_20261004_uk where noted_at = now();
  if v_n = 0 then
    raise notice '-- 20261004000006 RE-APPLY: nothing moved. The figures below are what the first apply recorded, re-checked against the live rows --';
  else
    raise notice '-- 20261004000006 moved these production numbers --';
  end if;

  for v_rec in
    select c.kind, c.label, c.old_weight, c.new_weight, c.pack,
           (select s.weight from public.size s where s.size_id = c.size_id) as now_weight
      from public._case_conversion_20261004_uk c
     where c.kind in ('bag_size', 'case_size')
       and c.size_id in (select size_id from _bag union all select size_id from _uk_convert)
     -- bag first: it is part one, and the case is six of whatever it holds.
     order by c.kind
  loop
    raise notice 'size  % (%)  % -> % lb  (% g -> % g, delta % lb, % g, % percent)',
      v_rec.label, v_rec.kind,
      round(v_rec.old_weight, 11), round(v_rec.now_weight, 11),
      round(v_rec.old_weight * 453.59237, 6), round(v_rec.now_weight * 453.59237, 6),
      round(v_rec.now_weight - v_rec.old_weight, 11),
      round((v_rec.now_weight - v_rec.old_weight) * 453.59237, 6),
      case when v_rec.old_weight is null or v_rec.old_weight = 0 then 'n/a'
           else round((v_rec.now_weight / v_rec.old_weight - 1) * 100, 4)::text end;
  end loop;

  -- The bag's products, BY BUCKET, because the three buckets moved for three
  -- different reasons and one sum would hide two of them.
  for v_rec in
    select case
             when c.old_weight_lbs is null then '3. cached NULL'
             when round(c.old_weight_lbs, 6) = v_defect then '1. cached the 453.6 conversion (the 227 g fix)'
             else '2. cached a third value (stale cache)'
           end                                              as bucket,
           count(*)                                         as n,
           sum(c.old_weight_lbs)                            as ow,
           sum(c.new_weight_lbs)                            as nw,
           sum(coalesce(c.new_weight_lbs, 0) - coalesce(c.old_weight_lbs, 0)) as dw
      from public._case_conversion_20261004_uk c
     where c.kind = 'bag_product'
     group by 1 order by 1
  loop
    raise notice 'bag products  %  % row(s)  weight_lbs % -> % lb  (delta % lb)',
      v_rec.bucket, v_rec.n,
      coalesce(round(v_rec.ow, 8)::text, 'NULL'), round(v_rec.nw, 8), round(v_rec.dw, 8);
  end loop;

  select count(*), sum(old_weight_lbs), sum(new_weight_lbs),
         sum(old_total_coffee_cost), sum(new_total_coffee_cost),
         sum(old_total_unit_cogs),   sum(new_total_unit_cogs),
         sum(old_gross_profit_per_unit), sum(new_gross_profit_per_unit)
    into v_n, v_ow, v_nw, v_oc, v_nc, v_ocg, v_ncg, v_ogp, v_ngp
    from public._case_conversion_20261004_uk where kind = 'bag_product';
  raise notice 'bag products  % total  weight_lbs % -> %  coffee % -> %  cogs % -> %  gross profit % -> %',
    v_n, round(coalesce(v_ow, 0), 8), round(coalesce(v_nw, 0), 8),
    round(coalesce(v_oc, 0), 6), round(coalesce(v_nc, 0), 6),
    round(coalesce(v_ocg, 0), 6), round(coalesce(v_ncg, 0), 6),
    round(coalesce(v_ogp, 0), 6), round(coalesce(v_ngp, 0), 6);

  select count(*), sum(old_weight_lbs), sum(new_weight_lbs),
         sum(old_total_coffee_cost), sum(new_total_coffee_cost),
         sum(old_total_unit_cogs),   sum(new_total_unit_cogs),
         sum(old_gross_profit_per_unit), sum(new_gross_profit_per_unit)
    into v_n, v_ow, v_nw, v_oc, v_nc, v_ocg, v_ncg, v_ogp, v_ngp
    from public._case_conversion_20261004_uk where kind = 'case_product';
  if v_n > 0 then
    raise notice 'case products % total  weight_lbs % -> %  coffee % -> %  cogs % -> %  gross profit % -> %',
      v_n, round(coalesce(v_ow, 0), 8), round(coalesce(v_nw, 0), 8),
      round(coalesce(v_oc, 0), 6), round(coalesce(v_nc, 0), 6),
      round(coalesce(v_ocg, 0), 6), round(coalesce(v_ncg, 0), 6),
      round(coalesce(v_ogp, 0), 6), round(coalesce(v_ngp, 0), 6);
  end if;

  -- Per product, where the money actually moved, so the next person reads the
  -- rows rather than a total.
  for v_rec in
    select c.kind, c.product_id, p.product_name, p.is_active,
           c.old_total_coffee_cost as was, c.new_total_coffee_cost as now_is
      from public._case_conversion_20261004_uk c
      join public.products p on p.product_id = c.product_id
     where c.kind in ('bag_product', 'case_product')
       and coalesce(c.old_total_coffee_cost, 0) <> coalesce(c.new_total_coffee_cost, 0)
     order by c.kind, 3
  loop
    raise notice 'COGS MOVED: % (%, %) coffee cost % -> %',
      v_rec.product_name, replace(v_rec.kind, '_product', ''),
      case when v_rec.is_active then 'active' else 'inactive' end,
      round(v_rec.was, 6), round(v_rec.now_is, 6);
  end loop;

  select count(*) into v_n from _bom_convert;
  raise notice 'divided % bill-of-materials line(s) this apply; effective draw unchanged on every one ever divided', v_n;

  select count(*) into v_n
    from public._case_conversion_20261004_uk c
    join public.products p on p.product_id = c.product_id
   where c.kind in ('bag_product', 'case_product') and not p.is_active;
  raise notice '% inactive product(s) took the corrected weight by explicit assignment, because the COGS trigger returns before it would set one, and they keep their frozen last_active_* figures, which were costed at the old weight', v_n;
end $verify$;

commit;
