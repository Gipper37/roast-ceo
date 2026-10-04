-- A report can see the chain behind the store.
--
-- This is the migration the chain feature exists for. 20261003000010 recorded
-- which customers are stores of which chain; nothing reads it yet, so the
-- reports are still flat and still wrong about who this roaster's biggest
-- accounts are.
--
-- MEASURED ON PROD TODAY, company 9ShiyDAXhV, re-run while writing this file so
-- the numbers are checked rather than quoted. Flat, by customer_revenue:
--
--      3  Kraken Coffee-Kahului             150,363
--      4  Kraken Coffee-Kihei               113,257
--      8  Kraken Coffee - Wailea             66,573
--      9  Kraken Coffee-Kihei Marketplace    66,008
--     51  Minit Stop - Dairy Rd               8,500
--     54  Minit Stop- Keaau                   8,049
--
-- Rolled up by chain, same view, same range:
--
--      1  Beans World, LTD      490,556   1 store
--      2  Kraken Coffee         396,201   4 stores   <- never been visible
--      3  Costco Wholesale      369,205   1 store
--      4  Maui Resort Rentals   106,596   1 store
--      5  Minit Stop            104,590  18 stores   <- never been visible
--
-- Kraken is the SECOND largest account this roastery has and no report has ever
-- said so. Minit Stop is the fifth and its best single store ranks 51st of 200,
-- so it appears in no top-N list anywhere. That is the whole point.
--
-- 🔴 THE VIEWS STAY PER CUSTOMER. They gain chain_id and chain_name and they do
-- not group by them. Rolling up is the caller's choice, and it has to be,
-- because both readings are needed by the same operator ten seconds apart: the
-- chain number to know what the account is worth, the per-store split to know
-- which store is shrinking. A view that collapsed the rows would answer the
-- first question and destroy the second, and the per-store split is the thing
-- the owner was explicit about keeping when he refused a merge.
--
-- ── Why this file is longer than the change ─────────────────────────────
--
-- 🔴 GOTCHA 1, AND IT HAS ALREADY LEAKED ONCE. pg_get_viewdef() returns a
-- view's SELECT and NOTHING ELSE. `with (security_invoker = true)` lives in
-- pg_class.reloptions, and CREATE OR REPLACE VIEW without a WITH clause RESETS
-- reloptions, so a view rebuilt from its own definition silently starts running
-- as its owner (postgres, who owns the base tables and therefore skips their
-- RLS) and reads every tenant's rows. On 2026-09-24 that shipped on
-- data_quality_issues and returned 766 rows across every tenant on staging.
--
-- SO, READ OFF PROD BEFORE TOUCHING EITHER VIEW:
--
--     customer_revenue        reloptions = {security_invoker=true}
--     customer_profitability  reloptions = {security_invoker=true}
--
-- Both are restored EXPLICITLY on the create statements below, and the verify
-- block refuses to commit unless pg_class.reloptions still says so. Nothing
-- else in this file could see the omission.
--
-- 🔴 GOTCHA 2. LEFT JOIN to customer_chain, never inner. 2,123 customers, 31 of
-- them in a chain. An inner join would silently delete 98.5% of the revenue
-- report, and a report that is missing rows looks exactly like a report of a
-- quiet month. The verify block compares every row of both views before and
-- after and fails on a single changed number, which is the only assertion that
-- actually proves the join direction.
--
-- 🔴 GOTCHA 3. customer_profitability ALREADY loses rows, on purpose:
-- `join order_revenue orv on ... orv.order_total > 0 and orv.order_cogs > 0`
-- drops any order with no cost against it, which is 57% of MCR's lines because
-- they arrived from QuickBooks with a price and no cost. That guard is correct
-- and is documented in the app at app/app/(app)/customers/[id]/page.tsx:86.
-- It is NOT touched here. Adding a second row-losing join to a view that is
-- already known to lose rows is how a reporting bug becomes unfindable.
--
-- 🔴 GOTCHA 4. The chain columns go at the END of each view's column list.
-- CREATE OR REPLACE VIEW can only append, never reorder or retype, so this is
-- also the only shape Postgres will accept without a drop. A drop would take
-- the grants with it: both views grant SELECT to `authenticated` and nothing to
-- `anon`, and a replace keeps that, which is why neither view is dropped here.
--
-- ── What gross_margin_report needed, and why it is a drop ────────────────
--
-- The RPC's body below is the output of pg_get_functiondef() with four lines
-- inserted. It was NOT retyped: CREATE OR REPLACE FUNCTION rewrites the whole
-- body, so reconstructing it from the call sites would have silently dropped
-- whichever clause I did not remember, and the clauses at risk are the ones
-- that make the number right (the void/written_off exclusion and the legacy
-- import filter). The verify block asserts each of them is still present in
-- prosrc, by text, for exactly that reason.
--
-- IT HAD TO BE DROPPED AND RECREATED. Adding columns changes the return type
-- and CREATE OR REPLACE FUNCTION refuses that. Preserved verbatim across the
-- drop, each read off pg_proc first and asserted afterwards:
--
--     signature     (date, date, text, text, boolean), same parameter names,
--                   same three defaults
--     volatility    STABLE
--     security      INVOKER (prosecdef = false, so pg_get_functiondef prints
--                   nothing; the absence IS the setting)
--     search_path   NONE. proconfig is NULL on prod. Adding a SET search_path
--                   here because it looks tidy would change how the function
--                   resolves every table it names
--     grants        proacl was {postgres=X, authenticated=X, service_role=X}.
--                   A recreated function takes schema public's default ACL,
--                   which for the `postgres` grantor is the same three roles,
--                   but db-push could connect as another role whose default ACL
--                   includes `anon`. So the grants are stated explicitly rather
--                   than inherited, and asserted
--
-- WHAT BREAKS FOR CALLERS: nothing. The single caller is
-- app/app/(app)/accounting/reportActions.ts, which types MarginRow as
-- { period, group_label, revenue, cogs, orders }, selects nothing by position
-- and spreads the row (`{ ...r }`), so two extra columns arrive and pass
-- through untouched. Nothing in the database calls this function.
--
-- 🔴 THE RPC STILL GROUPS BY total, product_type, customer AND channel, AND
-- NOTHING ELSE. An earlier draft of this file added a fifth `when 'chain'`
-- branch to the grouping CASE. It is gone, on two counts.
--
-- It was WRONG. The reason given for it was that reportActions pages the RPC
-- and so a caller summing chains in TypeScript would sum only the pages that
-- arrived. Read the loop: reportActions.ts pages with .range(offset, offset +
-- 999) and breaks on the first short page, up to a HARD_CAP of 20,000 rows,
-- and only then reports `truncated`. The caller gets every row, so a caller
-- that folds them gets the right number. Rolling up is the caller's choice
-- here for the same reason it is in the two views above, and the per-store
-- split is the thing the owner was explicit about keeping.
--
-- And it was UNREACHABLE, so it could not even have been tested. The chain
-- view already exists in the frontend and already decided this: MarginReport
-- declares `MarginView = MarginGroup | 'chain'`, viewGroup() rewrites 'chain'
-- to 'customer' before the action is called, and rollUpMarginToChain folds the
-- per-store rows. p_group never arrives as 'chain', so a server branch for it
-- is dead code that would have sat here looking like a supported grouping,
-- and a second roll-up path that can disagree with the one the UI uses.
--
-- WHAT THE RPC DOES GAIN is the two columns the fold needs: chain_id and
-- chain_name on the customer grouping, so the caller can tell a store of
-- Kraken from a customer that stands alone without a second query. They are
-- NULL on total, product_type and channel, where a chain means nothing.

