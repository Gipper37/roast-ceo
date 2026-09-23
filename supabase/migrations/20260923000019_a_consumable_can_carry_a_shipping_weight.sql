-- A consumable can say what it weighs, so the shop can ship it.
--
-- The storefront prices shipping per POUND, off products.weight_lbs. Every one
-- of the 327 coffee products carries a weight and every one of the 105
-- consumables carries none, so a cart of syrups computes zero pounds and ships
-- FREE at any rate. Not some consumables -- all of them.
--
-- The owner's fix, and it is the right shape: "we could resolve the shipping
-- for consumable by adding a shipping weight the the consumable adds and
-- detail page?" A bottle has a weight; the app simply never asked.
--
-- WHERE IT LIVES. On the consumable, because that is the thing an operator
-- weighs, and propagated to its resale variants' products.weight_lbs -- which
-- is the column the shop already reads, so nothing downstream changes. Exactly
-- how the NAME already works: propagate_consumable_name_to_products keeps the
-- product named after the consumable, and this keeps it weighed after it.
--
-- One source of truth, mirrored. A weight typed on the product directly would
-- be a second one, and the two would drift the way the srm names did.
--
-- Only when it is positive: products_weight_lbs_positive refuses zero, and a
-- consumable nobody has weighed should stay null rather than claim to weigh
-- nothing.

begin;

alter table public.consumable_inventory
  add column if not exists shipping_weight_lbs numeric;

alter table public.consumable_inventory
  drop constraint if exists consumable_shipping_weight_positive;
alter table public.consumable_inventory
  add constraint consumable_shipping_weight_positive
  check (shipping_weight_lbs is null or shipping_weight_lbs > 0);

comment on column public.consumable_inventory.shipping_weight_lbs is
  'What one unit weighs, in pounds, for shipping. Propagated to the resale variants'' products.weight_lbs, which is what the storefront prices shipping from. Null means nobody has weighed it.';

create or replace function public.propagate_consumable_weight_to_products()
returns trigger
language plpgsql
as $function$
begin
  if NEW.shipping_weight_lbs is distinct from OLD.shipping_weight_lbs
     and NEW.shipping_weight_lbs is not null
     and NEW.shipping_weight_lbs > 0 then
    update public.products
       set weight_lbs = NEW.shipping_weight_lbs,
           updated_at = now()
     where source_consumable_id = NEW.consumable_inventory_id
       and weight_lbs is distinct from NEW.shipping_weight_lbs;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_propagate_consumable_weight on public.consumable_inventory;
create trigger trg_propagate_consumable_weight
  after update of shipping_weight_lbs on public.consumable_inventory
  for each row execute function public.propagate_consumable_weight_to_products();

do $$
declare
  v_unweighed int;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='consumable_inventory'
      and column_name='shipping_weight_lbs'
  ) then
    raise exception 'shipping_weight_lbs was not added';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.consumable_inventory'::regclass
      and tgname='trg_propagate_consumable_weight'
  ) then
    raise exception 'the weight propagation trigger was not attached';
  end if;

  -- Say plainly how many resold items still ship free, so the size of the
  -- data-entry job is on the record rather than a surprise later.
  select count(*) into v_unweighed
  from public.products p
  where p.source_consumable_id is not null and p.is_active
    and coalesce(p.weight_lbs, 0) = 0;
  raise notice '% resold consumable variants still have no shipping weight and will ship free', v_unweighed;
end $$;

commit;
