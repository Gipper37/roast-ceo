-- A case variant's compiled name says it is a case, and says the SIZE too.
--
-- The owner has settled this, 2026-10-04:
--
--     "it jsut needs to show the case in the name when its a case item. its
--      not that hard. why wouldnt shuks size be listed in the name. the size
--      is in the variant as is the case. is that not how you designed it."
--
-- So the size part of a case variant's compiled name is "227g (Case of 6)".
-- Not "Case of 6", which is what Social Hour UK reads today and which is the
-- whole complaint: a buyer sees no size at all. Not "Case of 6" with the size
-- hidden in a column either. Both halves, in the name, on the invoice.
--
-- Renaming churn is ACCEPTED. There is no flag, no opt-in, no
-- default-to-leaving-it-alone, and this file does not ask the question again.
--
-- -- WHAT WAS WRONG ----------------------------------------------------------
--
-- `build_product_name()` composes `{group_name} - {size_name} - {channel}`
-- into products.product_name. Until 20261002000002 gave a case a real model
-- (size.base_size_id + size.units_per_case) a case read as a case only because
-- somebody typed the case into the size name. Two roasters typed it two ways:
--
--   Maui Coffee Roasters  "2lb (Case of 12)", "2oz (Case of 40 - labeled,
--                         green bags)"            size AND case, by hand
--   Social Hour UK        "Case of 6"             case only, size nowhere
--
-- Now that units_per_case carries the count and base_size_id carries the unit,
-- the name can be composed from the DATA instead of from what somebody typed,
-- and "Case of 6" stops being a product nobody can order correctly.
--
-- -- THE FORMAT LIVES IN ONE PLACE -------------------------------------------
--
-- An earlier attempt at this repeated the same "(Case of N)" regex in five
-- places with nothing to check it against, so the function, the assertions and
-- the backfill could all disagree and nothing would catch it. Here the shape
-- is `public.case_size_label(base_size_name, units_per_case)` and that one
-- function is what composes the name, what the assertions test the stored
-- result against, and what the backfill derives from. Change the shape there
-- and all three move together.
--
-- -- THE ONE CASE THAT IS LEFT AS TYPED, AND WHY -----------------------------
--
-- A size whose typed name ALREADY states this pack count AND this base unit
-- keeps its typed name. That is not a hedge; it is a measured defect in the
-- alternative. MCR has four 2oz cases distinguished only by the qualifier the
-- roaster typed:
--
--   2oz (Case of 40)                        2oz (Case of 40 - labeled, green bags)
--   2oz (Case of 80 - labeled)              2oz (Case of 80 - no label)
--
-- Composing every case as "{base} (Case of {N})" collapses the first pair to
-- the same string and the second pair to the same string, so two different
-- variants of the same product on the same channel end up with byte-identical
-- product_name. That string is how QuickBooks matches a line and how the shop
-- lists an item. The owner accepted churn in the names; he did not accept two
-- products becoming indistinguishable. A typed name that already says the size
-- and the case satisfies his requirement exactly and may say more besides, so
-- it is kept.
--
-- The test is an ORACLE, not a parser: the count still comes from
-- units_per_case and the unit still comes from the base size row. The typed
-- text is only asked a yes/no question, "do you already say both of these",
-- and `case_size_label_is_implied()` is the one place that asks it.
--
-- -- SCOPE: CASE VARIANTS, AND NOTHING ELSE ----------------------------------
--
-- 🔴 The recompile is scoped to products whose size IS a case
-- (`size.units_per_case is not null`). It is deliberately NOT "every product
-- whose compiled name differs from its stored one". Measured on prod, 57 of
-- 990 group-derived products disagree with the current function, and most of
-- that disagreement is damage waiting to happen:
--
--   "Anglesey Sunrise - 227g - VIP"  recompiles to  "... - Vip"   36 rows
--   "Kona Extra Fancy - 100G - Retail"              "... - 100g"
--   "Mokka Peaberry - 2LBS - Wholesale"             "... - 2lbs"
--
-- `initcap()` turns the VIP channel into "Vip" on more than thirty live
-- product names. That is a separate defect in the channel part of the
-- composer, it is not what the owner asked for, and a naming migration about
-- cases has no business shipping it. Not one case product is on the vip
-- channel (all 33 are wholesale or Safeway), so the case scope avoids it
-- entirely. The "Vip" problem is left open and untouched.
--
-- Two further exclusions, each one line:
--   - a tombstoned product (merge_into_id set) keeps its name, because that
--     name is what historical invoices for the merged-away variant read;
--   - a resold consumable keeps its name, because
--     propagate_consumable_name_to_products owns it (unchanged behaviour).
--
-- -- WHAT MOVES ON PROD ------------------------------------------------------
--
-- With 20261004000005 and 20261004000006 applied, 33 products sit on a case
-- size and 30 of them are renamed. Measured on a throwaway clone of prod:
--
--   21  Social Hour UK, size uk-case6 ("Case of 6", base 227g, pack 6)
--         "Brazil - Case of 6 - Wholesale"
--      -> "Brazil - 227g (Case of 6) - Wholesale"
--
--    5  of those 21 were ALREADY stale before this file: they were compiled
--       from the product-named sizes the owner archived, and they have been
--       reading a size the product does not sit on. The owner, same day:
--       "for shuk aren't those hendrix case of 6 archived. didn't i change
--       that in their system by just adding a case of 6 variant and archive
--       the ones they had created that were at the product group level."
--       Correct, and verified: of the six UK case sizes only uk-case6 is
--       active, and the five product-named ones (637f51ad Anglesey,
--       89f62c10 Hendrix, 17ee9018 Nova, 27c76630 Sunset Decaf, caac333c
--       Vinyl) carry ZERO products. Their names were fossils.
--         "Hendrix - Hendrix Case of 6 - Wholesale"
--      -> "Hendrix - 227g (Case of 6) - Wholesale"
--
--    9  Maui Coffee Roasters, whose product names never agreed with their own
--       size names either:
--         "Maui Blend - 2oz case 40 - Wholesale"
--      -> "Maui Blend - 2oz (Case of 40) - Wholesale"
--         "Ka'u - 10-count 8oz case - Wholesale"
--      -> "Ka'u - 8oz (Case of 10) - Wholesale"
--       and two where the base size row is named "2lbs" while the case was
--       typed "2lb", so the composed name adopts the base row's spelling:
--         "Maui Blend - 10x2lb case - Wholesale"
--      -> "Maui Blend - 2lbs (Case of 10) - Wholesale"
--
--    3  are left alone because their stored name already agrees exactly, e.g.
--       "Dawn Patrol - 8oz (Case of 10) - Safeway". A product whose name is
--       already right is not written.
--
-- 🔴 product_name is read by the invoice, the shop listing and QuickBooks
-- matching. Every single change is printed by notice, before and after, and
-- recorded in public._case_naming_20261004 so it can be put back.
--
-- -- ORDER IN THE PUSH -------------------------------------------------------
--
-- 🔴 20261004000006 asserts that no product_name changed anywhere in the
-- database (its check C). It must therefore COMMIT BEFORE this file runs. On a
-- normal filename-ordered push it does, because 0006 sorts before 0007 and
-- each file carries its own begin/commit. Do not reorder them and do not merge
-- them into one transaction.
--
-- This file also tolerates 0005 or 0006 NOT having been applied. The scope is
-- a single predicate on the data, `units_per_case is not null`, so:
--   - neither applied: no size is a case, the function is installed, nothing
--     is renamed, and a notice says so;
--   - only 0005: MCR's 12 case products are recompiled, Social Hour UK's 21
--     keep their current names because uk-case6 has no pack count yet;
--   - only 0006: the mirror of that.
-- Nothing here asserts that any particular size, product or roaster exists.
--
-- -- A SIDE EFFECT OF WRITING TO products AT ALL -----------------------------
--
-- 🔴 trg_update_product_cogs fires BEFORE INSERT OR UPDATE on products with NO
-- column list, so a write that touches only product_name still re-runs
-- update_product_total_cogs, which recomputes weight_lbs from the size and the
-- cached cost columns from current coffee and consumable costs. For a row that
-- is inactive both before and after, that function returns early and nothing
-- is recomputed at all.
--
-- Whether any cached number actually MOVES depends on how stale the cache was,
-- which is this database's data and not this change, so movement is reported
-- by notice with before and after and is never asserted. What IS asserted is
-- the blast radius: only the rows this file set out to rename changed name,
-- and no other product in the database did.
--
-- -- WHAT THE SCHEMA ALREADY GUARANTEES, AND WHAT IT DOES NOT ---------------
--
-- Three CHECK constraints and one FK on `size` narrow the cases this file has
-- to handle, and they are worth naming because two of them make a branch here
-- defensive rather than reachable:
--
--   size_case_fields_agree      (base_size_id is null) = (units_per_case is null)
--   size_base_size_id_fkey      base_size_id references size(size_id)
--   size_units_per_case_gt_one  units_per_case is null or units_per_case > 1
--   size_base_is_not_self       base_size_id is null or base_size_id <> size_id
--
-- So a case ALWAYS has a base_size_id, that base row ALWAYS exists, and the
-- pack is ALWAYS at least 2. "The base cannot be resolved" therefore reduces
-- to one real case: `size.size_name` is nullable, so the base row can have no
-- name. That is the case the fallback is for, and it is proven below. The
-- pack-of-one guard in case_size_label() is belt and braces against the
-- constraint being relaxed later.
--
-- Likewise `products_group_id_not_null` means the null-group early return
-- cannot be reached from the table any more. It is preserved verbatim anyway,
-- because compile_product_name() is now callable directly and because the
-- constraint is not this file's to rely on.
--
-- -- PROVEN ON A THROWAWAY CLONE OF PROD -------------------------------------
--
-- A local Postgres 17 cluster loaded with prod's real DDL, real function
-- bodies and real rows (product_name and the cached cost columns checksummed
-- identical to prod before anything ran), with 20261004000005 and
-- 20261004000006 applied:
--
--   30 of 33 case products renamed, 3 left alone, and across all 1093
--      products in the table exactly 30 names differ. Nothing else moved.
--   0  CACHE RECOMPUTED notices: no cached cost number moved, because 0006
--      had already synced them.
--   second apply: "every case product's name already agrees"; zero writes.
--   0006 not applied: 9 MCR renames, and all 21 uk-case6 products keep their
--      current names, exactly as intended.
--   neither 0005 nor 0006 applied: zero renames, product names byte-identical
--      to the pre-state, and the function still installed and composing.
--   a case whose base row has no name: "Hendrix - Mystery Case of 6 -
--      Wholesale", the typed name, not half a name.
--   a fresh, properly modelled case ("Trade Pack", base 227g, pack 12):
--      "Hendrix - 227g (Case of 12) - Wholesale", composed from the data with
--      the typed name discarded, which is the point.
--   a resold consumable (103 of them) and a null group: both return null and
--      the stored name is untouched.
--
-- 🔴 One measurement that matters for the scope argument above: firing the
-- trigger on uk-227g, a NON-case size, renames 19 of its 73 products. It does
-- that identically with the OLD function and with this one, because it is the
-- pre-existing `initcap()` channel defect ("VIP" to "Vip"), not anything this
-- file introduces. That is exactly why the backfill is scoped to case sizes
-- and not to "every name that disagrees".
--
-- -- LEFT FOR LATER, DELIBERATELY NOT TOUCHED HERE ---------------------------
--
--   - the initcap channel defect above, which will rename "VIP" to "Vip" on
--     36 live products the next time anything writes their size or channel;
--   - two Add-size placeholders still teaching the roaster to type the case
--     into the size name, "e.g. 12oz, 1KG, Case of 6" (stratos
--     products/VariantsTable.tsx:127 and configuration/QuickBooksImport.tsx:3177).
--     Nothing in the frontend writes units_per_case or base_size_id yet, so
--     typing it by hand is still the only way a roaster makes a case, and the
--     oracle above is what keeps those hand-typed names working;
--   - merge_product_preview() shows the raw size_name, so a merge preview will
--     read "Case of 6" beside a product_name that now reads "227g (Case of 6)".
--
-- -- REHEARSING THIS FILE ----------------------------------------------------
--
-- 🔴 This file has its own begin/commit, so `BEGIN; \i file; ROLLBACK;` LANDS
-- the changes (the inner commit wins). Rehearse with
--   sed 's/^commit;$/rollback;/' <file> | psql ...
--
-- Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>