begin;

do $precondition$
begin
  -- customer_chain arrives in 20261003000010, which is committed but was not
  -- applied to prod when this file was written. Ordering guarantees it lands
  -- first; saying so here turns a bare "relation does not exist" into a
  -- sentence that names the cause.
  if to_regclass('public.customer_chain') is null then
    raise exception 'public.customer_chain does not exist; apply 20261003000010 before this file';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'customers'
                    and column_name = 'chain_id') then
    raise exception 'public.customers.chain_id does not exist; apply 20261003000010 before this file';
  end if;
end;
$precondition$;

-- The before picture of both views, to compare against after the replace. This
-- is the assertion that proves the new join is a LEFT one and that no number
-- moved; nothing else in this file can tell. Run as the migration role, which
-- owns the base tables and so sees every tenant's rows.
create temporary table _revenue_before on commit drop as
  select customer_id, company_id, total_orders, revenue from public.customer_revenue;
create temporary table _profitability_before on commit drop as
  select customer_id, customer_name, company_id, total_orders, revenue,
         cogs, gross_profit, margin_pct, data_warning
    from public.customer_profitability;

-- ── customer_revenue ────────────────────────────────────────────────────
-- What a customer actually bought: every non-Canceled order line, no cost
-- filter. This is the view the customers list and the customer detail page read
-- for revenue, precisely because it does NOT drop un-costed orders.
create or replace view public.customer_revenue
  with (security_invoker = true) as
 SELECT customer_id,
    company_id,
    total_orders,
    revenue,
    chain_id,
    chain_name
   FROM ( SELECT c.customer_id,
            c.company_id,
            count(DISTINCT o.order_id) AS total_orders,
            COALESCE(sum(od.total_price), 0::numeric) AS revenue,
            cch.chain_id,
            cch.chain_name
           FROM public.customers c
             JOIN public.orders o ON o.customer_id = c.customer_id AND o.order_status <> 'Canceled'::text
             JOIN public.order_details od ON od.order_id = o.order_id
             LEFT JOIN public.customer_chain cch ON cch.chain_id = c.chain_id AND cch.company_id = c.company_id
          GROUP BY c.customer_id, c.company_id, cch.chain_id, cch.chain_name) v
  WHERE public.auth_is_team_member();

