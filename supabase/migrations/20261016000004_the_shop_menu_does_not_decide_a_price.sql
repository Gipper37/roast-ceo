-- The shop menu no longer decides which discount a customer gets.
--
-- Owner, 2026-10-16: *"why the fuck would sort order affect discounts. fuck. we
-- didn't jsut build collections for discounts. collections are there own thing
-- just like type is. it just happens to be able to be used when adding
-- discounts. fuck! remove the deals column for that reason."*
--
-- He is right, and the coupling was worse than untidy. When two collections a
-- customer qualifies for both carried a discount, `resolve_customer_discount`
-- broke the tie on `collection.sort_order` -- the collection's position in the
-- roaster's own STOREFRONT MENU. So dragging a collection up the shop nav
-- REPRICED live orders, silently, from a screen that mentions no prices. A menu
-- is presentation; it must not be arithmetic.
--
-- ── What replaces it: THE BETTER DEAL WINS, which is what Shopify does ─────
--
-- Owner, 2026-10-16, asked which tie-break to use: *"do what shopify does"*.
-- So this is Shopify's, checked against their documentation rather than
-- recalled, and their model is TWO STAGES in a strict order:
--
--   1. SPECIFICITY SELECTS THE LEVEL. shopify.dev, on resolving catalogs:
--      "Only catalogs of the highest precedence are considered". Our scope
--      ladder is that stage and is UNCHANGED -- a variant rule still beats a
--      product rule, which still beats a collection rule, and a lower rung is
--      discarded rather than price-compared. That is what lets a roaster say
--      "20% off all coffee, but only 5% on Hawaiian" and mean it; pure
--      best-price would make the narrower exception unsayable.
--   2. PRICE BREAKS A TIE *WITHIN* THAT LEVEL. For peers Shopify says "the
--      lowest price for that item", and for discounts "the best discount for
--      the customer's cart is always applied". That is this change.
--   3. AND A TIE ON PRICE BREAKS ON CREATION ORDER -- Shopify uses "the first
--      catalog that was created", so `d.created_at asc` replaces the date
--      term, with `d.customer_discount_id asc` underneath it as the absolute
--      floor so the answer is never planner-dependent.
--
-- Only `collection` can ever reach stage 2. Every other scope matches at most
-- once for a given product (one product_type, one group, one variant; `all`
-- and `distribution` have a single key), and the two partial unique indexes
-- stop one party holding two active rules for the same collection. So the
-- tie is always "this product is in two collections and both carry a deal".
--
-- ── 🔴 THE RANKING BASE, AND THE ONE CASE IT GETS WRONG ───────────────────
--
-- The comparison ranks on `p.price`, the variant's catalogue price. The ENGINE
-- charges on `order_details.unit_price_at_sale`, which is snapshotted at
-- insert and KEPT on later updates. At insert the two are the same value, so
-- the overwhelming majority of resolutions rank on exactly what is charged.
--
-- They diverge on one path: `handle_order_detail_logic` re-resolves a standing
-- rule when a line's discount is CLEARED, and on that pass an old line keeps
-- its quoted price while this ranks on today's catalogue price. Percent and
-- amount cross over at base = 100 * amount / percent, so on that path the
-- cheaper-looking rule can be the dearer one. Measured on prod: 20,865 of
-- 35,716 priced lines already carry a `unit_price_at_sale` that differs from
-- today's `products.price`.
--
-- NOT FIXED HERE, deliberately. The fix is a 4th `p_unit_price` parameter,
-- which cannot be added by CREATE OR REPLACE (a defaulted 4th argument makes
-- every existing 3-argument call ambiguous, 42725), so it means DROP + CREATE
-- plus patching `handle_order_detail_logic` -- the function that writes every
-- order line in the app. That is a bigger blast radius than the bug: it is
-- reachable only by a customer holding TWO collection-scoped deals of
-- DIFFERENT kinds on a re-resolved old line, and prod holds ZERO
-- collection-scoped deals. It goes on the open list as its own release.
--
-- ── MEASURED ON PROD BEFORE CHANGING, because this is money ────────────────
--
-- A change to the tie-break can only move a price for a customer who currently
-- resolves THROUGH it. Counted on prod 2026-10-16:
--
--     active collection-scoped discounts ............ 0
--     parties holding 2+ collection discounts ....... 0
--     overlapping product pairs between any two ..... 0
--
-- Nobody holds even one, so no live price changes today. That is the reason
-- this ships as its own migration rather than riding along with the menu work:
-- if the numbers had been non-zero, the right move was to show them first and
-- let the owner decide, not to pick a tie-break and hope.
--
-- ── Body patched from `pg_get_functiondef`, not retyped ────────────────────
--
-- The function carries the scope precedence ladder, the store-beats-chain rule,
-- the date window and the collection membership EXISTS test. Two things changed
-- and nothing else: the `left join public.collection` is gone, and one ORDER BY
-- term is replaced. The verify block asserts each survivor by name.

