-- The category belongs to the PRODUCT, not to each size of it.
--
-- "why would it live on the variant row. wouldn't category be tied to the
-- product group."
--
-- Yes. `product_groups` IS the product -- what a customer buys -- and `products`
-- rows are its variants, size x channel. A shelf is a fact about the product:
-- every size of Monin Vanilla is a syrup. Putting it on the variant lets the
-- 12oz be a Syrup and the 1L be a Sauce, which is not a state anybody wants and
-- not one any screen offers.
--
-- ── It has already drifted, measured on prod ──────────────────────────────
--
--    5 groups  have variants pointing at DIFFERENT categories
--   41 groups  are partly categorised: some variants carry one, some do not
--
-- 46 products where "what shelf is this on" has no single answer. A category
-- discount reads the variant, so today it can catch the 12oz and miss the 1L of
-- the same product, and the invoice is the first place that shows.
--
-- The precedent is already here: `product_type` sits on product_groups AND on
-- products, and the group is the one the Products list believes.
--
-- ── What this does ────────────────────────────────────────────────────────
--
-- product_groups gains category_id. Every group is backfilled from its own
-- variants: the category the most of them carry, ties broken by the smallest id
-- so a re-run lands identically. The resolver then reads the GROUP.
--
-- products.category_id is deliberately NOT dropped here. Nothing reads it after
-- this migration, but "nothing reads it" is a claim a release should prove
-- before a column holding 379 rows of a roaster's own classification goes away.
-- It is commented as superseded and dropped in a later migration.
--
-- 🔴 The mixed groups are REPORTED at apply time, by name, because the backfill
-- has to pick one and the roaster is the only one who knows which is right.

begin;

alter table public.product_groups
  add column if not exists category_id text
    references public.product_category(id) on delete set null;

comment on column public.product_groups.category_id is
  'The shelf this product sits on. The one the discount resolver and the storefront read.';

comment on column public.products.category_id is
  'SUPERSEDED by product_groups.category_id (20261015000002). Not read. Kept until a release proves nothing depends on it, then dropped.';

-- ── The backfill ──────────────────────────────────────────────────────────

create temporary table _shelf_backfill_20261015 on commit drop as
with counted as (
  select p.group_id, p.category_id, count(*) as n
    from public.products p
   where p.group_id is not null and p.category_id is not null
   group by p.group_id, p.category_id
),
ranked as (
  select group_id, category_id, n,
         row_number() over (partition by group_id order by n desc, category_id) as rn,
         count(*) over (partition by group_id) as distinct_categories
    from counted
)
select group_id, category_id, distinct_categories from ranked where rn = 1;

update public.product_groups g
   set category_id = b.category_id
  from _shelf_backfill_20261015 b
 where g.group_id = b.group_id
   and g.category_id is distinct from b.category_id;

-- ── The resolver reads the group ──────────────────────────────────────────

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
      -- The shelf, read from the PRODUCT. Every size of a product is on the
      -- same shelf, so a category rule can no longer catch one size and miss
      -- another. Null never matches: an unshelved product is in no rule.
      or (d.scope = 'category'      and d.scope_ref = pg.category_id)
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
      or (d.scope = 'variant'       and d.scope_ref = p.product_id)
    )
  order by case d.scope
             when 'variant' then 6
             when 'product' then 5
             when 'category' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc,
           case when d.customer_id is not null then 1 else 0 end desc
  limit 1;
$function$;

do $verify$
declare v_rec record; v_n int; v_bad int; v_cust text; v_prod text; v_cat text;
begin
  -- 1. Every group that had a categorised variant now carries a shelf.
  select count(*) into v_bad
    from _shelf_backfill_20261015 b
    join public.product_groups g on g.group_id = b.group_id
   where g.category_id is null;
  if v_bad > 0 then
    raise exception '% group(s) should have been backfilled and were not', v_bad;
  end if;

  select count(*) into v_n from _shelf_backfill_20261015;
  raise notice 'put % product(s) on a shelf', v_n;

  -- 2. 🔴 Name the ones where the variants disagreed. The backfill took the
  --    majority, which is a guess dressed as a decision unless it is said out
  --    loud. Only the roaster knows whether the 1L really is a Sauce.
  for v_rec in
    select g.group_name, pc.name as chosen, b.distinct_categories
      from _shelf_backfill_20261015 b
      join public.product_groups g on g.group_id = b.group_id
      left join public.product_category pc on pc.id = b.category_id
     where b.distinct_categories > 1
     order by 1
  loop
    raise notice 'MIXED: "%" had % different categories across its sizes; put on "%". Check it.',
      v_rec.group_name, v_rec.distinct_categories, coalesce(v_rec.chosen, '(none)');
  end loop;

  -- 3. No group points at another company's shelf.
  select count(*) into v_bad
    from public.product_groups g
    join public.product_category pc on pc.id = g.category_id
   where pc.company_id is distinct from g.company_id;
  if v_bad > 0 then
    raise exception '% group(s) point at another company''s category', v_bad;
  end if;

  -- 4. The resolver reads the GROUP now. Proved by shelving a product's group,
  --    clearing the variant's own column, and checking the rule still lands.
  select c.customer_id, p.product_id, g.category_id
    into v_cust, v_prod, v_cat
    from public.product_groups g
    join public.products p on p.group_id = g.group_id and p.is_active
    join public.customers c on c.company_id = g.company_id
   where g.category_id is not null
   limit 1;

  if v_cat is null then
    raise notice 'nothing shelved here; skipping the live resolver check';
  else
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
    select '_probe_shelf_20261015', c.company_id, v_cust, 'category', v_cat, 'percent', 13, current_date - 1, true
      from public.customers c where c.customer_id = v_cust;

    update public.products set category_id = null where product_id = v_prod;

    select count(*) into v_n
      from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.value = 13 and r.scope = 'category';
    if v_n <> 1 then
      raise exception 'the resolver did not read the shelf off the product group';
    end if;
    raise notice 'a category rule resolves from the product group, not the variant';

    raise exception 'rollback the probe' using errcode = 'triggered_action_exception';
  end if;
exception
  when triggered_action_exception then
    -- The probe nulled a real variant's column and wrote a rule. Neither may
    -- survive, and a sub-transaction is the only way to undo the UPDATE.
    raise notice 'probe rolled back; no row was changed by it';
end $verify$;

-- The probe above raises to unwind itself, which also unwinds the backfill if
-- it is in the same block. It is not: the backfill ran and committed its work
-- to this transaction before the verify block started, and the exception
-- handler catches rather than propagates, so only the probe's own writes are
-- lost. Asserted here, after the handler, that the backfill survived.
do $after$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.products p
    join public.product_groups g on g.group_id = p.group_id
   where p.category_id is not null and g.category_id is null;
  if v_bad > 0 then
    raise exception '% variant(s) carry a shelf their product does not', v_bad;
  end if;
  raise notice 'every shelved variant has a shelved product';
end $after$;

commit;
