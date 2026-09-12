-- M11 phase 2, tranche 1: the tables nothing writes behind your back.
--
-- Phase 1 put auth_has_permission() into the write policies of the money and
-- identity tables. This is the first tranche of the rest: 41 tables whose
-- policy today is tenant-only, so ANY member of the tenant can write them
-- whatever their role.
--
-- HOW THIS TRANCHE WAS CHOSEN, and why it is not simply "the next 41":
--
-- 1. The surface was measured, not estimated. 114 tables have write policies
--    with no permission behind them (the audit guessed ~140; the roast tables
--    it counted are already gated, through auth_roast_log_company_ids()).
--
-- 2. Every table here has NO SECURITY INVOKER function that writes it. That is
--    the trap phase 1 fell into twice: a trigger on table Y writes table X as
--    the INVOKER, so gating X on a key that Y's writer does not hold turns a
--    legitimate write into a silent zero-row failure. Checked against pg_proc
--    directly rather than taken on trust — which is how consumable_inventory
--    (written by a trigger on ORDER_DETAILS), customers (written by a trigger
--    on ORDERS) and recipe_components (written by a trigger on
--    COFFEE_INVENTORY) were held back for a later tranche.
--
-- 3. Each key is the one the app's own server action already requires before
--    writing that table — read out of the code, not inferred from the name.
--
-- 4. Every statement is explicit. Phase 1 looped over a VALUES list dropping
--    every policy per table, which is fine until a table's correct answer is
--    "leave it alone" — then the loop rebuilds it with NO write policy and
--    denies everyone. activity_events and client_telemetry_events would have
--    gone that way silently, since both are best-effort inserts inside
--    try/catch from every signed-in browser. They are not in this list, and
--    there is no loop here to put them in one.
--
-- Read policies are preserved verbatim: each table's existing tenant
-- expression becomes its SELECT policy unchanged, and any other policy it
-- carries (global catalogue reads, parent-join reads) is left alone.

begin;

-- channel — insert channel.create · update channel.edit|channel.archive · delete channel.archive
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.channel;
create policy channel_tenant_read on public.channel
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy channel_write_insert on public.channel
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('channel.create', company_id));
create policy channel_write_update on public.channel
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('channel.edit', company_id) or public.auth_has_permission('channel.archive', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('channel.edit', company_id) or public.auth_has_permission('channel.archive', company_id)));
create policy channel_write_delete on public.channel
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('channel.archive', company_id));

-- channel_tax_settings — insert tax.configure · update tax.configure · delete tax.configure
-- other policies left untouched: none
drop policy if exists channel_tax_settings_all on public.channel_tax_settings;
create policy channel_tax_settings_tenant_read on public.channel_tax_settings
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy channel_tax_settings_write_insert on public.channel_tax_settings
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));
create policy channel_tax_settings_write_update on public.channel_tax_settings
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));
create policy channel_tax_settings_write_delete on public.channel_tax_settings
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));

-- cmarket_alerts — insert market.alerts_manage · update market.alerts_manage · delete market.alerts_manage
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.cmarket_alerts;
create policy cmarket_alerts_tenant_read on public.cmarket_alerts
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy cmarket_alerts_write_insert on public.cmarket_alerts
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('market.alerts_manage', company_id));
create policy cmarket_alerts_write_update on public.cmarket_alerts
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('market.alerts_manage', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('market.alerts_manage', company_id));
create policy cmarket_alerts_write_delete on public.cmarket_alerts
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('market.alerts_manage', company_id));

-- company_holiday — insert delivery.manage_zones · update delivery.manage_zones · delete delivery.manage_zones
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.company_holiday;
create policy company_holiday_tenant_read on public.company_holiday
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy company_holiday_write_insert on public.company_holiday
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy company_holiday_write_update on public.company_holiday
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy company_holiday_write_delete on public.company_holiday
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));

-- consumable_inventory_purchased — insert inventory.purchase|inventory.receive · update inventory.purchase|inventory.receive|inventory.edit · delete inventory.void
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.consumable_inventory_purchased;
create policy consumable_inventory_purchased_tenant_read on public.consumable_inventory_purchased
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy consumable_inventory_purchased_write_insert on public.consumable_inventory_purchased
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('inventory.receive', company_id)));
create policy consumable_inventory_purchased_write_update on public.consumable_inventory_purchased
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('inventory.receive', company_id) or public.auth_has_permission('inventory.edit', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('inventory.receive', company_id) or public.auth_has_permission('inventory.edit', company_id)));
create policy consumable_inventory_purchased_write_delete on public.consumable_inventory_purchased
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.void', company_id));

