-- The chain policy names the key.
--
-- 🔴 THIS CLOSES A HOLE, it is not tidying. 20261003000010 shipped
-- customer_chain with one policy:
--
--     create policy tenant_company_access on public.customer_chain
--       for all to authenticated
--       using      (company_id in (select public.auth_company_ids()))
--       with check (company_id in (select public.auth_company_ids()));
--     grant select, insert, update, delete on public.customer_chain to authenticated;
--
-- FOR ALL, with no role and no key in it. So any member of the tenant can
-- create a chain, rename one, retire one or delete one straight through
-- PostgREST, whatever their role: a sales_person, a staff login, a roastmaster.
-- customers.chain_id rides the customers table's own FOR ALL tenant policy the
-- same way. 20261004000001 created `customer.chain_manage` and the server
-- action calls requirePermission() on it, but a server action is not a fence.
-- /rest/v1/customer_chain is reachable by every signed-in browser with the
-- anon key and the user's own JWT, and nothing on that path runs the action.
--
-- This is the same class as the hole where any authenticated user could rewrite
-- their own team row, including its company_id. A chain decides which customer
-- rows roll up together in every revenue and margin report, so a member who can
-- rewrite it can rewrite what the owner sees the business earning.
--
-- ── What a chain write is worth, so the gate is the right size ───────────
--
-- READS STAY OPEN TO THE WHOLE TENANT. The chain name is shown on the customer
-- list, the customer detail page and the margin report, and
-- accounting/chainMembership.ts reads it for the report fold while deliberately
-- NOT asking for customer.chain_manage, because reading who an account is has
-- nothing to do with being allowed to redraw it. Gating the read would empty
-- those surfaces for everybody below manager, in silence, since RLS refuses by
-- returning zero rows rather than an error.
--
-- WRITES REQUIRE customer.chain_manage: company_admin, facility_admin, manager.
-- The same three that may merge customers, which is the same kind of act.
--
-- ── The mechanism is the one this schema already uses ────────────────────
--
-- Not invented here. 20260910000025 (M11 phase 2, tranche 1) converted 41
-- tables from a bare tenant policy to exactly this shape, and the helper is
-- public.auth_has_permission(key, company_id), which already resolves the role
-- rows, the plan gate, the module switch and the terminal narrowing:
--
--     <table>_tenant_read     for select, tenant only
--     <table>_write_insert    for insert, tenant and the key
--     <table>_write_update    for update, tenant and the key, both sides
--     <table>_write_delete    for delete, tenant and the key
--
-- 🔴 AND THE FOR ALL POLICY HAS TO GO, not just be joined by the four. Policies
-- for the same command OR together, so a surviving permissive FOR ALL would
-- grant every write on its own and these four would be decoration. The verify
-- block refuses to commit while one exists, which is the assertion tranche 1
-- ends with for the same reason.
--
-- ── customers.chain_id cannot be done with a policy ──────────────────────
--
-- The hole on the customers side is one COLUMN of a table that must stay
-- writable by every role that edits a customer, and a policy is per ROW. The
-- shape this schema uses for that is a guard trigger: guard_order_invoice_columns
-- gates the invoice columns on orders, guard_team_privileged_columns gates role
-- and company_id on team. This adds the third, for one column.
--
-- Each of those starts `if auth.uid() is null then return new; end if;` and so
-- does this one. Service role, cron, the QuickBooks import and a migration have
-- no JWT, they are already trusted, and they are not what this closes. Checked
-- before relying on it: no function in public names chain_id, so no SECURITY
-- INVOKER trigger writes this column and none can be turned into a silent
-- zero-row failure by gating it, which is the trap tranche 1 documents.
--
-- It also asserts the chain is one of the CUSTOMER'S OWN company's chains. The
-- FK only requires the chain row to exist. 20261003000010 checks company match
-- once, at apply time, which is an assertion and not a constraint, and
-- 20261004000003 had to fence all three report joins on company_id because of
-- it. Refusing the write is the half that stops the bad value being stored at
-- all, and it is only that half: the auth.uid() carve-out means a service-role
-- or cron write is not judged here, so the company_id predicates on the three
-- report joins in 20261004000003 stay load-bearing rather than belt and braces.
--
-- Deliberately NOT done with a composite FK on (chain_id, company_id):
-- that would give customers.chain_id a second foreign key, and a PostgREST
-- embed over a column with two FKs is a 400 (the orders/customers embed
-- gotcha), which accounting/chainMembership.ts is written around today.
--
-- 🔴 AND THE COLUMN HAS NO UPDATE GRANT AT ALL, which is a separate defect this
-- file has to fix or the feature is dead on arrival. Measured on prod:
-- `authenticated` holds SELECT, INSERT and DELETE on public.customers at TABLE
-- level, but UPDATE only on 63 NAMED COLUMNS (the 20260908000034 lesson, which
-- held back merge_into_id and provider_vault_customer_id). A column added by
-- ALTER TABLE gets no privilege, so chain_id arrived updatable by nobody.
-- Proved on a throwaway cluster carrying the same grant arrangement:
-- has_column_privilege('authenticated','customers','<new column>','UPDATE') is
-- false while SELECT and INSERT are true. setCustomerChain would have failed
-- for the company_admin who owns the tenant with `permission denied for table
-- customers`, which is both a dead feature and raw Postgres text in front of a
-- user. SELECT needs nothing: it is granted at table level, which is also what
-- keeps customer_revenue and customer_profitability readable, since
-- security_invoker views check the invoker's privileges on the base columns.
--
-- INSERT is left alone on purpose. No path creates a customer with a chain
-- already set (the only writer of this column is setCustomerChain, an update),
-- and a grant nothing needs is a grant nobody audits.
--
-- ── The refusal messages are UI copy, which is why they read like it ────
--
-- A policy refuses a write in two different ways and the user sees both. An
-- UPDATE or DELETE that matches no row comes back with NO error and zero rows,
-- which chains/actions.ts already handles: every write there selects a column
-- and shows "Nothing changed. Your role cannot make that change here." An
-- INSERT refused by WITH CHECK, though, raises 42501 and PostgREST hands the
-- caller the sentence `new row violates row-level security policy for table
-- "customer_chain"`, which createChain would print as-is. That string is raw
-- Postgres text in front of a user and
-- [[feedback_warnings_must_make_sense_to_the_user]] says it must not ship, so
-- createChain needs 42501 mapped onto the same refusal copy it uses for the
-- zero-row case. That is a frontend change and is not in this file.
--
-- The guard trigger below is the other half of the same rule, and it is the
-- reason its two RAISE messages are written as sentences rather than as
-- diagnostics: a trigger exception IS what the user reads. "You may not change
-- which chain a customer belongs to." and "That chain belongs to a different
-- roastery." both reach setCustomerChain as error.message and are shown.
--
-- ── One dry note on the plan gate ───────────────────────────────────────
-- customer.chain_manage is is_plan_gated, so auth_has_permission also requires
-- the tenant's plan to grant it. Every plan does (20261004000001 inserts a row
-- for each), but a company whose company_subscription_status carries a NULL
-- plan_id resolves to no plan and is therefore refused. shopify-test-company-001
-- is in that state on prod today, as it already is for the other 70 plan-gated
-- keys. Nothing to fix here; stated so the next reader does not rediscover it
-- as a chain bug.

