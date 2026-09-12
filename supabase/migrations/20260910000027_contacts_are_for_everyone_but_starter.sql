-- Contact management is a Pro feature, not an Enterprise one.
--
-- Owner, 2026-09-12: "contact add edit is for everything but starter."
--
-- Today plan_permissions grants the four contact.* keys on enterprise and
-- enterprise_plus and explicitly DENIES them on pro — so a Pro tenant is locked
-- out of something they are meant to have. Starter stays denied, as intended.
--
-- The keys were also enforced nowhere: createContact, updateContact and
-- toggleContactActive all asked for customer.edit, which is not plan-gated,
-- while the contact detail page gated its Edit button on contact.edit. So the
-- button hid on Pro and the action it guarded would have run anyway. The app
-- side is fixed alongside this migration (stratos); this is the half that has
-- to land FIRST, because a permission key the database does not grant resolves
-- to "denied" for every role, silently.
--
-- Roles: contact.* is granted to company_admin, facility_admin, manager,
-- roastmaster and sales_person. customer.edit — what the actions ask for today
-- — additionally covers accounting_admin and assistant_roaster, so switching
-- the actions over would quietly take contact editing away from those two.
-- They keep it. The owner's answer was about PLAN, not about role, and removing
-- a capability nobody asked to remove is not a fix.

begin;

-- ── The plan gate the owner actually described ────────────────────────────
update public.plan_permissions
   set granted = true
 where plan_id = 'pro'
   and permission_id in ('contact.view', 'contact.create', 'contact.edit', 'contact.archive');

-- ── Keep every role that can edit contacts today ──────────────────────────
insert into public.role_permissions (role_id, permission_id, granted)
select r.role_id, p.permission_id, true
  from (values ('accounting_admin'), ('assistant_roaster')) as r(role_id)
  cross join (values ('contact.view'), ('contact.create'), ('contact.edit'), ('contact.archive')) as p(permission_id)
on conflict (role_id, permission_id) do update set granted = true;

-- ── Probe ─────────────────────────────────────────────────────────────────
do $probe$
declare
  v_missing text;
begin
  -- Every plan except starter grants contact editing.
  select string_agg(pp.plan_id || '.' || pp.permission_id, ', ')
    into v_missing
    from public.plan_permissions pp
   where pp.permission_id like 'contact.%'
     and pp.plan_id <> 'starter'
     and pp.granted is not true;
  if v_missing is not null then
    raise exception 'contact.* still denied on a non-starter plan: %', v_missing;
  end if;

  -- Starter still denied — this was not a licence to give it away.
  if exists (select 1 from public.plan_permissions
              where plan_id = 'starter' and permission_id like 'contact.%' and granted) then
    raise exception 'contact.* was granted on starter, which is not what was asked for';
  end if;

  -- Nobody who can edit a contact today loses it when the app switches keys.
  select string_agg(rp.role_id, ', ')
    into v_missing
    from public.role_permissions rp
   where rp.permission_id = 'customer.edit' and rp.granted
     and not exists (select 1 from public.role_permissions x
                      where x.role_id = rp.role_id and x.permission_id = 'contact.edit' and x.granted);
  if v_missing is not null then
    raise exception 'these roles hold customer.edit but not contact.edit, so they would lose contacts: %', v_missing;
  end if;
end
$probe$;

commit;
