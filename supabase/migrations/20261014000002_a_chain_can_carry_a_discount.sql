-- A discount can belong to a CHAIN, not only to one store.
--
-- "i thought we added a place where we can manage chain discounts. if we
-- didn't we need to." We hadn't: customer_chain carried chain_name, notes and
-- is_active and nothing else, and customer_discount could only name a single
-- customer_id. A roaster who agrees 10% with Minit Stop had to add the same
-- rule to all EIGHTEEN stores by hand, and keep them in step forever after.
--
-- ── Why this is a column on customer_discount, not a new table ────────────
--
-- The rule a chain carries is the same object a store carries: a scope, a kind,
-- a value and an effective window. A second table would mean a second resolver,
-- a second unique constraint, a second policy and a second UI, all of which
-- would have to stay in step with these by hand -- and the first time they
-- drifted, two surfaces would price the same order differently.
--
-- So customer_discount gains `chain_id`, `customer_id` becomes nullable, and a
-- CHECK says a rule names EXACTLY ONE of them. One table, one resolver, one
-- answer.
--
-- ── Who wins ──────────────────────────────────────────────────────────────
--
-- The resolver already picks the most specific SCOPE: variant > product >
-- distribution > product_type > all. A chain rule and a store rule can tie on
-- scope, so a second ordering key breaks the tie in favour of the STORE.
--
-- That is the right way round. A chain-wide 10% is the floor the business
-- negotiated; a rule written against one store is somebody deliberately saying
-- "this one is different", and the specific statement must beat the general
-- one. It also means a store can be given a BETTER or a WORSE deal than its
-- chain without the chain rule having to be deleted.
--
-- ── What this does NOT change ─────────────────────────────────────────────
--
-- resolve_customer_discounts_for_products delegates to resolve_customer_discount
-- and is left untouched, so the shop checkout, the order form preview and order
-- creation all pick chain rules up for free. No frontend call site changes to
-- make a chain discount apply; the only new frontend is the place to TYPE one.
--
-- Permissions are deliberately unchanged: the table's policies already require
-- `customer.edit` on the row's own company, and a chain rule is a pricing
-- decision of exactly the same weight as a store rule. No new permission key,
-- so nothing can ship dark for want of a role or plan row.

begin;

-- ── 1. The column, and the "exactly one owner" rule ───────────────────────

alter table public.customer_discount
  add column if not exists chain_id text
    references public.customer_chain(chain_id) on delete cascade;

alter table public.customer_discount
  alter column customer_id drop not null;

alter table public.customer_discount
  drop constraint if exists customer_discount_one_owner;
alter table public.customer_discount
  add constraint customer_discount_one_owner
  check (num_nonnulls(customer_id, chain_id) = 1);

comment on column public.customer_discount.chain_id is
  'Set instead of customer_id when the rule belongs to a whole chain. Exactly one of the two is non-null (customer_discount_one_owner). A store''s own rule outranks its chain''s at the same scope.';

-- ── 2. Uniqueness, which the old index could not carry alone ──────────────
--
-- customer_discount_unique_scope is (customer_id, scope, coalesce(scope_ref))
-- WHERE is_active. With customer_id now nullable, two identical CHAIN rules
-- would both have customer_id NULL, and NULLs are distinct in a btree, so the
-- index would not see them as duplicates. It is narrowed to customer rules and
-- a sibling added for chain rules.

drop index if exists public.customer_discount_unique_scope;
create unique index customer_discount_unique_scope
  on public.customer_discount (customer_id, scope, coalesce(scope_ref, '__all__'))
  where is_active and customer_id is not null;

create unique index if not exists customer_discount_unique_chain_scope
  on public.customer_discount (chain_id, scope, coalesce(scope_ref, '__all__'))
  where is_active and chain_id is not null;

create index if not exists customer_discount_chain_lookup
  on public.customer_discount (chain_id, is_active, effective_from, effective_to)
  where chain_id is not null;

-- ── 3. The tenant guard has to cope with a rule that names no customer ────
--
-- Edited from pg_get_functiondef rather than retyped: the customer branch below
-- is the original body, unchanged, and the chain branch is added beside it.

create or replace function public.guard_customer_discount_same_tenant()
 returns trigger
 language plpgsql
