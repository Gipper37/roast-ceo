-- Give Enterprise Plus its Stripe price ids.
--
-- The checkout path is real and works: /api/checkout forwards to the
-- create-checkout edge function, which reads stripe_price_id and
-- stripe_annual_price_id off this table and hands the chosen one to Stripe
-- as the line item. Enterprise Plus had neither, so the function's own guard
-- ("No Stripe price configured for plan 'enterprise_plus'") refused every
-- attempt to buy the top tier. It had no price and no way to pay it.
--
-- Ids supplied by the owner from the Stripe dashboard:
--   monthly  price_1UHuTcCTfAcCOA6ld5lqZzIT
--   annual   price_1UHuUkCTfAcCOA6lKz5GjOq8
--
-- A Stripe price id is not a secret: it travels in the checkout URL of every
-- site that uses Stripe, which is why it belongs in a committed migration
-- rather than an env var.
--
-- stripe_product_id stays null. The edge function never reads it; only the
-- two price ids reach Stripe.
--
-- ── A NOTE ON THE PLAN BELOW THIS ONE, WHICH THIS DOES NOT FIX ────────────
--
-- enterprise carries the SAME id in both columns:
--   stripe_price_id        = price_1TKuoUCTfAcCOA6lOgusYtjq
--   stripe_annual_price_id = price_1TKuoUCTfAcCOA6lOgusYtjq
-- The edge function picks by interval, so both intervals resolve to that one
-- price and one of them charges the wrong amount: either an annual buyer is
-- billed $250 for a year, or a monthly buyer is charged $2,400 up front.
-- Which one depends on what that id actually is in Stripe, which cannot be
-- determined from this database. Left alone deliberately: guessing would
-- replace a known-wrong row with a possibly-wrong one. The probe below
-- therefore checks only the plan this migration touches.

begin;

update public.subscription_plans
   set stripe_price_id        = 'price_1UHuTcCTfAcCOA6ld5lqZzIT',
       stripe_annual_price_id = 'price_1UHuUkCTfAcCOA6lKz5GjOq8',
       updated_at             = now()
 where plan_id = 'enterprise_plus';

do $probe$
declare m text; a text;
begin
  select stripe_price_id, stripe_annual_price_id into m, a
    from public.subscription_plans where plan_id = 'enterprise_plus';

  if m is null or a is null then
    raise exception 'enterprise_plus is still missing a Stripe price id, so the checkout will refuse it';
  end if;

  -- The exact shape of the bug sitting on `enterprise` today. Two intervals
  -- pointing at one price means one of them bills the wrong amount, and it
  -- is invisible until a customer's card is charged.
  if m = a then
    raise exception 'enterprise_plus has the same Stripe price id for monthly and annual, so one interval would bill the wrong amount';
  end if;

  -- A price id that is not a price id reaches Stripe as a line item and
  -- fails at the worst moment: after the buyer has clicked Upgrade.
  if m !~ '^price_[A-Za-z0-9]+$' or a !~ '^price_[A-Za-z0-9]+$' then
    raise exception 'a Stripe price id on enterprise_plus is not shaped like one (monthly %, annual %)', m, a;
  end if;
end
$probe$;

commit;
