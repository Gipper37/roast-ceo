-- Stripe subscription infrastructure
-- Adds stripe_customer_id to companies, creates subscription_plans and subscriptions tables,
-- and a company_subscription_status view for easy status lookups.

-- 1. Add stripe_customer_id to companies
ALTER TABLE public.companies ADD COLUMN stripe_customer_id text UNIQUE;

-- 2. Subscription plans reference table
CREATE TABLE public.subscription_plans (
  plan_id          text PRIMARY KEY,
  plan_name        text NOT NULL,
  stripe_price_id  text,           -- filled in after Stripe product setup
  price_monthly    numeric,
  max_facilities   integer,        -- NULL = unlimited
  max_team_members integer,        -- NULL = unlimited
  features         jsonb,
  active           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.subscription_plans (plan_id, plan_name) VALUES
  ('starter',    'Starter'),
  ('pro',        'Pro'),
  ('enterprise', 'Enterprise');

-- 3. Subscriptions table (mirrors Stripe subscription object)
CREATE TABLE public.subscriptions (
  subscription_id        text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  company_id             text NOT NULL REFERENCES public.companies(company_id) ON DELETE CASCADE,
  stripe_subscription_id text UNIQUE,
  stripe_customer_id     text,
  plan_id                text REFERENCES public.subscription_plans(plan_id),
  status                 text NOT NULL DEFAULT 'trialing',
  trial_end              timestamptz,
  current_period_start   timestamptz,
  current_period_end     timestamptz,
  cancel_at_period_end   boolean NOT NULL DEFAULT false,
  canceled_at            timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  created_by             text,
  updated_by             text,
  CONSTRAINT subscriptions_status_check CHECK (
    status IN ('trialing','active','past_due','canceled','unpaid','paused','incomplete')
  )
);

CREATE INDEX idx_subscriptions_company_id ON public.subscriptions(company_id);
CREATE INDEX idx_subscriptions_stripe_customer_id ON public.subscriptions(stripe_customer_id);

-- 4. View: company_subscription_status
CREATE VIEW public.company_subscription_status AS
SELECT
  c.company_id,
  c.company_name,
  c.stripe_customer_id,
  s.subscription_id,
  s.plan_id,
  sp.plan_name,
  s.status,
  s.trial_end,
  s.current_period_end,
  s.cancel_at_period_end,
  CASE
    WHEN s.status IN ('active', 'trialing') THEN true
    ELSE false
  END AS is_active
FROM public.companies c
LEFT JOIN public.subscriptions s ON s.company_id = c.company_id
LEFT JOIN public.subscription_plans sp ON sp.plan_id = s.plan_id;
