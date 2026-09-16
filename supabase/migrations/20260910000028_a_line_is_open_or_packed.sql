-- A line is Open or Packed. "Delivered" is not a line state.
--
-- sync_item_status_on_order_status_change copied the ORDER's status straight
-- onto every one of its lines:
--     UPDATE order_details SET item_status = NEW.order_status WHERE order_id = ...
-- So marking an order Delivered set every line to 'Delivered', and Shipped set
-- them to 'Shipped'. Those are order words. A line is packed into a box or it is
-- not, and every consumer reads it that way:
--
--   ProductFilter.tsx:82   `if (item.item_status !== 'Packed') detailIds.push(...)`
--       — the Tools bulk-pack selected DELIVERED lines for packing. Harmless in
--         the end only because allocate_line_from_stock refuses a second draw.
--   OrderFilter.tsx:79     `item_status === 'Open' && order_status !== 'Delivered'`
--       — had to hand-code a second condition to undo exactly this.
--
-- The line vocabulary is now Open / Packed / Canceled, and the trigger maps into
-- it: anything that means the coffee is in a box and gone — Packed, Delivered,
-- Shipped — lands as Packed.
--
-- Deliberately NOT backfilled. Existing rows keep whatever they were set to:
-- item_status is read, never summed, and rewriting history on every tenant's
-- order_details to tidy a vocabulary is a bigger and riskier act than the fix
-- itself. New transitions are correct from here; old rows stay as they are, and
-- the consumers tolerate both because 'Delivered' simply is not 'Packed'.

begin;

create or replace function public.sync_item_status_on_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  update public.order_details
     set item_status = case
           -- In a box and accounted for.
           when new.order_status in ('Packed', 'Delivered', 'Shipped') then 'Packed'
           -- Back on the shelf, or never leaving it.
           when new.order_status = 'Canceled' then 'Canceled'
           else 'Open'
         end
   where order_id = new.order_id;
  return new;
end;
$fn$;

-- ── Probe: the mapping is what the consumers assume ───────────────────────
do $probe$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc where proname = 'sync_item_status_on_order_status_change';
  if v_src is null then
    raise exception 'sync_item_status_on_order_status_change is missing';
  end if;
  if v_src like '%item_status = NEW.order_status%' or v_src like '%item_status = new.order_status%' then
    raise exception 'the trigger still copies the order status onto the line verbatim';
  end if;
  if v_src not like '%''Packed'', ''Delivered'', ''Shipped''%' then
    raise exception 'the trigger no longer maps Delivered/Shipped onto Packed';
  end if;
end
$probe$;

commit;