begin;

-- ---------------------------------------------------------------------------
-- 0. Schema prerequisite. This is the SCHEMA this file is written against, not
--    this database's data, so it is the one thing here that raises.
-- ---------------------------------------------------------------------------
do $$
declare
  v_missing text[] := '{}';
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'size'
                    and column_name = 'units_per_case') then
    v_missing := v_missing || 'size.units_per_case';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'size'
                    and column_name = 'base_size_id') then
    v_missing := v_missing || 'size.base_size_id';
  end if;
  if array_length(v_missing, 1) > 0 then
    raise exception '% does not exist; apply 20261002000002 (the case model) before this file',
      array_to_string(v_missing, ' and ');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. The down path. Every rename this file performs is recorded here with the
--    numbers that surrounded it, so a name can be put back by hand.
--
--    🔴 A new table in public is born granted to `authenticated` with ALL
--    privileges (Supabase pg_default_acl) and with RLS OFF, which is how
--    20261004000008 found five snapshot tables serving tenant data to every
--    logged-in user in every tenant. This one is revoked, has RLS enabled and
--    deliberately has NO policy, so nothing but a superuser or the service
--    role can read it.
-- ---------------------------------------------------------------------------
create table if not exists public._case_naming_20261004 (
  product_id                text,
  company_id                text,
  size_id                   text,
  size_name                 text,
  base_size_name            text,
  units_per_case            integer,
  old_product_name          text,
  new_product_name          text,
  was_active                boolean,
  old_weight_lbs            numeric,
  new_weight_lbs            numeric,
  old_total_coffee_cost     numeric,
  new_total_coffee_cost     numeric,
  old_total_consumable_cost numeric,
  new_total_consumable_cost numeric,
  old_total_unit_cogs       numeric,
  new_total_unit_cogs       numeric,
  old_cogs_pct              numeric,
  new_cogs_pct              numeric,
  old_margin_pct            numeric,
  new_margin_pct            numeric,
  noted_at                  timestamptz not null default now()
);

