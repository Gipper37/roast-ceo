-- The shop menu is a tree the roaster builds, not a list derived from data.
--
-- Owner, 2026-10-16: *"no do full menu build and don't fucking fuck it up"*,
-- after reasoning his own way to Shopify's model:
--   *"it doesnt seem like theres a way to choose what the collection belongs to
--    and a problem could be cause if a user chooses a consumable and coffee in
--    the same collection. which i guess maybe need to be allowed because
--    sometimes it would make sense. hmmm so maybe we just need to allow them to
--    group the collections in menu navs whether by type or their own names."*
--
-- 🔴 AND THAT IS WHY THERE IS NO `type` ON A COLLECTION. A collection holding
-- both coffee and a consumable is legitimate ("Holiday Gifts"), so deriving the
-- menu from a type would be a restriction whose only benefit is making an edge
-- case disappear. Shopify keeps Collections and NAVIGATION separate: menus of
-- menu items, nestable, each pointing at a collection. The tree is the
-- roaster's and has nothing to do with what is inside a collection -- which
-- gives both of his options through one mechanism. An item called "Coffee" with
-- coffee collections nested under it IS grouping by type; an item called
-- anything else is grouping by his own names.
--
-- ── SHAPE ─────────────────────────────────────────────────────────────────
--
-- One row per menu item. `collection_id` NULL means the item is a pure heading
-- (Shopify's "menu item with no link, just children"); set means it opens that
-- collection. `parent_id` NULL means top level.
--
-- DEPTH IS CAPPED AT TWO by the guard below: a top-level item and its children,
-- no deeper. That is what "subnavs under the type" needs and it is what
-- Shopify's own editor offers. Without a cap, a tree can also be made
-- CYCLIC by re-parenting, and a cyclic menu is an infinite render.
--
-- ── 🔴 A NEW TABLE IN `public`, SO THE DEFAULT-ACL TRAP APPLIES ───────────
--
-- A table created here is born granted to `authenticated` with RLS OFF. That
-- is exactly how `shop_config` sat world-readable for five months. RLS is
-- enabled explicitly below, the policies are written explicitly, and the verify
-- block ASSERTS both rather than trusting that they happened.

begin;

create table if not exists public.shop_menu_item (
  id           text primary key,
  company_id   text not null references public.companies(company_id) on delete cascade,
  -- Self-FK. CASCADE: deleting a heading takes its children with it, which is
  -- what Shopify does and what the UI has to name before it fires.
  parent_id    text references public.shop_menu_item(id) on delete cascade,
  label        text not null,
  -- SET NULL, not CASCADE: deleting a collection must not delete the menu item
  -- that pointed at it. The item becomes a heading -- visible but inert --
  -- which is the safe direction for a nav.
  collection_id text references public.collection(id) on delete set null,
  sort_order   integer not null default 0,
  is_visible   boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   text,
  updated_at   timestamptz not null default now(),
  updated_by   text
);

comment on table public.shop_menu_item is
  'The storefront navigation menu, as a tree the roaster arranges. One row per menu item: parent_id NULL is top level, collection_id NULL is a heading with no link. Deliberately separate from `collection`, Shopify-style, so a collection can hold more than one kind of product without the menu forcing it into one.';
comment on column public.shop_menu_item.collection_id is
  'The collection this item opens, or NULL for a heading that only groups its children. ON DELETE SET NULL so removing a collection leaves an inert heading rather than silently deleting part of the menu.';
comment on column public.shop_menu_item.parent_id is
  'The item this one sits under, or NULL for top level. Depth is capped at two by guard_shop_menu_item_depth: a child may not itself have children.';

create index if not exists idx_shop_menu_item_company on public.shop_menu_item (company_id, parent_id, sort_order);
create index if not exists idx_shop_menu_item_collection on public.shop_menu_item (collection_id) where collection_id is not null;

-- ── Depth, and no cycles ──────────────────────────────────────────────────
create or replace function public.guard_shop_menu_item_depth()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  v_parent_parent text;
  v_has_children  boolean;
begin
  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'A menu item cannot sit under itself.' using errcode = 'check_violation';
  end if;

  -- The parent must be top level: two levels, no deeper. This also makes a
  -- cycle impossible, because every non-top-level row has a top-level parent.
  select parent_id into v_parent_parent
    from public.shop_menu_item where id = new.parent_id;
  if v_parent_parent is not null then
    raise exception 'The shop menu goes two levels deep. Put this under a top-level item instead.'
      using errcode = 'check_violation';
  end if;

  -- And this row must not already be a parent itself, or moving it under
  -- another item would create a third level.
  select exists (select 1 from public.shop_menu_item where parent_id = new.id) into v_has_children;
  if v_has_children then
    raise exception 'That item has items under it, so it cannot also sit under another one. Move its children out first.'
      using errcode = 'check_violation';
  end if;

  -- Same tenant on both ends, which no FK here can express.
  if not exists (
    select 1 from public.shop_menu_item p
     where p.id = new.parent_id and p.company_id = new.company_id) then
    raise exception 'A menu item can only sit under one of your own.' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists aaa_guard_shop_menu_item_depth on public.shop_menu_item;
create trigger aaa_guard_shop_menu_item_depth
  before insert or update of parent_id, company_id on public.shop_menu_item
  for each row execute function public.guard_shop_menu_item_depth();

drop trigger if exists trg_audit_insert on public.shop_menu_item;
create trigger trg_audit_insert before insert on public.shop_menu_item
  for each row execute function public.handle_new_record();
drop trigger if exists trg_audit_update on public.shop_menu_item;
create trigger trg_audit_update before update on public.shop_menu_item
  for each row execute function public.handle_updated_record();

-- ── RLS, explicitly, because a new table does not get it for free ─────────
alter table public.shop_menu_item enable row level security;

-- ── 🔴 AND THE GRANTS, EXPLICITLY IN BOTH DIRECTIONS ──────────────────────
--
-- CAUGHT BY THE STAGING REHEARSAL, 2026-10-16: verify step 3 below failed with
-- `anon can select shop_menu_item`. It was right. A new table in `public` is
-- born carrying the `supabase_admin` default ACL, and on staging that ACL
-- grants anon. RLS was already on, so anon would have read zero rows today --
-- but the grant is the hole, and `shop_config` sat world-readable for five
-- months on exactly this footing.
--
-- It would have PASSED on prod, whose default ACL is clean. That is the trap
-- worth naming: the migration was relying on an environment's default rather
-- than stating what it wants, so the same file meant two different things on
-- two databases. Stated here instead, so it means one thing everywhere.
--
-- Both directions, because each fails silently on its own: anon keeping a
-- grant is a leak, and `authenticated` losing one breaks every read while the
-- policies look perfectly correct. `revoke ... from public` does NOT revoke
-- from `authenticated`, so anon is named outright. service_role is left alone
-- deliberately -- the webhook/admin client needs it.
revoke all on public.shop_menu_item from anon, public;
grant select, insert, update, delete on public.shop_menu_item to authenticated;

drop policy if exists shop_menu_item_read   on public.shop_menu_item;
drop policy if exists shop_menu_item_insert on public.shop_menu_item;
drop policy if exists shop_menu_item_update on public.shop_menu_item;
drop policy if exists shop_menu_item_delete on public.shop_menu_item;

-- Reading the menu is reading the shop: anyone in the tenant.
create policy shop_menu_item_read on public.shop_menu_item
  for select to authenticated
  using (company_id in (select auth_company_ids()));

-- Arranging it is shop.configure, the same key that guards the collection
-- order and a collection's name. No new permission key: this is the same
-- decision, and an unknown key is denied silently.
create policy shop_menu_item_insert on public.shop_menu_item
  for insert to authenticated
  with check (company_id in (select auth_company_ids())
              and public.auth_has_permission('shop.configure', company_id));
create policy shop_menu_item_update on public.shop_menu_item
  for update to authenticated
  using (company_id in (select auth_company_ids())
         and public.auth_has_permission('shop.configure', company_id))
  with check (company_id in (select auth_company_ids())
              and public.auth_has_permission('shop.configure', company_id));
create policy shop_menu_item_delete on public.shop_menu_item
  for delete to authenticated
  using (company_id in (select auth_company_ids())
         and public.auth_has_permission('shop.configure', company_id));

do $verify$
declare
  v_n int;
  v_top text; v_kid text; v_co text;
  v_verb text;
begin
  -- 1. 🔴 RLS IS ON. A new table in public is born with it OFF and granted to
  --    authenticated, which is how shop_config sat world-readable for five
  --    months. Asserted, not assumed.
  if not (select c.relrowsecurity from pg_class c
           where c.oid = 'public.shop_menu_item'::regclass) then
    raise exception 'shop_menu_item has row level security OFF';
  end if;

  -- 2. And it has a policy for every verb, with the write ones gated on a key.
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'shop_menu_item';
  if v_n <> 4 then
    raise exception 'shop_menu_item has % policies, expected 4', v_n;
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'shop_menu_item'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')
     and coalesce(qual, '') || coalesce(with_check, '') like '%auth_has_permission%';
  if v_n <> 3 then
    raise exception 'only % of 3 write policies gate on a permission key', v_n;
  end if;

  -- 3. anon can reach nothing, and `authenticated` can reach everything the
  --    policies then filter. Checked per verb rather than on SELECT alone: the
  --    default ACL this file now revokes granted ALL, so testing one verb
  --    would have left three behind. Asserted on the GRANT rather than by
  --    selecting as anon, because a blocked select and an empty table look
  --    identical from the outside.
  foreach v_verb in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
    if has_table_privilege('anon', 'public.shop_menu_item', v_verb) then
      raise exception 'anon still holds % on shop_menu_item', v_verb;
    end if;
    if not has_table_privilege('authenticated', 'public.shop_menu_item', v_verb) then
      raise exception 'authenticated cannot % shop_menu_item; its policies would never fire', v_verb;
    end if;
  end loop;

  -- 4. 🔴 THE DEPTH GUARD WORKS, exercised on real rows and rolled back.
  select company_id into v_co from public.companies limit 1;
  if v_co is null then
    raise notice 'no company here, skipping the depth probe';
  else
    BEGIN
      insert into public.shop_menu_item (id, company_id, label) values ('zzprobe-top', v_co, 'Top');
      insert into public.shop_menu_item (id, company_id, parent_id, label)
        values ('zzprobe-kid', v_co, 'zzprobe-top', 'Kid');
      -- a third level must be refused
      begin
        insert into public.shop_menu_item (id, company_id, parent_id, label)
          values ('zzprobe-grandkid', v_co, 'zzprobe-kid', 'Grandkid');
        raise exception 'the depth guard allowed a third level';
      exception when check_violation then null;
      end;
      -- and an item cannot sit under itself
      begin
        update public.shop_menu_item set parent_id = 'zzprobe-top' where id = 'zzprobe-top';
        raise exception 'the depth guard allowed an item under itself';
      exception when check_violation then null;
      end;
      -- and a parent cannot be demoted under someone else
      begin
        update public.shop_menu_item set parent_id = 'zzprobe-kid' where id = 'zzprobe-top';
        raise exception 'the depth guard allowed a parent to be nested';
      exception when check_violation then null;
      end;
      raise exception 'ZZPROBE_OK';
    EXCEPTION
      WHEN others THEN
        if sqlerrm <> 'ZZPROBE_OK' then raise; end if;
    END;
    -- the probe rolled itself back to its implicit savepoint
    if exists (select 1 from public.shop_menu_item where id like 'zzprobe-%') then
      raise exception 'the depth probe left rows behind';
    end if;
  end if;

  raise notice 'the shop menu is the roaster''s own: % item(s) so far',
    (select count(*) from public.shop_menu_item);
end $verify$;

commit;
