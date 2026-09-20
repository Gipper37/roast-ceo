-- Let an unauthenticated visitor read the price list.
--
-- subscription_plans has one policy, catalog_read, granted to `authenticated`.
-- That was right while prices only appeared inside the app. It stops being
-- right the moment the marketing pricing page reads them, because that page
-- is served to people who have not signed up: that is its entire purpose.
--
-- The alternative was to read the catalogue with the service-role client on a
-- public page, which would mean reaching for the key that bypasses every
-- policy in the database in order to fetch four rows we print on a billboard.
-- Widening a read policy on a table whose contents are advertised is the
-- smaller hole by a wide margin.
--
-- Only SELECT, only this table. The rows say what a plan costs and what it
-- includes. They carry no tenant data: a tenant's own subscription lives in
-- subscriptions, which is untouched here and stays company-scoped.
--
-- stripe_price_id and the other provider ids sit on this table too. They are
-- not secrets (a Stripe price id appears in the checkout URL of every site
-- that uses Stripe) but they are not advertising either, so the page selects
-- named columns rather than *.

begin;

drop policy if exists catalog_read on public.subscription_plans;

create policy catalog_read on public.subscription_plans
  for select
  to anon, authenticated
  using (true);

do $probe$
begin
  if not exists (
    select 1 from pg_policy
     where polrelid = 'public.subscription_plans'::regclass
       and polname = 'catalog_read'
       and 'anon' = any (select rolname from pg_roles where oid = any(polroles))
  ) then
    raise exception 'anon still cannot read the price list, so the pricing page would render empty';
  end if;

  -- The policy widened above must not have widened anything but reads.
  if exists (
    select 1 from pg_policy
     where polrelid = 'public.subscription_plans'::regclass
       and polname = 'catalog_read'
       and polcmd <> 'r'
  ) then
    raise exception 'catalog_read is no longer SELECT-only';
  end if;
end
$probe$;

commit;