comment on table public._case_naming_20261004 is
  'Before and after state for every product renamed by 20261004000007 (a case variant''s name gained its base size). Append-only across re-applies: this table IS the down path, so a row is written the first time that product is renamed and never rewritten. Keep until the case naming has been seen on a real invoice, then drop.';

revoke all on table public._case_naming_20261004 from public, anon, authenticated;
alter table public._case_naming_20261004 enable row level security;
-- No policy, on purpose. RLS with no policy denies every non-superuser read.

-- ---------------------------------------------------------------------------
-- 2. THE FORMAT. One definition. The composer builds the name with it, the
--    assertions below test the stored result against it, and the backfill
--    derives from the composer, so none of the three can drift from the other
--    two.
--
--    "227g (Case of 6)", "2lbs (Case of 12)", "8oz (Case of 10)": the shape
--    MCR's hand-typed names already use, so nothing about how a case reads
--    changes for the roaster who was already typing it correctly.
--
--    Returns null when it cannot say both halves, which is the caller's signal
--    to fall back rather than print half a name. A pack of one is not a case
--    worth announcing, so it falls back too.
-- ---------------------------------------------------------------------------
create or replace function public.case_size_label(
  p_base_size_name text,
  p_units_per_case integer)
returns text
language sql
immutable
as $$
  select case
           when p_units_per_case is null or p_units_per_case < 2        then null
           when coalesce(btrim(p_base_size_name), '') = ''              then null
           else format('%s (Case of %s)', btrim(p_base_size_name), p_units_per_case)
         end
