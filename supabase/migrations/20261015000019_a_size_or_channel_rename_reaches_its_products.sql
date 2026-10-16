-- Renaming a size or a channel reaches the products named after it.
--
-- `compile_product_name` reads THREE tables live -- `product_groups.group_name`,
-- `size.size_name` (plus the base size's name, for a case label) and
-- `channel.channel` -- but `products.product_name` is a STORED string, written
-- only by `trg_build_product_name`, which is
--     BEFORE INSERT OR UPDATE OF group_id, size, channel ON products
-- So the composed name is refreshed only when a PRODUCT row is written on one
-- of those three columns. Of the three tables it reads, exactly one has a path
-- that does that: `renameProductGroup` writes `update products set group_id =
-- group_id`, a self-assignment that fires the trigger because group_id is in
-- its column list. `merge_product_groups` does the same.
--
-- `updateSize` and `updateChannel` write their row and stop (both copies of
-- updateSize: products/actions.ts:1154 and company/actions.ts:987). So
-- renaming a size or a channel leaves every product on it holding the old
-- name -- and product_name is what order pickers, pack-run labels, the
-- storefront and QuickBooks line matching all read.
--
-- ── NOT HYPOTHETICAL, AND SIX MONTHS OLD ──────────────────────────────────
--
-- Prod today. Size `58691df6` was renamed to `100g` on 2026-04-14 and size
-- `25dbab14` to `2lbs` on 2026-04-15. Five products still carry the old text:
--
--   803aa45c  Kona Extra Fancy - 100G - Retail      size says 100g   active
--   4c091d56  Kona Extra Fancy - 100G - Wholesale   size says 100g   active
--   23b13937  Kona Melody - 100G - Retail           size says 100g   active
--   fe4e2354  Kona Melody - 100G - Wholesale        size says 100g   active
--   bb7b2772  Mokka Peaberry - 2LBS - Wholesale     size says 2lbs   archived
--
-- All four live ones have been WRITTEN since the rename (2026-09-25 and
-- 2026-10-04) and still did not pick it up, because those writes touched
-- price and flags rather than group_id, size or channel. Waiting for an
-- unrelated edit is not a repair path.
--
-- ── 🔴 WHY THE REPAIR BELOW DOES NOT FIX ALL 43 DISAGREEING ROWS ──────────
--
-- 43 of prod's 992 composable products disagree with what the composer would
-- produce. Only 5 of them are this bug. The other 38 are the channel-casing
-- issue on the open list: `compile_product_name` does
-- `initcap(replace(channel,'_',' '))`, the four GLOBAL channel rows are stored
-- lowercase so initcap is what makes them read "Wholesale", and it turns `vip`
-- into "Vip" while Social Hour UK's products are stored "- VIP" (written
-- verbatim by migrate_social_hour_uk.py, never by the composer).
--
-- Normalising that is a DECISION -- it renames rows a customer has seen on an
-- invoice -- and it is the owner's, not mine. So this file must repair the
-- size-rename casualties WITHOUT recomposing the 38, and the containment is a
-- rule rather than a list of ids:
--
--     repair a row only when the channel text the composer would write is
--     ALREADY present in the stored name, so recomposing provably cannot
--     move the channel segment.
--
-- "Kona Extra Fancy - 100G - Retail" contains "Retail", so it repairs.
-- "Brazil - 1KG - VIP" does not contain "Vip", so it does not. Measured on
-- prod: the rule selects exactly those 5 and leaves exactly those 38.
--
-- 🔴 And the trigger this file adds INHERITS that casing bug: once it is live,
-- renaming the 1KG or 227g size recomposes the UK products on it and re-cases
-- their channel as a side effect. That door is already open -- renaming a
-- product group does the same thing today, through the self-assignment above
-- -- so this is one more door into a room that needs closing, not a new room.
-- It is an argument for taking the casing decision, not for leaving a size
-- rename broken.
--
-- ── SCOPE: ALL PRODUCTS, INCLUDING ARCHIVED ───────────────────────────────
--
-- Deliberately different from `cascade_size_weight` in 20261015000014, which
-- is scoped to active rows. That scope is forced: `update_product_total_cogs`
-- early-returns for a row that is inactive and was already inactive, ABOVE its
-- `NEW.weight_lbs := v_weight`, so an archived variant's cached numbers cannot
-- be refreshed and must not be -- they are frozen at the moment it was
-- archived and the UI reads them.
--
-- No such freeze exists for the NAME. `build_product_name` has no is_active
-- test, and `renameProductGroup` selects variants by group alone, archived
-- included. So a rename reaches everything, which is also what you want: an
-- archived variant still appears on the orders it was sold on. The archived
-- row in the repair above gets its name fixed and its numbers left alone, in
-- the same statement, because the two BEFORE triggers are independent and
-- `trg_build_product_name` sorts ahead of `trg_update_product_cogs`.
--
-- Functions patched from `pg_get_functiondef`; nothing here is retyped.

