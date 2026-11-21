-- ─────────────────────────────────────────────────────────────────────────────
-- customers_update carries no permission key, and it must STAY that way.
--
-- THE HOLE. public.customers has 67 columns. The table-level ACL gives
-- `authenticated` only 'arxm' (no UPDATE), but 65 of the 67 columns carry their
-- own `authenticated=w` column grant, and the only RLS policy on UPDATE is
--
--     customers_update  using (company_id in (select auth_company_ids()))
--                  with check (company_id in (select auth_company_ids()))
--
-- which is tenancy and nothing else. customers_insert, right above it, names
-- auth_has_permission('customer.create', company_id). So a role that is denied
-- customer.edit can PATCH almost any customer column over REST with its own
-- token, bounded only by which roastery it belongs to.
--
-- Measured on prod before writing this, not assumed:
--   * 8 of 11 roles hold customer.edit. THREE DO NOT, and they hold no
--     role_permissions row for it at all, which in this schema is a silent deny
--     identical to granted=false: accounting_view, equipment_tech, staff.
--   * 4 active team members are on `staff` today. accounting_view and
--     equipment_tech have no members — today's data, not a verdict.
--   * 63 columns were reachable: 65 grantable, less payment_terms and chain_id,
--     which already carry their own guard triggers.
--   * Among them shop_access (text[], the storefront access grant that decides
--     which price list a buyer sees: {wholesale} on 462 prod customers, {vip}
--     on 5) and tax_rate_id.
-- Reproduced on a local cluster loaded from a schema-only dump of prod: a
-- session whose auth_has_permission('customer.edit') returns false set
-- shop_access to {vip} and got UPDATE 1.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 🔴 WHY THIS IS NOT FIXED BY PUTTING THE KEY IN THE POLICY.
--
-- Because it was already decided, twice, and I had forgotten both.
--
--   20260910000025:14-20 held `customers` back from a 41-table gating tranche
--   because "a trigger on table Y writes table X as the INVOKER".
--
--   20261028000019:146-151 then created this very policy tenancy-only, with the
--   comment "Deliberately NOT gated: update_customer_metrics_on_order() is
--   SECURITY INVOKER and updates this table from inside every orders write."
--   Its header names the consequence as "Breaker 1": `staff` holds order.pack
--   and delivery.mark_delivered, the cascade runs as `authenticated`, and so
--   gating the policy stops the cascade. It prescribes converting the cascades
--   to SECURITY DEFINER owned by postgres first, as its own batch.
--
-- SEVEN functions in public UPDATE public.customers. Every one of them is
-- SECURITY INVOKER (prosecdef = f), so every one runs as the caller and is
-- matched against this policy. relforcerowsecurity is false on customers, which
-- exempts SECURITY DEFINER functions and does nothing for these:
--
--   update_customer_metrics_on_order()  trigger on orders       6 cadence cols
--   recompute_all_customer_cadence()    nightly cron            same 6
--   update_customer_sales_metrics()     trigger on sales_notes  last_contact, sales_status
--   flag_customer_on_email_bounce()     trigger on email_log    email_bounced_at, email_bounce_reason
--   refresh_needs_follow_up()           callable                needs_follow_up
--   sync_primary_from_contact()         trigger on contacts     primary_contact_id
--   trg_do_customer_merge()             trigger on customers    is_active
--
-- And RLS USING is a SCAN FILTER, not a check. A row it rejects never reaches
-- ModifyTable, so no BEFORE trigger fires and the statement returns 0 rows and
-- raises NOTHING. Gating the policy would therefore mean: a staff member enters
-- an order, the order saves, psql exits 0 — and last_order_date,
-- days_since_last_order, weeks_since_last_order, avg_interval_wks,
-- effective_interval_wks and last_order_id silently stop moving for that
-- customer. 2,136 of 2,142 prod customers carry avg_interval_wks, and
-- lib/account-management/dueCustomers.ts reads the cadence to decide who is due
-- a reminder, so the visible symptom would be re-nagging customers who just
-- ordered. Putting the key in WITH CHECK instead makes it loud in the worst
-- way: the AFTER trigger raises 42501 and rolls back the whole order insert.
--
-- 20261004000004:57 already wrote the rule down, for this table, under the
-- heading "customers.chain_id cannot be done with a policy":
--   "The hole on the customers side is one COLUMN of a table that must stay
--    writable by every role that edits a customer, and a policy is per ROW."
-- That is why both existing guards here are zzz_-prefixed BEFORE UPDATE
-- triggers, and so are guard_order_invoice_columns and
-- guard_team_privileged_columns elsewhere. This is the fourth of that family.
--
-- The cascade columns are DISJOINT from the columns worth guarding, which is
-- what makes a column-scoped guard work where a row-scoped policy cannot.
--
-- Also considered and rejected: narrowing the column GRANT (20261103000014's
-- mechanism, "checked before RLS, so it refuses out loud"). The app edits these
-- columns on the user's own client, so revoking the grant would refuse
-- company_admin too, not just staff.
--
-- WHAT THIS DOES NOT CHANGE. No new permission key: customer.edit already
-- exists, is_plan_gated = false, feature_key = null, granted by all plans, and
-- already has live gate sites in the frontend. So there are no role_permissions
-- or plan_permissions rows to ship with it. The policy is untouched, and the
-- verify block below asserts it is still tenancy-only so that this decision
-- cannot be quietly reversed by a later file.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- One source of truth for the passthrough, called by the guard AND re-checked
-- by the verify block, so the two cannot drift. A later migration that adds a
-- SECURITY INVOKER cascade writing customers extends THIS list.
create or replace function public.customer_system_maintained_columns()
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $fn$
  -- Written by the SECURITY INVOKER cascades above, never typed by a person on
  -- a customer form. Each one is reachable by a caller who legitimately lacks
  -- customer.edit (a staff order entry refreshes cadence), so gating these
  -- would recreate Breaker 1.
  select array[
    -- update_customer_metrics_on_order() + recompute_all_customer_cadence()
    'last_order_id',
    'last_order_date',
    'days_since_last_order',
    'weeks_since_last_order',
    'avg_interval_wks',
    'effective_interval_wks',
    -- flag_customer_on_email_bounce()
    'email_bounced_at',
    'email_bounce_reason',
    -- refresh_needs_follow_up()
    'needs_follow_up',
    -- sync_primary_from_contact()
    'primary_contact_id',
    -- update_customer_sales_metrics()
    'last_contact',
    'sales_status'
  ]::text[];