$$;

comment on function public.case_size_label(text, integer) is
  'The one definition of how a case variant states its size: "{base size name} (Case of {units per case})". Null when the base unit or the pack count is missing, or when the pack is 1, which tells the caller to fall back to the typed size name instead of printing half a name.';

-- ---------------------------------------------------------------------------
-- 3. THE ORACLE. Does a typed size name already state THIS pack count and THIS
--    base unit?
--
--    The count comes from units_per_case and the unit comes from the base size
--    row; this function never derives either from the text. It asks the text
--    one yes/no question, and it is the only place that question is asked.
--
--    "2oz (Case of 40 - labeled, green bags)" answers yes, so it is kept whole
--    and the "labeled, green bags" that distinguishes it from the plain case
--    of 40 survives. "Case of 6" answers no, because stripping the clause
--    leaves nothing that names the 227g bag, so it gets composed.
-- ---------------------------------------------------------------------------
create or replace function public.case_size_label_is_implied(
  p_size_name      text,
  p_base_size_name text,
  p_units_per_case integer)
returns boolean
language sql
immutable
as $$
  with said as (
    select coalesce(p_size_name, '')             as typed,
           btrim(coalesce(p_base_size_name, '')) as base,
           -- The clause for THIS pack count and no other: with pack 8,
           -- "Case of 80" must not match. The character that ended the clause
           -- is captured so stripping the clause does not eat it.
           'case[[:space:]]+of[[:space:]]+' || p_units_per_case::text || '([^0-9]|$)' as clause
  ),
  stripped as (
    select typed, base, regexp_replace(typed, clause, '\1', 'gi') as outside
      from said
  )
  select p_units_per_case is not null
     and base <> ''
     -- it names this pack count: removing the clause changed the text
     and outside <> typed
     -- and it names the unit somewhere other than inside that clause
     and strpos(lower(outside), lower(base)) > 0
    from stripped