begin;

-- What the casing rows look like before this file runs, so the verify can
-- assert it left them alone rather than assert something about the database's
-- contents. Snapshotted, not counted, so it can name a row that moved.
create temporary table _names_before_20261015000019 on commit drop as
  select p.product_id, p.product_name, p.weight_lbs, p.total_unit_cogs
    from public.products p;

-- ── 1. A size's name reaches its products, and the cases built on it ───────
create or replace function public.cascade_size_name()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Three columns, because all three feed the size segment of the name:
  -- `size_name` is used verbatim for a bag, and for a case whose typed name
  -- already states the pack (`case_size_label_is_implied`); otherwise
  -- `case_size_label(base_name, units_per_case)` replaces it. So changing the
  -- pack count or re-pointing the base row rewrites the label too.
  if new.size_name      is not distinct from old.size_name
 and new.base_size_id   is not distinct from old.base_size_id
 and new.units_per_case is not distinct from old.units_per_case then
    return null;
  end if;

  -- Touched by SELF-ASSIGNING `size`, which is in `trg_build_product_name`'s
  -- column list, so the composer runs and is the ONE definition of the name.
  -- The same idiom `renameProductGroup` uses for `group_id`. Computing the
  -- name here instead is how two spellings of one rule come to disagree.
  --
  -- Both the products on this row AND the products on any case built on it:
  -- a case's label is made from the BASE row's size_name, so renaming a bag
  -- renames every case of it.
  update public.products p
     set size = p.size
   where p.size = new.size_id
      or p.size in (select c.size_id from public.size c where c.base_size_id = new.size_id);

  return null;
end;
$$;

comment on function public.cascade_size_name() is
  'A size rename reaches the stored product_name of every product on that size, and of every product on a case built on it. Self-assigns products.size so build_product_name recomposes; never composes the name itself.';

drop trigger if exists zzb_cascade_size_name on public.size;
-- AFTER: it writes other rows. Named to sort after zza_cascade_size_weight so
-- that when one statement changes both a weight and a name, the weight has
-- settled before any product row is touched.
create trigger zzb_cascade_size_name
  after update of size_name, base_size_id, units_per_case on public.size
  for each row execute function public.cascade_size_name();

-- ── 2. A channel's name reaches its products ───────────────────────────────
create or replace function public.cascade_channel_name()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.channel is not distinct from old.channel then
    return null;
  end if;

  update public.products p
     set channel = p.channel
   where p.channel = new.channel_id;

  return null;
end;
$$;

comment on function public.cascade_channel_name() is
  'A channel rename reaches the stored product_name of every product on it. Self-assigns products.channel so build_product_name recomposes.';

drop trigger if exists zzb_cascade_channel_name on public.channel;
create trigger zzb_cascade_channel_name
  after update of channel on public.channel
  for each row execute function public.cascade_channel_name();