-- ── customer_profitability ──────────────────────────────────────────────
-- The MARGIN view. Its order_revenue join deliberately requires a cost, which
-- is why it hides revenue and why it is not the view to ask "what did they
-- buy". Untouched here apart from the two appended columns.
create or replace view public.customer_profitability
  with (security_invoker = true) as
 SELECT customer_id,
    customer_name,
    company_id,
    total_orders,
    revenue,
    cogs,
    gross_profit,
    margin_pct,
    data_warning,
    chain_id,
    chain_name
   FROM ( WITH order_revenue AS (
                 SELECT order_details.order_id,
                    sum(order_details.total_price) AS order_total,
                    sum(order_details.unit_cost_at_sale) AS order_cogs
                   FROM public.order_details
                  GROUP BY order_details.order_id
                )
         SELECT c.customer_id,
            c.name_company AS customer_name,
            c.company_id,
            count(DISTINCT o.order_id) AS total_orders,
            COALESCE(sum(od.total_price), 0::numeric) AS revenue,
            COALESCE(sum(od.unit_cost_at_sale), 0::numeric) AS cogs,
            COALESCE(sum(od.total_price), 0::numeric) - COALESCE(sum(od.unit_cost_at_sale), 0::numeric) AS gross_profit,
            round((COALESCE(sum(od.total_price), 0::numeric) - COALESCE(sum(od.unit_cost_at_sale), 0::numeric)) / NULLIF(COALESCE(sum(od.total_price), 0::numeric), 0::numeric) * 100::numeric, 1) AS margin_pct,
                CASE
                    WHEN COALESCE(sum(od.unit_cost_at_sale), 0::numeric) = 0::numeric THEN true
                    WHEN round((COALESCE(sum(od.total_price), 0::numeric) - COALESCE(sum(od.unit_cost_at_sale), 0::numeric)) / NULLIF(COALESCE(sum(od.total_price), 0::numeric), 0::numeric) * 100::numeric, 1) < 0::numeric THEN true
                    WHEN round((COALESCE(sum(od.total_price), 0::numeric) - COALESCE(sum(od.unit_cost_at_sale), 0::numeric)) / NULLIF(COALESCE(sum(od.total_price), 0::numeric), 0::numeric) * 100::numeric, 1) > 90::numeric THEN true
                    ELSE false
                END AS data_warning,
            cch.chain_id,
            cch.chain_name
           FROM public.customers c
             JOIN public.orders o ON o.customer_id = c.customer_id
             JOIN order_revenue orv ON orv.order_id = o.order_id AND orv.order_total > 0::numeric AND orv.order_cogs > 0::numeric
             JOIN public.order_details od ON od.order_id = o.order_id
             LEFT JOIN public.customer_chain cch ON cch.chain_id = c.chain_id AND cch.company_id = c.company_id
          WHERE o.order_status <> 'Canceled'::text
          GROUP BY c.customer_id, c.name_company, c.company_id, cch.chain_id, cch.chain_name) v
  WHERE public.auth_is_team_member();

