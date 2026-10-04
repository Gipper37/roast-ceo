-- A product can be exclusive to a whole chain.
--
-- 20261003000008 restricted the Kraken Coffee private label to the customers it
-- was made for, and had to do it by listing four customer ids:
--
--     'mcrimp-cust-d08432ef51c510',   -- Kraken Coffee-Kahului
--     'mcrimp-cust-43e78e9da69842',   -- Kraken Coffee-Kihei
--     'mcrimp-cust-7f6bc70d5c5d39',   -- Kraken Coffee-Kihei Marketplace
--     'mcrimp-cust-0c2288a028b242'    -- Kraken Coffee - Wailea
--
-- That file said at the time why this column had to follow: "it is a list
-- somebody has to remember to extend when Kraken opens a fifth store -- and
-- Kraken Coffee-Lahaina already exists, inactive since the fire, and is
-- deliberately NOT on this list. A chain reference would say the thing once."
--
-- 🔴 THE FAILURE MODE IS SILENT IN THE DIRECTION THAT HURTS. An allowlist that
-- does not name a customer hides the product from them with no error and no
-- trace: the storefront simply does not render it, and the only person who can
-- notice is the buyer who expected to find their own coffee. Reopening Lahaina
-- or opening a sixth Kraken store means somebody has to know that this array
-- exists and go edit it. Naming the chain means the store inherits visibility
-- the moment it is attached to the chain, which is a thing an operator does on
-- the customer record for other reasons anyway.
--
-- MIRRORS exclusive_to_customer_ids EXACTLY, read off prod rather than assumed:
--   text[]              not a jsonb array, not a child table
--   nullable            NULL is the "visible to everybody" case, and it is the
--                       resting state of almost every row: on prod right now
--                       0 of MCR's 318 products carry a customer allowlist,
--                       and 4 will once 20261003000008 lands
--   no default          so NULL stays the resting state. A default of '{}'
--                       would be a different thing entirely: an EMPTY
--                       allowlist is an allowlist matching nobody, which hides
--                       the product from every customer. NULL and '{}' must not
--                       be confused and giving the column a default is how they
--                       get confused
--   gin index, partial  idx_product_groups_exclusive_customers is
--                       `using gin (...) where (... is not null)`, which is the
--                       right shape when almost every row is NULL
--
-- NOTHING READS IT YET. The storefront's eligibility rule lives in
-- app/(shop)/[slug]/eligibility.ts and today reads only the customer arrays, so
-- adding this column changes no shop behaviour until that file learns about it.
-- The column goes in first because the frontend cannot name a column that does
-- not exist, and because an unapplied column is the same silent-denial problem
-- as an unapplied permission key.
--
-- 🔴 ALLOWLIST STILL WINS, AND THE TWO ALLOWLISTS MUST UNION, NOT INTERSECT.
-- The existing rule is: if exclusive_to_customer_ids is set, only those
-- customers see the product, and excluded_from_customer_ids is ignored. When
-- BOTH exclusive arrays are set, a customer must pass EITHER one, or setting a
-- chain on a product that already names a customer would hide it from that
-- customer. Recorded here because it is the first thing the reader of
-- eligibility.ts will have to decide and the answer is not in the column.

begin;

-- Snapshot first, and compare against it at the end rather than against
-- `updated_at > now() - interval '1 minute'`. The clock test is the house habit
-- and it is wrong HERE: 20261003000008 updates four product_groups rows and
-- lands moments before this file in the same push, well inside a one-minute
-- window, so a clock test would read that migration's work as this one's and
-- fail a correct migration. A snapshot answers the question actually being
-- asked, which is "did THIS file move anything".
create temporary table _product_groups_before on commit drop as
  select group_id, updated_at, exclusive_to_customer_ids, excluded_from_customer_ids
    from public.product_groups;

alter table public.product_groups
  add column if not exists exclusive_to_chain_ids text[];

comment on column public.product_groups.exclusive_to_chain_ids is
  'If NULL, this product is not restricted by chain. If set, only customers belonging to one of the listed customer_chain rows can see it in the wholesale shop (e.g. a private label made for a chain, which every store of that chain inherits). Unions with exclusive_to_customer_ids rather than narrowing it: a customer passes if either array names them. An EMPTY array is not the same as NULL and would match nobody.';

create index if not exists idx_product_groups_exclusive_chains
  on public.product_groups using gin (exclusive_to_chain_ids)
  where exclusive_to_chain_ids is not null;

do $verify$
declare v_bad int; v_cust_type text; v_chain_type text;
begin
  -- The column exists and is the same TYPE as the one it mirrors. Compared
  -- against its sibling rather than against the literal 'ARRAY'/'_text', so a
  -- future change to one is caught instead of both quietly diverging.
  select data_type || '/' || udt_name || '/' || is_nullable || '/' || coalesce(column_default, 'no-default')
    into v_cust_type
    from information_schema.columns
   where table_schema = 'public' and table_name = 'product_groups'
     and column_name = 'exclusive_to_customer_ids';
  select data_type || '/' || udt_name || '/' || is_nullable || '/' || coalesce(column_default, 'no-default')
    into v_chain_type
    from information_schema.columns
   where table_schema = 'public' and table_name = 'product_groups'
     and column_name = 'exclusive_to_chain_ids';

  if v_chain_type is null then
    raise exception 'product_groups.exclusive_to_chain_ids was not added';
  end if;
  if v_cust_type is null then
    raise exception 'product_groups.exclusive_to_customer_ids is missing; there is nothing to mirror';
  end if;
  if v_chain_type is distinct from v_cust_type then
    raise exception 'exclusive_to_chain_ids is % but its sibling exclusive_to_customer_ids is %',
      v_chain_type, v_cust_type;
  end if;

  -- The partial gin index landed, matching the sibling's shape.
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'product_groups'
                    and indexname = 'idx_product_groups_exclusive_chains'
                    and indexdef ilike '%using gin%'
                    and indexdef ilike '%is not null%') then
    raise exception 'idx_product_groups_exclusive_chains is missing or is not a partial gin index';
  end if;

  -- 🔴 NOTHING WAS RESTRICTED. Adding the column must not hide a single product
  -- from a single customer. Every row has to be NULL, because an empty array
  -- here would be an allowlist matching nobody.
  select count(*) into v_bad from public.product_groups where exclusive_to_chain_ids is not null;
  if v_bad > 0 then
    raise exception '% product(s) already carry a chain allowlist; this migration must set none', v_bad;
  end if;

  -- And no product row moved, measured against the snapshot taken above. Row
  -- count both ways, so neither a lost product nor an invented one passes.
  if (select count(*) from _product_groups_before) <> (select count(*) from public.product_groups) then
    raise exception 'product_groups went from % row(s) to %; adding a column must change neither',
      (select count(*) from _product_groups_before), (select count(*) from public.product_groups);
  end if;

  select count(*) into v_bad
    from _product_groups_before b
    join public.product_groups g using (group_id)
   where g.updated_at                 is distinct from b.updated_at
      or g.exclusive_to_customer_ids  is distinct from b.exclusive_to_customer_ids
      or g.excluded_from_customer_ids is distinct from b.excluded_from_customer_ids;
  if v_bad > 0 then
    raise exception 'this touched % product row(s); it must touch none', v_bad;
  end if;
end;
$verify$;

commit;