begin;

do $precondition$
begin
  -- Both halves have to be in place first, and in this order, or the result is
  -- a policy that denies everybody in silence.
  if to_regclass('public.customer_chain') is null then
    raise exception 'public.customer_chain does not exist; apply 20261003000010 before this file';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'customers'
                    and column_name = 'chain_id') then
    raise exception 'public.customers.chain_id does not exist; apply 20261003000010 before this file';
  end if;
  -- 🔴 An unregistered permission_id is DENIED for every role, so a policy that
  -- names a key the permissions table does not carry locks the feature for the
  -- whole tenant with no error anywhere. That is the other direction of
  -- [[feedback_key_and_policy_must_agree]] and it fails here instead.
  if not exists (select 1 from public.permissions
                  where permission_id = 'customer.chain_manage') then
    raise exception 'customer.chain_manage is not registered; apply 20261004000001 before this file, or this policy denies every role';
  end if;
end;
$precondition$;

-- ── customer_chain: one open read, three gated writes ───────────────────
-- Each name dropped first, so a re-push after a failed one applies rather than
-- erroring on a policy that is already half there.
drop policy if exists tenant_company_access       on public.customer_chain;
drop policy if exists customer_chain_tenant_read  on public.customer_chain;
drop policy if exists customer_chain_write_insert on public.customer_chain;
drop policy if exists customer_chain_write_update on public.customer_chain;
drop policy if exists customer_chain_write_delete on public.customer_chain;

