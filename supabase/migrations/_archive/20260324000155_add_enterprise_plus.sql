-- Add Enterprise+ plan and populate feature metadata for all tiers

INSERT INTO public.subscription_plans (plan_id, plan_name, features) VALUES
  ('enterprise_plus', 'Enterprise+', '{"modules": ["roaster_ops","inventory","cogs","crm","maintenance","multi_facility"]}')
ON CONFLICT (plan_id) DO NOTHING;

UPDATE public.subscription_plans SET features = '{"modules": ["roaster_ops"]}'
  WHERE plan_id = 'starter';

UPDATE public.subscription_plans SET features = '{"modules": ["roaster_ops","inventory","cogs"]}'
  WHERE plan_id = 'pro';

UPDATE public.subscription_plans SET features = '{"modules": ["roaster_ops","inventory","cogs","crm","maintenance"]}'
  WHERE plan_id = 'enterprise';

UPDATE public.subscription_plans SET features = '{"modules": ["roaster_ops","inventory","cogs","crm","maintenance","multi_facility"]}'
  WHERE plan_id = 'enterprise_plus';
