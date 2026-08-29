-- Whether you sell a thing is not what the thing IS.
--
-- The order form needs to know what may be put on an invoice. There were two
-- ways to express that and the owner asked which:
--
--   (A) sellability is its own attribute, defaulted by type and overridable per
--       product
--   (B) bake it into the type — "Consumable (sellable)", "Consumable (internal)",
--       "Coffee (sellable)", "Coffee (not for resale)", and so on
--
-- (B) IS THE WRONG ONE, and the data says why rather than taste. There are 6
-- types across 1,035 products, and exactly TWELVE products are the exception —
-- MCR's internal consumables, the bags and filters. Doubling the type list and
-- re-typing a thousand products to express twelve exceptions is a bad trade on
-- its own.
--
-- But the real objection is that product_type is LOAD-BEARING for money. A tax
-- rule can be keyed on it and a discount can be scoped to it. Split the type on
-- an unrelated axis and every one of those has to be doubled too, forever: a
-- discount on "Coffee" would silently miss "Coffee (not for resale)", and a tax
-- rule for consumables would miss half of them. Nobody would notice until an
-- invoice was wrong. Sellability and identity vary independently, so they get
-- separate columns.
--
-- (A) also happens to be the shape this app already uses everywhere else. Tax
-- resolves rule -> customer -> order. A discount resolves store -> category ->
-- product. Sellability now resolves TYPE -> PRODUCT. That is a pattern an
-- operator has already learned twice, not a third thing to learn.
--
-- ── AND SERVICE WAS SEEDED WRONG ─────────────────────────────────────────────
-- product_type.is_sellable marks Service false. MCR has invoiced 290 service
-- lines worth $24,696.88 — Labor, Service Fee, Equipment Lease. That flag would
-- have blocked genuine business, so it is corrected here rather than worked
-- around in a query.

begin;

alter table public.product_groups
  add column if not exists is_sellable boolean;

comment on column public.product_groups.is_sellable is
  'Whether this product may be put on an order. NULL inherits the default from '
  'its product_type, which is the normal case — set it only for an exception. '
  'Deliberately separate from product_type: what a thing IS and whether you sell '
  'it vary independently, and the type is load-bearing for tax rules and '
  'category discounts that would all have to be duplicated if the two were '
  'merged.';

-- Service is sellable. Corrected from the seed, not from a query.
update public.product_type
   set is_sellable = true, updated_at = now()
 where product_type_id = 'ptype_service' and is_sellable = false;

-- The twelve exceptions, made EXPLICIT rather than left to a hidden rule in the
-- query. An internal consumable is one with no source_consumable_id — it is a
-- supply the roaster buys for itself, not something resold. Writing it down
-- means an operator can SEE that a filter is not sellable, and can change it the
-- day they start reselling filters.
update public.product_groups pg
   set is_sellable = false
 where pg.is_sellable is null
   and exists (
     select 1 from public.products p
      join public.product_type pt on pt.product_type_id = p.product_type
     where p.group_id = pg.group_id
       and lower(pt.product_type) = 'consumable'
       and p.source_consumable_id is null
   )
   and not exists (
     -- ...unless some variant of it IS resold, in which case the product as a
     -- whole is sellable and only that variant is internal.
     select 1 from public.products p2
      where p2.group_id = pg.group_id and p2.source_consumable_id is not null
   );

-- One place that answers "can this be sold", so the order form, the shop and
-- anything later all agree without each re-deriving it.
create or replace function public.product_is_sellable(p_group_id uuid)
returns boolean
language sql
stable
as $function$
  select coalesce(
           pg.is_sellable,                    -- the product's own answer, if set
           pt.is_sellable,                    -- otherwise its type's default
           true                               -- otherwise sellable: a product with
         )                                    -- no type is not a reason to hide it
  from public.product_groups pg
  left join public.product_type pt on pt.product_type_id = pg.product_type
  where pg.group_id = p_group_id;
$function$;

comment on function public.product_is_sellable is
  'Can this product go on an order? The product''s own is_sellable if set, '
  'otherwise its type''s default. Discount-type products are excluded separately '
  'by the caller — they are not a product at all any more, they are the old model.';

commit;