as $function$
declare
  v_customer_company text;
  v_chain_company    text;
begin
  if NEW.customer_id is not null then
    select company_id into v_customer_company
    from public.customers where customer_id = NEW.customer_id;

    if v_customer_company is null then
      raise exception 'That customer does not exist.';
    end if;
    if v_customer_company is distinct from NEW.company_id then
      -- Deliberately does not name the other tenant.
      raise exception 'That customer belongs to a different company.';
    end if;
  end if;

  if NEW.chain_id is not null then
    select company_id into v_chain_company
    from public.customer_chain where chain_id = NEW.chain_id;

    if v_chain_company is null then
      raise exception 'That chain does not exist.';
    end if;
    if v_chain_company is distinct from NEW.company_id then
      raise exception 'That chain belongs to a different company.';
    end if;
  end if;

  return NEW;
end;
$function$;

-- ── 4. The resolver. The ONE place any surface asks "what do they pay?" ───
--
-- Edited from the deployed definition. Three changes, and nothing else moved:
--   a) the customers join now keys off the customer being PRICED rather than
--      off the rule's own customer_id, because a chain rule has none. For a
--      customer rule the two are the same row, so the tenant predicate it was
--      added to carry is unchanged;
--   b) the where clause admits a rule owned by this customer's chain;
--   c) a tie on scope is broken in favour of the store's own rule.

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
  -- THE TENANT PREDICATE. Without this the resolver matched on customer_id
  -- alone, so a rule belonging to company A could price company B's order the
  -- moment it named one of B's customers -- and customer_discount's INSERT
  -- policy only checks that the RULE is yours, not the customer it names.
  --
  -- Now keyed on the customer being priced, because a chain rule names no
  -- customer. Identical for a customer rule, where d.customer_id = p_customer_id.
  join public.customers c
    on c.customer_id = p_customer_id
   and c.company_id  = d.company_id
   and c.company_id  = p.company_id
  where (
         d.customer_id = p_customer_id
         -- A rule the whole chain carries. c.chain_id is null for a store that
         -- belongs to no chain, and null = null is not true, so an unchained
         -- store can never match one.
      or (d.chain_id is not null and d.chain_id = c.chain_id)
      )
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      -- Resold goods: the same derived test the Products page filter uses.
      -- Deliberately not the Consumable product type, which would also catch
      -- the internal supplies that are never resold.
      or (d.scope = 'distribution'  and p.source_consumable_id is not null)
      or (d.scope = 'product_type'  and d.scope_ref = p.product_type)
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
      -- A VARIANT is the thing a customer actually buys, and the only level
      -- at which a price exists: one group can hold 8 variants from $6.83 to
      -- $245, so "they pay $9" is not a statement the group can carry.
      or (d.scope = 'variant'       and d.scope_ref = p.product_id)
    )
  -- Most specific wins. Distribution sits above a plain type because "resold
  -- goods" is the narrower statement about the same item.
  order by case d.scope
             when 'variant' then 5
             when 'product' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc,
           -- Tie on scope: the store's own rule beats the chain's. A chain-wide
           -- deal is the floor; a rule written against one store is somebody
           -- saying "this one is different", and it has to be able to win.
           case when d.customer_id is not null then 1 else 0 end desc
  limit 1;
$function$;