comment on view public.customer_revenue is
  'Revenue per CUSTOMER, every non-Canceled line, no cost filter. chain_id and chain_name are the chain that customer is a store of, NULL for the 2,092 that stand alone. Rows are never rolled up here: group by chain_id in the caller when you want the account, leave it alone when you want the store.';

comment on view public.customer_profitability is
  'Margin per CUSTOMER. Deliberately requires a cost on the order, which means it HIDES revenue on un-costed orders -- use customer_revenue for "what did they buy". chain_id and chain_name are the chain that customer is a store of, NULL when it stands alone, and rows are never rolled up here.';

-- ── gross_margin_report ─────────────────────────────────────────────────
--
-- 🔴 THE BEFORE PICTURE OF THE RPC, AND WHY IT TAKES A JWT TO GET ONE. The
-- first draft of this file asserted the row shape of the two VIEWS and never
-- the function's, and that is exactly where it broke a report: the chain
-- columns were in the GROUP BY and the by-customer grouping silently split
-- duplicate-named customers into two rows. Nothing here would have said so.
--
-- The function cannot be snapshotted as the migration role. Its tenant fence
-- is `o.company_id in (select public.auth_company_ids())`, which reads
-- auth.uid(), and a migration has no JWT, so it returns ZERO rows and an
-- empty-to-empty comparison would pass whatever the body did. So this borrows
-- the probe shape from 20260925000003: set request.jwt.claims for the
-- transaction, which is what auth.uid() reads, take the snapshot, clear it.
--
-- 🔴 AND IT NEVER DOES `set local role`. 20260921000001 records what happens:
-- the role did not come back cleanly, the CLI's own INSERT into
-- supabase_migrations was refused, and the change committed without the
-- version being recorded. Setting the claim changes no privileges, only what
-- auth.uid() answers, which is all this probe needs.
do $snapshot$
declare
  v_user text;
begin
  -- Any active login whose company has orders. Picked by query, never by id:
  -- a probe that needs one tenant's data is a probe that fails on staging.
  select t.auth_user_id::text into v_user
    from public.team t
   where t.auth_user_id is not null
     and coalesce(t.is_active, true)
     and exists (select 1 from public.orders o where o.company_id = t.company_id)
   limit 1;

  create temporary table _margin_probe on commit drop as select v_user as auth_user_id;

  create temporary table _margin_before on commit drop as
    select null::date as period, null::text as group_label, null::numeric as revenue,
           null::numeric as cogs, null::bigint as orders
     where false;

  if v_user is null then
    raise notice 'no active login with orders here; the by-customer row shape cannot be compared';
    return;
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  insert into _margin_before
    select period, group_label, revenue, cogs, orders
      from public.gross_margin_report(
             (select min(order_date) from public.orders),
             (select max(order_date) from public.orders),
             'month', 'customer', true);
  perform set_config('request.jwt.claims', null, true);
end;
$snapshot$;

-- Dropped and recreated because the two new columns change the return type and
-- CREATE OR REPLACE FUNCTION refuses that. No CASCADE: nothing in the database
-- depends on this function, checked on pg_depend and on prosrc across every
-- function in public.
drop function if exists public.gross_margin_report(date, date, text, text, boolean);

CREATE OR REPLACE FUNCTION public.gross_margin_report(p_from date, p_to date, p_interval text DEFAULT 'month'::text, p_group text DEFAULT 'total'::text, p_exclude_imported boolean DEFAULT true)
 RETURNS TABLE(period date, group_label text, revenue numeric, cogs numeric, orders bigint, chain_id text, chain_name text)
 LANGUAGE sql
 STABLE
