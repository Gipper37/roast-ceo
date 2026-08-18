-- equipment_tech and sales_person keep the Roast tab.
--
-- The nav gates Roast with hideForRoles: ['accounting_admin','accounting_view']
-- — a DENY-list, so everyone else sees it. The catalog's roast.view is an
-- ALLOW-list and is narrower: assistant_roaster, company_admin, facility_admin,
-- manager, roastmaster, staff. Converting the nav to roast.view without this
-- would silently take the tab from equipment_tech and sales_person.
--
-- equipment_tech in particular is the specialist who maintains the roasters;
-- losing sight of the roast schedule as a side effect of a refactor is not a
-- decision anyone made. Grant the key so the conversion is the no-op it is meant
-- to be, and the question "should sales see Roast?" becomes a dev-portal
-- checkbox that can be answered on its merits.
--
-- Same reasoning as 20260813000003 for assistant_roaster and roast_stock.edit:
-- when a deny-list and an allow-list disagree, preserve today's behaviour and
-- move the argument into the portal.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('equipment_tech', 'roast.view', true),
  ('sales_person',   'roast.view', true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

commit;

notify pgrst, 'reload schema';
