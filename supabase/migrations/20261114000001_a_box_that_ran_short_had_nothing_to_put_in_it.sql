-- A box that ran short had nothing to put in it.
--
-- 20261113000001 relaxed order_details_quantity_positive to
--   check (quantity > 0 or short_reason is not null)
-- so a line supplied none can be recorded. It is the right constraint and it
-- has a hole underneath it that only mixed cases can fall through.
--
-- 🔴 A BOX SHORTED TO ZERO RE-EXPLODES ITS CONTENTS AT ZERO, WITH NO REASON.
-- trg_explode_bundle_upd fires on a quantity change, DELETEs the children and
-- calls explode_bundle_order_line to write them again at
-- `coalesce(v_line.quantity, 0) * r.quantity`. short_reason was never in that
-- insert's column list, so every child comes back with quantity 0 and
-- short_reason NULL -- which is exactly the row the new CHECK exists to
-- refuse. The packer marks a 12-bag sampler out of stock and the save dies on
-- `order_details_quantity_positive` in front of them. There is no way through
-- it: the box cannot be marked out of stock at all.
--
-- The fix is one clause, and it is the honest one rather than the cheap one:
-- the reason is the PARENT's, because it is the parent that ran short. The
-- contents never had a say -- nobody decided the bags were missing, the box
-- was. quantity_ordered follows for the same reason, scaled by how many of
-- that item the box holds, so a child can still say what would have been in
-- it.
--
-- 🔴 WHY THIS IS DORMANT TODAY AND WILL NOT BE TOMORROW. There are ZERO
-- bundle products and ZERO product_components rows on prod and on staging --
-- the feature shipped 20261112000002 and nobody has ever found it. The
-- "A mixed case" card on New Product is what makes bundles start existing, so
-- this lands first. A defect that is unreachable only because a feature is
-- unfindable is not a dormant defect; it is a scheduled one.
--
-- 🔴 WHAT THIS MIGRATION CANNOT PROVE, SAID OUT LOUD. The verify block below
-- is STRUCTURAL: it reads the installed definition back and asserts the two
-- columns are in the INSERT's column list. It does not explode a real box,
-- because there is no box on prod to explode and a fixture built inside a
-- verify block would fire a dozen unrelated triggers and fail for reasons
-- that are not this one. The functional proof is on staging, through the app,
-- against a real mixed case -- which is the rehearsal the protocol asks for.
--
-- The body below is prod's own pg_get_functiondef output with two lines
-- inserted. Nothing was retyped.

begin;

CREATE OR REPLACE FUNCTION public.explode_bundle_order_line(p_order_detail_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_line  record;
  r       record;
  v_n     integer := 0;
begin
  select * into v_line from public.order_details where order_detail_id = p_order_detail_id;
  if v_line.order_detail_id is null then return 0; end if;
  -- never explode a component line: that is what would recurse
  if v_line.parent_order_detail_id is not null then return 0; end if;

  for r in
    select pc.child_product_id, pc.quantity
      from public.product_components pc
     where pc.parent_product_id = v_line.product_id
     order by pc.sort_order, pc.child_product_id
  loop
    insert into public.order_details (
      order_detail_id, order_id, product_id, quantity, item_status,
      company_id, facility_id, coffee_prep,
      amount_override, parent_order_detail_id,
      quantity_ordered, short_reason
    ) values (
      gen_random_uuid()::text, v_line.order_id, r.child_product_id,
      coalesce(v_line.quantity, 0) * r.quantity, v_line.item_status,
      v_line.company_id, v_line.facility_id, v_line.coffee_prep,
      -- 0, not null: handle_order_detail_logic takes an override ahead of the
      -- catalogue price, so this is what holds the line at zero and keeps the
      -- customer discount off it. The box carries the price.
      0, v_line.order_detail_id,
      -- 🔴 THE BOX'S SHORT IS THE CONTENTS' SHORT.
      -- order_details_quantity_positive (20261113000001) reads
      -- (quantity > 0 or short_reason is not null). A box shorted to
      -- zero re-explodes its contents at zero, and without a reason on
      -- the child the CHECK refuses the insert -- so the packer's save
      -- dies on a raw constraint name and the box cannot be marked out
      -- of stock at all. The reason is the parent's, because it is the
      -- parent that ran short; the contents never had a say.
      case when v_line.quantity_ordered is null then null
           else v_line.quantity_ordered * r.quantity end,
      v_line.short_reason
    );
    v_n := v_n + 1;
  end loop;

  return v_n;
end
$function$;

do $verify$
declare
  v_def text;
  v_ins text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'explode_bundle_order_line';

  if v_def is null then
    raise exception 'explode_bundle_order_line is not installed';
  end if;

  -- 🔴 THE COLUMN LIST, NOT A GREP OF THE BODY. A plain
  -- `v_def like '%short_reason%'` would be satisfied by the COMMENT three
  -- lines below the insert, which is how a prosrc grep passes on a function
  -- that does nothing. Cut the text down to the insert's parenthesised column
  -- list first, then look inside only that.
  v_ins := substring(v_def from 'insert into public\.order_details \(([^)]*)\)');
  if v_ins is null then
    raise exception 'could not find the insert column list in explode_bundle_order_line';
  end if;
  if position('quantity_ordered' in v_ins) = 0 then
    raise exception 'explode_bundle_order_line does not write quantity_ordered (column list was: %)', v_ins;
  end if;
  if position('short_reason' in v_ins) = 0 then
    raise exception 'explode_bundle_order_line does not write short_reason (column list was: %)', v_ins;
  end if;

  -- And the constraint this exists to satisfy is still the one we think it
  -- is. If somebody tightens it back, the clause above stops being enough and
  -- this says so here rather than in front of a packer.
  if not exists (
    select 1 from pg_constraint
     where conname = 'order_details_quantity_positive'
       and pg_get_constraintdef(oid) ilike '%short_reason is not null%'
  ) then
    raise exception 'order_details_quantity_positive no longer admits a zero line with a reason; re-check this fix';
  end if;

  raise notice 'verified: the explode carries the box''s reason onto its contents';
end
$verify$;

commit;