begin;

-- ── 🔴 FIRST: A STATED PRICE CANNOT HANG OFF A COLLECTION ─────────────────
--
-- `customer_discount_price_needs_a_target` admitted
-- `scope in ('product','variant','collection')` for `kind = 'price'`. A price
-- rule says "they pay $9 each". That is a statement about ONE thing that has
-- ONE price, and a collection is not one: `Hawaiian` on prod spans 78 variants
-- from $0.00 to $292.50.
--
-- This has been a hole all along, but the tie-break below is what makes it
-- systematic. Ranking by what the customer ends up paying means a flat $9 on a
-- collection beats EVERY percentage rule on EVERY variant in it dearer than
-- $9, automatically and for ever: $9 for a case that costs $132.55 to make.
-- Under the old date tie-break the bad rule at least had to be the newest.
--
-- So it closes in the same migration that makes it dangerous. This is the
-- reasoning 20260923000009 already wrote down for groups -- "a group holds
-- variants at different prices ... 'They pay $9' is not a statement a group
-- can carry" -- applied to the scope that inherited the same problem, and it
-- is Shopify's shape too: their fixed prices are set per VARIANT.
--
-- Measured on prod and on staging before writing this: 0 rows would fail. The
-- only price-kind rule anywhere is scope 'product' and inactive.
alter table public.customer_discount
  drop constraint if exists customer_discount_price_needs_a_target;
alter table public.customer_discount
  add constraint customer_discount_price_needs_a_target
  check (kind <> 'price' or scope = any (array['product', 'variant']));

