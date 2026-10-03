-- A consumable you no longer stock is not on sale.
--
-- Marking a resale consumable Resale MINTS a product for it. Archiving that
-- consumable did nothing to the product, so the product stayed on the Products
-- page, sellable, for an item the roaster has taken out of inventory.
-- toggleConsumableActive (stratos, app/app/(app)/inventory/actions.ts) writes
-- consumable_inventory.is_active and nothing else.
--
-- Owner, 2026-10-02, on finding Monin Caramel Sauce in that state: "that
-- shouldn't be possible that a consumable product is allowed to exist."
--
-- MEASURED ON PROD, all tenants: exactly one. Monin Caramel Sauce at MCR,
-- product 0b00382e, carrying 14 order lines. Archived, not deleted, because
-- those 14 lines are history.
--
-- 🔴 WHY updated_at COULD NOT DATE THE DAMAGE. nudge_all_inventory() runs
-- hourly and sets updated_at = NOW() on every consumable whose facility has
-- just reached midnight. Last night it stamped 221 MCR consumables with one
-- identical timestamp. So consumable_inventory.updated_at records when the
-- cron last ran, not when anybody changed anything, and there was no way to
-- tell when this consumable was archived. That is worth fixing on its own; it
-- is not fixed here.
--
-- THE GUARD IS ONE-DIRECTIONAL, DELIBERATELY. Archiving a consumable archives
-- the product: you cannot sell what you have taken out of inventory. Restoring
-- a consumable does NOT bring the product back, because the reverse is a real
-- and different intention -- six MCR products sit archived today against a live
-- consumable (Nice Matcha 1.1lb with 77 order lines, Bhakti Chai with 22),
-- which is a roaster who still stocks the item and has stopped reselling it.
-- Resurrecting those would undo a decision, so restoring stays a deliberate act
-- on the product.
--
-- The trigger is the guard rather than the frontend action, because the action
-- is one of several paths and a future one would reopen this. It fires only
-- when is_active actually goes true -> false, so the hourly nudge, which never
-- touches is_active, cannot trip it.

begin;

create or replace function public.archive_products_with_consumable()
returns trigger
language plpgsql
as $function$
begin
  update public.products
     set is_active = false
   where source_consumable_id = new.consumable_inventory_id
     and is_active
     and merge_into_id is null;
  return new;
end;
$function$;

comment on function public.archive_products_with_consumable() is
  'Takes a resold product off sale when its consumable is archived. One way only: restoring the consumable does not restore the product, because stocking an item again is not the same decision as selling it again.';

drop trigger if exists trg_archive_products_with_consumable on public.consumable_inventory;
create trigger trg_archive_products_with_consumable
  after update of is_active on public.consumable_inventory
  for each row
  when (old.is_active and not new.is_active)
  execute function public.archive_products_with_consumable();

-- The one that already got through.
update public.products p
   set is_active = false
  from public.consumable_inventory ci
 where ci.consumable_inventory_id = p.source_consumable_id
   and not ci.is_active
   and p.is_active
   and p.merge_into_id is null;

do $verify$
declare v_bad int;
begin
  -- Nothing is on sale for a consumable that is not stocked.
  select count(*) into v_bad
    from public.products p
    join public.consumable_inventory ci on ci.consumable_inventory_id = p.source_consumable_id
   where p.is_active and not ci.is_active and p.merge_into_id is null;
  if v_bad > 0 then
    raise exception '% product(s) still on sale for an archived consumable', v_bad;
  end if;

  -- 🔴 The six deliberately-retired products are UNTOUCHED. This migration
  -- archives; it must never restore.
  select count(*) into v_bad
    from public.products p
    join public.consumable_inventory ci on ci.consumable_inventory_id = p.source_consumable_id
   where p.is_active and ci.is_active and p.merge_into_id is null
     and p.updated_at > now() - interval '1 minute';
  if v_bad > 0 then
    raise exception 'this restored % product(s); it must only archive', v_bad;
  end if;

  -- And nothing whose consumable is live was archived by it either.
  select count(*) into v_bad
    from public.products p
    join public.consumable_inventory ci on ci.consumable_inventory_id = p.source_consumable_id
   where ci.is_active and not p.is_active and p.merge_into_id is null
     and p.updated_at > now() - interval '1 minute';
  if v_bad > 0 then
    raise exception 'this archived % product(s) whose consumable is still stocked', v_bad;
  end if;

  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.consumable_inventory'::regclass
                    and tgname = 'trg_archive_products_with_consumable') then
    raise exception 'the guard trigger was not created';
  end if;
end;
$verify$;

commit;
