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
-- ── What replaces it: the newer rule wins ──────────────────────────────────
--
-- `d.effective_from desc`. It reads only the discount, which is where a
-- decision about a discount belongs, and it is explicable to a roaster in one
-- sentence: *the most recently dated rule applies.* `customer_discount_id asc`
-- stays underneath it so the answer is stable rather than planner-dependent,
-- which is what makes two equally-dated rules deterministic.
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
           -- TWO COLLECTIONS, TWO DEALS: THE NEWER RULE WINS.
           --
           -- This tie-break used to read the collection's position in the
           -- roaster's SHOP MENU, so dragging a collection up the storefront
           -- nav silently REPRICED orders, from a screen that said nothing
           -- about discounts. Owner, 2026-10-16: *"why the fuck would sort
           -- order affect discounts. we didn't jsut build collections for
           -- discounts. collections are there own thing just like type is. it
           -- just happens to be able to be used when adding discounts."*
           --
           -- A menu is presentation. This reads only the discount, which is
           -- where a decision about a discount belongs, and is explicable to a
           -- roaster in one sentence. The collection join went with it.
           d.effective_from desc,
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
  if v_src not like '%d.effective_from desc%' then
    raise exception 'the newer-rule-wins tie-break is not there';
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
  --    one product, dated a week apart, and the newer must win. A grep proves
  --    the text changed; only a call proves the tie-break resolves.
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
    select p.company_id, p.product_id
      into v_company, v_product
      from public.products p
      join public.product_group_collection pgc on pgc.group_id = p.group_id
     where p.company_id is not null
     group by p.company_id, p.product_id
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
        insert into public.customer_discount
          (customer_discount_id, company_id, customer_id, scope, scope_ref,
           kind, value, effective_from, is_active)
        values
          ('zzprobe-older', v_company, v_customer, 'collection', v_coll_a,
           'percent', 5, current_date - 8, true),
          ('zzprobe-newer', v_company, v_customer, 'collection', v_coll_b,
           'percent', 9, current_date - 1, true);

        select count(*), min(customer_discount_id)
          into v_rows, v_won
          from public.resolve_customer_discount(v_customer, v_product, current_date);

        if v_rows <> 1 then
          raise exception 'the resolver returned % rows for one customer and one product; it must return at most one', v_rows;
        end if;
        if v_won <> 'zzprobe-newer' then
          raise exception 'the older rule won the tie (%); the newer one must', v_won;
        end if;

        -- And the reverse, so this is not just "whichever id sorts first":
        -- re-date the pair so the OTHER row is the newer one and it must flip.
        update public.customer_discount set effective_from = current_date - 20
          where customer_discount_id = 'zzprobe-newer';
        select min(customer_discount_id) into v_won
          from public.resolve_customer_discount(v_customer, v_product, current_date);
        if v_won <> 'zzprobe-older' then
          raise exception 'the tie-break did not follow the dates when they were swapped (got %); it is sorting on something else', v_won;
        end if;

        raise notice 'the newer collection discount wins, both ways round';
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
