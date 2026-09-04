-- SMARTroast gets its own gated settings section, and two new parameters.
--
-- config.smartroast (Pro+, same roles as config.parameters): SMARTroast rides
-- on the live-telemetry hardware that config.connections already gates at Pro,
-- so the intelligence sits at the tier of the hardware it listens to. The
-- settings section renders locked with upsell copy below Pro.
--
-- resume_roast_window_secs: the post-DROP "Saved — Resume Roast (Ns)" window,
-- previously hardcoded 60s in the profiler. Owner set the default to 30
-- (2026-09-04) and wants it adjustable per roastery.
--
-- smartroast_autoload: when ON, the profiler loads the next queued roast
-- automatically once the resume window closes — as if the operator pressed
-- that roast's own start button. OFF by default.

begin;

insert into public.permissions (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values (
  'config.smartroast',
  'Configuration',
  'Configure SMARTroast',
  'Auto-detect CHARGE/DROP, detection sensitivity, cancel window, and auto-loading the next queued roast.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  true,
  36
)
on conflict (permission_id) do nothing;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter',         'config.smartroast', false, 'SMARTroast — Pro and above (tier of the hardware it listens to)'),
  ('pro',             'config.smartroast', true,  'SMARTroast — Pro and above'),
  ('enterprise',      'config.smartroast', true,  'SMARTroast — Pro and above'),
  ('enterprise_plus', 'config.smartroast', true,  'SMARTroast — Pro and above')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Same roles that hold config.parameters.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'config.smartroast', true),
  ('facility_admin', 'config.smartroast', true),
  ('manager',        'config.smartroast', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

insert into public.standard_parameters (parameters_id, parameter, data_type, amount)
values ('resume_roast_window_secs', 'Resume roast window (seconds)', 'number', 30)
on conflict (parameters_id) do nothing;

insert into public.standard_parameters (parameters_id, parameter, data_type, text_value)
values ('smartroast_autoload', 'SMARTroast — auto-load next roast', 'boolean', 'off')
on conflict (parameters_id) do nothing;

commit;