create policy customer_chain_tenant_read on public.customer_chain
  for select to authenticated
  using (company_id in (select public.auth_company_ids()));

create policy customer_chain_write_insert on public.customer_chain
  for insert to authenticated
  with check ((company_id in (select public.auth_company_ids()))
              and public.auth_has_permission('customer.chain_manage', company_id));

-- Both sides. USING decides which rows may be touched, WITH CHECK decides what
-- they may become; without the second half a manager could move a chain into
-- another company by rewriting company_id, which is precisely the shape of the
-- team-row hole.
create policy customer_chain_write_update on public.customer_chain
  for update to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('customer.chain_manage', company_id))
  with check ((company_id in (select public.auth_company_ids()))
              and public.auth_has_permission('customer.chain_manage', company_id));

-- The app offers RETIRE, not delete (is_active), because deleting would have to
-- decide what happens to the stores pointing at the chain. This policy is the
-- backstop for the REST endpoint rather than a feature: the grant from
-- 20261003000010 exists, so the command needs a gate the same as the others.
create policy customer_chain_write_delete on public.customer_chain
  for delete to authenticated
  using ((company_id in (select public.auth_company_ids()))
         and public.auth_has_permission('customer.chain_manage', company_id));

-- ── customers.chain_id: the grant, then the guard ───────────────────────
-- Column-level, to match how UPDATE is granted on this table. A blanket
-- `grant update on public.customers` would hand `authenticated` the two columns
-- 20260908000034 deliberately withheld.
grant update (chain_id) on public.customers to authenticated;

create or replace function public.guard_customer_chain_column()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_ins boolean := (tg_op = 'INSERT');
begin
  -- Service role, cron, the import and migrations have no JWT. They are
  -- already trusted and they are not the hole this closes.
  if auth.uid() is null then return new; end if;

  -- Nothing to say unless the chain pointer is actually being set or moved. An
  -- UPDATE that merely names chain_id with the value it already has is the
  -- common case from a form post, and it is not a chain change.
  if v_ins then
    if new.chain_id is null then return new; end if;
  elsif new.chain_id is not distinct from old.chain_id then
    return new;
  end if;

  if not public.auth_has_permission('customer.chain_manage', new.company_id) then
    raise exception 'You may not change which chain a customer belongs to.'
      using errcode = 'insufficient_privilege';
  end if;

  -- 🔴 The chain has to belong to this customer's own roastery. The foreign key
  -- only requires the chain row to exist, so without this a member could point
  -- their customer at another tenant's chain and that tenant's chain_name would
  -- surface in reports that join on chain_id.
  if new.chain_id is not null and not exists (
       select 1 from public.customer_chain ch
        where ch.chain_id = new.chain_id
          and ch.company_id = new.company_id) then
    raise exception 'That chain belongs to a different roastery.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$function$;

comment on function public.guard_customer_chain_column() is
  'Gates customers.chain_id on customer.chain_manage, and refuses a chain belonging to another company. The row policy on customers has to stay open to every role that edits a customer, so this one column is guarded here instead. Same shape as guard_order_invoice_columns and guard_team_privileged_columns, including the auth.uid() is null carve-out for service role, cron and migrations.';

-- UPDATE OF chain_id, so an ordinary customer edit and the order triggers that
-- rewrite customer metrics do not pay for this at all. The column cannot change
-- without the statement naming it. Same shape as customers_payment_terms_available.
-- zzz_ prefix for the same reason the other guards carry it: BEFORE triggers run
-- in name order and a guard belongs after the triggers that derive values.
drop trigger if exists zzz_guard_customer_chain_column on public.customers;
create trigger zzz_guard_customer_chain_column
  before insert or update of chain_id on public.customers
  for each row execute function public.guard_customer_chain_column();

do $verify$
declare
  v_bad     int;
  v_roles   int;
  v_user    text;
  v_company text;
  v_can     boolean;
