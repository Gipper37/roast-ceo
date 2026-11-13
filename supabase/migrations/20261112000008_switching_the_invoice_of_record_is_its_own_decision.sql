-- Switching the invoice of record is its own decision.
--
-- Owner: "only upper level roles should be able to instigate that switch over.
-- manager, accounting admin, company admin, facility admin etc."
--
-- Both toggle actions already require billing.configure, which stops at
-- accounting_admin, company_admin and facility_admin -- manager is missing,
-- and manager is first on his list.
--
-- 🔴 NOT BY WIDENING billing.configure. That key is "Configure billing
-- settings": invoice numbering and prefixes, tax, the accounting basis, late
-- fees. Adding manager to it to let them flip one switch would hand them all
-- of that, which is not what was asked for.
--
-- And the switch deserves its own key on the merits. It is a one-way,
-- company-defining decision -- it decides which system is the invoice of
-- record, stamps the cutover that seals everything before it, and sets the
-- first invoice number. That is a different weight of act from changing a late
-- fee percentage, so it gets a different key.
--
-- Granted to exactly the four roles he named. Plan-gated to match the rest of
-- invoicing (invoice.send, invoice.print, invoice.void and billing.configure
-- are all enterprise and enterprise_plus): a tenant who cannot send an invoice
-- has no reason to be offered the switch.

begin;

insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order)
values
  ('billing.invoice_of_record', 'Payments', 'Switch invoicing to STRATA',
   'Choose whether invoices come from STRATA or stay in QuickBooks, and set the date STRATA starts from. A one-way decision for the whole company.',
   'Only a manager or an admin can switch where your invoices come from. Ask one of them to turn it on.',
   true, 86)
on conflict (permission_id) do update
  set category             = excluded.category,
      label                = excluded.label,
      description          = excluded.description,
      default_deny_message = excluded.default_deny_message,
      is_plan_gated        = excluded.is_plan_gated,
      sort_order           = excluded.sort_order,
      updated_at           = now();

-- His four, and only his four. roastery_manager holds invoice.send but runs
-- the floor, not the books; deciding which system IS the invoice of record is
-- not an operations call. One row adds them if he disagrees.
insert into public.role_permissions (role_id, permission_id, granted, updated_by)
select r.role_id, 'billing.invoice_of_record', true, 'migration:20261112000008'
  from (values ('manager'),('accounting_admin'),('company_admin'),('facility_admin')) as r(role_id)
on conflict (role_id, permission_id) do update
  set granted = true, deny_message = null,
      updated_at = now(), updated_by = 'migration:20261112000008';

-- Named explicitly rather than defaulted, so a plan added later has to be
-- decided rather than inheriting a yes.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('enterprise',      'billing.invoice_of_record', true,  'Switching the invoice of record: with the rest of invoicing'),
  ('enterprise_plus', 'billing.invoice_of_record', true,  'Switching the invoice of record: with the rest of invoicing'),
  ('pro',             'billing.invoice_of_record', false, 'Invoicing is not on this plan, so neither is switching to it'),
  ('starter',         'billing.invoice_of_record', false, 'Invoicing is not on this plan, so neither is switching to it')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason, updated_at = now();

-- 🔴 A KEY AND ITS PLAN POLICY MUST ADMIT THE SAME THING, and both directions
-- fail silently: a plan-gated key with no plan rows is denied to everyone, and
-- a key granted on a plan that cannot invoice offers a switch that leads
-- nowhere. Checked against the key it is modelled on rather than hardcoded, so
-- the two cannot drift apart later.
do $$
declare v_roles integer; v_plans integer; v_mismatch integer;
begin
  select count(*) into v_roles from public.role_permissions
   where permission_id = 'billing.invoice_of_record' and granted;
  if v_roles <> 4 then
    raise exception 'billing.invoice_of_record granted to % role(s), expected 4', v_roles;
  end if;

  select count(*) into v_plans from public.plan_permissions
   where permission_id = 'billing.invoice_of_record';
  if v_plans < (select count(distinct plan_id) from public.plan_permissions) then
    raise exception 'billing.invoice_of_record covers only % of the plans', v_plans;
  end if;

  select count(*) into v_mismatch
    from public.plan_permissions a
    join public.plan_permissions b on b.plan_id = a.plan_id
   where a.permission_id = 'billing.invoice_of_record'
     and b.permission_id = 'invoice.send'
     and a.granted is distinct from b.granted;
  if v_mismatch > 0 then
    raise exception 'the switch is offered on % plan(s) that cannot send an invoice (or withheld on one that can)', v_mismatch;
  end if;

  -- Every role that may switch must also be able to send, or the switch hands
  -- someone a system they cannot then use.
  select count(*) into v_mismatch
    from public.role_permissions r
   where r.permission_id = 'billing.invoice_of_record' and r.granted
     and not exists (select 1 from public.role_permissions s
                      where s.role_id = r.role_id and s.permission_id = 'invoice.send' and s.granted);
  if v_mismatch > 0 then
    raise exception '% role(s) may switch the invoice of record but may not send an invoice', v_mismatch;
  end if;
end $$;

commit;
