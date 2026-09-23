-- A quoted consumable price is not an invoiced one.
--
-- coffee_inventory_purchased carries cost_lb AND target_cost_lb, and the
-- coffee order form makes the operator say which one they are typing: a
-- target is what the supplier quoted, an actual is what the invoice said, and
-- only the actual becomes cost of goods. consumable_inventory_purchased has
-- one column, cost_unit, so a consumable order had nowhere to put a quote.
--
-- The consequence was not a missing feature, it was a wrong number. Ordering
-- is the mode where you are working from a quote, and every figure typed
-- there landed in cost_unit -- the column that costs the item. A price the
-- supplier had merely quoted became the item's real cost the moment the order
-- was saved, and from there it feeds fallback costing and every margin that
-- reads it.
--
-- So: the same pair coffee has. target_cost_unit for the quote, cost_unit
-- stays the invoiced truth. Nullable with no default, exactly like
-- target_cost_lb -- most lines will only ever have one of the two, and a
-- zero would be a claim that something was free.
--
-- NOT backfilled. Existing rows have one number and no record of which kind
-- it was; inventing a split would be making up history. They stay as
-- invoiced, which is how everything downstream has always read them.

begin;

alter table public.consumable_inventory_purchased
  add column if not exists target_cost_unit numeric;

comment on column public.consumable_inventory_purchased.target_cost_unit is
  'The QUOTED price per unit — what you expect to pay. Never cost of goods. Mirrors coffee_inventory_purchased.target_cost_lb; cost_unit remains the invoiced figure that costs the item.';

comment on column public.consumable_inventory_purchased.cost_unit is
  'The INVOICED price per unit. This is what costs the item. A quote belongs in target_cost_unit.';

do $$
declare v_type text; v_notnull boolean;
begin
  select data_type, is_nullable = 'NO' into v_type, v_notnull
    from information_schema.columns
   where table_schema = 'public' and table_name = 'consumable_inventory_purchased'
     and column_name = 'target_cost_unit';

  if v_type is null then
    raise exception 'target_cost_unit was not added';
  end if;

  -- Must match target_cost_lb's shape: numeric and nullable. A NOT NULL or a
  -- zero default would turn "no quote" into "quoted at nothing".
  if v_type <> 'numeric' or v_notnull then
    raise exception 'target_cost_unit is % / notnull=% — target_cost_lb is numeric and nullable',
      v_type, v_notnull;
  end if;

  -- Nothing was touched: every existing line keeps its invoiced cost and has
  -- no quote, which is the honest reading of rows written before the split.
  if exists (select 1 from consumable_inventory_purchased where target_cost_unit is not null) then
    raise exception 'target_cost_unit was populated — this migration must not invent history';
  end if;

  raise notice 'target_cost_unit added beside cost_unit on % line(s), none backfilled',
    (select count(*) from consumable_inventory_purchased);
end $$;

commit;
