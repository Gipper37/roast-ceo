-- A collection can be reserved for named customers or chains.
--
-- Owner, 2026-10-15: *"for shop purposes the collection should be the
-- visibility gate like shopify"*. So "only Kraken sees this collection" becomes
-- one action instead of a per-product sweep that goes stale the next time
-- somebody adds a product to it.
--
-- Three columns mirroring the ones already on product_groups, so there is one
-- vocabulary and not two:
--   exclusive_to_customer_ids  — named customers, nobody else
--   exclusive_to_chain_ids     — every store of a named chain
--   excluded_from_customer_ids — everybody EXCEPT these, and ignored outright
--                                when either allowlist above is set
--
-- ── 🔴 THE RULE IS ALL-ALLOW, AND SHOPIFY IS THE REASON IT IS NOT ANY ──────
--
-- Shopify gates a B2B buyer on a CATALOG attached to their company location,
-- and its rule is "visible if published in AT LEAST ONE applicable catalog".
-- That is safe there because Shopify's default is HIDDEN: "any" can only ever
-- widen from nothing.
--
-- Here the default is VISIBLE and a restriction is an exception, so the same
-- rule inverts into a hole: a private label filed into any public collection
-- would silently un-reserve itself, from a screen showing no sign of the other
-- collection. A product is therefore allowed only if EVERY restricted
-- collection it belongs to admits the buyer. A collection with no restriction
-- is silent, not a vote.
--
-- Within one collection the two allowlists UNION, exactly as they do on a
-- product: "this chain, plus these other accounts".
--
-- ── What this migration deliberately does NOT do ──────────────────────────
--
-- It does not touch product_groups. The per-product arrays keep working
-- unchanged and the collection axis ANDs with them. A product pinned to Cafe A
-- inside a collection pinned to Cafe B resolves to nobody, which is the right
-- answer for a contradiction and is the operator's to see and fix.
--
-- No FK or CHECK is possible on a text[] of ids, which is already true of the
-- product-level columns. The ids are validated where they are written.
--
-- `collection` is an EXISTING table, so the Supabase default-ACL trap (a new
-- table in public born granted to `authenticated` with RLS off, which is how
-- shop_config sat world-readable for five months) does not apply here. That is
-- a deliberate reason to put the columns on this table rather than inventing a
-- collection_exclusivity one.

begin;

-- A snapshot, so the verify block can assert this file moved no DATA rather
-- than asserting anything about what the database happens to contain. An
-- updated_at comparison would be read as this file's work when another
-- migration lands in the same push seconds earlier.
create temporary table _collection_before_20261015000006 on commit drop as
  select id, name, sort_order, is_active from public.collection;

alter table public.collection
  add column if not exists exclusive_to_customer_ids  text[],
  add column if not exists exclusive_to_chain_ids     text[],
  add column if not exists excluded_from_customer_ids text[];

comment on column public.collection.exclusive_to_customer_ids is
  'If NULL, this collection is not restricted to named customers. If set, only those customers may see its products in the wholesale shop. Unions with exclusive_to_chain_ids. An EMPTY array is not a restriction: the operator UI writes [] as readily as NULL when the last entry is removed, and treating [] as "nobody" would retire a collection the moment a roaster cleared the field.';
comment on column public.collection.exclusive_to_chain_ids is
  'If NULL, this collection is not restricted by chain. If set, every store of a listed customer_chain may see its products. Unions with exclusive_to_customer_ids rather than narrowing it.';
-- 🔴 This comment stated the OLD rule, which `bdb43d9c` deleted in the same
-- batch -- so the database's own catalogue documented the hole as the design.
-- It said the exclude list was "ignored outright when either allowlist above is
-- set". It is not, any more: `groupAllowed` treats passing an allowlist as
-- earning the right to be asked the next question, so "the chain, except that
-- one store" is now sayable, and a contradiction resolves to nobody.
comment on column public.collection.excluded_from_customer_ids is
  'Customers who may NOT see this collection''s products. Always consulted, including when an allowlist above is set: passing an allowlist earns the right to be asked this question rather than ending it, so "this chain except that store" is sayable. A customer named here and also named in an allowlist resolves to NOT allowed. An EMPTY array is not a restriction, same as the columns above.';

comment on table public.collection is
  'A collection a product can appear in: Syrups, Hawaiian, Decaf. A product belongs to MANY. sort_order is the storefront menu order, and it also decides which collection wins when two of them carry a discount for the same customer. The exclusive_/excluded_ columns gate VISIBILITY in the wholesale shop, ALL-allow: a product is visible only if every restricted collection it is in admits the buyer.';