$$;

comment on function public.case_size_label_is_implied(text, text, integer) is
  'True when a typed size name already states both this pack count and this base unit, so composing case_size_label() over it would add nothing and would throw away any qualifier the roaster typed (MCR distinguishes four 2oz cases only by "labeled", "no label" and "green bags"). The count and the unit are supplied by the caller from units_per_case and the base size row; this function only asks the text whether it already says them.';

-- ---------------------------------------------------------------------------
-- 4. THE COMPOSER, lifted out of the trigger so the backfill below can call
--    the same code the trigger calls instead of a second copy of it.
--
--    🔴 This body is build_product_name()'s body, moved. Every branch is the
--    original text:
--      - the source_consumable_id early return, with its comment recording
--        that group-deriving a resold consumable is what produced the "srm"
--        drift;
--      - the null group_id early return;
--      - the omit-empty-part assembly, so a missing piece never leaves a
--        stray " - ".
--    The two early returns now return NULL instead of NEW, and NULL means
--    "this row's name is not group-derived, leave whatever is stored alone".
--    The trigger in step 5 honours that, so behaviour is unchanged.
--
--    Left VOLATILE (unmarked), exactly as build_product_name() is, so the
--    three lookups keep the snapshot semantics they have today. Marking it
--    STABLE would quietly change which snapshot they see inside a statement.
--
--    SECURITY INVOKER, also as today: the trigger runs as the writing user, so
--    RLS still governs the product_groups, size and channel lookups and a
--    tenant cannot read another tenant's group name through it. Supabase grants
--    EXECUTE by name to authenticated and that grant must STAY, because the
--    trigger needs it on every ordinary product write.
-- ---------------------------------------------------------------------------
create or replace function public.compile_product_name(
  p_group_id             uuid,     -- products.group_id is uuid, the rest are text
  p_size                 text,
  p_channel              text,
  p_source_consumable_id text)
returns text
language plpgsql
as $function$
DECLARE
  v_group_name text;
  v_size_name  text;
  v_channel    text;
  v_parts      text[] := '{}';
  v_base_name  text;
  v_units      integer;
  v_case_label text;
BEGIN
  -- Resold consumable/equipment (source_consumable_id set): name follows the
  -- linked consumable and is kept in sync by propagate_consumable_name_to_products,
  -- so do NOT group-derive it (that is exactly what produced the "srm" drift).
  IF p_source_consumable_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  IF p_group_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT group_name INTO v_group_name FROM public.product_groups WHERE group_id = p_group_id;
  IF p_size IS NOT NULL THEN
    SELECT s.size_name, b.size_name, s.units_per_case
      INTO v_size_name, v_base_name, v_units
      FROM public.size s
      LEFT JOIN public.size b ON b.size_id = s.base_size_id
     WHERE s.size_id = p_size;

    -- The case, in the name, with the size. The count is units_per_case and
    -- the unit is the base size row's own name; neither is read out of
    -- v_size_name. size_case_fields_agree and size_base_size_id_fkey mean a
    -- case always HAS a base row, so the one way this can fail is a base row
    -- whose size_name is null or blank: case_size_label returns null, the
    -- typed size name stands, and nobody gets half a name on an invoice.
    IF v_units IS NOT NULL
       AND NOT public.case_size_label_is_implied(v_size_name, v_base_name, v_units) THEN
      v_case_label := public.case_size_label(v_base_name, v_units);
      IF v_case_label IS NOT NULL THEN
        v_size_name := v_case_label;
      END IF;
    END IF;
  END IF;
  IF p_channel IS NOT NULL THEN
    SELECT initcap(replace(channel, '_', ' ')) INTO v_channel FROM public.channel WHERE channel_id = p_channel;
  END IF;

  IF v_group_name IS NOT NULL THEN v_parts := v_parts || v_group_name; END IF;
  IF v_size_name IS NOT NULL AND v_size_name != '' THEN v_parts := v_parts || v_size_name; END IF;
  IF v_channel  IS NOT NULL AND v_channel  != '' THEN v_parts := v_parts || v_channel;   END IF;

  RETURN array_to_string(v_parts, ' - ');
