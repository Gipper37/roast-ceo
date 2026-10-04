-- Only some people may rearrange a chain.
--
-- 20261003000010 added customer_chain and customers.chain_id with nothing but a
-- tenant policy over them, because the key this migration creates did not exist
-- yet. This is that key: `customer.chain_manage`.
--
-- 🔴 THE ORDER MATTERS AND IT IS NOT A STYLE POINT. An unknown permission_id
-- resolves to DENIED for every role, silently, with no error anywhere. So this
-- file has to land BEFORE any frontend names the key, or the Chains surface
-- renders empty for the company_admin who owns the tenant and the only symptom
-- is a button nobody can find. This is the standing rule and it is why the key
-- ships in SQL ahead of the UI rather than alongside it.
--
-- WIRED LIKE customer.merge, deliberately, because it is the same kind of act:
-- deciding that two customer rows are one business. Read off prod:
--
--     company_admin    t        starter         t
--     facility_admin   t        pro             t
--     manager          t        enterprise      t
--     accounting_admin f        enterprise_plus t
--     sales_person     f
--
-- SO WHY is_plan_gated = true WHEN ALL FOUR PLANS ARE GRANTED? Same reason
-- customer.merge carries it. The flag says the key is ALLOWED to be a plan
-- lever; the plan rows say nobody is charged for it today. Setting the flag
-- later means finding and editing a live key under a tenant that is already
-- using the feature; setting it now and granting everyone costs nothing. The
-- flag without the rows would be the dangerous combination, so both go in here.
--
-- NOT GRANTED TO accounting_admin, mirroring the merge. A chain changes which
-- customer rows roll up together in every revenue and margin report, and an
-- accounting role that cannot merge customers should not be able to redraw the
-- reporting boundary either. sales_person is out for the same reason.
--
-- NOT GRANTED TO roastery_manager, roastmaster, assistant_roaster,
-- accounting_view, equipment_tech or staff -- customer.merge has no row at all
-- for any of them, and a missing row is denied. Mirroring it exactly means
-- mirroring the silence too: adding rows customer.merge does not have would
-- make this key wider than the sibling it is modelled on, which is the kind of
-- drift [[feedback_key_and_policy_must_agree]] is about.
--
-- sort_order 70 puts it immediately after customer.merge (60) in the Customers
-- category, which is how the role matrix page orders a category
-- (idx_permissions_category_sort is on category, sort_order, permission_id).
-- Grouping and merging sit next to each other because an operator looking at
-- one is deciding between them.
--
-- feature_key stays NULL. feature_catalog is for a module a roastery turns on;
-- chains are not a module, they are a property of the customer list.
--
-- 🔴 THE KEY IS NOT THE FENCE UNTIL A POLICY NAMES IT, AND 20261004000004 IS
-- WHERE IT DOES. customer_chain's write policy, from 20261003000010, is plain
-- tenant access:
--
--     using (company_id in (select public.auth_company_ids()))
--
-- It does not name this key, so on that file alone ANY member of the tenant can
-- insert, update or delete a chain through PostgREST whatever their role, and
-- customers.chain_id rides the customers table's policy the same way. A key
-- enforced only inside a server action is not a fence: the REST endpoint is
-- public to every signed-in user and goes around requirePermission() and
-- currentUserCan() alike. That is the same class as the hole where any
-- authenticated user could rewrite their own team row, so it is not left
-- standing: 20261004000004 rewrites the policy and guards the column, and the
-- two files have to land together. This one first, because a policy that
-- demands an unregistered key denies everybody, in silence, in the other
-- direction -- which is both halves of
-- [[feedback_key_and_policy_must_agree]].

begin;

-- ── The key ─────────────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order)
values
  ('customer.chain_manage', 'Customers', 'Manage chains',
   'Create a chain and say which customers are its stores. A chain groups one business that trades from several locations, so reports can show the whole account and a product can be sold only to that chain. Orders, invoices and prices stay with the store.',
   true, 70)
-- 🔴 do update, NOT do nothing. `do nothing` cannot correct a row that is
-- already there with different attributes, and the verify block below then
-- aborts the whole file on exactly the four attributes the insert refused to
-- write (category, is_plan_gated, sort_order, feature_key). Any box where
-- somebody registered this key by hand while building the UI would be left
-- with a migration that can never apply and no way forward but manual repair.
-- The role and plan inserts below already use `do update` for this reason, and
-- so do the two nearest siblings (20260926000009, 20260929000001), which carry
-- category, label and description. This one also writes is_plan_gated,
-- sort_order and feature_key, because those are the three the verify block
-- asserts: the update list and the assertion list have to be the same list.
on conflict (permission_id) do update set
  category       = excluded.category,
  label          = excluded.label,
  description    = excluded.description,
  is_plan_gated  = excluded.is_plan_gated,
  sort_order     = excluded.sort_order,
  feature_key    = excluded.feature_key,
  updated_at     = now();