do $verify$
declare v_bad int; v_chain text; v_cust text; v_prod text; v_company text; v_n int;
begin
  -- 1. The column exists and is nullable in the right places.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='customer_discount'
                    and column_name='chain_id') then
    raise exception 'customer_discount.chain_id was not created';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='customer_discount'
                and column_name='customer_id' and is_nullable='NO') then
    raise exception 'customer_id is still NOT NULL, so no chain rule can be written';
  end if;

  -- 2. The "exactly one owner" CHECK actually refuses both of the wrong shapes.
  --    Asserted by TRYING them in a sub-block, because a CHECK that is present
  --    but wrong reads identically to one that works.
  --
  --    🔴 THE IDS MUST COME FROM THE SAME COMPANY. The first draft took
  --    `(select customer_id from customers limit 1)` and
  --    `(select chain_id from customer_chain limit 1)` independently, which on
  --    staging picked a customer from one tenant and a chain from another. The
  --    tenant guard added above then fired FIRST -- it is a BEFORE trigger, and
  --    the CHECK is evaluated after -- and raised 'That customer belongs to a
  --    different company.' as P0001, which is not check_violation, so it
  --    escaped the handler and failed the push. Two lessons, both worth the
  --    ink: a BEFORE trigger can mask the constraint you are trying to test,
  --    and a probe built from unrelated rows is testing the wrong thing.
  select c.customer_id, cc.chain_id, c.company_id
    into v_cust, v_chain, v_company
    from public.customers c
    join public.customer_chain cc on cc.company_id = c.company_id
   limit 1;

  if v_cust is null then
    raise notice 'no company here has both a customer and a chain; skipping the one-owner probes';
  else
    begin
      insert into public.customer_discount
        (customer_discount_id, company_id, customer_id, chain_id, scope, kind, value, effective_from, is_active)
      values ('_probe_both_20261014', v_company, v_cust, v_chain,
              'all', 'percent', 5, current_date, true);
      raise exception 'a rule naming BOTH a customer and a chain was accepted; the one-owner CHECK does not work';
    exception
      when check_violation then null;   -- correct
    end;
  end if;

  begin
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, chain_id, scope, kind, value, effective_from, is_active)
    values ('_probe_neither_20261014', coalesce(v_company, (select company_id from public.companies limit 1)),
            null, null, 'all', 'percent', 5, current_date, true);
    raise exception 'a rule naming NEITHER a customer nor a chain was accepted';
  exception
    when check_violation then null;   -- correct
  end;

  -- 3. 🔴 THE CHANGE THAT MATTERS: a chain rule actually reaches a store.
  --    Written as a round trip on real rows and then rolled back to a
  --    savepoint, so this asserts THIS MIGRATION'S behaviour rather than any
  --    database's data. Skipped, with a notice, where there is no chain with a
  --    store and a product to price -- which is every fresh database.
  --    Re-picked here against the MEMBERSHIP (c.chain_id), which is a stricter
  --    join than the one above: the store has to actually be IN the chain for
  --    the rule to reach it, and it needs a product of its own company to price.
  select cc.chain_id, c.customer_id, p.product_id
    into v_chain, v_cust, v_prod
    from public.customer_chain cc
    join public.customers c on c.chain_id = cc.chain_id
    join public.products p on p.company_id = c.company_id
   limit 1;

  if v_chain is null then
    raise notice 'no chain with a store and a product here; skipping the live resolver check';
  else
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, chain_id, scope, kind, value, effective_from, is_active)
    values ('_probe_chain_20261014', (select company_id from public.customer_chain where chain_id=v_chain),
            null, v_chain, 'all', 'percent', 7, current_date - 1, true);

    select count(*) into v_n
      from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.kind='percent' and r.value=7;
    if v_n <> 1 then
      raise exception 'a chain rule did not reach a store in that chain; the resolver change did not take';
    end if;
    raise notice 'a chain-wide rule reaches its stores';

    -- And the store's own rule outranks it at the same scope.
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, chain_id, scope, kind, value, effective_from, is_active)
    values ('_probe_store_20261014', (select company_id from public.customers where customer_id=v_cust),
            v_cust, null, 'all', 'percent', 3, current_date - 1, true);

    select count(*) into v_n
      from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.kind='percent' and r.value=3;
    if v_n <> 1 then
      raise exception 'the store''s own rule did not outrank its chain''s at the same scope';
    end if;
    raise notice 'a store''s own rule outranks its chain''s';

    delete from public.customer_discount
     where customer_discount_id in ('_probe_chain_20261014','_probe_store_20261014');
  end if;

  -- 4. Nothing was left behind by the probes.
  select count(*) into v_bad from public.customer_discount
   where customer_discount_id like '\_probe\_%\_20261014';
  if v_bad > 0 then
    raise exception '% probe row(s) survived; this migration must leave no data behind', v_bad;
  end if;

  -- 5. Both unique indexes are in place, so neither kind of rule can be doubled.
  select count(*) into v_bad from pg_indexes
   where schemaname='public'
     and indexname in ('customer_discount_unique_scope','customer_discount_unique_chain_scope');
  if v_bad <> 2 then
    raise exception 'expected both uniqueness indexes, found %', v_bad;
  end if;
end $verify$;

commit;
