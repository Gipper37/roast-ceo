-- A discount can be scoped to a product CATEGORY.
--
-- "kraken (or a chain in general) needs a chunk of products to be grouped
-- beyond just 'coffee' or 'consumable' so that group can have a discount
-- applied. in this scenario its all syrups are $8.91 for kraken but sauces are
-- a different price."
--
-- Today the scopes are all / distribution / product_type / product / variant.
-- `product_type` is Coffee, Consumable, Service, Equipment — far too coarse: a
-- syrup and a sauce are both Consumable. So the only way to express the deal
-- was to pick every syrup variant by hand.
--
-- ── Why a category rather than a hand-picked list ─────────────────────────
--
-- The form already takes many targets at once, so a list of twelve syrups is
-- expressible today. It is also WRONG THE DAY SOMEBODY ADDS THE THIRTEENTH:
-- the new syrup is not in the list, Kraken quietly pays list price on it, and
-- nothing surfaces that until an invoice goes out. A rule that names the
-- category stays true as the catalogue grows, which is the same reason a chain
-- discount exists instead of eighteen store discounts.
--
-- ── Why product_category, which was sitting there unused ──────────────────
--
-- `product_category` already exists per company with `name`, `sort_order` and
-- `is_active`, and `products.category_id` references it. It is read by NOTHING:
-- no view, no function, no trigger, nothing in the frontend. It was built for
-- the storefront's category nav — ShopStorefront calls itself "the eventual
-- home for category and sub-category filters too" — and that use never landed.
--
-- Being unused is what makes it safe to adopt now: there is no existing meaning
-- to break. And it is deliberately ONE taxonomy for everything sellable rather
-- than a separate consumable one, because the axis is "what shelf is this on",
-- not "is this coffee". Two taxonomies would mean two discount scopes meaning
-- the same thing, and the storefront merging two lists to draw one menu.
--
-- ── Where it sits in the ladder ───────────────────────────────────────────
--
--   variant 6 > product 5 > CATEGORY 4 > distribution 3 > product_type 2 > all 1
--
-- Above `distribution` because "syrups" is a narrower statement than "anything
-- we resell", and below `product` because a rule naming one product is somebody
-- being deliberate about that product.
--
-- ── A category MAY carry a price, and that is the point ───────────────────
--
-- customer_discount_price_needs_a_target currently allows kind='price' only on
-- product and variant, reasoning that "a price you pay only means something
-- against a thing that HAS a price". A category holds many products at many
-- prices, so that reasoning says no.
--
-- It is widened anyway, because "all syrups are $8.91" is the literal
-- requirement and it is a normal way to sell: a shelf of like-sized items at
-- one price. The resolver already derives the discount from each line's own
-- list price at order time, so a category price behaves exactly like a variant
-- price, one line at a time.

begin;

-- ── 1. The scope is sayable ───────────────────────────────────────────────

alter table public.customer_discount drop constraint if exists customer_discount_scope_check;
alter table public.customer_discount add constraint customer_discount_scope_check
  check (scope = any (array['all','product_type','product','distribution','variant','category']));

-- A category rule names which category, so scope_ref is required.
alter table public.customer_discount drop constraint if exists customer_discount_scope_ref_present;
alter table public.customer_discount add constraint customer_discount_scope_ref_present
  check (
       (scope = any (array['all','distribution'])                        and scope_ref is null)
    or (scope = any (array['product_type','product','variant','category']) and scope_ref is not null)
  );

-- A set price may now name a category. See the header.
alter table public.customer_discount drop constraint if exists customer_discount_price_needs_a_target;
alter table public.customer_discount add constraint customer_discount_price_needs_a_target
  check (kind <> 'price' or scope = any (array['product','variant','category']));

-- ── 2. The resolver learns the rung ───────────────────────────────────────
--
-- Edited from the deployed definition. Two changes and nothing else moved: the
-- category arm in the scope test, and the category rung in the ORDER BY.

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
  -- THE TENANT PREDICATE. Keyed on the customer being priced, because a chain
  -- rule names no customer. Identical for a customer rule.
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
      -- The shelf this product sits on. Null category never matches, because
      -- null = null is not true, so an uncategorised product is simply not in
      -- any category rule -- which is the honest answer rather than a guess.
      or (d.scope = 'category'      and d.scope_ref = p.category_id)
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
           -- Tie on scope: the store's own rule beats the chain's.
           case when d.customer_id is not null then 1 else 0 end desc
  limit 1;