-- contact_role — insert customer.edit · update customer.edit · delete customer.edit
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.contact_role;
create policy contact_role_tenant_read on public.contact_role
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy contact_role_write_insert on public.contact_role
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy contact_role_write_update on public.contact_role
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy contact_role_write_delete on public.contact_role
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));

-- customer_category — insert customer.edit · update customer.edit · delete customer.edit
-- other policies left untouched: public_read_global(SELECT)
drop policy if exists tenant_company_access on public.customer_category;
create policy customer_category_tenant_read on public.customer_category
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy customer_category_write_insert on public.customer_category
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy customer_category_write_update on public.customer_category
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy customer_category_write_delete on public.customer_category
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));

-- customer_discount — insert customer.edit · update customer.edit · delete customer.edit
-- other policies left untouched: none
drop policy if exists customer_discount_tenant on public.customer_discount;
create policy customer_discount_tenant_read on public.customer_discount
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy customer_discount_write_insert on public.customer_discount
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy customer_discount_write_update on public.customer_discount
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));
create policy customer_discount_write_delete on public.customer_discount
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.edit', company_id));

-- data_imports — insert config.import_data · update config.import_data · delete config.import_data
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.data_imports;
create policy data_imports_tenant_read on public.data_imports
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy data_imports_write_insert on public.data_imports
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));
create policy data_imports_write_update on public.data_imports
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));
create policy data_imports_write_delete on public.data_imports
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));

-- equipment — insert equipment.create · update equipment.edit|equipment.archive · delete equipment.archive
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.equipment;
create policy equipment_tenant_read on public.equipment
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy equipment_write_insert on public.equipment
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.create', company_id));
create policy equipment_write_update on public.equipment
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('equipment.edit', company_id) or public.auth_has_permission('equipment.archive', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('equipment.edit', company_id) or public.auth_has_permission('equipment.archive', company_id)));
create policy equipment_write_delete on public.equipment
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.archive', company_id));

-- equipment_model — insert equipment.create · update equipment.create · delete equipment.create
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.equipment_model;
create policy equipment_model_tenant_read on public.equipment_model
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy equipment_model_write_insert on public.equipment_model
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.create', company_id));
create policy equipment_model_write_update on public.equipment_model
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.create', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.create', company_id));
create policy equipment_model_write_delete on public.equipment_model
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.create', company_id));

-- equipment_program_subscription — insert equipment.edit · update equipment.edit · delete equipment.edit
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.equipment_program_subscription;
create policy equipment_program_subscription_tenant_read on public.equipment_program_subscription
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy equipment_program_subscription_write_insert on public.equipment_program_subscription
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.edit', company_id));
create policy equipment_program_subscription_write_update on public.equipment_program_subscription
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.edit', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.edit', company_id));
create policy equipment_program_subscription_write_delete on public.equipment_program_subscription
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.edit', company_id));

-- equipment_visit_line_item — insert equipment.log_maintenance · update equipment.log_maintenance · delete equipment.log_maintenance
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.equipment_visit_line_item;
create policy equipment_visit_line_item_tenant_read on public.equipment_visit_line_item
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy equipment_visit_line_item_write_insert on public.equipment_visit_line_item
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy equipment_visit_line_item_write_update on public.equipment_visit_line_item
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy equipment_visit_line_item_write_delete on public.equipment_visit_line_item
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));

-- facilities — insert company.facilities · update company.facilities · delete company.facilities
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.facilities;
create policy facilities_tenant_read on public.facilities
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy facilities_write_insert on public.facilities
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('company.facilities', company_id));
create policy facilities_write_update on public.facilities
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('company.facilities', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('company.facilities', company_id));
create policy facilities_write_delete on public.facilities
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('company.facilities', company_id));

-- invitations — insert team.invite · update team.invite · delete team.invite
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.invitations;
create policy invitations_tenant_read on public.invitations
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy invitations_write_insert on public.invitations
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('team.invite', company_id));
create policy invitations_write_update on public.invitations
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('team.invite', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('team.invite', company_id));
create policy invitations_write_delete on public.invitations
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('team.invite', company_id));

-- invoice_documents — insert inventory.purchase · update inventory.purchase · delete inventory.purchase
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.invoice_documents;
create policy invoice_documents_tenant_read on public.invoice_documents
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy invoice_documents_write_insert on public.invoice_documents
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));
create policy invoice_documents_write_update on public.invoice_documents
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));
create policy invoice_documents_write_delete on public.invoice_documents
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));

-- maintenance_log — insert equipment.log_maintenance · update equipment.log_maintenance · delete equipment.log_maintenance
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.maintenance_log;
create policy maintenance_log_tenant_read on public.maintenance_log
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy maintenance_log_write_insert on public.maintenance_log
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_log_write_update on public.maintenance_log
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_log_write_delete on public.maintenance_log
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));

