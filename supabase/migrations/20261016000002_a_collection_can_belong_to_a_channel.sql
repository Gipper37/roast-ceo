-- A collection can belong to a sales channel, like Shopify. Optionally.
--
-- Owner, 2026-10-16: *"it doesn't show up in the wholesale shop unless its
-- under the wholesale channel. get it 'channel' same same. sales channel is
-- equivalent to our channel. a colleciton can be set for a specific channel or
-- not. its optional in shopify because the products also have specific
-- channels."*
--
-- So `public.channel` (retail / sample / vip / wholesale) IS our sales channel,
-- and a collection gets the same publishing relationship Shopify gives one:
--
--   channel_id IS NULL  -> not scoped. The collection appears wherever its
--                          PRODUCTS appear, which is the existing behaviour and
--                          stays the default. This is why Shopify makes it
--                          optional: a product already carries its own channel,
--                          so most collections never need to say anything.
--   channel_id SET      -> scoped. The collection only appears in that
--                          channel's storefront, whatever its products say.
--
-- Nullable on purpose, and NOT defaulted. A default would silently publish
-- every existing collection into one channel and hide it from the others --
-- 12 collections on prod, all currently visible to every buyer who can see
-- their products.
--
-- 🔴 THE FK POINTS AT A TABLE WITH GLOBAL ROWS. `channel` holds four GLOBAL
-- rows (company_id IS NULL: retail, sample, vip, wholesale) plus per-tenant
-- ones, so a collection may legitimately reference a channel its own company
-- does not own. That is the normal case -- "wholesale" is global -- so this is
-- a plain FK with no company equality check. The read side is what enforces
-- tenancy, and `collection` already carries company_id for that.
--
-- No ON DELETE CASCADE: deleting a channel must not delete collections. ON
-- DELETE SET NULL is the honest answer -- the collection reverts to
-- unscoped, which is the safe direction (visible rather than hidden).

begin;

create temporary table _collection_before_20261016000002 on commit drop as
  select id, company_id, name, sort_order, is_active from public.collection;

alter table public.collection
  add column if not exists channel_id text
    references public.channel(channel_id) on delete set null;

comment on column public.collection.channel_id is
  'The sales channel this collection is published to, Shopify-style. NULL means it is not scoped and appears wherever its products appear, which is the default and what every existing collection does. When set, the collection only appears in that channel''s storefront. Optional because products carry their own channel.';

create index if not exists idx_collection_channel
  on public.collection (channel_id)
  where channel_id is not null;

do $verify$
declare
  v_bad int;
  v_type text;
begin
  -- 1. The column exists and is the SAME shape as the column it references,
  --    compared against that column rather than a literal so a future change
  --    to channel.channel_id is caught instead of the two quietly diverging.
  select data_type || '/' || udt_name into v_type
    from information_schema.columns
   where table_schema = 'public' and table_name = 'collection' and column_name = 'channel_id';
  if v_type is null then
    raise exception 'collection.channel_id was not created';
  end if;
  if v_type is distinct from (
       select data_type || '/' || udt_name from information_schema.columns
        where table_schema = 'public' and table_name = 'channel' and column_name = 'channel_id') then
    raise exception 'collection.channel_id is % but channel.channel_id is %', v_type,
      (select data_type || '/' || udt_name from information_schema.columns
        where table_schema = 'public' and table_name = 'channel' and column_name = 'channel_id');
  end if;

  -- 2. EVERY EXISTING COLLECTION IS UNSCOPED. A default would have published
  --    each one into a single channel and hidden it from every other buyer.
  select count(*) into v_bad from public.collection where channel_id is not null;
  if v_bad > 0 then
    raise exception '% collection(s) were born scoped to a channel; this migration must scope none', v_bad;
  end if;

  -- 3. And it moved no data.
  select count(*) into v_bad from (
    select id, company_id, name, sort_order, is_active from public.collection
    except
    select id, company_id, name, sort_order, is_active from _collection_before_20261016000002
  ) q;
  if v_bad > 0 then
    raise exception '% collection row(s) changed; adding a column must change no data', v_bad;
  end if;

  -- 4. The FK really is SET NULL, because CASCADE here would delete a
  --    roaster's collections when they tidied up a channel.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collection'::regclass
       and c.contype = 'f'
       and c.confdeltype = 'n'
       and 'channel_id' = any (
         select a.attname from pg_attribute a
          where a.attrelid = c.conrelid and a.attnum = any (c.conkey))) then
    raise exception 'collection.channel_id has no ON DELETE SET NULL foreign key';
  end if;

  raise notice 'a collection can now belong to a channel; % collection(s), all unscoped',
    (select count(*) from public.collection);
end $verify$;

commit;