$fn$;

comment on function public.customer_system_maintained_columns() is
  'Columns of public.customers written by SECURITY INVOKER cascade functions '
  'rather than by a person editing a customer. guard_customer_privileged_columns() '
  'lets these through without customer.edit; everything else needs the key. '
  'is_active is deliberately NOT here: trg_do_customer_merge writes it, but it '
  'fires only from merge_into_id, which carries no authenticated UPDATE grant.';

create or replace function public.guard_customer_privileged_columns()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
declare
  v_changed text[];
  v_col     text;
  v_allowed text[] := public.customer_system_maintained_columns();
begin
  -- Service role, cron, the QuickBooks import and migrations have no JWT. They
  -- are already trusted and they are not the hole this closes. The same first
  -- line as guard_customer_chain_column, guard_customer_payment_terms,
  -- guard_order_invoice_columns and guard_team_privileged_columns.
  --
  -- 🔴 A SECURITY DEFINER RPC called by a person does NOT land here: definer
  -- changes the current role, not the JWT, so auth.uid() is still theirs and
  -- the check below still runs. That is deliberate.
  if auth.uid() is null then
    return new;
  end if;

  -- What is this statement actually CHANGING? A customer form re-posts every
  -- field, so "named in the UPDATE" is not "changed" — both existing guards on
  -- this table draw the same distinction with IS NOT DISTINCT FROM, and
  -- guard_team_privileged_columns uses exactly this jsonb diff.
  --
  -- updated_at/updated_by are excluded because trg_audit_update stamps them in
  -- a BEFORE trigger that sorts ahead of this zzz_ one, so they have already
  -- moved by the time this runs and would make every statement look like a
  -- change.
  select array_agg(n.key order by n.key)
    into v_changed
    from jsonb_each(to_jsonb(new)) n
    join jsonb_each(to_jsonb(old)) o on o.key = n.key
   where n.value is distinct from o.value
     and n.key not in ('updated_at', 'updated_by')
     and n.key <> all (v_allowed);

  -- Nothing but system-maintained columns moved: this is a cascade, not an edit.
  if v_changed is null then
    return new;
  end if;

  -- The key is checked against the company the customer is in NOW. A statement
  -- that also moves company_id has company_id in v_changed, and the policy's
  -- WITH CHECK independently requires membership of the destination.
  if not public.auth_has_permission('customer.edit', old.company_id) then
    raise exception 'You may not change this customer''s details.'
      using errcode = 'insufficient_privilege',
            detail  = format('customer.edit is required to change: %s',
                             array_to_string(v_changed, ', '));
  end if;

  return new;
end;
$fn$;

comment on function public.guard_customer_privileged_columns() is
  'Requires customer.edit to change any column of public.customers except the '
  'system-maintained ones in customer_system_maintained_columns(). Exists '
  'because customers_update must stay tenancy-only: seven SECURITY INVOKER '
  'cascades write this table as the caller, and RLS USING would reject their '
  'rows silently (0 rows, no error). See 20261028000019 "Breaker 1".';

drop trigger if exists zzz_guard_customer_privileged_columns on public.customers;
create trigger zzz_guard_customer_privileged_columns
  before update on public.customers
  for each row
  execute function public.guard_customer_privileged_columns();