-- maintenance_log_step — insert equipment.log_maintenance · update equipment.log_maintenance · delete equipment.log_maintenance
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.maintenance_log_step;
create policy maintenance_log_step_tenant_read on public.maintenance_log_step
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy maintenance_log_step_write_insert on public.maintenance_log_step
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_log_step_write_update on public.maintenance_log_step
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_log_step_write_delete on public.maintenance_log_step
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));

-- maintenance_part_used — insert equipment.log_maintenance · update equipment.log_maintenance · delete equipment.log_maintenance
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.maintenance_part_used;
create policy maintenance_part_used_tenant_read on public.maintenance_part_used
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy maintenance_part_used_write_insert on public.maintenance_part_used
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_part_used_write_update on public.maintenance_part_used
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));
create policy maintenance_part_used_write_delete on public.maintenance_part_used
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.log_maintenance', company_id));

-- maintenance_program — insert equipment.manage_pricing · update equipment.manage_pricing · delete equipment.manage_pricing
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.maintenance_program;
create policy maintenance_program_tenant_read on public.maintenance_program
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy maintenance_program_write_insert on public.maintenance_program
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy maintenance_program_write_update on public.maintenance_program
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy maintenance_program_write_delete on public.maintenance_program
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));

-- maintenance_template — insert equipment.manage_pricing · update equipment.manage_pricing · delete equipment.manage_pricing
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.maintenance_template;
create policy maintenance_template_tenant_read on public.maintenance_template
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy maintenance_template_write_insert on public.maintenance_template
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy maintenance_template_write_update on public.maintenance_template
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy maintenance_template_write_delete on public.maintenance_template
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));

-- parts_catalog — insert equipment.manage_pricing · update equipment.manage_pricing · delete equipment.manage_pricing
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.parts_catalog;
create policy parts_catalog_tenant_read on public.parts_catalog
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy parts_catalog_write_insert on public.parts_catalog
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy parts_catalog_write_update on public.parts_catalog
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy parts_catalog_write_delete on public.parts_catalog
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));

-- parts_catalog_override — insert equipment.manage_pricing · update equipment.manage_pricing · delete equipment.manage_pricing
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.parts_catalog_override;
create policy parts_catalog_override_tenant_read on public.parts_catalog_override
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy parts_catalog_override_write_insert on public.parts_catalog_override
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy parts_catalog_override_write_update on public.parts_catalog_override
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));
create policy parts_catalog_override_write_delete on public.parts_catalog_override
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('equipment.manage_pricing', company_id));

-- qb_import_batches — insert config.import_data · update config.import_data · delete config.import_data
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.qb_import_batches;
create policy qb_import_batches_tenant_read on public.qb_import_batches
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy qb_import_batches_write_insert on public.qb_import_batches
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));
create policy qb_import_batches_write_update on public.qb_import_batches
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));
create policy qb_import_batches_write_delete on public.qb_import_batches
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.import_data', company_id));

-- restock_category — insert config.restock_category · update config.restock_category · delete config.restock_category
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.restock_category;
create policy restock_category_tenant_read on public.restock_category
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy restock_category_write_insert on public.restock_category
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.restock_category', company_id));
create policy restock_category_write_update on public.restock_category
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.restock_category', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.restock_category', company_id));
create policy restock_category_write_delete on public.restock_category
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.restock_category', company_id));

-- roast_recipes — insert recipe.create · update recipe.edit|recipe.archive · delete recipe.archive
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.roast_recipes;
create policy roast_recipes_tenant_read on public.roast_recipes
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy roast_recipes_write_insert on public.roast_recipes
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('recipe.create', company_id));
create policy roast_recipes_write_update on public.roast_recipes
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('recipe.edit', company_id) or public.auth_has_permission('recipe.archive', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('recipe.edit', company_id) or public.auth_has_permission('recipe.archive', company_id)));
create policy roast_recipes_write_delete on public.roast_recipes
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('recipe.archive', company_id));

-- roast_stock_log — insert roast_stock.edit · update roast_stock.edit · delete roast_stock.edit
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.roast_stock_log;
create policy roast_stock_log_tenant_read on public.roast_stock_log
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy roast_stock_log_write_insert on public.roast_stock_log
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('roast_stock.edit', company_id));
create policy roast_stock_log_write_update on public.roast_stock_log
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('roast_stock.edit', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('roast_stock.edit', company_id));
create policy roast_stock_log_write_delete on public.roast_stock_log
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('roast_stock.edit', company_id));