create index if not exists idx_collection_exclusive_customers
  on public.collection using gin (exclusive_to_customer_ids)
  where exclusive_to_customer_ids is not null;
create index if not exists idx_collection_exclusive_chains
  on public.collection using gin (exclusive_to_chain_ids)
  where exclusive_to_chain_ids is not null;
create index if not exists idx_collection_excluded_customers
  on public.collection using gin (excluded_from_customer_ids)
  where excluded_from_customer_ids is not null;

do $verify$
declare
  v_bad int;
  v_group_type text;
  v_coll_type  text;
  v_col text;
begin
  -- 1. All three columns exist, and each is the SAME shape as the product-level
  --    column it mirrors. Compared against the sibling rather than a literal,
  --    so a future change to one is caught instead of the two quietly
  --    diverging. Skipped where the product-level column is absent, which is
  --    a database that predates it rather than a failure of this file.
  foreach v_col in array array['exclusive_to_customer_ids', 'exclusive_to_chain_ids', 'excluded_from_customer_ids'] loop
    select data_type || '/' || udt_name || '/' || is_nullable || '/' || coalesce(column_default, 'no-default')
      into v_coll_type
      from information_schema.columns
     where table_schema = 'public' and table_name = 'collection' and column_name = v_col;
    if v_coll_type is null then
      raise exception 'collection.% was not created', v_col;
    end if;

    select data_type || '/' || udt_name || '/' || is_nullable || '/' || coalesce(column_default, 'no-default')
      into v_group_type
      from information_schema.columns
     where table_schema = 'public' and table_name = 'product_groups' and column_name = v_col;
    if v_group_type is null then
      raise notice 'product_groups.% is not here to compare against; shape unchecked', v_col;
    elsif v_group_type is distinct from v_coll_type then
      raise exception 'collection.% is % but product_groups.% is %; the two must match',
        v_col, v_coll_type, v_col, v_group_type;
    end if;
  end loop;

  -- 2. Every collection starts UNRESTRICTED. A column added with a default of
  --    '{}' would mean "nobody may see this" the moment the predicate reads an
  --    empty array as a restriction somewhere, and would hide every product in
  --    every collection on every shop. NULL is the only safe birth state.
  select count(*) into v_bad from public.collection
   where exclusive_to_customer_ids is not null
      or exclusive_to_chain_ids is not null
      or excluded_from_customer_ids is not null;
  if v_bad > 0 then
    raise exception '% collection(s) were born with a restriction; this migration must restrict nothing', v_bad;
  end if;

  -- 3. And it moved no data.
  select count(*) into v_bad
    from (
      select id, name, sort_order, is_active from public.collection
      except
      select id, name, sort_order, is_active from _collection_before_20261015000006
    ) q;
  if v_bad > 0 then
    raise exception '% collection row(s) changed; adding a column must change no data', v_bad;
  end if;

  raise notice 'collection can now be reserved; % collection(s), all unrestricted',
    (select count(*) from public.collection);
end $verify$;

-- ── "Is this collection reserved?" lives in 20261015000017 ────────────────
--
-- 🔴 IT WAS HERE, AND MOVING IT IS NOT A TIDY-UP. On 2026-10-16 CI's
-- db-push-staging failed with
--     ERROR: function public.collection_is_reserved(text) does not exist
-- while applying 20261015000017, because THIS FILE WAS ALREADY APPLIED to
-- staging by an earlier push, and `supabase db push` records a version and
-- never re-applies an edited file. The function was added to this file after
-- that push, so on staging it simply never existed -- and 017 names it inside
-- a POLICY predicate, which Postgres resolves at CREATE POLICY time, so it
-- failed hard rather than lazily.
--
-- 20261015000009 also names it, but inside a FUNCTION BODY, which Postgres
-- resolves at CALL time -- so 009 applied cleanly and left
-- merge_product_groups quietly broken on staging instead. That is the more
-- dangerous half of the same mistake.
--
-- So the definition now lives in the earliest migration that was NOT yet
-- applied anywhere and that needs it at apply time: 20261015000017. Still ONE
-- definition, which was the point of putting it in a shared place to begin
-- with. Do not copy it back here.
--
-- 🔴 THE RULE THIS BROKE: once a migration has been applied ANYWHERE, editing
-- it changes nothing on that database. New behaviour needs a new file.

commit;
