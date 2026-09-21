-- Enterprise had one Stripe price id in both columns, and it was the YEARLY one.
--
--   stripe_price_id        = price_1TKuoUCTfAcCOA6lOgusYtjq   <- annual price
--   stripe_annual_price_id = price_1TKuoUCTfAcCOA6lOgusYtjq   <- annual price
--
-- stripe_price_id is the MONTHLY line item. The create-checkout edge
-- function reads it directly for a monthly purchase
-- (`isAnnual ? stripe_annual_price_id : stripe_price_id`), so a roaster
-- choosing Enterprise monthly was sent to Stripe with the annual price and
-- would have been charged $2,400 on the spot instead of $250.
--
-- Not $250 taken twelve times. $2,400, once, immediately, from someone who
-- clicked a button that said $250/mo. That is a chargeback and an apology,
-- and it was one purchase away the entire time.
--
-- The owner confirmed which id is which from the Stripe dashboard:
--   monthly  price_1TELYBCTfAcCOA6llWX4qOmW
--   annual   price_1TKuoUCTfAcCOA6lOgusYtjq
--
-- The monthly id is also the one the pattern predicts: Starter and Pro both
-- carry price_1TEL-era ids in their monthly column (price_1TELT3...,
-- price_1TELWe...) and price_1TKu-era ids in their annual column. Enterprise
-- was the odd one out because its monthly id was never written.
--
-- Nobody has been billed through Stripe yet: every subscriptions row has an
-- empty stripe_subscription_id. So this cost nothing, and it stops costing
-- anything the moment billing is switched on rather than after.

begin;

update public.subscription_plans
   set stripe_price_id = 'price_1TELYBCTfAcCOA6llWX4qOmW',
       updated_at      = now()
 where plan_id = 'enterprise';

do $probe$
declare r record;
begin
  -- The class of bug, not just this instance. Any active plan priced both
  -- ways must point at two DIFFERENT Stripe prices, or one of its two
  -- intervals charges the wrong amount and nothing says so until a real card
  -- is charged.
  for r in
    select plan_id, stripe_price_id, stripe_annual_price_id
      from public.subscription_plans
     where active
       and stripe_price_id is not null
       and stripe_annual_price_id is not null
  loop
    if r.stripe_price_id = r.stripe_annual_price_id then
      raise exception
        'plan % points monthly and annual at the same Stripe price (%), so one interval bills the wrong amount',
        r.plan_id, r.stripe_price_id;
    end if;
  end loop;

  -- And a plan that is priced but unbuyable is the other half of the same
  -- problem: the checkout function refuses it with "No Stripe price
  -- configured", which a customer reads as the product being broken.
  for r in
    select plan_id
      from public.subscription_plans
     where active and price_monthly is not null and stripe_price_id is null
  loop
    raise exception 'plan % has a price but no Stripe price id, so it cannot be bought', r.plan_id;
  end loop;
end
$probe$;

commit;