-- ── Who holds it ────────────────────────────────────────────────────────
-- Listed rather than copied from customer.merge with a join, so the file says
-- out loud who gets it and a reviewer can check it against the matrix above
-- without querying anything. The verify block below then asserts the two keys
-- resolve to the same people, which is what a list on its own cannot prove.
--
-- The `false` rows are not decoration. A missing row and a false row both deny,
-- but the matrix page renders what it finds: a false row shows the role with
-- the box unticked, which is a decision somebody made, and a missing row shows
-- nothing at all. customer.merge carries both false rows, so this does too.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',    'customer.chain_manage', true),
  ('facility_admin',   'customer.chain_manage', true),
  ('manager',          'customer.chain_manage', true),
  ('accounting_admin', 'customer.chain_manage', false),
  ('sales_person',     'customer.chain_manage', false)
on conflict (role_id, permission_id) do update set
  granted    = excluded.granted,
  updated_at = now();

-- ── Which plans ─────────────────────────────────────────────────────────
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, 'customer.chain_manage', true,
       'Chains: every plan, same as merging customers'
  from public.subscription_plans p
on conflict (plan_id, permission_id) do update set
  granted        = excluded.granted,
  updated_reason = excluded.updated_reason,
  updated_at     = now();

do $verify$
declare v_bad int; v_n int; v_merge_roles int;
begin
  -- The key is registered, and registered the way the frontend will read it.
  if not exists (select 1 from public.permissions where permission_id = 'customer.chain_manage') then
    raise exception 'customer.chain_manage was not registered; every check of it would deny silently';
  end if;

  select count(*) into v_bad from public.permissions
   where permission_id = 'customer.chain_manage'
     and (category <> 'Customers' or not is_plan_gated or sort_order <> 70 or feature_key is not null);
  if v_bad > 0 then
    raise exception 'customer.chain_manage is registered with the wrong category, plan flag, sort order or feature key';
  end if;

  -- 🔴 THE ASSERTION THAT MATTERS: it admits exactly the people customer.merge
  -- admits. Stated as a set difference in both directions rather than as a
  -- count, so neither a missing grant nor an extra one can pass.
  select count(*) into v_merge_roles from public.role_permissions where permission_id = 'customer.merge';
  if v_merge_roles = 0 then
    raise exception 'customer.merge has no role rows here, so the sibling this key was modelled on cannot be compared against';
  end if;

  select count(*) into v_bad from (
    (select role_id, granted from public.role_permissions where permission_id = 'customer.merge'
     except
     select role_id, granted from public.role_permissions where permission_id = 'customer.chain_manage')
    union all
    (select role_id, granted from public.role_permissions where permission_id = 'customer.chain_manage'
     except
     select role_id, granted from public.role_permissions where permission_id = 'customer.merge')
  ) d;
  if v_bad > 0 then
    raise exception '% role(s) differ between customer.chain_manage and customer.merge', v_bad;
  end if;

  -- Somebody can actually use it. A key granted to nobody is a feature nobody
  -- can reach, and it fails here rather than in a support message.
  select count(*) into v_n from public.role_permissions
   where permission_id = 'customer.chain_manage' and granted;
  if v_n = 0 then raise exception 'customer.chain_manage is granted to no role'; end if;

  -- Every role named is a role that exists. A grant to a role_id that does not
  -- resolve fences nobody and reads as authority on the matrix page.
  select count(*) into v_bad from public.role_permissions rp
   where rp.permission_id = 'customer.chain_manage'
     and not exists (select 1 from public.user_roles ur where ur.role_id = rp.role_id);
  if v_bad > 0 then
    raise exception '% grant(s) of customer.chain_manage name a role that does not exist', v_bad;
  end if;

  -- Plan-gated means the plan rows have to be complete, or the plan check
  -- resolves to denied on whichever plan was left out.
  select count(*) into v_bad from public.subscription_plans p
   where not exists (select 1 from public.plan_permissions pp
                      where pp.plan_id = p.plan_id
                        and pp.permission_id = 'customer.chain_manage' and pp.granted);
  if v_bad > 0 then
    raise exception '% plan(s) do not grant customer.chain_manage; a plan-gated key missing a plan row denies that plan', v_bad;
  end if;

  raise notice 'customer.chain_manage: % role row(s), % granted, all % plan(s) granted',
    (select count(*) from public.role_permissions where permission_id = 'customer.chain_manage'),
    v_n, (select count(*) from public.subscription_plans);
end;
$verify$;

commit;