AS $function$
  select date_trunc(
           case when p_interval in ('day','week','month','quarter','year')
                then p_interval else 'month' end,
           o.order_date::timestamp)::date as period,
         case p_group
           when 'product_type' then coalesce(pt.product_type, 'Untyped')
           when 'customer'     then coalesce(c.name_company, 'Unknown')
           when 'channel'      then coalesce(ch.channel, 'No channel')
           else 'Total'
         end as group_label,
         coalesce(sum(od.total_price), 0)       as revenue,
         coalesce(sum(od.unit_cost_at_sale), 0) as cogs,
         count(distinct o.order_id)             as orders,
         -- 🔴 AGGREGATED, NEVER GROUPED BY. These two must not reach the
         -- GROUP BY list, and the first draft of this file put them there as
         -- output columns 6 and 7, which SPLIT the shipped p_group =
         -- 'customer' report. group_label for that grouping is
         -- coalesce(c.name_company, 'Unknown'), and a name is not a key:
         -- company R7CbqHmA1j has ten duplicate (company_id, name_company)
         -- pairs, two customers both called 'Andaz' among them. Chain
         -- membership belongs to the customer_id, not to the name, so putting
         -- it in the GROUP BY turned one row into two rows carrying the SAME
         -- label and half the revenue each. Adding a column to a report must
         -- not change the rows the report already returns.
         --
         -- Aggregating also keeps 'total', 'product_type' and 'channel' whole:
         -- a chain in the GROUP BY would split every period into one row per
         -- chain and the Total line would stop being a total.
         --
         -- 🔴 AND ONLY WHEN THE GROUP HAS ONE CHAIN BEHIND IT. min() alone
         -- would be worse than the split: min() skips NULLs, so a bucket that
         -- merged 'Andaz' the Kraken store with 'Andaz' the standalone would
         -- hand the standalone's revenue to Kraken and overstate the account
         -- this feature exists to measure. count(chain_id) = count(*) says
         -- every line in the bucket is in a chain; count(distinct) = 1 says it
         -- is the same one. Anything else leaves chain_id NULL, and
         -- rollUpMarginToChain then keys that row as a store under its own
         -- label, which is the honest answer for an ambiguous name.
         --
         -- Qualified by the alias so the OUT parameters of the same name
         -- cannot capture them.
         case when p_group = 'customer'
                   and count(cch.chain_id) = count(*)
                   and count(distinct cch.chain_id) = 1
              then min(cch.chain_id)   end as chain_id,
         case when p_group = 'customer'
                   and count(cch.chain_id) = count(*)
                   and count(distinct cch.chain_id) = 1
              then min(cch.chain_name) end as chain_name
  from public.order_details od
  join public.orders o on o.order_id = od.order_id
  left join public.products p       on p.product_id = od.product_id
  left join public.product_type pt  on pt.product_type_id = p.product_type
  left join public.channel ch       on ch.channel_id = p.channel
  left join public.customers c      on c.customer_id = o.customer_id
  -- LEFT, like every other join here. 2,092 of 2,123 customers have no chain
  -- and an inner join would delete them from every grouping including 'total'.
  -- 🔴 AND MATCHED ON company_id AS WELL AS chain_id. The FK only requires the
  -- chain row to exist, not that it belongs to this customer's roastery, and
  -- nothing in 20261003000010 constrains that beyond an apply-time assertion.
  -- Without the predicate this is a tenant-crossing join in a tenant-scoped
  -- report: a service_role reader (rolbypassrls) would see another roaster's
  -- chain_name on this roaster's row, and a user who is a member of two
  -- companies would see company A's revenue folded under company B's chain.
  left join public.customer_chain cch
         on cch.chain_id = c.chain_id and cch.company_id = c.company_id
  where o.company_id in (select public.auth_company_ids())
    and o.order_status <> 'Canceled'
    and coalesce(o.invoice_state, '') not in ('void', 'written_off')
    and o.order_date >= p_from
    and o.order_date <= p_to
    and (not p_exclude_imported or not coalesce(o.is_legacy_import, false))
  group by 1, 2
  order by 1, 2;
$function$;

comment on function public.gross_margin_report(date, date, text, text, boolean) is
  'Revenue, COGS and order count over a range, grouped by total, product_type, customer or channel. There is deliberately no chain grouping: the function NAMES the chain on each customer row (chain_id, chain_name) and the caller folds, because a collapsed row cannot be un-collapsed and both readings are needed. The two chain columns are aggregated, never grouped by, so they cannot split a row; they are NULL on the other groupings, and NULL on a customer row whose label covers more than one chain, since name_company is not unique.';

-- 🔴 Stated, not inherited. A recreated function picks up schema public''s
-- default ACL, and whether that includes `anon` depends on which role db-push
-- connected as. See [[gotcha_revoke_from_public_does_not_revoke_from_authenticated]]:
-- Supabase grants EXECUTE to roles BY NAME, so revoking from PUBLIC alone
-- revokes nothing that matters.
revoke all on function public.gross_margin_report(date, date, text, text, boolean) from public;
revoke all on function public.gross_margin_report(date, date, text, text, boolean) from anon;
grant execute on function public.gross_margin_report(date, date, text, text, boolean) to authenticated, service_role;

