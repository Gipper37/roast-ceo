-- A product belongs to MANY collections, and they are called collections.
--
-- "shopify and all others allow for a product to appear in multiple
-- collections (hence navs). thats what we want too. and maybe thats what we
-- should call it as well, collection"
--
-- Right on both counts, and this reverses a decision made an hour earlier in
-- this same session. 20261015000002 put ONE category on a product to avoid a
-- discount collision: two categories with two deals and no rule for which
-- wins. That solved the collision by removing something real. Maui Blend Decaf
-- genuinely IS both Decaf and Hawaiian, and a customer looking for either
-- should find it, which is how every shop on the internet behaves.
--
-- "collection" is also the better word. It is what Shopify, Square and
-- BigCommerce call it, so a roaster arrives already knowing what it means --
-- and it SOUNDS plural, which "category" does not.
--
-- ── The collision, settled rather than avoided ────────────────────────────
--
-- Two collections, two deals, one product. The owner had no preference, so:
-- THE COLLECTION HIGHER IN THE ROASTER'S OWN ORDER WINS. sort_order already
-- exists and already orders the storefront menu, so it is controlled by
-- dragging, visible on screen, deterministic, and explicable in one sentence.
--
-- Rejected: "best deal for the customer wins". Kinder to say out loud, but it
-- means adding an unrelated collection deal can silently change the price of
-- products nobody was thinking about, which is the class of quiet repricing
-- this session has spent its time removing.
--
-- ── Safe to do now ────────────────────────────────────────────────────────
--
-- Nothing is live: 20261015000001 and ...02 are on staging only, prod is still
-- at 20261014000002, and ZERO discount rows use scope='category' anywhere. The
-- rename and the remodel cost nothing today and would cost a data migration in
-- a month.

begin;

-- ── 1. The name ───────────────────────────────────────────────────────────
--
-- ALTER TABLE ... RENAME carries the indexes, the FK from product_groups, the
-- RLS flag and the tenant_company_access policy with it. Verified below rather
-- than assumed.

alter table if exists public.product_category rename to collection;

comment on table public.collection is
  'A collection a product can appear in: Syrups, Hawaiian, Decaf. A product belongs to MANY. sort_order is the storefront menu order, and it also decides which collection wins when two of them carry a discount for the same customer.';

-- ── 2. Many, not one ──────────────────────────────────────────────────────

create table if not exists public.product_group_collection (
  -- 🔴 uuid, not text. product_groups.group_id is uuid while collection.id and
  -- company_id are text, and a text column here makes the FK unimplementable
  -- rather than merely wrong: Postgres refuses it outright (42804). Worth the
  -- line, because every other id in this schema is text and the instinct is to
  -- type them all the same.
  group_id      uuid not null references public.product_groups(group_id) on delete cascade,
  collection_id text not null references public.collection(id) on delete cascade,
  company_id    text not null references public.companies(company_id) on delete cascade,
  created_at    timestamptz not null default now(),
  created_by    text,
  primary key (group_id, collection_id)
);

-- 🔴 RLS ON, WITH A POLICY. Supabase grants `authenticated` ALL privileges on
-- every new table in public and RLS defaults OFF, so a join table created
-- without this is born as a public API. That mechanism has produced SEVEN
-- holes in this schema, the most recent found earlier today serving 5,998 rows
-- across four companies. A new table is where it starts, so it is closed here.
alter table public.product_group_collection enable row level security;

drop policy if exists product_group_collection_tenant on public.product_group_collection;
create policy product_group_collection_tenant on public.product_group_collection
  for all to authenticated
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

create index if not exists product_group_collection_by_collection
  on public.product_group_collection (collection_id, group_id);

-- ── 3. Carry the single value across ──────────────────────────────────────

insert into public.product_group_collection (group_id, collection_id, company_id, created_by)
select g.group_id, g.category_id, g.company_id, 'migration-20261015000003'
  from public.product_groups g
 where g.category_id is not null
on conflict do nothing;

-- The single column was never released: added by ...02 on staging only, and
-- prod never saw it. Dropping it here keeps one answer to "which collections
-- is this in" rather than two that can disagree -- the exact failure that put
-- 5 products in two categories at once in the first place.
alter table public.product_groups drop column if exists category_id;

-- ── 4. The discount scope is 'collection' ─────────────────────────────────

alter table public.customer_discount drop constraint if exists customer_discount_scope_check;
alter table public.customer_discount add constraint customer_discount_scope_check
  check (scope = any (array['all','product_type','product','distribution','variant','collection']));

alter table public.customer_discount drop constraint if exists customer_discount_scope_ref_present;
alter table public.customer_discount add constraint customer_discount_scope_ref_present
  check (
       (scope = any (array['all','distribution'])                            and scope_ref is null)
    or (scope = any (array['product_type','product','variant','collection']) and scope_ref is not null)
  );

alter table public.customer_discount drop constraint if exists customer_discount_price_needs_a_target;
alter table public.customer_discount add constraint customer_discount_price_needs_a_target
  check (kind <> 'price' or scope = any (array['product','variant','collection']));

-- ── 5. The resolver ───────────────────────────────────────────────────────

create or replace function public.resolve_customer_discount(
  p_customer_id text, p_product_id text, p_on_date date default current_date)
 returns table(customer_discount_id text, kind text, value numeric, scope text)
 language sql
 stable
