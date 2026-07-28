-- product_type moves to the PRODUCT (product_groups), where it belongs.
--
-- product_groups IS the product; products rows are its VARIANTS (size × channel).
-- A variant can never be a different KIND of thing than the product it varies —
-- "House Blend - 12oz - Wholesale" is Coffee because House Blend is Coffee. Yet
-- product_type has always lived on products, denormalized onto every variant.
--
-- That is an artifact, not a design: products.product_type already existed holding
-- the OLD meaning (Retail DTC / Wholesale Bulk / Sample / Merged — all is_active
-- false today) and the taxonomy work repurposed the column in place rather than
-- moving it. The cost shows up wherever you need a product's type without loading
-- its variants: the QuickBooks import wizard's "Product" picker could not filter by
-- the chosen Type at all, so picking Coffee still listed every consumable.
--
-- Verified before writing (prod, every tenant): 416 product_groups, ZERO with
-- variants of differing product_type, ZERO variants with a NULL type outside the
-- 2 variant-less groups below. The denormalization has never actually diverged.
--
-- This migration makes the group AUTHORITATIVE while KEEPING products.product_type
-- correct, so every existing reader keeps working untouched. Retiring the variant
-- column is a separate change, after auditing its readers.

begin;

-- ── 1. The column ──────────────────────────────────────────────────────────
alter table public.product_groups
  add column if not exists product_type text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_groups'::regclass
      and conname = 'product_groups_product_type_fkey'
  ) then
    -- Mirrors products_product_type_fkey exactly (text id, SET NULL on delete).
    alter table public.product_groups
      add constraint product_groups_product_type_fkey
      foreign key (product_type) references public.product_type(product_type_id)
      on delete set null;
  end if;
end $$;

-- Filtering products BY type is the whole point of the move.
create index if not exists idx_product_groups_product_type
  on public.product_groups (product_type)
  where product_type is not null;

-- ── 2. Backfill from the variants ──────────────────────────────────────────
-- min() is not an arbitrary pick: no group has more than one distinct type
-- (asserted below), so min() IS the group's type.
update public.product_groups g
set product_type = v.product_type
from (
  select group_id, min(product_type) as product_type
  from public.products
  where group_id is not null and product_type is not null
  group by group_id
) v
where v.group_id = g.group_id
  and g.product_type is distinct from v.product_type;

-- Fail loudly rather than silently mis-typing a product, in case a tenant created
-- a mixed group between the check above and this migration running.
do $$
declare mixed int;
begin
  select count(*) into mixed from (
    select group_id from public.products
    where group_id is not null and product_type is not null
    group by group_id having count(distinct product_type) > 1
  ) x;
  if mixed > 0 then
    raise exception 'product_type is not a group property: % group(s) have variants of differing type', mixed;
  end if;
end $$;

-- Left NULL by design: the only groups without a derivable type are ones with no
-- variants at all (a demo "test" group and one empty "Roasters Choice"). They get
-- a type the moment they get their first variant — see the self-heal trigger.

-- ── 3. Keep the two in sync, group-wins ────────────────────────────────────
-- A variant NEVER dictates its product's type when the product already has one.
create or replace function public.products_inherit_group_type()
returns trigger
language plpgsql
as $$
declare gtype text;
begin
  if new.group_id is null then
    return new;
  end if;
  select product_type into gtype from public.product_groups where group_id = new.group_id;
  if gtype is not null then
    new.product_type := gtype;
  end if;
  return new;
end $$;

drop trigger if exists trg_products_inherit_group_type on public.products;
create trigger trg_products_inherit_group_type
  before insert or update of product_type, group_id on public.products
  for each row execute function public.products_inherit_group_type();

-- Self-heal the other direction: a brand-new product created variant-first (the QB
-- importer inserts the group before it knows the type) adopts its first variant's
-- type. Only fills a NULL — it can never overwrite the product's own answer.
create or replace function public.product_group_adopt_variant_type()
returns trigger
language plpgsql
as $$
begin
  if new.group_id is null or new.product_type is null then
    return null;
  end if;
  update public.product_groups
  set product_type = new.product_type
  where group_id = new.group_id and product_type is null;
  return null;
end $$;

drop trigger if exists trg_product_group_adopt_variant_type on public.products;
create trigger trg_product_group_adopt_variant_type
  after insert or update of product_type, group_id on public.products
  for each row execute function public.product_group_adopt_variant_type();

-- Retyping the PRODUCT retypes its variants. The `is distinct from` guard stops
-- this from ping-ponging with the inherit trigger above.
create or replace function public.product_group_type_cascade()
returns trigger
language plpgsql
as $$
begin
  if new.product_type is null then
    return null;
  end if;
  update public.products
  set product_type = new.product_type
  where group_id = new.group_id
    and product_type is distinct from new.product_type;
  return null;
end $$;

drop trigger if exists trg_product_group_type_cascade on public.product_groups;
create trigger trg_product_group_type_cascade
  after update of product_type on public.product_groups
  for each row
  when (new.product_type is distinct from old.product_type)
  execute function public.product_group_type_cascade();

commit;

-- New column has to be visible to PostgREST or the frontend can't select it.
notify pgrst, 'reload schema';