-- ── 3. The five stale rows ─────────────────────────────────────────────────
--
-- The containment rule from the header, as a statement. `channel_text is null`
-- covers a product with no channel at all, whose name has no channel segment
-- to move.
update public.products p
   set size = p.size
  from public.channel ch
 where ch.channel_id = p.channel
   and p.group_id is not null
   and p.source_consumable_id is null
   and public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id) is not null
   and p.product_name is distinct from
       public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id)
   and strpos(p.product_name, initcap(replace(ch.channel, '_', ' '))) > 0;

update public.products p
   set size = p.size
 where p.channel is null
   and p.group_id is not null
   and p.source_consumable_id is null
   and public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id) is not null
   and p.product_name is distinct from
       public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id);

do $verify$
declare
  v_n        int;
  v_bad      text;
  v_size     text;
  v_chan     text;
  v_orig     text;
  v_pid      text;
  v_name     text;
  v_expected text;
begin
  -- 1. Both triggers exist, on the columns that feed the name.
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.size'::regclass and tgname = 'zzb_cascade_size_name') then
    raise exception 'zzb_cascade_size_name was not created';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.channel'::regclass and tgname = 'zzb_cascade_channel_name') then
    raise exception 'zzb_cascade_channel_name was not created';
  end if;
  for v_bad in
    select 'size:' || c
      from unnest(array['size_name', 'base_size_id', 'units_per_case']) c
     where pg_get_triggerdef((select oid from pg_trigger
             where tgrelid = 'public.size'::regclass and tgname = 'zzb_cascade_size_name')) not like '%' || c || '%'
  loop
    raise exception 'zzb_cascade_size_name does not watch %', v_bad;
  end loop;

  -- 2. Nothing remains stale that the containment rule admits. Phrased as the
  --    rule, not as "5 rows", so it keeps meaning on any database.
  select count(*) into v_n
    from public.products p
    left join public.channel ch on ch.channel_id = p.channel
   where p.group_id is not null and p.source_consumable_id is null
     and public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id) is not null
     and p.product_name is distinct from
         public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id)
     and (ch.channel is null
          or strpos(p.product_name, initcap(replace(ch.channel, '_', ' '))) > 0);
  if v_n > 0 then
    raise exception '% product(s) still disagree with their size and could safely be repaired', v_n;
  end if;

  -- 3. 🔴 And the casing rows were NOT touched. This is the assertion that
  --    keeps the repair honest: recomposing them is a decision nobody has
  --    taken, so a file that silently renamed 38 live products would have
  --    passed check 2 just as well.
  select string_agg(b.product_id || ': "' || b.product_name || '" became "' || p.product_name || '"', '; ')
    into v_bad
    from _names_before_20261015000019 b
    join public.products p using (product_id)
    left join public.channel ch on ch.channel_id = p.channel
   where b.product_name is distinct from p.product_name
     and (ch.channel is not null
          and strpos(b.product_name, initcap(replace(ch.channel, '_', ' '))) = 0);
  if v_bad is not null then
    raise exception 'this file recomposed a row whose channel casing would move: %', v_bad;
  end if;

  -- 4. And no cost number moved. Every row the repair touched already had
  --    weight_lbs = size.weight on prod, so the COGS recompute it triggers is
  --    a no-op; if that stops being true the repair is doing more than it says.
  select string_agg(b.product_id, ', ') into v_bad
    from _names_before_20261015000019 b
    join public.products p using (product_id)
   where b.weight_lbs      is distinct from p.weight_lbs
      or b.total_unit_cogs is distinct from p.total_unit_cogs;
  if v_bad is not null then
    raise exception 'the name repair moved cost numbers on: %', v_bad;
  end if;

  -- 5. 🔴 THE CASCADE WORKS, exercised on a real row and put back.
  --
  -- Picked deterministically, and ONLY where every product in the blast radius
  -- already agrees with the composer. Without that condition the probe would
  -- land on one of the 38: renaming its size recomposes the name, and
  -- restoring the size name recomposes it AGAIN -- to the composer's spelling,
  -- not the original -- so the round trip would permanently re-case a live
  -- product and check 3 would catch my own probe.
  select s.size_id into v_size
    from public.size s
   where exists (select 1 from public.products p
                  where (p.size = s.size_id
                      or p.size in (select c.size_id from public.size c where c.base_size_id = s.size_id)))
     and not exists (
       select 1 from public.products p
        where (p.size = s.size_id
            or p.size in (select c.size_id from public.size c where c.base_size_id = s.size_id))
          and p.group_id is not null and p.source_consumable_id is null
          and p.product_name is distinct from
              public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id))
     and s.size_name is not null
   order by s.size_id
   limit 1;

  if v_size is null then
    raise notice 'no size here whose products all agree with the composer, skipping the probe';
  else
    select size_name into v_orig from public.size where size_id = v_size;
    select p.product_id into v_pid
      from public.products p
     where (p.size = v_size
         or p.size in (select c.size_id from public.size c where c.base_size_id = v_size))
       and p.group_id is not null and p.source_consumable_id is null
     order by p.product_id limit 1;

    update public.size set size_name = v_orig || ' ZZPROBE' where size_id = v_size;

    select product_name into v_name from public.products where product_id = v_pid;
    select public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id)
      into v_expected from public.products p where p.product_id = v_pid;
    if v_name is distinct from v_expected then
      raise exception 'a size rename did not reach product %: name is "%", composer says "%"',
        v_pid, v_name, v_expected;
    end if;
    if strpos(v_name, 'ZZPROBE') = 0 then
      raise exception 'a size rename did not reach product %: "%" does not carry the new size name',
        v_pid, v_name;
    end if;

    update public.size set size_name = v_orig where size_id = v_size;
    if (select size_name from public.size where size_id = v_size) is distinct from v_orig then
      raise exception 'the probe did not put the size name back';
    end if;
    if (select product_name from public.products where product_id = v_pid)
       is distinct from (select b.product_name from _names_before_20261015000019 b
                          where b.product_id = v_pid) then
      raise exception 'the probe left product % renamed: "%" against "%"', v_pid,
        (select product_name from public.products where product_id = v_pid),
        (select b.product_name from _names_before_20261015000019 b where b.product_id = v_pid);
    end if;
  end if;

  -- 6. A TENANT channel, same shape. Global channel rows are skipped on
  --    purpose: `vip` is global and the 38 are on it, so probing it would
  --    re-case them. RLS cannot reach a global row from the browser anyway
  --    (`company_id IS NULL` is not IN auth_company_ids()), so the only caller
  --    who can rename one is a migration.
  select ch.channel_id into v_chan
    from public.channel ch
   where ch.company_id is not null
     and exists (select 1 from public.products p where p.channel = ch.channel_id)
     and not exists (select 1 from public.products p
                      where p.channel = ch.channel_id
                        and p.group_id is not null and p.source_consumable_id is null
                        and p.product_name is distinct from
                            public.compile_product_name(p.group_id, p.size, p.channel, p.source_consumable_id))
   order by ch.channel_id limit 1;

  if v_chan is null then
    raise notice 'no tenant channel here whose products all agree, skipping the channel probe';
  else
    select channel into v_orig from public.channel where channel_id = v_chan;
    select p.product_id into v_pid from public.products p
     where p.channel = v_chan and p.group_id is not null and p.source_consumable_id is null
     order by p.product_id limit 1;

    update public.channel set channel = v_orig || ' zzprobe' where channel_id = v_chan;
    select product_name into v_name from public.products where product_id = v_pid;
    if strpos(lower(v_name), 'zzprobe') = 0 then
      raise exception 'a channel rename did not reach product %: "%"', v_pid, v_name;
    end if;

    update public.channel set channel = v_orig where channel_id = v_chan;
    if (select product_name from public.products where product_id = v_pid)
       is distinct from (select b.product_name from _names_before_20261015000019 b
                          where b.product_id = v_pid) then
      raise exception 'the channel probe left product % renamed', v_pid;
    end if;
  end if;

  select count(*) into v_n
    from _names_before_20261015000019 b join public.products p using (product_id)
   where b.product_name is distinct from p.product_name;
  raise notice 'a size or channel rename now reaches its products; % name(s) repaired', v_n;
end;
$verify$;

commit;