END;
$function$;

comment on function public.compile_product_name(uuid, text, text, text) is
  'The composed product_name for a variant: "{group name} - {size name} - {channel}", where a case variant''s size part is case_size_label(base size, units per case) unless the typed size name already states both. Returns null for a resold consumable or a null group, meaning the stored name is not group-derived and must be left alone. Lifted out of build_product_name() so a backfill can call the same code the trigger calls.';

-- ---------------------------------------------------------------------------
-- 5. The trigger now delegates. trg_build_product_name stays exactly as it is
--    (BEFORE INSERT OR UPDATE OF group_id, size, channel) and is not touched.
-- ---------------------------------------------------------------------------
create or replace function public.build_product_name()
returns trigger
language plpgsql
as $function$
DECLARE
  v_name text;
BEGIN
  v_name := public.compile_product_name(NEW.group_id, NEW.size, NEW.channel, NEW.source_consumable_id);
  -- Null means this row's name is not group-derived (a resold consumable, or
  -- no group): leave the stored name alone, as this function always has.
  IF v_name IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.product_name := v_name;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Before-snapshot, in this transaction, so the blast radius below is
--    measured against what was actually there and not against a count typed
--    into this file.
-- ---------------------------------------------------------------------------
create temporary table _products_before on commit drop as
  select product_id, product_name, is_active, weight_lbs,
         total_coffee_cost, total_consumable_cost, total_unit_cogs,
         gross_profit_per_unit, cogs_pct, margin_pct
    from public.products;

create unique index on _products_before (product_id);

-- ---------------------------------------------------------------------------
-- 7. The rename set: products on a CASE size whose composed name differs from
--    what is stored. Derived from compile_product_name(), never from a second
--    copy of its logic.
-- ---------------------------------------------------------------------------
create temporary table _rename on commit drop as
select p.product_id,
       p.company_id,
       p.size                as size_id,
       s.size_name,
       b.size_name           as base_size_name,
       s.units_per_case,
       p.is_active,
       p.product_name        as old_name,
       public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id) as new_name
  from public.products p
  join public.size s on s.size_id = p.size
  left join public.size b on b.size_id = s.base_size_id
 where s.units_per_case is not null      -- a case variant, and nothing else
   and p.merge_into_id is null;          -- a tombstone's name is history

-- A resold consumable or a null group composes to null: that name is not ours.
-- A blank composition would erase a name, so it is refused rather than written.
-- A name that already agrees is not written at all.
delete from _rename
 where new_name is null
    or btrim(new_name) = ''
    or new_name is not distinct from old_name;

create unique index on _rename (product_id);

-- ---------------------------------------------------------------------------
-- 8. Say what is about to happen, line by line. This string is read by
--    invoices, the shop listing and QuickBooks matching, so every change is
--    printed and none of it is silent.
-- ---------------------------------------------------------------------------
do $$
declare
  v_cases    integer;
  v_products integer;
  v_rename   integer;
  v_rec      record;