begin
  -- ══ 1. One read policy, and it carries no key ═════════════════════════
  -- Gating the read would blank the chain name on every customer surface for
  -- everybody below manager, and it would do it by returning zero rows.
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'customer_chain'
         and cmd = 'SELECT') <> 1 then
    raise exception 'customer_chain does not have exactly one SELECT policy';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'customer_chain'
                and cmd = 'SELECT' and coalesce(qual, '') like '%auth_has_permission%') then
    raise exception 'the customer_chain read policy demands a permission; the chain name is shown to every role';
  end if;

  -- ══ 2. Three write policies, each naming the key ══════════════════════
  select count(*) into v_bad from pg_policies
   where schemaname = 'public' and tablename = 'customer_chain'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')
     and coalesce(qual, '') || coalesce(with_check, '') like '%auth_has_permission(''customer.chain_manage''%';
  if v_bad <> 3 then
    raise exception 'customer_chain has % gated write policies, not 3', v_bad;
  end if;

  -- 🔴 And no FOR ALL survivor. Policies for a command OR together, so one
  -- permissive FOR ALL would allow every write by itself and make the three
  -- above decoration. This is the assertion tranche 1 ends with.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'customer_chain' and cmd = 'ALL') then
    raise exception 'a FOR ALL policy survived on customer_chain; it would OR the permission gate away';
  end if;

  -- The UPDATE policy has both halves. USING alone would let a chain be
  -- rewritten into another company.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'customer_chain'
                and cmd = 'UPDATE' and with_check is null) then
    raise exception 'the customer_chain UPDATE policy has no WITH CHECK; company_id could be rewritten';
  end if;

  -- Nothing reaches anon, and authenticated kept the grants the policies gate.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'customer_chain' and 'anon' = any(roles)) then
    raise exception 'a customer_chain policy admits anon';
  end if;
  if has_table_privilege('anon', 'public.customer_chain', 'SELECT') then
    raise exception 'anon can select from customer_chain';
  end if;
  if not has_table_privilege('authenticated', 'public.customer_chain', 'SELECT')
     or not has_table_privilege('authenticated', 'public.customer_chain', 'INSERT')
     or not has_table_privilege('authenticated', 'public.customer_chain', 'UPDATE') then
    raise exception 'authenticated lost a grant on customer_chain; the policies would gate nothing and the Chains surface would 403';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.customer_chain'::regclass and relrowsecurity) then
    raise exception 'row level security is not enabled on customer_chain';
  end if;

  -- ══ 3. 🔴 The key and the policy admit the same people ════════════════
  -- Both directions fail silently, so both are asserted. The policy names
  -- customer.chain_manage; this is the other end of that name.
  select count(*) into v_roles from public.role_permissions
   where permission_id = 'customer.chain_manage' and granted;
  if v_roles = 0 then
    raise exception 'customer.chain_manage is granted to no role, so these policies refuse every write';
  end if;
  select count(*) into v_bad from public.subscription_plans p
   where not exists (select 1 from public.plan_permissions pp
                      where pp.plan_id = p.plan_id
                        and pp.permission_id = 'customer.chain_manage' and pp.granted);
  if v_bad > 0 then
    raise exception '% plan(s) do not grant customer.chain_manage; the policy would refuse those tenants', v_bad;
  end if;

  -- ══ 4. The column is writable, and only through the guard ═════════════
  if not has_column_privilege('authenticated', 'public.customers', 'chain_id', 'UPDATE') then
    raise exception 'authenticated cannot update customers.chain_id; putting a store in a chain would fail for every role';
  end if;
  if not has_column_privilege('authenticated', 'public.customers', 'chain_id', 'SELECT') then
    raise exception 'authenticated cannot read customers.chain_id; the revenue views join on it under security_invoker';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.customers'::regclass
                    and t.tgname = 'zzz_guard_customer_chain_column'
                    and not t.tgisinternal) then
    raise exception 'the chain column guard is not attached to customers';
  end if;
  -- BEFORE, and on both commands. An AFTER trigger cannot refuse a write, and
  -- an UPDATE-only guard would let the value in through an INSERT.
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.customers'::regclass
                    and t.tgname = 'zzz_guard_customer_chain_column'
                    and (t.tgtype & 2) = 2      -- BEFORE
                    and (t.tgtype & 4) = 4      -- INSERT
                    and (t.tgtype & 16) = 16) then  -- UPDATE
    raise exception 'the chain column guard is not a BEFORE INSERT OR UPDATE trigger';
  end if;
  -- SECURITY DEFINER, or it cannot read permissions and role_permissions as the
  -- caller, and every chain assignment would fail instead of being judged.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'guard_customer_chain_column'
                    and p.prosecdef and p.proconfig is not null) then
    raise exception 'guard_customer_chain_column is not SECURITY DEFINER with a pinned search_path';
  end if;

  -- ══ 5. 🔴 Functional, in both directions, with a borrowed JWT ═════════
  -- 🔴 NOT `set local role`. 20260921000001 records what that cost: the role
  -- did not come back cleanly, the CLI's own INSERT into supabase_migrations
  -- was refused, and the change committed with no version recorded. Setting
  -- request.jwt.claims changes no privileges, only what auth.uid() answers,
  -- which is what auth_has_permission reads. The row-level refusal itself is
  -- rehearsed on a throwaway cluster, where becoming `authenticated` is free.
  --
  -- Picked by query, never by id: a probe that needs one tenant's data has
  -- failed before.
  --
  -- 🔴 The PLAN has to resolve too, and `order by` is not cosmetic.
  --
  -- This picked an unordered `limit 1` from every member whose ROLE grants the
  -- key, and customer.chain_manage is plan-gated, so auth_has_permission also
  -- needs the tenant's plan to grant it. A legitimate FALSE therefore exists in
  -- that population: shopify-test-company-001 carries a company_subscription_status
  -- row with NULL status and NULL plan_id, so its active manager resolves false
  -- for this key and for the other 70 plan-gated ones. Proved on prod: with that
  -- member's claims set inside `begin read only`, auth_has_permission returned
  -- false while the role row existed.
  --
  -- So the probe as written could abort a CORRECT migration whenever the planner
  -- happened to return that row, which nothing pins and which differs between
  -- prod and staging. The deny direction cannot false-fail (a missing role row
  -- always resolves false), which is why 20260925000003 asserts only that one.
  -- Here the fix is to ask only about members whose plan can actually grant it,
  -- and to pick deterministically so a pass today is a pass tomorrow.
  select t.auth_user_id::text, t.company_id into v_user, v_company
    from public.team t
    join public.role_permissions rp
      on rp.role_id = t.role and rp.permission_id = 'customer.chain_manage' and rp.granted
   where t.auth_user_id is not null and coalesce(t.is_active, true)
     and not coalesce(t.is_terminal, false)
     and exists (
       select 1
         from public.company_subscription_status s
         join public.plan_permissions pp
           on pp.plan_id = (case when s.status = 'trialing' then 'enterprise' else s.plan_id end)
          and pp.permission_id = 'customer.chain_manage'
          and pp.granted
        where s.company_id = t.company_id
     )
   order by t.team_member_id
   limit 1;
  if v_user is null then
    raise notice 'no active login holds customer.chain_manage with a plan that grants it; the allow direction is unproven';
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    select public.auth_has_permission('customer.chain_manage', v_company) into v_can;
    perform set_config('request.jwt.claims', null, true);
    if not v_can then
      raise exception 'a member whose role grants customer.chain_manage is refused it; these policies would lock the Chains surface for the people who own it';
    end if;
  end if;

  select t.auth_user_id::text, t.company_id into v_user, v_company
    from public.team t
   where t.auth_user_id is not null and coalesce(t.is_active, true)
     and not coalesce(t.is_terminal, false)
     and not exists (select 1 from public.role_permissions rp
                      where rp.role_id = t.role
                        and rp.permission_id = 'customer.chain_manage' and rp.granted)
   order by t.team_member_id
   limit 1;
  if v_user is null then
    raise notice 'every active login here holds customer.chain_manage; the refuse direction is unproven';
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    select public.auth_has_permission('customer.chain_manage', v_company) into v_can;
    perform set_config('request.jwt.claims', null, true);
    if v_can then
      raise exception 'a member whose role does not grant customer.chain_manage resolves to allowed; the gate is not a gate';
    end if;
  end if;

  raise notice 'customer_chain: 1 open read, 3 writes gated on customer.chain_manage (% role(s) hold it), customers.chain_id granted and guarded',
    v_roles;
end;
$verify$;

commit;