do $verify$
declare
  v_bad int;
  v_before int;
  v_after int;
  v_view text;
  v_src text;
  v_opts text;
  v_user text;
begin
  -- ══ 1. The leak that has happened before ══════════════════════════════
  -- Both views ran with security_invoker = true before this file. If either
  -- comes out of the replace without it, it is running as postgres, who owns
  -- customers and orders and therefore skips their RLS, and it returns every
  -- tenant's revenue to every signed-in user.
  foreach v_view in array array['customer_revenue', 'customer_profitability'] loop
    select array_to_string(c.reloptions, ',') into v_opts
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_view;
    if coalesce(v_opts, '') not ilike '%security_invoker=true%' then
      raise exception 'view % lost security_invoker (reloptions = %); it is now reading every tenant',
        v_view, coalesce(v_opts, 'null');
    end if;

    -- And no policy-free path opened up underneath. Asked with
    -- has_table_privilege rather than read off information_schema, because the
    -- information_schema views only show grants involving roles the current
    -- user is a member of, and the answer that matters is the one the planner
    -- would give. anon held nothing on either view before.
    if has_table_privilege('anon', 'public.' || v_view, 'SELECT') then
      raise exception 'anon can now select from %; it could not before', v_view;
    end if;
  end loop;

  -- The replace kept the grant the app relies on. A view the frontend cannot
  -- select from fails as an empty customers list, not as an error.
  if not has_table_privilege('authenticated', 'public.customer_revenue', 'SELECT')
     or not has_table_privilege('authenticated', 'public.customer_profitability', 'SELECT') then
    raise exception 'authenticated lost SELECT on one of the revenue views';
  end if;

  -- ══ 2. The columns actually arrived ═══════════════════════════════════
  select count(*) into v_bad
    from (values ('customer_revenue'), ('customer_profitability')) t(v)
   cross join (values ('chain_id'), ('chain_name')) k(c)
   where not exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = t.v and column_name = k.c);
  if v_bad > 0 then
    raise exception '% of the 4 chain columns are missing from the revenue views', v_bad;
  end if;

  -- ══ 2b. 🔴 The view joins are fenced to the customer's company ═══════
  -- Asserted on the stored definition, because the row comparison below cannot
  -- see it: that comparison deliberately excludes the two new columns, and a
  -- cross-tenant chain_name changes only those. Without the predicate the join
  -- is tenant-crossing in a tenant-scoped report, and the FK does not stop a
  -- chain_id from another company being stored.
  foreach v_view in array array['customer_revenue', 'customer_profitability'] loop
    if pg_get_viewdef(('public.' || v_view)::regclass, true) not ilike '%cch.company_id = c.company_id%' then
      raise exception 'the chain join in % is not fenced to the customer''s company', v_view;
    end if;
  end loop;

  -- And no row carries one today. A tautology on a clean database, which is the
  -- point: the day it stops being one, a roaster sees another roaster's account
  -- name on their own revenue line.
  select count(*) into v_bad from (
    select 1 from public.customer_revenue r
      join public.customer_chain ch on ch.chain_id = r.chain_id
     where ch.company_id is distinct from r.company_id
    union all
    select 1 from public.customer_profitability pr
      join public.customer_chain ch on ch.chain_id = pr.chain_id
     where ch.company_id is distinct from pr.company_id
  ) d;
  if v_bad > 0 then
    raise exception '% revenue row(s) name a chain belonging to another company', v_bad;
  end if;

  -- ══ 3. 🔴 NOT ONE NUMBER MOVED ════════════════════════════════════════
  -- The assertion that proves the join is LEFT and that the GROUP BY did not
  -- split or collapse a customer. Compared row by row in both directions
  -- against the snapshot, so a dropped customer and an invented one both fail.
  select count(*) into v_before from _revenue_before;
  select count(*) into v_after  from public.customer_revenue;
  if v_before <> v_after then
    raise exception 'customer_revenue went from % row(s) to %; a reporting column must change neither', v_before, v_after;
  end if;
  select count(*) into v_bad from (
    (select customer_id, company_id, total_orders, revenue from _revenue_before
     except
     select customer_id, company_id, total_orders, revenue from public.customer_revenue)
    union all
    (select customer_id, company_id, total_orders, revenue from public.customer_revenue
     except
     select customer_id, company_id, total_orders, revenue from _revenue_before)
  ) d;
  if v_bad > 0 then
    raise exception '% customer_revenue row(s) changed; adding chain columns must change no number', v_bad;
  end if;

  select count(*) into v_before from _profitability_before;
  select count(*) into v_after  from public.customer_profitability;
  if v_before <> v_after then
    raise exception 'customer_profitability went from % row(s) to %; a reporting column must change neither', v_before, v_after;
  end if;
  select count(*) into v_bad from (
    (select customer_id, customer_name, company_id, total_orders, revenue,
            cogs, gross_profit, margin_pct, data_warning from _profitability_before
     except
     select customer_id, customer_name, company_id, total_orders, revenue,
            cogs, gross_profit, margin_pct, data_warning from public.customer_profitability)
    union all
    (select customer_id, customer_name, company_id, total_orders, revenue,
            cogs, gross_profit, margin_pct, data_warning from public.customer_profitability
     except
     select customer_id, customer_name, company_id, total_orders, revenue,
            cogs, gross_profit, margin_pct, data_warning from _profitability_before)
  ) d;
  if v_bad > 0 then
    raise exception '% customer_profitability row(s) changed; the COGS join was not to be touched', v_bad;
  end if;

  -- One chain per customer, or the row count above was a coincidence.
  -- customers.chain_id references a primary key, so this is a tautology today;
  -- it is asserted because the day it stops being true, both views start
  -- double-counting revenue and nothing else would say so.
  select count(*) into v_bad from (
    select chain_id from public.customer_chain group by chain_id having count(*) > 1
  ) d;
  if v_bad > 0 then
    raise exception '% chain id(s) appear more than once; the revenue views would double-count', v_bad;
  end if;

  -- ══ 4. gross_margin_report came back exactly as it was, plus two ══════
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'gross_margin_report') then
    raise exception 'gross_margin_report was dropped and not recreated';
  end if;

  select count(*) into v_bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report';
  if v_bad <> 1 then
    raise exception 'there are % gross_margin_report overloads; the drop targeted the wrong signature', v_bad;
  end if;

  -- Signature, volatility, security and search_path, each read off prod before
  -- the drop and asserted here. STABLE because the planner may inline it;
  -- INVOKER because the tenant fence is auth_company_ids() inside the body and
  -- a DEFINER function would run that as postgres; proconfig NULL because it
  -- had none and adding one changes how every table name in the body resolves.
  select pg_get_function_identity_arguments(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report';
  if v_src <> 'p_from date, p_to date, p_interval text, p_group text, p_exclude_imported boolean' then
    raise exception 'gross_margin_report signature changed to (%)', v_src;
  end if;

  select count(*) into v_bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report'
     and (p.provolatile <> 's' or p.prosecdef or p.proconfig is not null or not p.proretset);
  if v_bad > 0 then
    raise exception 'gross_margin_report came back with a different volatility, security setting or search_path';
  end if;

  -- All three defaults survived. A lost default turns the RPC into a 400 for a
  -- caller that omits p_exclude_imported.
  select count(*) into v_bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report' and p.pronargdefaults = 3;
  if v_bad <> 1 then
    raise exception 'gross_margin_report lost its parameter defaults';
  end if;

  -- The two new columns are on the return type, at the end, after the five the
  -- caller already types.
  select pg_get_function_result(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report';
  if v_src <> 'TABLE(period date, group_label text, revenue numeric, cogs numeric, orders bigint, chain_id text, chain_name text)' then
    raise exception 'gross_margin_report returns %, which is not the five original columns plus the two chain ones', v_src;
  end if;

  -- ══ 5. 🔴 The body was edited, not retyped ════════════════════════════
  -- Every clause that makes the margin number right, asserted by text. These
  -- are the ones a reconstruction from the call sites would have lost, and
  -- losing any of them inflates revenue with no error: a voided invoice or the
  -- whole QuickBooks import would start counting as sales.
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gross_margin_report';
  if v_src not like '%o.company_id in (select public.auth_company_ids())%' then
    raise exception 'the tenant fence is gone from gross_margin_report';
  end if;
  if v_src not like '%o.order_status <> ''Canceled''%' then
    raise exception 'the Canceled-order filter is gone from gross_margin_report';
  end if;
  if v_src not like '%coalesce(o.invoice_state, '''') not in (''void'', ''written_off'')%' then
    raise exception 'the void / written-off filter is gone from gross_margin_report';
  end if;
  if v_src not like '%not p_exclude_imported or not coalesce(o.is_legacy_import, false)%' then
    raise exception 'the legacy-import filter is gone from gross_margin_report';
  end if;
  if v_src not like '%left join public.customer_chain%' then
    raise exception 'the chain join is not a LEFT join in gross_margin_report';
  end if;
  -- 🔴 And the chain join is fenced to the customer's own company. Without
  -- this predicate one roaster's chain_name lands on another roaster's row for
  -- any reader that bypasses RLS, and for a user who belongs to two companies.
  if v_src not like '%cch.company_id = c.company_id%' then
    raise exception 'the chain join in gross_margin_report is not fenced to the customer''s company';
  end if;

  -- 🔴 NO 'chain' GROUPING, AND THE CHAIN COLUMNS ARE NOT IN THE GROUP BY.
  -- Both halves of the defect this file shipped in draft. A `when 'chain'`
  -- branch is dead code the frontend can never reach (MarginReport maps the
  -- chain view to 'customer' and folds the rows itself), and a chain column in
  -- the GROUP BY splits the by-customer report wherever two customers share a
  -- name. Asserted by text because the row-shape comparison below can only
  -- catch the second one, and only on a database that HAS a duplicate name.
  if v_src like '%when ''chain''%' then
    raise exception 'gross_margin_report has a chain grouping again; no caller can reach it and it is a second roll-up path';
  end if;
  -- Matched as a clause, GROUP BY immediately followed by ORDER BY, rather than
  -- as a substring: a text assertion that can be satisfied or broken by a
  -- COMMENT inside the body is not an assertion. Adding a third grouping
  -- expression breaks the match and fails here.
  if v_src !~ 'group by 1, 2\s+order by 1, 2' then
    raise exception 'gross_margin_report groups by something other than period and label; a reporting column must not split a row';
  end if;

  -- ══ 5b. 🔴 The by-customer report returns the SAME rows it did ════════
  -- The assertion the first draft did not have. Compared in both directions
  -- against the snapshot taken under the same borrowed JWT, so a split row, a
  -- lost row and a moved number all fail here. Chain membership is a property
  -- of the customer_id and NEVER of group_label, which is a name: company
  -- R7CbqHmA1j has ten duplicate (company_id, name_company) pairs.
  select auth_user_id into v_user from _margin_probe;
  if v_user is null then
    raise notice 'no login was available for the by-customer comparison; the structural checks above stand alone';
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    create temporary table _margin_after on commit drop as
      select period, group_label, revenue, cogs, orders
        from public.gross_margin_report(
               (select min(order_date) from public.orders),
               (select max(order_date) from public.orders),
               'month', 'customer', true);
    perform set_config('request.jwt.claims', null, true);

    select count(*) into v_before from _margin_before;
    select count(*) into v_after  from _margin_after;
    if v_before <> v_after then
      raise exception 'the by-customer margin report went from % row(s) to %; naming the chain must not change the rows', v_before, v_after;
    end if;
    select count(*) into v_bad from (
      (select * from _margin_before except all select * from _margin_after)
      union all
      (select * from _margin_after except all select * from _margin_before)
    ) d;
    if v_bad > 0 then
      raise exception '% by-customer margin row(s) changed; naming the chain must change no number', v_bad;
    end if;
  end if;

  -- ══ 6. The grants, stated rather than inherited ═══════════════════════
  if not has_function_privilege('authenticated',
       'public.gross_margin_report(date, date, text, text, boolean)', 'EXECUTE') then
    raise exception 'authenticated cannot execute gross_margin_report; the margin report is dead for every user';
  end if;
  if has_function_privilege('anon',
       'public.gross_margin_report(date, date, text, text, boolean)', 'EXECUTE') then
    raise exception 'anon can execute gross_margin_report; the recreate inherited a wider default ACL';
  end if;

  raise notice 'chain axis added: customer_revenue % rows, customer_profitability % rows, both security_invoker, gross_margin_report recreated with 7 output columns',
    (select count(*) from public.customer_revenue),
    (select count(*) from public.customer_profitability);
end;
$verify$;

commit;
