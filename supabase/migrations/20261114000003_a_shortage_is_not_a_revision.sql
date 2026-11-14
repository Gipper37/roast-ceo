-- A shortage is not a revision of the order.
--
-- The Revised orders bar exists in the owner's own words: *"the production
-- related roles should have a status/warning section at the top of orders that
-- says an order has been revised."* RevisedOrdersBar.tsx says what it is for:
-- *"an order can change while somebody is packing it, and this is how they
-- find out."* It is a PRODUCTION alert -- somebody changed this under you.
--
-- A short is written BY the person packing, at the bench, as part of packing.
-- They do not need to be told about it, and it lowers what anyone else has to
-- roast or pack. So `trg_stamp_order_revision_upd` has no WHEN clause and
-- fires on every quantity move, which means a pick round with six shortages
-- puts six orders in that bar. Whoever watches it for genuine corrections then
-- has to clear routine shelf shortages out of it, and stops reading it -- which
-- costs the feature the bar was built for.
--
-- 🔴 THE PREDICATE IS NOT "short_reason MOVED". A second short on the same
-- line (10 → 9, then 9 → 8) leaves BOTH `short_reason` and `quantity_ordered`
-- exactly where they were: only `quantity` moves. A WHEN clause keyed on the
-- reason moving would have silenced the first short and stamped the second,
-- which is the worst of both. The test is the STATE of the line:
--
--   * short afterwards            -> the short being recorded or deepened
--   * was short, and the count is
--     back at `quantity_ordered`  -> the short being UNDONE
--
-- and anything else is a revision. That second arm is what tells an undo from
-- an office edit: `clearLineOutOfStock` restores the count to exactly
-- `quantity_ordered`, while cutting the order to five does not. Both are
-- `short_reason` going to null with the count rising or falling, and without
-- the `quantity_ordered` test the office edit would have been silenced too --
-- the one case in all of this that production genuinely has to see.
--
-- 🔴 AND A CHANGE TO SOMETHING OTHER THAN THE COUNT STILL STAMPS, even on a
-- line that is short: the product, the grind and the discount are all in this
-- trigger's column list because moving one of them is a real revision, and a
-- line that happens to be short must not become a quiet place to make one.
--
-- `amount_override` is deliberately NOT in that list. A short RESTATES a typed
-- amount at the same unit (overrideForCount: $160.20 over ten becomes $144.18
-- over nine), so requiring it to hold still would stamp every short of the 17
-- prod lines that carry one. The cost is that retyping an amount by hand on a
-- line that is already short does not raise the bar. The alternative is
-- re-deriving the short's own arithmetic inside a WHEN clause to tell the two
-- apart, which is a guard that infers intent from a rounded figure.
--
-- 🔴 THE TRIGGER IS REPLACED, THE FUNCTION IS NOT TOUCHED.
-- `stamp_order_revision()` is shared with the INSERT/DELETE trigger and with
-- the header trigger on `orders`; this is a statement about one of the three.
-- The column list is unchanged: `short_reason` and `quantity_ordered` are
-- deliberately absent from it, so a write that moves nothing but those two
-- never reaches the WHEN clause at all.

begin;

-- CREATE OR REPLACE TRIGGER takes ACCESS EXCLUSIVE on order_details. It is
-- held for microseconds, but it queues behind the hourly matview refresh at
-- :10 and would then be a queue-head blocker in front of every order read.
-- Three seconds, then roll back and retry, rather than park.
set local lock_timeout = '3s';

create or replace trigger trg_stamp_order_revision_upd
  after update of quantity, product_id, amount_override, discount_kind, discount_value, coffee_prep
  on public.order_details
  for each row
  when (
    not (
      new.short_reason is not null
      or (old.short_reason is not null
          and new.quantity is not distinct from old.quantity_ordered)
    )
    or new.product_id is distinct from old.product_id
    or new.coffee_prep is distinct from old.coffee_prep
    or new.discount_kind is distinct from old.discount_kind
    or new.discount_value is distinct from old.discount_value
  )
  execute function public.stamp_order_revision();

comment on trigger trg_stamp_order_revision_upd on public.order_details is
  'Flags an order as revised when a line changes under production. A short -- recorded, deepened or undone -- is not a revision: the packer wrote it, and it lowers what anyone else has to make. A move of the product, grind or discount still flags, even on a line that is short.';

-- ── Prove it ───────────────────────────────────────────────────────────────
-- Structural only, deliberately. A behavioural assertion here would need a
-- tenant, a customer and an order to write against, and a verify block that
-- can only RAISE rolls back the whole release when it is wrong about the
-- fixture rather than about the change.
do $$
declare
  v_qual text;
  v_bits integer;
begin
  select pg_get_triggerdef(t.oid), t.tgtype
    into v_qual, v_bits
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'order_details'
     and t.tgname = 'trg_stamp_order_revision_upd';

  if v_qual is null then
    raise exception 'trg_stamp_order_revision_upd is gone, so nothing flags a revised order at all';
  end if;

  -- The WHEN clause survived, and it is the one written above rather than an
  -- earlier attempt: all three columns the predicate turns on have to be in it.
  if position('short_reason' in v_qual) = 0 then
    raise exception 'the trigger has no short_reason test, so every shortage still flags a revision';
  end if;
  if position('quantity_ordered' in v_qual) = 0 then
    raise exception 'the trigger cannot tell an UNDO from an office edit without quantity_ordered';
  end if;
  if position('coffee_prep' in v_qual) = 0 then
    raise exception 'a grind change on a short line would be silenced';
  end if;

  -- AFTER (bit 2 clear), ROW (bit 1 set), UPDATE (bit 16 set), and NOT insert
  -- or delete: a trigger replaced into the wrong timing would run before the
  -- row exists.
  if (v_bits & 1) = 0 then raise exception 'the revision stamp is no longer FOR EACH ROW'; end if;
  if (v_bits & 2) <> 0 then raise exception 'the revision stamp became a BEFORE trigger'; end if;
  if (v_bits & 16) = 0 then raise exception 'the revision stamp no longer fires on UPDATE'; end if;
  if (v_bits & 4) <> 0 or (v_bits & 8) <> 0 then
    raise exception 'the UPDATE trigger now also fires on insert or delete, which the _ins trigger already does';
  end if;

  -- The function it calls still does the work. CREATE OR REPLACE TRIGGER does
  -- not touch it, so this asserts nothing else in this release did.
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'stamp_order_revision'
       and p.prosrc like '%revision_dismissed_at%'
  ) then
    raise exception 'stamp_order_revision no longer clears the dismissal, so the bar cannot re-raise';
  end if;

  raise notice 'a shortage no longer flags the order as revised';
end $$;

commit;
