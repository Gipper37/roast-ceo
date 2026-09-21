-- 🔴 LIVE CROSS-TENANT LEAK. Every roaster can read every other roaster.
--
-- 24 of the 31 views in public were created without `security_invoker`, so
-- they execute with the privileges of their owner, which is postgres.
-- postgres owns the base tables too, and row level security does not apply
-- to a table's owner unless the table FORCES it. None of them do. So the
-- view reads every row in the database, and `authenticated` holds SELECT on
-- the view.
--
-- The base tables are fine. This is only true through the views, which is
-- why it has gone unnoticed: every RLS test that queries a table passes.
--
-- PROVEN ON PRODUCTION 2026-09-20, impersonating a real Maui Coffee Roasters
-- roastmaster (auth_user_id f3665a01-eabb-45b6-bd1b-75787bf4ee9f) inside a
-- rolled-back transaction:
--
--   auth_company_ids()                  -> {9ShiyDAXhV}          correct
--   select from roast_log               -> 9ShiyDAXhV only, 1011 rows   RLS works
--   select from monthly_coffee_usage..  -> FOUR companies, 713 rows     RLS bypassed
--
-- What one roaster can read about the others today:
--   order_profitability          11,297 rows
--   contacts_view                   279 rows
--   product_margins                 299 rows
--   company_subscription_status       4 rows, so competitors' plans
--   and Social Hour Coffee Roasters' total revenue reads as $2,589,659.
--
-- Maui Coffee Roasters and Social Hour are both coffee roasters. This is one
-- competitor able to read another's revenue, per-product margins and contact
-- list, through a URL any signed-in user of either can call.
--
-- ── The fix ───────────────────────────────────────────────────────────────
--
-- security_invoker = true makes a view execute as the CALLER, so the base
-- tables' existing RLS policies apply exactly as they do to a direct select.
-- No policy is added and no view definition changes: the policies were
-- always right, the views were stepping around them.
--
-- The four views with no company_id column are included deliberately.
-- equipment_grinder_lbs, equipment_roaster_lbs and weekly_orders_live read
-- tenant tables and simply do not project the column, so they leak the
-- aggregate rather than the label, which is worse rather than better.
-- sorted_onboarding_slides reads a genuine global catalogue, so invoker
-- rights change nothing for it, and consistency is worth more than an
-- exception nobody will remember the reason for.
--
-- ── Why this is separate from the service role ────────────────────────────
--
-- Server code using createAdminClient() runs as service_role, which has
-- BYPASSRLS, so every admin-client read through these views is unaffected.
-- Code using createUserClient() becomes correctly scoped, which is the
-- point. If a surface depended on seeing another tenant's rows it was
-- already a bug; the probe below would have caught it.

begin;

do $fix$
declare v record; n int := 0;
begin
  for v in
    select c.oid::regclass as vw
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public'
       and c.relkind = 'v'
       and not coalesce(c.reloptions::text like '%security_invoker%', false)
  loop
    execute format('alter view %s set (security_invoker = true)', v.vw);
    n := n + 1;
  end loop;
  raise notice 'security_invoker set on % views', n;
end
$fix$;

do $probe$
declare
  v_left int;
  v_actor uuid;
  v_seen  int;
begin
  -- 1. Nothing in public may still run as its owner.
  select count(*) into v_left
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'v'
     and not coalesce(c.reloptions::text like '%security_invoker%', false);
  if v_left > 0 then
    raise exception '% view(s) in public still execute as their owner and bypass RLS', v_left;
  end if;

  -- 2. The leak itself is closed, tested the way it was found: as a real
  --    tenant member, through the view that proved it. A migration that
  --    only checks the setting would pass on a database where the policies
  --    were also missing.
  select auth_user_id into v_actor
    from public.team
   where auth_user_id is not null and is_active
     and company_id = (select company_id from public.team
                        where auth_user_id is not null and is_active
                        group by company_id order by count(*) desc limit 1)
   limit 1;

  if v_actor is null then
    raise notice 'no active member with an auth user, so the live check was skipped';
  else
    perform set_config('request.jwt.claims',
             json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);

    select count(distinct company_id) into v_seen from public.monthly_coffee_usage_by_origin;

    perform set_config('role', 'none', true);

    if v_seen > 1 then
      raise exception
        'a single tenant member still sees % companies through monthly_coffee_usage_by_origin', v_seen;
    end if;
    raise notice 'live check passed: one tenant member sees % company', v_seen;
  end if;
end
$probe$;

commit;
