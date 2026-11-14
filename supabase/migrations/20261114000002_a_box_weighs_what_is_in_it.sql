-- A box weighs what is in it, so it carries no weight of its own.
--
-- Owner, 2026-11-14: "why wouldn't the weight be derived from the products in
-- the mixed case." It is now — in lib/shop/shipWeight.ts, on the read, for the
-- storefront and for the postage quote. This migration is the other half: it
-- makes sure the COLUMN can never disagree with that answer.
--
-- 🔴 THE HOLE THIS CLOSES. `products.weight_lbs` is what
-- `handle_order_detail_logic` turns into `order_details.roasted_weight`, and
-- `update_order_aggregates` sets `orders.total_weight` to the SUM of
-- roasted_weight over every line of the order — including the one line per
-- content that `trg_explode_bundle_order_line` writes. A four-bag sampler
-- whose own row also carries four pounds therefore reports EIGHT pounds of
-- coffee for four pounds sold: on the order, in roast demand, and in every
-- function that reads roasted pounds.
--
-- `guard_product_component` already refuses a mixed case whose SIZE carries
-- weight, for exactly this reason. But the column is reachable two other ways:
--
--   1. RETYPING. Nothing clears weight_lbs when a product becomes a Bundle.
--      A 5 lb bag retyped on the product screen's TYPE dropdown — or by
--      `trg_product_group_type_cascade`, which retypes every variant of a
--      group at once — keeps its 5 lb forever, and the size guard never looks
--      because `trg_guard_bundle_parent_stays_valid` only fires when `size` or
--      `product_type` MOVE on a product that ALREADY has contents.
--   2. `update_product_total_cogs` RE-DERIVES IT. That trigger does
--      `select s.weight into v_weight ... if v_weight is not null then
--      NEW.weight_lbs := v_weight`, on every insert and every update. So a box
--      sitting on a weighted size has the weight written back onto it by any
--      unrelated edit — a price change, a rename — with nothing in the UI
--      saying so.
--
-- 🔴 WHICH IS WHY THIS TRIGGER IS NAMED `trg_zz_...` AND NOT `trg_bundle_...`.
-- Row-level BEFORE triggers on one table fire in ALPHABETICAL order, and
-- `trg_update_product_cogs` is the one that re-derives the weight. A name
-- sorting before it would be undone by it on the same statement. The verify
-- block at the bottom asserts both halves of that: that the cogs trigger still
-- re-derives, and that this one still sorts after it.
--
-- It CORRECTS rather than refuses, deliberately. A raise here would turn
-- editing one shared size's weight into a refusal naming some unrelated mixed
-- case, which is the trap that kept mixed cases off shared sizes in the first
-- place. A weight on a box is not a value worth arguing about: it has no
-- meaning, so it goes.
--
-- Nothing to back-fill: prod holds 0 bundle variants today, and 0 with a
-- weight. This is the guard for the first one.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.bundle_has_no_weight()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  -- The type test is in the WHEN clause as well, so this costs one comparison
  -- for every non-bundle row. Repeated here so the function is still correct
  -- if it is ever attached without one.
  if NEW.product_type is distinct from 'ptype_bundle' then
    return NEW;
  end if;

  -- A mixed case's weight is the sum of its contents, which arrive on their
  -- own order lines. Its own row must contribute nothing.
  NEW.weight_lbs := null;
  return NEW;
end
$$;

comment on function public.bundle_has_no_weight() is
  'Keeps products.weight_lbs NULL on a mixed case, so the box cannot double-count the weight that arrives on its contents'' order lines. Must sort AFTER trg_update_product_cogs, which re-derives weight_lbs from the size.';

drop trigger if exists trg_zz_bundle_has_no_weight on public.products;
create trigger trg_zz_bundle_has_no_weight
  before insert or update on public.products
  for each row
  when (NEW.product_type = 'ptype_bundle')
  execute function public.bundle_has_no_weight();

-- ── Verify ────────────────────────────────────────────────────────────────
--
-- Structural, and every assertion can fail: the two that matter read the
-- CATALOGUE, not this file. The behaviour itself is proved by making a mixed
-- case on staging after db-push, not here — a verify block that writes to
-- products would fire eleven other triggers and the demo guard with it.
do $$
declare
  v_type   int2;
  v_cogs   text;
  v_after  boolean;
begin
  select t.tgtype into v_type
  from pg_trigger t
  where t.tgrelid = 'public.products'::regclass
    and t.tgname  = 'trg_zz_bundle_has_no_weight';

  if v_type is null then
    raise exception 'trg_zz_bundle_has_no_weight was not created on public.products';
  end if;
  -- row (1) + before (2) + insert (4) + update (16)
  if (v_type & 1) = 0 then raise exception 'the weight trigger is not FOR EACH ROW (tgtype %)', v_type; end if;
  if (v_type & 2) = 0 then raise exception 'the weight trigger is not BEFORE (tgtype %); AFTER cannot change NEW', v_type; end if;
  if (v_type & 4) = 0 then raise exception 'the weight trigger does not fire on INSERT (tgtype %)', v_type; end if;
  if (v_type & 16) = 0 then
    raise exception 'the weight trigger does not fire on UPDATE (tgtype %); update_product_total_cogs re-derives the weight on every update, so INSERT alone leaves the hole open', v_type;
  end if;

  -- The premise of the name: the cogs trigger writes weight_lbs from the size.
  select p.prosrc into v_cogs
  from pg_trigger t join pg_proc p on p.oid = t.tgfoid
  where t.tgrelid = 'public.products'::regclass
    and t.tgname  = 'trg_update_product_cogs';
  if v_cogs is null then
    raise exception 'trg_update_product_cogs is gone; re-read whether anything still re-derives products.weight_lbs before trusting this trigger''s name';
  end if;
  if position('NEW.weight_lbs := v_weight' in v_cogs) = 0 then
    raise exception 'trg_update_product_cogs no longer re-derives weight_lbs from the size; the ordering this trigger''s name buys may no longer be needed -- read it rather than assuming';
  end if;

  -- ...and this one must fire after it, or its work is overwritten.
  select bool_or(t.tgname > 'trg_zz_bundle_has_no_weight') into v_after
  from pg_trigger t
  where t.tgrelid = 'public.products'::regclass
    and not t.tgisinternal
    and (t.tgtype & 2) <> 0             -- BEFORE triggers only; AFTER cannot touch NEW
    and t.tgname = 'trg_update_product_cogs';
  if coalesce(v_after, false) then
    raise exception 'trg_update_product_cogs sorts AFTER trg_zz_bundle_has_no_weight, so it will write the weight back onto every mixed case';
  end if;
end $$;

commit;