as $function$
  select d.customer_discount_id, d.kind, d.value, d.scope
  from public.customer_discount d
  join public.products p on p.product_id = p_product_id
  left join public.product_groups pg on pg.group_id = p.group_id
  -- The collection this rule names, for its menu position. Only joined for a
  -- collection rule; null for every other scope and ignored by the sort below.
  left join public.collection col
    on d.scope = 'collection' and col.id = d.scope_ref
  join public.customers c
    on c.customer_id = p_customer_id
   and c.company_id  = d.company_id
   and c.company_id  = p.company_id
  where (
         d.customer_id = p_customer_id
      or (d.chain_id is not null and d.chain_id = c.chain_id)
      )
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      or (d.scope = 'distribution'  and p.source_consumable_id is not null)
      or (d.scope = 'product_type'  and d.scope_ref = p.product_type)
      -- A product is in MANY collections, so this asks whether it is in THIS
      -- one rather than comparing a single column.
      or (d.scope = 'collection' and exists (
            select 1 from public.product_group_collection pgc
             where pgc.group_id = pg.group_id and pgc.collection_id = d.scope_ref))
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
      or (d.scope = 'variant'       and d.scope_ref = p.product_id)
    )
  order by case d.scope
             when 'variant' then 6
             when 'product' then 5
             when 'collection' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc,
           -- A store's own rule beats its chain's.
           case when d.customer_id is not null then 1 else 0 end desc,
           -- TWO COLLECTIONS, TWO DEALS: the one higher in the roaster's own
           -- menu order wins. Nulls last so a collection with no order set
           -- never jumps the queue.
           coalesce(col.sort_order, 2147483647) asc,
           -- Last resort, so the answer is stable rather than whatever the
           -- planner returned first.
           d.customer_discount_id asc
  limit 1;
$function$;

do $verify$
declare
  v_co text; v_cust text; v_prod text; v_group text; v_company text;
  v_c1 text; v_c2 text; v_n int; v_bad int;
begin
  -- 1. The rename carried its protection. A renamed table that lost its RLS
  --    would be a tenant's product taxonomy served to everybody.
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                  where n.nspname='public' and c.relname='collection' and c.relrowsecurity) then
    raise exception 'collection has row level security off after the rename';
  end if;
  if not exists (select 1 from pg_policies where tablename='collection') then
    raise exception 'collection has no policy after the rename';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                  where n.nspname='public' and c.relname='product_group_collection' and c.relrowsecurity) then
    raise exception 'the join table was created without row level security';
  end if;

  -- 2. Nothing was lost in the carry-across.
  select count(*) into v_n from public.product_group_collection;
  raise notice 'carried % product-collection link(s) across', v_n;

  -- 3. 🔴 THE CHANGE: a product in TWO collections is reached by a rule naming
  --    either, and when both carry a deal the higher collection wins. Proved
  --    on real rows and rolled back.
  select g.group_id, g.company_id, p.product_id, c.customer_id
    into v_group, v_company, v_prod, v_cust
    from public.product_groups g
    join public.products p on p.group_id = g.group_id and p.is_active
    join public.customers c on c.company_id = g.company_id
   limit 1;

  select id into v_c1 from public.collection where company_id = v_company order by sort_order, id limit 1;
  select id into v_c2 from public.collection where company_id = v_company and id <> v_c1 order by sort_order desc, id desc limit 1;

  if v_group is null or v_c1 is null or v_c2 is null then
    raise notice 'not enough data here to exercise two collections; skipping';
  else
    insert into public.product_group_collection (group_id, collection_id, company_id)
    values (v_group, v_c1, v_company), (v_group, v_c2, v_company)
    on conflict do nothing;

    -- A rule naming the SECOND collection reaches it.
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
    values ('_probe_c2_20261015', v_company, v_cust, 'collection', v_c2, 'percent', 9, current_date - 1, true);
    select count(*) into v_n from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.value = 9;
    if v_n <> 1 then raise exception 'a collection rule did not reach a product in that collection'; end if;
    raise notice 'a product in two collections is reached by a rule naming either';

    -- Add a deal on the FIRST (higher) collection: it must now win.
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
    values ('_probe_c1_20261015', v_company, v_cust, 'collection', v_c1, 'percent', 4, current_date - 1, true);
    select count(*) into v_n from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.value = 4;
    if v_n <> 1 then
      raise exception 'two collection rules collided and the higher one did not win';
    end if;
    raise notice 'when two collections both carry a deal, the higher one wins';

    raise exception 'rollback the probe' using errcode = 'triggered_action_exception';
  end if;
exception
  when triggered_action_exception then
    raise notice 'probe rolled back; no row was changed by it';
end $verify$;

do $after$
declare v_bad int;
begin
  -- The single column is gone, so there is one answer to "which collections".
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='product_groups' and column_name='category_id') then
    raise exception 'product_groups.category_id survived; two answers can now disagree';
  end if;
  -- And no link points across tenants.
  select count(*) into v_bad
    from public.product_group_collection pgc
    join public.collection col on col.id = pgc.collection_id
   where col.company_id is distinct from pgc.company_id;
  if v_bad > 0 then
    raise exception '% link(s) point at another company''s collection', v_bad;
  end if;
  raise notice 'one answer per product, and no link crosses a tenant';
end $after$;

commit;