$function$;

do $verify$
declare
  v_cat text; v_cust text; v_prod text; v_company text; v_n int; v_bad int;
  v_anycust text; v_anyco text;
begin
  -- 🔴 EVERY PROBE TAKES ITS COMPANY FROM THE CUSTOMER IT NAMES. Picking the
  -- two with independent `limit 1` selects gets a customer from one tenant and
  -- a company from another, and guard_customer_discount_same_tenant -- a BEFORE
  -- trigger -- then raises P0001 before the CHECK under test is ever evaluated.
  -- That failed the staging push for 20261014000002 earlier today and failed it
  -- again here, which is twice in one evening for the same reason. A probe
  -- built from unrelated rows is testing the wrong thing.
  select c.customer_id, c.company_id into v_anycust, v_anyco
    from public.customers c limit 1;

  -- 1. The scope is accepted, and still refuses a nonsense one.
  if v_anycust is not null then
    begin
      insert into public.customer_discount
        (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
      values ('_probe_badscope_20261015', v_anyco, v_anycust,
              'shelf', 'x', 'percent', 5, current_date, true);
      raise exception 'an unknown scope was accepted; the CHECK is not doing its job';
    exception when check_violation then null;
    end;
  end if;

  -- 2. 🔴 THE CHANGE: a category rule reaches a product on that shelf, and a
  --    product on a different shelf is untouched. Proved on real rows, then
  --    rolled back. Skipped with a notice where no categorised product exists.
  select p.category_id, c.customer_id, p.product_id, p.company_id
    into v_cat, v_cust, v_prod, v_company
    from public.products p
    join public.customers c on c.company_id = p.company_id
   where p.category_id is not null and p.is_active
   limit 1;

  if v_cat is null then
    raise notice 'no categorised product here; skipping the live resolver check';
  else
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
    values ('_probe_cat_20261015', v_company, v_cust, 'category', v_cat, 'percent', 11, current_date - 1, true);

    select count(*) into v_n
      from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.kind='percent' and r.value=11 and r.scope='category';
    if v_n <> 1 then
      raise exception 'a category rule did not reach a product in that category';
    end if;
    raise notice 'a category rule reaches the products on that shelf';

    -- A product on another shelf must NOT pick it up.
    perform 1 from public.products p2
      where p2.company_id = v_company and p2.is_active
        and (p2.category_id is distinct from v_cat)
      limit 1;
    if found then
      select count(*) into v_bad
        from public.products p2
        cross join lateral public.resolve_customer_discount(v_cust, p2.product_id, current_date) r
       where p2.company_id = v_company and p2.is_active
         and (p2.category_id is distinct from v_cat)
         and r.customer_discount_id = '_probe_cat_20261015';
      if v_bad > 0 then
        raise exception '% product(s) outside the category picked the rule up', v_bad;
      end if;
      raise notice 'products on other shelves are untouched by it';
    end if;

    -- And a rule naming the product itself still outranks the category.
    insert into public.customer_discount
      (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
    select '_probe_var_20261015', v_company, v_cust, 'variant', v_prod, 'percent', 2, current_date - 1, true;

    select count(*) into v_n
      from public.resolve_customer_discount(v_cust, v_prod, current_date) r
     where r.value=2;
    if v_n <> 1 then
      raise exception 'a variant rule no longer outranks a category rule';
    end if;
    raise notice 'a rule naming the variant still outranks the shelf';

    delete from public.customer_discount
     where customer_discount_id in ('_probe_cat_20261015','_probe_var_20261015');
  end if;

  -- 3. A set price may name a category now, and still may not name 'all'.
  if v_anycust is not null then
    begin
      insert into public.customer_discount
        (customer_discount_id, company_id, customer_id, scope, scope_ref, kind, value, effective_from, is_active)
      values ('_probe_priceall_20261015', v_anyco, v_anycust,
              'all', null, 'price', 5, current_date, true);
      raise exception 'a set price was accepted against Everything, which prices nothing';
    exception when check_violation then null;
    end;
  end if;

  -- 4. Nothing survived.
  select count(*) into v_bad from public.customer_discount
   where customer_discount_id like '\_probe\_%\_20261015';
  if v_bad > 0 then
    raise exception '% probe row(s) survived', v_bad;
  end if;
end $verify$;

commit;
