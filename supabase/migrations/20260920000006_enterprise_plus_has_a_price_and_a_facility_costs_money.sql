-- Enterprise Plus gets a price, and a facility becomes something you buy.
--
-- Two changes, both to the published rate card.
--
-- ── Enterprise Plus had no price at all ───────────────────────────────────
--
-- price_monthly and price_annual were both NULL on the top tier, and the
-- marketing page said "Custom / Contact Sales". Two tenants sit on it today
-- billing nothing. (Nothing else is billing either: every subscriptions row
-- has an empty Stripe id. This migration sets the CARD, not the collection.)
--
-- $900/month, $9,000/year. The comparison is Cropster Advanced at EUR 999,
-- so this lands just under it in dollars while bundling card acceptance,
-- invoice-of-record and HACCP that Cropster does not. Against the tier
-- below, it is a clear step from $250 rather than a rounding error.
--
-- No usage meter. It was designed and measured and then deliberately not
-- built: the two real candidates run 2,712 and 3,833 roasts a year, so any
-- honest allowance bills both of them zero, and the first overage anyone
-- would see is roughly $360 in year two. The allowance is published as a
-- stated boundary because the NUMBER does the commercial work -- it tells a
-- buyer who the tier is for -- and the machinery to bill it can be built the
-- month someone approaches the line.
--
-- ── A facility stops being a cap and becomes a line item ──────────────────
--
-- max_facilities was a wall: addFacility counted active facilities and threw
-- "Upgrade to add more". NULL meant unlimited, which is what Enterprise and
-- Enterprise Plus had, so the top two tiers gave away locations for free
-- while the bottom two could not have a second one at any price.
--
-- The model is Toast's: the subscription buys the software, each location
-- costs. So max_facilities now means INCLUDED, and where
-- price_per_extra_facility_monthly is set, going past the included count is
-- a purchase rather than a refusal. Where it is NULL the old wall stands,
-- which is right for Starter and Pro: a single-site roaster who opens a
-- second site is not buying an add-on, they are changing tier.
--
-- $150/month per additional facility. That number is a judgement call, not a
-- derivation: it is a sixth of the Enterprise Plus base and roughly what
-- Toast charges for an additional terminal. It is one UPDATE to change.
--
-- WHO THIS AFFECTS TODAY: Social Hour Coffee Roasters (R7CbqHmA1j) is on
-- Enterprise with 2 active facilities, only one of which roasts. Under the
-- old NULL they were unlimited and free; under this card their second
-- facility is $150/month. Nobody is being billed yet, so this is a
-- conversation to have before billing starts, not a charge that lands.

begin;

alter table public.subscription_plans
  add column if not exists price_per_extra_facility_monthly numeric;

comment on column public.subscription_plans.price_per_extra_facility_monthly is
  'Monthly price for each facility beyond max_facilities. NULL means extra facilities cannot be bought on this plan and max_facilities is a hard cap.';

comment on column public.subscription_plans.max_facilities is
  'Facilities INCLUDED in the plan price. Beyond this, price_per_extra_facility_monthly applies where it is set, and where it is NULL this is a hard cap.';

update public.subscription_plans
   set price_monthly = 900,
       price_annual  = 9000,
       updated_at    = now()
 where plan_id = 'enterprise_plus';

-- Every plan includes one facility. The tiers differ in whether a second one
-- can be bought at all, not in how many are free.
update public.subscription_plans
   set max_facilities = 1,
       price_per_extra_facility_monthly = case
         when plan_id in ('enterprise', 'enterprise_plus') then 150
         else null
       end,
       updated_at = now()
 where plan_id in ('starter', 'pro', 'enterprise', 'enterprise_plus');

do $probe$
declare
  v_price numeric;
  v_extra numeric;
  v_walled int;
begin
  select price_monthly, price_per_extra_facility_monthly
    into v_price, v_extra
    from public.subscription_plans where plan_id = 'enterprise_plus';

  if v_price is null then
    raise exception 'enterprise_plus still has no price, which is the thing this migration exists to fix';
  end if;
  if v_extra is null then
    raise exception 'enterprise_plus cannot buy an extra facility, so the top tier is still walled';
  end if;

  -- A plan with no included facilities and no way to buy one cannot be sold.
  select count(*) into v_walled
    from public.subscription_plans
   where active
     and coalesce(max_facilities, 0) < 1
     and price_per_extra_facility_monthly is null;
  if v_walled > 0 then
    raise exception '% active plan(s) allow no facility at all', v_walled;
  end if;
end
$probe$;

commit;