-- roaster_units — insert config.roaster_unit · update config.roaster_unit|roast.log · delete config.roaster_unit.archive
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.roaster_units;
create policy roaster_units_tenant_read on public.roaster_units
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy roaster_units_write_insert on public.roaster_units
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.roaster_unit', company_id));
create policy roaster_units_write_update on public.roaster_units
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('config.roaster_unit', company_id) or public.auth_has_permission('roast.log', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('config.roaster_unit', company_id) or public.auth_has_permission('roast.log', company_id)));
create policy roaster_units_write_delete on public.roaster_units
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.roaster_unit.archive', company_id));

-- sales_area — insert delivery.manage_zones · update delivery.manage_zones · delete delivery.manage_zones
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.sales_area;
create policy sales_area_tenant_read on public.sales_area
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy sales_area_write_insert on public.sales_area
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy sales_area_write_update on public.sales_area
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy sales_area_write_delete on public.sales_area
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));

-- shipping_date — insert delivery.manage_zones · update delivery.manage_zones · delete delivery.manage_zones
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.shipping_date;
create policy shipping_date_tenant_read on public.shipping_date
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shipping_date_write_insert on public.shipping_date
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy shipping_date_write_update on public.shipping_date
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy shipping_date_write_delete on public.shipping_date
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));

-- shipping_recurring_day — insert delivery.manage_zones · update delivery.manage_zones · delete delivery.manage_zones
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.shipping_recurring_day;
create policy shipping_recurring_day_tenant_read on public.shipping_recurring_day
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shipping_recurring_day_write_insert on public.shipping_recurring_day
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy shipping_recurring_day_write_update on public.shipping_recurring_day
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));
create policy shipping_recurring_day_write_delete on public.shipping_recurring_day
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('delivery.manage_zones', company_id));

-- shop_config — insert shop.configure · update shop.configure · delete shop.configure
-- other policies left untouched: public_read_enabled(SELECT)
drop policy if exists tenant_company_access on public.shop_config;
create policy shop_config_tenant_read on public.shop_config
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shop_config_write_insert on public.shop_config
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.configure', company_id));
create policy shop_config_write_update on public.shop_config
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.configure', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.configure', company_id));
create policy shop_config_write_delete on public.shop_config
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.configure', company_id));

-- shop_invitations — insert shop.customer_invite · update shop.customer_invite · delete shop.customer_invite
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.shop_invitations;
create policy shop_invitations_tenant_read on public.shop_invitations
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shop_invitations_write_insert on public.shop_invitations
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.customer_invite', company_id));
create policy shop_invitations_write_update on public.shop_invitations
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.customer_invite', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.customer_invite', company_id));
create policy shop_invitations_write_delete on public.shop_invitations
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('shop.customer_invite', company_id));

-- shopify_connections — insert config.shopify · update config.shopify · delete config.shopify
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.shopify_connections;
create policy shopify_connections_tenant_read on public.shopify_connections
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shopify_connections_write_insert on public.shopify_connections
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));
create policy shopify_connections_write_update on public.shopify_connections
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));
create policy shopify_connections_write_delete on public.shopify_connections
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));

-- shopify_product_mappings — insert config.shopify · update config.shopify · delete config.shopify
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.shopify_product_mappings;
create policy shopify_product_mappings_tenant_read on public.shopify_product_mappings
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy shopify_product_mappings_write_insert on public.shopify_product_mappings
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));
create policy shopify_product_mappings_write_update on public.shopify_product_mappings
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));
create policy shopify_product_mappings_write_delete on public.shopify_product_mappings
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('config.shopify', company_id));

-- size — insert product.create · update product.edit|product.archive · delete product.archive
-- other policies left untouched: catalog_read_global(SELECT)
drop policy if exists tenant_company_access on public.size;
create policy size_tenant_read on public.size
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy size_write_insert on public.size
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('product.create', company_id));
create policy size_write_update on public.size
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('product.edit', company_id) or public.auth_has_permission('product.archive', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('product.edit', company_id) or public.auth_has_permission('product.archive', company_id)));
create policy size_write_delete on public.size
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('product.archive', company_id));

-- staged_line_items — insert inventory.purchase|invoice.process · update inventory.purchase · delete inventory.purchase
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.staged_line_items;
create policy staged_line_items_tenant_read on public.staged_line_items
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy staged_line_items_write_insert on public.staged_line_items
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('invoice.process', company_id)));
create policy staged_line_items_write_update on public.staged_line_items
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));
create policy staged_line_items_write_delete on public.staged_line_items
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));

