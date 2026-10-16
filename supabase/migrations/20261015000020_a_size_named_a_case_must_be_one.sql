-- A size whose name says "case of 6" has to be a case of 6.
--
-- The case model is two columns: `base_size_id` (the bag it is a case of) and
-- `units_per_case` (how many). Everything downstream reads them --
-- `case_size_label` builds the display name, `product_consumables_effective`
-- multiplies the per-bag BOM by `coalesce(units_per_case,1)`,
-- `product_bag_weight_lbs` divides the case weight by the pack count for a
-- label, and `products.price` holds the CASE price while the roaster types
-- per-unit, so the pack count is half of what that number means.
--
-- THREE surfaces mint a size row from a free-text name and set NEITHER column:
--   app/app/(app)/configuration/qbImportActions.ts:1354   the QuickBooks wizard
--   app/app/(app)/configuration/ShopifyMappings.tsx:260   the Shopify mapper
--   app/app/(app)/products/group/[group_id]/GroupDetail.tsx:393  the Products page
-- So an operator who TYPES "2lb Case of 12" instead of picking an existing
-- size gets a plain bag: nothing divides its weight for a label, nothing
-- multiplies its per-bag BOM, and its price is read as a bag's. The name says
-- case, every reader says bag.
--
-- ── IT HAS ALREADY HAPPENED, FIVE TIMES ───────────────────────────────────
--
-- Social Hour Coffee Roasters UK, 2026-04-08 and 04-09, all by one user:
--   637f51ad  Anglesey Case of 6       weight 3.042376  no base, no pack count
--   89f62c10  Hendrix Case of 6        weight 3.042376  no base, no pack count
--   17ee9018  Nova Case of 6           weight 3.042376  no base, no pack count
--   27c76630  Sunset Decaf Case of 6   weight 3.042376  no base, no pack count
--   caac333c  Vinyl Case of 6          weight 3.042376  no base, no pack count
--
-- 🔴 AND NO MONEY MOVED, which is the part worth being accurate about. All
-- five are `is_active = f` with ZERO products on them, zero order lines and
-- zero BOM rows; the tenant went on to build `uk-case6` properly (base
-- `uk-227g`, pack 6) and has 21 products on that. So this was an afternoon
-- lost to a model that accepted a name it could not honour, not a mispriced
-- invoice. The guard is worth having because the next one might carry
-- products -- not because these five did.
--
-- ── WHY A TRIGGER AND NOT A CHECK ─────────────────────────────────────────
--
-- A CHECK applies to every row on every write, so those five archived rows
-- would have to be deleted, repaired or carried as NOT VALID before one could
-- exist. They are inert and they are also the evidence, so none of those is
-- attractive. A trigger scoped to `UPDATE OF size_name, units_per_case,
-- base_size_id` leaves an existing row alone until somebody edits the very
-- fields in question, which is the ordinary way to put a rule on live data
-- without a backfill. Archiving one of the five still works; renaming one is
-- refused, which is correct -- a rename is a chance to fix the model.

begin;

-- ── Does this name state a pack count? ────────────────────────────────────
--
-- Returns the count the NAME claims, or NULL if it claims none. One
-- definition, because the guard below and any UI that wants to warn earlier
-- must agree about what "names a case" means.
--
-- 🔴 TESTED AGAINST EVERY REAL SIZE NAME ON PROD plus adversarial ones, read
-- only, before this file existed. It must not trip on a bag whose name merely
-- contains the letters: "Caseload 8oz", "Compact 1lb", "Impact 2oz",
-- "Octoberfest 8oz", "Select 8oz", "Sampler", "Sample", "Pack" and all 38 real
-- names return NULL. It must read: "Case of 6" 6, "2lb (Case of 12)" 12,
-- "2oz (Case of 80 - no label)" 80, "Box of 24" 24, "Carton of 4" 4,
-- "12-pack" 12, "12 pack" 12, "6ct" 6, "24 count" 24.
--
-- `[^0-9a-z]{0,4}` is what keeps "Caseload" out: the gap between the keyword
-- and the number may hold punctuation and spaces, never more letters.
create or replace function public.size_name_states_pack_count(p_name text)
returns int
language sql
immutable
as $$
  select coalesce(
    (substring(lower(coalesce(p_name, '')) from
      '(?:case|box|carton|pack)[^0-9a-z]{0,4}(?:of[^0-9a-z]{0,4})?([0-9]+)'))::int,
    (substring(lower(coalesce(p_name, '')) from
      '([0-9]+)[[:space:]]*-?[[:space:]]*(?:pack|ct|count)\y'))::int
  )
$$;

comment on function public.size_name_states_pack_count(text) is
  'The pack count a size NAME claims ("2lb (Case of 12)" -> 12), or NULL if it claims none. Deliberately blind to names that merely contain the letters, such as "Caseload 8oz". The one definition of "this name says it is a case".';

