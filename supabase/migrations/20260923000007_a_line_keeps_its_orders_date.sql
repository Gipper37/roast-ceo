-- order_details.order_date is a copy that nothing kept in sync.
--
-- Every line carries its own copy of the header's date, stamped by
-- handle_order_detail_logic on INSERT OR UPDATE **of the line**. Nothing
-- watches the header. Move an order's date and the lines keep the old one
-- until something unrelated happens to touch them.
--
-- That matters because the copy is not decorative: get_product_cogs_on_date
-- is called with od.order_date by all four of its callers, so the LINE copy
-- is what prices an order's COGS. A header moved to the day the goods
-- actually went out would re-date the order everywhere a human looks while
-- costing it on the day it was originally typed.
--
-- Measured before writing this: exactly ONE line out of 37,637 across every
-- tenant is currently out of step, and it is on the demo tenant. MCR has
-- zero. So this is a latent gap, not live damage -- and it is worth closing
-- now precisely because back-dating just became easy to reach from the
-- order detail page.
--
-- WHY THIS CANNOT FIGHT THE POSTED GUARD. zzz_guard_posted_order_detail
-- refuses writes to the lines of a posted order, which would make this
-- trigger fail -- except guard_posted_order_immutable already refuses to let
-- order_date change on a posted order at all, so the case cannot arise. The
-- two guards agree, and this rides on that.
--
-- DELIBERATELY NARROW. It fires only when order_date actually changes, and it
-- writes only order_date. It does NOT recompute consumable usage: the line's
-- own usage trigger watches quantity and product_id, not the date, and
-- dragging a stock recompute into a date edit is how one edit becomes a
-- trigger storm. Stock still recomputes on its own schedule from the header
-- date, which is what update_consumable_metrics reads.

begin;

create or replace function public.propagate_order_date_to_details()
returns trigger
language plpgsql
as $function$
begin
  update public.order_details
     set order_date = NEW.order_date
   where order_id = NEW.order_id
     and order_date is distinct from NEW.order_date;
  return null;
end;
$function$;

comment on function public.propagate_order_date_to_details() is
  'Keeps order_details.order_date in step with its header. The line copy is what get_product_cogs_on_date is called with, so a header date that moves without it silently costs the order on the wrong day.';

drop trigger if exists trg_propagate_order_date on public.orders;
create trigger trg_propagate_order_date
  after update of order_date on public.orders
  for each row
  when (old.order_date is distinct from new.order_date)
  execute function public.propagate_order_date_to_details();

-- Bring the stragglers into line. One row today, but this is the statement
-- that makes the invariant true rather than merely true from now on.
set local lock_timeout = '2s';
update public.order_details od
   set order_date = o.order_date
  from public.orders o
 where o.order_id = od.order_id
   and od.order_date is distinct from o.order_date;

do $$
declare
  v_drift int;
begin
  select count(*) into v_drift
  from public.order_details od join public.orders o on o.order_id = od.order_id
  where od.order_date is distinct from o.order_date;
  if v_drift > 0 then
    raise exception '% order lines still disagree with their header date', v_drift;
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.orders'::regclass and tgname = 'trg_propagate_order_date'
  ) then
    raise exception 'trg_propagate_order_date was not created';
  end if;
end $$;

commit;