-- staged_shipments — insert inventory.purchase · update inventory.purchase|inventory.receive|invoice.process · delete inventory.purchase
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.staged_shipments;
create policy staged_shipments_tenant_read on public.staged_shipments
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy staged_shipments_write_insert on public.staged_shipments
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));
create policy staged_shipments_write_update on public.staged_shipments
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('inventory.receive', company_id) or public.auth_has_permission('invoice.process', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('inventory.purchase', company_id) or public.auth_has_permission('inventory.receive', company_id) or public.auth_has_permission('invoice.process', company_id)));
create policy staged_shipments_write_delete on public.staged_shipments
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('inventory.purchase', company_id));

-- standing_order_lines — insert customer.account_management · update customer.account_management · delete customer.account_management
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.standing_order_lines;
create policy standing_order_lines_tenant_read on public.standing_order_lines
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy standing_order_lines_write_insert on public.standing_order_lines
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.account_management', company_id));
create policy standing_order_lines_write_update on public.standing_order_lines
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.account_management', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.account_management', company_id));
create policy standing_order_lines_write_delete on public.standing_order_lines
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('customer.account_management', company_id));

-- supplier — insert supplier.create|config.import_data · update supplier.edit|supplier.archive · delete supplier.archive
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.supplier;
create policy supplier_tenant_read on public.supplier
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy supplier_write_insert on public.supplier
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('supplier.create', company_id) or public.auth_has_permission('config.import_data', company_id)));
create policy supplier_write_update on public.supplier
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('supplier.edit', company_id) or public.auth_has_permission('supplier.archive', company_id))) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and (public.auth_has_permission('supplier.edit', company_id) or public.auth_has_permission('supplier.archive', company_id)));
create policy supplier_write_delete on public.supplier
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('supplier.archive', company_id));

-- tax_forms — insert tax.configure · update tax.configure · delete tax.configure
-- other policies left untouched: none
drop policy if exists tenant_company_access on public.tax_forms;
create policy tax_forms_tenant_read on public.tax_forms
  for select to authenticated using ((company_id IN ( SELECT auth_company_ids() AS auth_company_ids)));
create policy tax_forms_write_insert on public.tax_forms
  for insert to authenticated with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));
create policy tax_forms_write_update on public.tax_forms
  for update to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id)) with check (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));
create policy tax_forms_write_delete on public.tax_forms
  for delete to authenticated using (((company_id IN ( SELECT auth_company_ids() AS auth_company_ids))) and public.auth_has_permission('tax.configure', company_id));

-- ── Probe: every table ends with a read and three gated writes ────────────
do $probe$
declare
  v_t     text;
  v_bad   text := '';
  v_tables text[] := array['channel', 'channel_tax_settings', 'cmarket_alerts', 'company_holiday', 'consumable_inventory_purchased', 'contact_role', 'customer_category', 'customer_discount', 'data_imports', 'equipment', 'equipment_model', 'equipment_program_subscription', 'equipment_visit_line_item', 'facilities', 'invitations', 'invoice_documents', 'maintenance_log', 'maintenance_log_step', 'maintenance_part_used', 'maintenance_program', 'maintenance_template', 'parts_catalog', 'parts_catalog_override', 'qb_import_batches', 'restock_category', 'roast_recipes', 'roast_stock_log', 'roaster_units', 'sales_area', 'shipping_date', 'shipping_recurring_day', 'shop_config', 'shop_invitations', 'shopify_connections', 'shopify_product_mappings', 'size', 'staged_line_items', 'staged_shipments', 'standing_order_lines', 'supplier', 'tax_forms'];
begin
  foreach v_t in array v_tables loop
    -- exactly one SELECT policy carrying no permission clause
    if (select count(*) from pg_policies
         where schemaname='public' and tablename=v_t and cmd='SELECT'
           and policyname = v_t||'_tenant_read') <> 1 then
      v_bad := v_bad || v_t || ':no-read ';
    end if;
    -- one gated policy per write command
    if (select count(*) from pg_policies
         where schemaname='public' and tablename=v_t
           and cmd in ('INSERT','UPDATE','DELETE')
           and coalesce(qual,'')||coalesce(with_check,'') like '%auth_has_permission%') <> 3 then
      v_bad := v_bad || v_t || ':writes ';
    end if;
    -- and NO permissive FOR ALL survivor, which would OR the gate away
    if exists (select 1 from pg_policies
                where schemaname='public' and tablename=v_t and cmd='ALL') then
      v_bad := v_bad || v_t || ':all-policy-survived ';
    end if;
  end loop;

  if v_bad <> '' then
    raise exception 'tranche 1 did not land cleanly: %', v_bad;
  end if;
end
$probe$;

commit;