begin
  select count(*) into v_cases from public.size where units_per_case is not null;
  select count(*) into v_products
    from public.products p join public.size s on s.size_id = p.size
   where s.units_per_case is not null;
  select count(*) into v_rename from _rename;

  raise notice 'OBSERVED: % size(s) in this database are cases, carrying % product(s)', v_cases, v_products;

  if v_cases = 0 then
    raise notice 'OBSERVED: no size is a case here, so nothing is renamed. build_product_name() is installed and will compose "{base} (Case of N)" the moment a size gets a pack count. Apply 20261004000005 / 20261004000006 to convert the cases a roaster already has.';
    return;
  end if;

  if v_rename = 0 then
    raise notice 'OBSERVED: every case product''s name already agrees with the composer; nothing to rename';
    return;
  end if;

  raise notice 'RENAMING % of % case product(s); the other % already agree',
    v_rename, v_products, v_products - v_rename;

  for v_rec in
    select company_id, size_name, is_active, old_name, new_name
      from _rename order by company_id, new_name
  loop
    raise notice '  [%] % (%)', v_rec.company_id, v_rec.size_name,
      case when v_rec.is_active then 'active' else 'archived' end;
    raise notice '      was: %', coalesce(v_rec.old_name, '<null>');
    raise notice '      now: %', v_rec.new_name;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 9. The write. SET touches product_name only, which is deliberately NOT one
--    of trg_build_product_name's columns (group_id, size, channel), so the
--    composed value is what lands rather than being recomputed under us.
-- ---------------------------------------------------------------------------
update public.products p
   set product_name = r.new_name
  from _rename r
 where p.product_id = r.product_id;

-- ---------------------------------------------------------------------------
-- 10. Internal consistency. These are about the change, not about the data, so
--     they are strict.
-- ---------------------------------------------------------------------------
do $$
declare
  v_expected integer;
  v_moved    integer;
  v_stray    integer;
  v_missed   integer;
  v_blank    integer;
  v_bad      integer;
  v_stale    integer;
  v_before_dupes integer;
  v_after_dupes  integer;
  v_rec      record;
