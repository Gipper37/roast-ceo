-- assistant_roaster keeps the roast-stock logging it already does.
--
-- Converting app/(app)/roast/actions.ts to the catalog would otherwise TAKE a
-- capability away. logRoastStock and logRoastStockBulk each carry two gates that
-- disagree:
--
--   requirePermission('roast_stock.edit')   → company_admin, facility_admin,
--                                             manager, roastmaster
--   const allowed = [...]                   → those four PLUS assistant_roaster
--
-- The array runs second, so today assistant_roaster logs roast stock and the
-- catalog says they cannot. Deleting the array without this migration makes the
-- catalog win and quietly removes a daily roast-floor task from the role whose
-- entire job is assisting on the roaster.
--
-- The conversion is supposed to be a no-op. So: grant the key, delete the array,
-- and the decision moves to the dev portal where it can be argued about on its
-- merits rather than settled by whichever gate happens to run last.
--
-- Everything else in that file converts with no delta:
--   addChargeWeight            array == config.roaster_unit          (identical)
--   toggleRoasterUnitActive    array == config.roaster_unit.archive  (identical)
--   addRoasterUnit             array is NARROWER than config.roaster_unit —
--   updateRoasterUnit          roastmaster holds the key and the array denies
--                              them, so those two GAIN roastmaster, which is
--                              what the catalog already intends.

begin;

insert into public.role_permissions (role_id, permission_id, granted)
values ('assistant_roaster', 'roast_stock.edit', true)
on conflict (role_id, permission_id) do update
  set granted = true, updated_at = now();

commit;

notify pgrst, 'reload schema';
