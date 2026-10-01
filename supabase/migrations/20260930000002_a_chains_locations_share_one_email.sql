-- A chain's locations share one back-office email.
--
-- customers_company_lower_email_uidx made (company_id, lower(email)) UNIQUE.
-- 20260706000006 added it with the note "Fix the claim/bind TOCTOU: one
-- customer per (company, email). Verified 0 dupes."
--
-- THE CLAIM/BIND IT WAS MEANT TO PROTECT DOES NOT RUN THROUGH THIS COLUMN.
-- Every shop session resolves a buyer through public.customer_users by
-- auth_user_id, never by customers.email:
--   app/api/login/route.ts:64                .eq('auth_user_id', user.id)
--   app/(shop)/[slug]/actions-checkout.ts:84
--   app/(shop)/[slug]/pay/actions-pay.ts:92
--   app/(shop)/[slug]/account/actions.ts:62
--   app/api/invoice/[orderId]/pdf/route.ts:41
-- and the acceptance path writes customer_users with
-- `onConflict: 'customer_id,auth_user_id'` (app/api/shop-invite/accept/route.ts:135),
-- which is backed by customer_users_customer_id_auth_user_id_key. That unique
-- constraint is the one holding the bind, and it is untouched here.
--
-- WHAT THE INDEX ACTUALLY DID WAS REFUSE REAL DATA. A chain hands one
-- back-office address to every location it operates. Measured on prod, MCR:
--   Safeway ............ 4 locations, 1 email,  3 blank
--   Minit Stop ......... 2 locations, 0 emails, 2 blank
--   Down to Earth ...... Kahului holds dataentry@downtoearth.org, so creating
--                        Down to Earth Kapolei failed outright (2026-09-30).
--   80 of 368 active customers carry no email at all.
--
-- The QuickBooks importer already carries a workaround for it, in its own
-- words at app/app/(app)/configuration/qbImportActions.ts:1038:
--   "A QuickBooks master routinely repeats ONE address across several
--    customers (a shared AP inbox, or the roaster's own address on a handful
--    of records), so the second write of it violated the index and lost that
--    whole customer's merge. An email now goes to the FIRST customer that
--    claims it; the others keep every other field."
-- So the constraint has been quietly dropping addresses on every import since
-- July, which is why the 0 dupes it was verified against stayed 0.
--
-- Replaced with a NON-unique index on the same expression, because the three
-- callers that look a customer up by (company, lower(email)) still want it
-- fast. All three tolerate several matches: guest-checkout dedup already pulls
-- .limit(5) and picks a reusable row, and the two Shopify importers are
-- hardened to take the oldest match in the same release (they used
-- .maybeSingle(), which would have created a duplicate customer instead).
--
-- NOT backfilling the 80 blank emails. Which address belongs on which location
-- is the roaster's to say, and the import that dropped them can be re-run now
-- without losing them.

begin;

drop index if exists public.customers_company_lower_email_uidx;

create index if not exists customers_company_lower_email_idx
  on public.customers (company_id, lower(email))
  where email is not null and email <> '';

do $verify$
declare v_bad int;
begin
  -- The refusal is gone.
  if exists (
    select 1 from pg_index i
     where i.indrelid = 'public.customers'::regclass
       and i.indisunique
       and pg_get_indexdef(i.indexrelid) ilike '%lower(email)%'
  ) then
    raise exception 'a unique index on customers.lower(email) is still present';
  end if;

  -- Nothing else constrains the column either, so this is not a half measure.
  select count(*) into v_bad
    from pg_constraint
   where conrelid = 'public.customers'::regclass
     and contype in ('u','x')
     and pg_get_constraintdef(oid) ilike '%email%';
  if v_bad > 0 then
    raise exception '% other unique/exclude constraint(s) still bind customers.email', v_bad;
  end if;

  -- The lookup the three callers depend on is still indexed.
  if not exists (
    select 1 from pg_index i
     where i.indrelid = 'public.customers'::regclass
       and not i.indisunique
       and pg_get_indexdef(i.indexrelid) ilike '%lower(email)%'
  ) then
    raise exception 'the replacement lookup index was not created';
  end if;

  -- THE POINT: the shop bind is protected by customer_users, and still is.
  if not exists (
    select 1 from pg_index i
     where i.indrelid = 'public.customer_users'::regclass
       and i.indisunique
       and pg_get_indexdef(i.indexrelid) ilike '%customer_id%'
       and pg_get_indexdef(i.indexrelid) ilike '%auth_user_id%'
  ) then
    raise exception 'customer_users lost the unique (customer_id, auth_user_id) that holds the bind';
  end if;

  -- And no customer lost anything: this migration only drops a constraint.
  select count(*) into v_bad from public.customers where updated_at > now() - interval '1 minute';
  if v_bad > 0 then
    raise exception 'this touched % customer row(s); it must not write any', v_bad;
  end if;
end;
$verify$;

commit;