CREATE OR REPLACE FUNCTION public.resolve_customer_discount(p_customer_id text, p_product_id text, p_on_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(customer_discount_id text, kind text, value numeric, scope text)
 LANGUAGE sql
 STABLE
AS $function$
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
           -- TWO COLLECTIONS, TWO DEALS: THE BETTER DEAL WINS. Shopify's
           -- rule for peers at one level, and what the owner asked for. This
           -- used to read the collection's position in the roaster's SHOP
           -- MENU, so dragging a collection up the storefront nav silently
           -- REPRICED orders from a screen that mentioned no prices.
           --
           -- What each rule leaves the customer paying, per unit, so three
           -- kinds that are written differently can be compared as one number.
           -- Lowest wins.
           --
           -- `least(d.value, base)` for a price rule is not belt and braces:
           -- the engine charges `greatest(0, list_total - value * qty)`, so a
           -- stated price ABOVE the list price actually charges the list
           -- price, and ranking it at its stated value would overstate it.
           -- `least` also IGNORES a null argument, which is the behaviour we
           -- want: two price rules on an unpriced variant still compare
           -- against each other on their own values.
           --
           -- The percent and amount arms need no null guard -- numeric
           -- arithmetic with NULL is already NULL, and `nulls last` then keeps
           -- an uncomputable rule from winning by being unknown.
           --
           -- 🔴 The `else` is written out. Without it Postgres appends
           -- `else null`, so the day a fourth kind is added it would lose
           -- every tie in silence. The verify block asserts that every kind in
           -- `customer_discount_kind_check` is named here.
           case
             when d.kind = 'price'   then least(d.value, p.price)
             when d.kind = 'percent' then greatest(p.price * (1 - d.value / 100.0), 0)
             when d.kind = 'amount'  then greatest(p.price - d.value, 0)
             else null
           end asc nulls last,
           -- Shopify breaks a tie on "the first catalog that was created", so
           -- the older rule wins when two leave the customer paying the same.
           d.created_at asc,
           -- Last resort, so the answer is stable rather than whatever the
           -- planner returned first.
           d.customer_discount_id asc
  limit 1;
$function$;

-- 🔴 The database's own catalogue documented the coupling AS THE DESIGN: this
-- comment said sort_order "also decides which collection wins when two of them
-- carry a discount for the same customer". Leaving that behind would send the
-- next reader looking for behaviour that no longer exists, which is how
-- project_open_prod_holes.md sat stale for ten days.
comment on table public.collection is
  'A collection a product can appear in: Syrups, Hawaiian, Decaf. A product belongs to MANY. sort_order is the storefront menu order and NOTHING else: it is presentation, and deliberately does not affect pricing (20261016000004 removed that coupling). The exclusive_/excluded_ columns gate VISIBILITY in the wholesale shop, ALL-allow: a product is visible only if every restricted collection it is in admits the buyer. channel_id, when set, limits the collection to one sales channel.';

do $verify$
DECLARE
  v_src text;
BEGIN
  select prosrc into v_src from pg_proc
   where oid = 'public.resolve_customer_discount(text,text,date)'::regprocedure;

  -- 1. The coupling is gone, both halves of it. Named separately because
  --    removing the join while leaving the sort term (or the reverse) is a
  --    different failure, and one of them would not even compile.
  if v_src like '%sort_order%' then
    raise exception 'the resolver still reads the collection menu order';
  end if;
  if v_src like '%public.collection col%' then
    raise exception 'the resolver still joins collection for its menu position';
  end if;
  if v_src not like '%least(d.value, p.price)%' then
    raise exception 'the better-deal tie-break is not there';
  end if;
  if v_src not like '%d.created_at asc%' then
    raise exception 'the creation-order tie-break under it is not there';
  end if;
  if v_src not like '%else null%' then
    raise exception 'the case has no explicit else; a new discount kind would lose every tie in silence';
  end if;

  -- 🔴 Every kind the table admits must be NAMED in the comparison. Read off
  -- the live CHECK constraint rather than a list typed here, so adding a kind
  -- without ranking it fails this release instead of quietly losing ties.
  DECLARE
    v_kinds text;
    v_kind  text;
  BEGIN
    select pg_get_constraintdef(oid) into v_kinds from pg_constraint
     where conrelid = 'public.customer_discount'::regclass
       and conname = 'customer_discount_kind_check';
    if v_kinds is null then
      raise notice 'no kind check constraint here; kinds unverified';
    else
      foreach v_kind in array
        array(select m[1] from regexp_matches(v_kinds, '''([a-z_]+)''::text', 'g') m)
      loop
        if v_src not like '%d.kind = ''' || v_kind || '''%' then
          raise exception 'discount kind % is allowed by the table but is not ranked by the tie-break', v_kind;
        end if;
      end loop;
    end if;
  END;

  -- And the constraint above actually tightened.
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.customer_discount'::regclass
       and conname = 'customer_discount_price_needs_a_target'
       and pg_get_constraintdef(oid) like '%collection%'
  ) then
    raise exception 'a stated price can still be attached to a collection';
  end if;

  -- 2. And the work that is NOT this change's survived the replace. 🔴 This is
  --    the half that matters: CREATE OR REPLACE rewrites the whole body, so a
  --    retyped line is a silent regression. Each survivor is asserted by name.
  if v_src not like '%when ''variant'' then 6%' or v_src not like '%when ''collection'' then 4%' then
    raise exception 'the scope precedence ladder is gone; a blanket deal could beat a variant deal';
  end if;
  if v_src not like '%case when d.customer_id is not null then 1 else 0 end desc%' then
    raise exception 'store-beats-chain is gone; a chain rule could override a store''s own';
  end if;
  if v_src not like '%d.scope = ''collection'' and exists (%' then
    raise exception 'the collection membership test is gone; collection discounts would never match';
  end if;
  if v_src not like '%d.effective_to is null%' or v_src not like '%d.is_active%' then
    raise exception 'the active/date window is gone; expired discounts would apply';
  end if;
  if v_src not like '%d.customer_discount_id asc%' then
    raise exception 'the stable last resort is gone; equally-dated rules would resolve at random';
  end if;

  -- 3. 🔴 EXERCISED, NOT GREPPED. Two collection discounts for one customer on
  --    one product, and the one that leaves them paying LESS must win --
  --    three times over: a straight percent-vs-percent, the same pair with
  --    the values swapped so the winner has to follow the money rather than
  --    the row, and a percent-vs-price pair so two DIFFERENT KINDS are
  --    actually compared. A grep proves the text changed; only a call proves
  --    the arithmetic ranks them.
  --
  --    Prod holds ZERO collection discounts (see the measurement above), so
  --    there is nothing real to read -- the probe has to make its own pair. It
  --    writes, asserts, then rolls itself back through a sentinel exception so
  --    the implicit savepoint around this block unwinds the inserts. The file
  --    carries its own begin;/commit;, so "the surrounding transaction rolls it
  --    back" would be FALSE here; 20261015000018 made exactly that wrong claim.
  DECLARE
    v_company  text;
    v_customer text;
    v_product  text;
    v_coll_a   text;
    v_coll_b   text;
    v_won      text;
    v_rows     int;
    v_price    numeric;
  BEGIN
    -- 🔴 TWO COLLECTIONS, NOT ONE. `customer_discount_unique_scope` is a
    -- partial unique index on (customer_id, scope, coalesce(scope_ref,
    -- '__all__')) where is_active -- so a customer can hold at most ONE active
    -- discount per collection, and the tie-break is only ever reachable
    -- through two DIFFERENT collections that share a product. The first draft
    -- of this probe inserted the same collection twice and staging refused it
    -- with 23505. The index is the thing that defines the case; it is not a
    -- detail of the probe.
    --
    -- Found by shape, never by id: MCR is the test case, not the spec. Prod
    -- holds 8 products sitting in 2+ collections, so this is reachable there
    -- rather than hypothetical.
    -- 🔴 IT MUST HAVE A PRICE. The whole tie-break is arithmetic on
    -- `p.price`, so a probe on an unpriced variant would assert nothing and
    -- pass. NOT filtered on `is_active`, because the resolver is not either:
    -- measured on prod, ALL 8 products sitting in 2+ collections are inactive
    -- variants (10 priced rows, 6 unpriced), so requiring is_active would
    -- silently skip this check on the one database that matters.
    select p.company_id, p.product_id, p.price
      into v_company, v_product, v_price
      from public.products p
      join public.product_group_collection pgc on pgc.group_id = p.group_id
     where p.company_id is not null
       and p.price is not null and p.price > 0
     group by p.company_id, p.product_id, p.price
    having count(distinct pgc.collection_id) >= 2
     limit 1;

    if v_product is not null then
      select min(pgc.collection_id), max(pgc.collection_id)
        into v_coll_a, v_coll_b
        from public.product_group_collection pgc
        join public.products p2 on p2.group_id = pgc.group_id
       where p2.product_id = v_product;

      -- A customer carrying NO active discount at all, so nothing already on
      -- the books outranks the probe's pair on the precedence ladder and
      -- nothing collides with the unique index. The index ignores company_id,
      -- so this exclusion does too.
      select c.customer_id into v_customer
        from public.customers c
       where c.company_id = v_company
         and not exists (select 1 from public.customer_discount d
                          where d.is_active
                            and (d.customer_id = c.customer_id
                                 or (d.chain_id is not null and d.chain_id = c.chain_id)))
       limit 1;
    end if;

    if v_customer is null or v_coll_a = v_coll_b then
      raise notice 'no unencumbered customer with a product in two collections here; tie-break asserted by source only';
    else
      BEGIN
        -- CASE 1: two percents. 20% off beats 5% off, and the row that wins
        -- is deliberately NOT the one that would win on date or on id, so a
        -- pass cannot come from the wrong key.
        insert into public.customer_discount
          (customer_discount_id, company_id, customer_id, scope, scope_ref,
           kind, value, effective_from, is_active)
        values
          ('zzprobe-a-small', v_company, v_customer, 'collection', v_coll_a,
           'percent', 5, current_date - 1, true),
          ('zzprobe-b-big', v_company, v_customer, 'collection', v_coll_b,
           'percent', 20, current_date - 8, true);

        select count(*), min(customer_discount_id)
          into v_rows, v_won
          from public.resolve_customer_discount(v_customer, v_product, current_date);
        if v_rows <> 1 then
          raise exception 'the resolver returned % rows for one customer and one product; it must return at most one', v_rows;
        end if;
        if v_won <> 'zzprobe-b-big' then
          raise exception 'the worse deal won (got %); 20%% off must beat 5%% off', v_won;
        end if;

        -- CASE 2: swap the values. The winner must follow the money, not the
        -- row -- if it did not flip, something else is doing the deciding.
        update public.customer_discount set value = 30
          where customer_discount_id = 'zzprobe-a-small';
        update public.customer_discount set value = 2
          where customer_discount_id = 'zzprobe-b-big';
        select min(customer_discount_id) into v_won
          from public.resolve_customer_discount(v_customer, v_product, current_date);
        if v_won <> 'zzprobe-a-small' then
          raise exception 'swapping the values did not move the winner (got %); the tie-break is reading something else', v_won;
        end if;

        -- CASE 3: two different KINDS, which is the whole point of ranking
        -- what the customer PAYS rather than the numbers as they are written.
        -- 30 (percent) is a bigger number than nothing, but an `amount` of
        -- 90% of the list price leaves them paying a tenth, and that must
        -- win. Both are collection-scoped, so the ladder keeps them on the
        -- same rung and the tie-break is what decides it.
        --
        -- Deliberately NOT a `price` rule: the constraint added at the top of
        -- this file stops a stated price naming a collection at all, so a
        -- price-vs-percent pair could not be written here even to test it.
        delete from public.customer_discount where customer_discount_id like 'zzprobe-%';
        insert into public.customer_discount
          (customer_discount_id, company_id, customer_id, scope, scope_ref,
           kind, value, effective_from, is_active)
        values
          ('zzprobe-pct', v_company, v_customer, 'collection', v_coll_a,
           'percent', 30, current_date - 1, true),
          ('zzprobe-cheap', v_company, v_customer, 'collection', v_coll_b,
           'amount', round(v_price * 0.9, 2), current_date - 8, true);
        select min(customer_discount_id) into v_won
          from public.resolve_customer_discount(v_customer, v_product, current_date);
        if v_won <> 'zzprobe-cheap' then
          raise exception 'an amount worth 90%% of list did not beat 30%% off (got %); kinds are not compared on what is paid', v_won;
        end if;

        raise notice 'the better deal wins: percent over percent, both ways round, and across kinds';
        -- Passed. Undo the probe's writes by failing deliberately.
        raise exception 'ZZPROBE_OK';
      EXCEPTION
        WHEN others THEN
          if sqlerrm <> 'ZZPROBE_OK' then raise; end if;
      END;
    end if;
  END;

  raise notice 'the storefront menu order no longer decides a price';
END;
$verify$;

commit;