-- ── verify ───────────────────────────────────────────────────────────────────
-- Every check below can fail. Check 3 is the one that matters: it re-derives,
-- from pg_proc, the columns the SECURITY INVOKER cascades actually write, and
-- refuses to commit if any of them is missing from the passthrough. That is
-- Breaker 1 caught at apply time instead of as silently stale cadence in prod.
do $verify$
declare
  v_n        int;
  v_allowed  text[] := public.customer_system_maintained_columns();
  v_missing  text[];
  v_qual     text;
  v_check    text;
  v_writers  text[];
  -- The SECURITY INVOKER functions whose UPDATE statements were READ, one by
  -- one, to derive the passthrough above. trg_do_customer_merge() is among them
  -- and writes is_active, which is deliberately NOT passed through: it fires
  -- only from merge_into_id, a column carrying no authenticated UPDATE grant,
  -- so no caller lacking customer.edit can reach it over REST.
  v_expected_writers text[] := array[
    'flag_customer_on_email_bounce',
    'recompute_all_customer_cadence',
    'refresh_needs_follow_up',
    'sync_primary_from_contact',
    'trg_do_customer_merge',
    'update_customer_metrics_on_order',
    'update_customer_sales_metrics'
  ];
begin
  -- 1. the trigger is attached, BEFORE UPDATE, per row
  select count(*) into v_n
    from pg_trigger t
   where t.tgrelid = 'public.customers'::regclass
     and t.tgname  = 'zzz_guard_customer_privileged_columns'
     and not t.tgisinternal
     and (t.tgtype & 2) <> 0      -- BEFORE
     and (t.tgtype & 16) <> 0     -- UPDATE
     and (t.tgtype & 1) <> 0;     -- FOR EACH ROW
  if v_n <> 1 then
    raise exception 'guard trigger is not attached as BEFORE UPDATE FOR EACH ROW (found %)', v_n;
  end if;

  -- 2. the policy is STILL tenancy-only. If a later file gates it, the
  --    cascades break silently, so this migration refuses to coexist with that.
  select pg_get_expr(pol.polqual, pol.polrelid), pg_get_expr(pol.polwithcheck, pol.polrelid)
    into v_qual, v_check
    from pg_policy pol
   where pol.polrelid = 'public.customers'::regclass
     and pol.polname  = 'customers_update';
  if v_qual is null then
    raise exception 'customers_update policy is missing';
  end if;
  if v_qual ilike '%auth_has_permission%' or coalesce(v_check,'') ilike '%auth_has_permission%' then
    raise exception 'customers_update now names a permission key (using=%, check=%) — '
                    'that is Breaker 1 from 20261028000019; the cascades will no-op silently',
                    v_qual, v_check;
  end if;

  -- 3. THE REAL CHECK. The passthrough was derived by READING the UPDATE
  --    statement of each SECURITY INVOKER function that writes this table. That
  --    derivation is only valid for the seven that existed when it was made, so
  --    pin the set by NAME: if an eighth appears, or one is renamed, this
  --    refuses to commit, and whoever added it must read its UPDATE and extend
  --    customer_system_maintained_columns() if it writes a new column.
  --
  --    Pinned by name rather than by parsing SET clauses on purpose. The first
  --    draft of this block did parse them and produced a false positive — it
  --    reported 'is_primary', a contacts column, because an optional-alias
  --    group swallowed the word SET and ran the capture into the next
  --    statement. A verify block that fires on noise rolls back the whole
  --    release, so the fragile half is gone and the behaviour is proved by the
  --    probe harness instead.
  select array_agg(p.proname order by p.proname) into v_writers
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and not p.prosecdef
     and p.proname <> 'guard_customer_privileged_columns'
     -- strip line comments first: prosrc greps in this project hit the
     -- functions' own prose, so a function that merely MENTIONS updating
     -- customers would otherwise count as a writer.
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
           ~* 'update[[:space:]]+(public\.)?customers[[:space:]]';

  if coalesce(v_writers, array[]::text[]) is distinct from v_expected_writers then
    raise exception 'the set of SECURITY INVOKER functions writing public.customers has '
                    'changed. expected [%], found [%]. Read the new one''s UPDATE '
                    'statement: if it writes a customers column absent from '
                    'customer_system_maintained_columns(), gating that column reproduces '
                    'Breaker 1 (see 20261028000019).',
                    array_to_string(v_expected_writers, ', '),
                    array_to_string(coalesce(v_writers, array[]::text[]), ', ');
  end if;

  -- 4. the passthrough names only real columns. A typo here would gate a
  --    cascade column and break it loudly, which is the failure this catches.
  select array_agg(c order by c) into v_missing
    from unnest(v_allowed) c
   where not exists (
     select 1 from information_schema.columns ic
      where ic.table_schema = 'public' and ic.table_name = 'customers'
        and ic.column_name = c);
  if v_missing is not null then
    raise exception 'customer_system_maintained_columns() names column(s) that do not exist on public.customers: %',
                    array_to_string(v_missing, ', ');
  end if;

  raise notice 'customers: % system-maintained columns pass through, everything else needs customer.edit',
               array_length(v_allowed, 1);
end
$verify$;

commit;
