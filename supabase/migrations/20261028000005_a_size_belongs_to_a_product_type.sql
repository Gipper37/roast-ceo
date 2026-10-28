-- A size belongs to a product type, so coffee's weights stop being everyone's.
--
-- ── What the roaster hit ─────────────────────────────────────────────────
--
-- He tried to sell Monin caramel sauce by the bottle and by the case of four,
-- and could not get past the variant form: it asks for a Size, and every Size
-- in the list is a coffee weight. In his words:
--
--     "those size are exclusive to coffee ... if we did have consumable
--      variants they would need to be their own."
--
-- ── Why this column and not a new pack number ────────────────────────────
--
-- 🔴 THE PACK MACHINERY ALREADY WORKS. I claimed otherwise from a superseded
-- migration file; the LIVE functions multiply. `calculate_current_stock_
-- consumables` depletes `SUM(od.quantity * COALESCE(s.units_per_case, 1))`,
-- `get_product_cogs_on_date` and `update_product_total_cogs` cost the pack,
-- and eight live functions in all read `size.units_per_case`. A second pack
-- column would duplicate a mechanism that is already right in all eight.
--
-- So a case of four bottles is already expressible, exactly:
--
--     "Bottle"      base, weight NULL
--     "Case of 4"   base_size_id = Bottle, units_per_case = 4
--
-- `size.weight` is nullable, `size_case_fields_agree` makes `units_per_case`
-- carry a `base_size_id`, and `derive_case_size_weight` leaves a weightless
-- base's case weight alone. Nothing in that chain is coffee-specific.
--
-- The one thing missing is who each size is FOR. There is a single flat list
-- per tenant, so a "Bottle" row would appear forever in coffee's dropdown,
-- and `size.weight` is a coffee weight in POUNDS feeding `product_bag_weight_
-- lbs` and the roast plan -- a "Bottle" with a weight of 1 would be claiming a
-- pound of green coffee. The type is what keeps those apart.
--
-- ── Why the backfill is safe, measured rather than assumed ───────────────
--
-- Production, every size row joined to the products that use it:
--
--     38 size rows, 30 of them in use, and EVERY ONE is used only by
--     product groups of type ptype_coffee. Zero exceptions, all five tenants.
--
-- The 8 unused rows are UK coffee cases and samples. So tagging the existing
-- rows as coffee's states what is already true; no picker loses an entry it
-- has today. Coffee is one shared row (`ptype_coffee`, company_id NULL), not
-- one per tenant, so there is a single id to write.
--
-- NULL stays meaningful: a size that genuinely suits every type can say so by
-- leaving this empty, and the picker admits those everywhere. Nothing creates
-- such a row today, which is why the backfill can be unconditional.

begin;

alter table public.size
  add column if not exists product_type_id text
    references public.product_type(product_type_id) on delete set null;

comment on column public.size.product_type_id is
  'Which product type this size is offered for. NULL means every type. Coffee''s '
  'weights are ptype_coffee so a consumable''s "Bottle" never lands in the bag-size '
  'dropdown, and so size.weight (pounds of coffee, read by product_bag_weight_lbs) '
  'is only ever asked for where pounds of coffee is the honest answer.';

-- Unconditional: see the measurement above. `is null` rather than a blanket
-- write so re-running after a tenant has set one cannot stamp over it.
update public.size
   set product_type_id = 'ptype_coffee'
 where product_type_id is null;

-- The picker filters on it on every product page.
create index if not exists size_product_type_id_idx
  on public.size (product_type_id);

do $$
declare
  n_untyped int;
  has_col   bool;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'size'
       and column_name = 'product_type_id'
  ) into has_col;
  if not has_col then
    raise exception 'size.product_type_id was not added';
  end if;

  -- Holds in any environment, including one with no size rows at all: the
  -- backfill ran against whatever was there. 🔴 NOT asserting a row count or
  -- a particular size -- staging's catalogue is not production's, and an
  -- assertion only production can satisfy would roll back the release.
  select count(*) into n_untyped from public.size where product_type_id is null;
  if n_untyped > 0 then
    raise exception '% size rows still have no product type after the backfill', n_untyped;
  end if;

  raise notice 'size.product_type_id exists and every size row carries a type';
end $$;

commit;