begin
  select count(*) into v_expected from _rename;

  -- A. Exactly the intended rows changed name, and no other product did.
  select count(*) into v_moved
    from public.products p
    join _products_before o on o.product_id = p.product_id
   where p.product_name is distinct from o.product_name;

  select count(*) into v_stray
    from public.products p
    join _products_before o on o.product_id = p.product_id
    left join _rename r on r.product_id = p.product_id
   where p.product_name is distinct from o.product_name
     and r.product_id is null;

  select count(*) into v_missed
    from _rename r
    join public.products p on p.product_id = r.product_id
   where p.product_name is distinct from r.new_name;

  if v_moved <> v_expected or v_stray > 0 or v_missed > 0 then
    raise exception 'blast radius: expected % renames, % product name(s) moved, % of them outside the rename set, % intended rename(s) did not land',
      v_expected, v_moved, v_stray, v_missed;
  end if;

  -- B. No name was erased or nulled.
  select count(*) into v_blank
    from public.products p
    join _rename r on r.product_id = p.product_id
   where p.product_name is null or btrim(p.product_name) = '';
  if v_blank > 0 then
    raise exception 'blank name: % renamed product(s) ended with an empty product_name', v_blank;
  end if;

  -- C. The oracle. Every case product whose typed size name did NOT already
  --    state the size and the pack must now carry case_size_label() verbatim,
  --    and must not still read as the bare typed size name. This tests the
  --    STORED string against the single format definition, which is the check
  --    the earlier five-copies-of-a-regex attempt had no way to make.
  select count(*) into v_bad
    from public.products p
    join public.size s on s.size_id = p.size
    left join public.size b on b.size_id = s.base_size_id
   where s.units_per_case is not null
     and p.merge_into_id is null
     and p.group_id is not null
     and p.source_consumable_id is null
     and public.case_size_label(b.size_name, s.units_per_case) is not null
     and not public.case_size_label_is_implied(s.size_name, b.size_name, s.units_per_case)
     and strpos(p.product_name,
                public.case_size_label(b.size_name, s.units_per_case)) = 0;
  if v_bad > 0 then
    raise exception 'format: % case product(s) do not carry "{base} (Case of N)" in product_name', v_bad;
  end if;

  -- D. Idempotency. Composing every case product again now yields exactly what
  --    is stored, so a second apply of this file renames nothing.
  select count(*) into v_stale
    from public.products p
    join public.size s on s.size_id = p.size
   where s.units_per_case is not null
     and p.merge_into_id is null
     and public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id) is not null
     and public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id)
         is distinct from p.product_name;
  if v_stale > 0 then
    raise exception 'not idempotent: % case product(s) would still be renamed by a second apply', v_stale;
  end if;

  -- E. No NEW collision. This is the defect the oracle in step 3 exists to
  --    prevent: composing every case as "{base} (Case of N)" unconditionally
  --    would give MCR's two cases of 40 and two cases of 80 the same
  --    product_name, and that string is how QuickBooks matches a line. There
  --    are already 22 (company, name) pairs shared by more than one product on
  --    prod, so the test is that the number did not GROW, measured against the
  --    snapshot taken in this transaction rather than against a number typed
  --    into this file.
  select count(*) into v_before_dupes
    from (select p2.company_id, o.product_name
            from _products_before o
            join public.products p2 on p2.product_id = o.product_id
           where o.product_name is not null
           group by 1, 2 having count(*) > 1) before_dupes;
  select count(*) into v_after_dupes
    from (select company_id, product_name from public.products
           where product_name is not null
           group by 1, 2 having count(*) > 1) after_dupes;
  if v_after_dupes > v_before_dupes then
    raise exception 'collision: renaming created % new duplicate product name(s) within a company (% before, % after)',
      v_after_dupes - v_before_dupes, v_before_dupes, v_after_dupes;
  end if;

  raise notice 'ASSERTED: % rename(s) landed, 0 outside the case scope, 0 blank, 0 missing the "{base} (Case of N)" shape, 0 new duplicate name(s) (% shared before, % after), 0 left for a second apply',
    v_expected, v_before_dupes, v_after_dupes;

  -- F. What writing to products cost, as an OBSERVATION. trg_update_product_cogs
  --    has no column list, so a name-only write re-ran update_product_total_cogs
  --    on every active row. Whether a cached number moved depends on how stale
  --    the cache was, which is data, so this reports and never raises.
  for v_rec in
    select p.product_name,
           o.weight_lbs        as old_w, p.weight_lbs        as new_w,
           o.total_unit_cogs   as old_c, p.total_unit_cogs   as new_c,
           o.cogs_pct          as old_p, p.cogs_pct          as new_p
      from public.products p
      join _products_before o on o.product_id = p.product_id
      join _rename r          on r.product_id = p.product_id
     where o.weight_lbs      is distinct from p.weight_lbs
        or o.total_unit_cogs is distinct from p.total_unit_cogs
        or o.cogs_pct        is distinct from p.cogs_pct
     order by p.product_name
  loop
    raise notice 'CACHE RECOMPUTED: % weight_lbs % -> %, total_unit_cogs % -> %, cogs_pct % -> %',
      v_rec.product_name,
      coalesce(v_rec.old_w::text, '<null>'), coalesce(v_rec.new_w::text, '<null>'),
      coalesce(v_rec.old_c::text, '<null>'), coalesce(v_rec.new_c::text, '<null>'),
      coalesce(v_rec.old_p::text, '<null>'), coalesce(v_rec.new_p::text, '<null>');
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 11. Record the down path. Append-only: a product that was already recorded
--     by an earlier apply keeps its ORIGINAL old_product_name, because that is
--     the name this file found before it ever touched it.
-- ---------------------------------------------------------------------------
insert into public._case_naming_20261004
  (product_id, company_id, size_id, size_name, base_size_name, units_per_case,
   old_product_name, new_product_name, was_active,
   old_weight_lbs, new_weight_lbs,
   old_total_coffee_cost, new_total_coffee_cost,
   old_total_consumable_cost, new_total_consumable_cost,
   old_total_unit_cogs, new_total_unit_cogs,
   old_cogs_pct, new_cogs_pct, old_margin_pct, new_margin_pct)
select r.product_id, r.company_id, r.size_id, r.size_name, r.base_size_name,
       r.units_per_case, r.old_name, r.new_name, r.is_active,
       o.weight_lbs,            p.weight_lbs,
       o.total_coffee_cost,     p.total_coffee_cost,
       o.total_consumable_cost, p.total_consumable_cost,
       o.total_unit_cogs,       p.total_unit_cogs,
       o.cogs_pct,              p.cogs_pct,
       o.margin_pct,            p.margin_pct
  from _rename r
  join _products_before o on o.product_id = r.product_id
  join public.products p  on p.product_id = r.product_id
 where not exists (select 1 from public._case_naming_20261004 n
                    where n.product_id = r.product_id);

commit;
