-- A consumable that is no longer resold leaves no product behind.
--
-- Marking a consumable Resale MINTS a product for it: createResoldProductForConsumable
-- inserts a products row carrying source_consumable_id. Changing the type away
-- from Resale wrote only consumable_inventory.consumable_type and did nothing
-- else, so the product it had created stayed on the Products page -- sellable,
-- for a thing that is now an ingredient in something else rather than something
-- you sell.
--
-- MEASURED ON PROD, all tenants:
--   3 products whose consumable is no longer Resale, all at MCR, all typed
--   other_bom, all still active, and NONE with a single order line.
-- The roaster created them as resale, then switched them to "other BOM" to use
-- them as a cost inside another product, and the phantom products remained.
--
-- ARCHIVED, not deleted. Archiving is reversible and is what the rest of this
-- app means by taking something off sale. A delete would take order history with
-- it if any of these ever acquired some, and none of them has any today only by
-- luck of timing. Marking the consumable Resale again is the roaster's own act,
-- and the product is sitting there to be restored.
--
-- The code path is fixed in the same release (stratos, updateConsumableType), so
-- this cleans up the three that already exist rather than a class of them.

begin;

update public.products p
   set is_active = false
  from public.consumable_inventory ci
 where ci.consumable_inventory_id = p.source_consumable_id
   and ci.consumable_type is distinct from 'global_consumable_type_distribution'
   and p.is_active
   and p.merge_into_id is null;

do $verify$
declare v_bad int;
begin
  -- No product is left on sale for a consumable that is not resold.
  select count(*) into v_bad
    from public.products p
    join public.consumable_inventory ci on ci.consumable_inventory_id = p.source_consumable_id
   where ci.consumable_type is distinct from 'global_consumable_type_distribution'
     and p.is_active and p.merge_into_id is null;
  if v_bad > 0 then
    raise exception '% product(s) still on sale for a consumable that is not resold', v_bad;
  end if;

  -- And nothing that IS still resold was touched. This must not reach the 97
  -- live resale products.
  select count(*) into v_bad
    from public.products p
    join public.consumable_inventory ci on ci.consumable_inventory_id = p.source_consumable_id
   where ci.consumable_type = 'global_consumable_type_distribution'
     and p.merge_into_id is null
     and not p.is_active
     and p.updated_at > now() - interval '1 minute';
  if v_bad > 0 then
    raise exception 'this archived % product(s) whose consumable IS still resold', v_bad;
  end if;
end;
$verify$;

commit;
