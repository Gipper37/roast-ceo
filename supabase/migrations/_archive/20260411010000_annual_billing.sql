-- Add annual billing columns to subscription_plans
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS stripe_annual_price_id text,
  ADD COLUMN IF NOT EXISTS price_annual numeric,
  ADD COLUMN IF NOT EXISTS stripe_product_id text;

-- Update monthly prices (Starter $75, Pro $150, Enterprise $250)
UPDATE public.subscription_plans SET price_monthly = 75  WHERE plan_id = 'starter';
UPDATE public.subscription_plans SET price_monthly = 150 WHERE plan_id = 'pro';
UPDATE public.subscription_plans SET price_monthly = 250 WHERE plan_id = 'enterprise';

-- Set annual prices (20% discount: Starter $720/yr, Pro $1440/yr, Enterprise $2400/yr)
UPDATE public.subscription_plans SET price_annual = 720  WHERE plan_id = 'starter';
UPDATE public.subscription_plans SET price_annual = 1440 WHERE plan_id = 'pro';
UPDATE public.subscription_plans SET price_annual = 2400 WHERE plan_id = 'enterprise';

-- Set Stripe annual product IDs (price IDs to be added manually from Stripe dashboard)
UPDATE public.subscription_plans SET stripe_product_id = 'prod_UJXzHiXXiPyIP1' WHERE plan_id = 'starter';
UPDATE public.subscription_plans SET stripe_product_id = 'prod_UJXxy5Y5GcxGQO' WHERE plan_id = 'pro';
UPDATE public.subscription_plans SET stripe_product_id = 'prod_UJXuuBswu5YweO' WHERE plan_id = 'enterprise';

-- stripe_annual_price_id left NULL — set from Stripe dashboard once price objects are created
