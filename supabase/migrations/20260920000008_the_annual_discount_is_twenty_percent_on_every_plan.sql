-- Enterprise Plus annual: $9,000 becomes $8,640.
--
-- The previous migration set it to $9,000, which is a round number and the
-- wrong one: against $900 a month it is a 16.7% discount, while Starter, Pro
-- and Enterprise are all exactly 20%. One plan discounting differently from
-- the other three is the kind of detail a buyer notices while comparing, and
-- it made the billing toggle's "Save 20%" a promise the top card visibly
-- failed to keep.
--
-- 20% off $10,800 is $8,640. Every plan now discounts identically, which is
-- both easier to say and easier to keep true.
--
-- The pricing page computes the saving per card from these two columns
-- rather than asserting it, so the page needs no change: it will read 20%
-- across the board the moment this lands.

begin;

update public.subscription_plans
   set price_annual = 8640,
       updated_at   = now()
 where plan_id = 'enterprise_plus';

do $probe$
declare r record;
begin
  -- Every active plan that is priced both ways must discount by the same
  -- 20%, or the toggle is lying about one of them again.
  for r in
    select plan_id, price_monthly, price_annual,
           round((1 - price_annual / (price_monthly * 12)) * 100) as pct
      from public.subscription_plans
     where active and price_monthly is not null and price_annual is not null
       and price_monthly > 0
  loop
    if r.pct <> 20 then
      raise exception 'plan % discounts % percent annually, not 20 (monthly %, annual %)',
        r.plan_id, r.pct, r.price_monthly, r.price_annual;
    end if;
  end loop;
end
$probe$;

commit;