-- ── The guard ─────────────────────────────────────────────────────────────
create or replace function public.guard_size_case_name_matches_the_pack()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  v_stated int := public.size_name_states_pack_count(new.size_name);
begin
  if v_stated is null then
    return new;   -- the name claims nothing; the columns are free to say anything
  end if;

  -- The message is for the ROASTER, not for me: it says what is wrong, in
  -- their words, and what to do instead. "violates check constraint" would
  -- reach them through a wizard that cannot explain it.
  if new.units_per_case is null or new.base_size_id is null then
    raise exception
      '"%" says it is a case of %, but it is saved as a single bag, so its price would be read as one bag''s and its packaging would be counted once. Pick the bag size it is a case of and how many go inside, or take the count out of the name if it really is one bag.',
      new.size_name, v_stated
      using errcode = 'check_violation';
  end if;

  if new.units_per_case is distinct from v_stated then
    raise exception
      '"%" says it is a case of %, but it is saved as a case of %. Make the name and the pack count agree before saving.',
      new.size_name, v_stated, new.units_per_case
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function public.guard_size_case_name_matches_the_pack() is
  'Refuses a size whose NAME states a pack count while base_size_id/units_per_case say it is a single bag, or state a different count. Scoped by its trigger to writes that touch those three fields, so existing rows are left alone until somebody edits them.';

drop trigger if exists aaa_guard_size_case_name on public.size;
-- `aaa_`, so it refuses BEFORE aab_derive_case_size_weight computes a weight
-- for a row that is not going to be stored.
create trigger aaa_guard_size_case_name
  before insert or update of size_name, units_per_case, base_size_id on public.size
  for each row execute function public.guard_size_case_name_matches_the_pack();

do $verify$
declare
  v_n     int;
  v_msg   text;
  v_bag   text;
  v_name  text;
begin
  -- 1. The predicate reads what it is supposed to, asserted rather than
  --    described. These are the cases prod actually contains plus the names
  --    that must NOT trip it.
  for v_name, v_n in
    select * from (values
      ('Case of 6', 6), ('2lb (Case of 12)', 12), ('2oz (Case of 80 - no label)', 80),
      ('Box of 24', 24), ('Carton of 4', 4), ('12-pack', 12), ('6ct', 6), ('24 count', 24)
    ) v(n, c)
  loop
    if public.size_name_states_pack_count(v_name) is distinct from v_n then
      raise exception 'size_name_states_pack_count(%) gave % and should give %',
        v_name, public.size_name_states_pack_count(v_name), v_n;
    end if;
  end loop;
  for v_name in
    select unnest(array['8oz', '12 oz', '2lbs', '100g', 'Sample', 'Sampler', 'Pack',
                        'Caseload 8oz', 'Compact 1lb', 'Impact 2oz', 'Select 8oz'])
  loop
    if public.size_name_states_pack_count(v_name) is not null then
      raise exception 'size_name_states_pack_count(%) read a pack count of % and should read none',
        v_name, public.size_name_states_pack_count(v_name);
    end if;
  end loop;

  -- 2. Every REAL size name here is still writable, i.e. this file refuses
  --    nothing that already exists and agrees with itself. The five archived
  --    fake cases are expected to be refusable: they are the bug.
  select count(*) into v_n
    from public.size s
   where public.size_name_states_pack_count(s.size_name) is not null
     and (s.units_per_case is null or s.base_size_id is null
          or s.units_per_case is distinct from public.size_name_states_pack_count(s.size_name));
  raise notice '% existing size(s) would be refused if renamed; all archived orphans on prod', v_n;

  -- 3. 🔴 THE GUARD FIRES, exercised rather than asserted. A real bag is
  --    renamed to claim a pack count, which must be refused, and then the
  --    legitimate shape must be accepted. Picked deterministically, and put
  --    back either way.
  select size_id into v_bag from public.size
   where units_per_case is null and base_size_id is null
     and public.size_name_states_pack_count(size_name) is null
   order by size_id limit 1;

  if v_bag is null then
    raise notice 'no plain bag here to probe the guard with, skipping';
  else
    select size_name into v_name from public.size where size_id = v_bag;
    begin
      update public.size set size_name = v_name || ' Case of 6' where size_id = v_bag;
      raise exception 'the guard let a bag be renamed to "% Case of 6"', v_name;
    exception
      when check_violation then
        v_msg := 'refused, as it should';
    end;
    if (select size_name from public.size where size_id = v_bag) is distinct from v_name then
      raise exception 'the refused rename changed the row anyway';
    end if;

    -- And a name that claims nothing is still free.
    update public.size set size_name = v_name where size_id = v_bag;
  end if;

  raise notice 'a size named a case must now be one';
end;
$verify$;

commit;
