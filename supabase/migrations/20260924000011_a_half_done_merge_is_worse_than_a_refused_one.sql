-- A half-done merge is worse than a refused one.
--
-- merge_product_variant moves every forward-looking pointer off the retiring
-- product: standing order lines, VMI check-in items, Shopify mappings, the shop
-- shipping product, product filters, customer discounts. It is SECURITY INVOKER,
-- so each of those UPDATEs runs under the caller's RLS — and four of those
-- policies require a permission key of their own. Two are PLAN-gated:
--
--     shopify_product_mappings -> config.shopify               enterprise, enterprise_plus
--     standing_order_lines     -> customer.account_management  pro and above, never starter
--
-- A policy that does not admit you does not raise. It matches zero rows and the
-- UPDATE reports success. So on pro or starter the merge completed, deactivated
-- the variant, wrote its audit row and returned a cheerful jsonb — while a
-- standing order went on drafting against a dead product and a Shopify listing
-- went on pointing at it. Nothing surfaced, and a merge has no undo.
--
-- The function now checks that nothing is left behind and aborts the whole
-- transaction if anything is, naming what it could not move. Refusing is the
-- only honest outcome: the operator can have the key granted, or the plan
-- raised, and try again.
--
-- Body from pg_get_functiondef() and patched in place; not retyped.

begin;

CREATE OR REPLACE FUNCTION public.merge_product_variant(p_keep_id text, p_kill_id text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_keep    public.products%rowtype;
  v_kill    public.products%rowtype;
  v_lines   integer;
  v_units   numeric;
  v_moved   jsonb := '{}'::jsonb;
  v_n       integer;
begin
  if p_keep_id is null or p_kill_id is null then
    raise exception 'merge needs two products';
  end if;
  if p_keep_id = p_kill_id then
    raise exception 'a product cannot be merged into itself';
  end if;

  select * into v_keep from public.products where product_id = p_keep_id;
  if not found then raise exception 'the surviving product does not exist: %', p_keep_id; end if;
  select * into v_kill from public.products where product_id = p_kill_id;
  if not found then raise exception 'the retiring product does not exist: %', p_kill_id; end if;

  if v_keep.company_id is distinct from v_kill.company_id then
    raise exception 'refusing to merge across companies';
  end if;
  if v_kill.merge_into_id is not null then
    raise exception '% is already merged away', p_kill_id;
  end if;
  -- Merging INTO something retired would build a chain; follow it instead.
  if v_keep.merge_into_id is not null then
    raise exception '% is itself retired — merge into % instead', p_keep_id, v_keep.canonical_product_id;
  end if;

  -- Same gate as merge_product_groups, and needed independently: this function
  -- is separately EXECUTE-able by `authenticated` over PostgREST, so gating only
  -- the group-level entry point would leave the variant-level one wide open.
  if not public.auth_has_permission('product.merge', v_kill.company_id) then
    raise exception 'You do not have permission to merge products.'
      using errcode = 'insufficient_privilege';
  end if;

  -- What history stays behind, recorded before anything changes.
  select count(*), coalesce(sum(quantity), 0) into v_lines, v_units
    from public.order_details where product_id = p_kill_id;

  -- ── Forward-looking pointers follow the survivor ──────────────────────
  -- UNIQUE (customer_id, product_id, coffee_prep): a customer who holds a
  -- standing line for BOTH rows at the same prep would make a bare repoint
  -- raise 23505 and abort the whole merge. Fold the quantities together
  -- instead, then drop the loser's line.
  update public.standing_order_lines k
     set quantity = coalesce(k.quantity, 0) + coalesce((
           select sum(d.quantity) from public.standing_order_lines d
            where d.product_id = p_kill_id and d.customer_id = k.customer_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0)
   where k.product_id = p_keep_id
     and exists (select 1 from public.standing_order_lines d
                  where d.product_id = p_kill_id and d.customer_id = k.customer_id
                    and d.coffee_prep is not distinct from k.coffee_prep);
  delete from public.standing_order_lines d
   where d.product_id = p_kill_id
     and exists (select 1 from public.standing_order_lines k
                  where k.product_id = p_keep_id and k.customer_id = d.customer_id
                    and k.coffee_prep is not distinct from d.coffee_prep);
  update public.standing_order_lines set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('standing_order_lines', v_n);

  -- UNIQUE (vmi_checkin_id, product_id, coffee_prep). Same trap, same remedy:
  -- one check-in counting both rows is exactly what a duplicate product causes.
  -- Three figures, not one: observed, suggested and ordered are each counted
  -- per product, so each folds on its own.
  update public.vmi_checkin_items k
     set observed_qty  = coalesce(k.observed_qty, 0) + coalesce((
           select sum(d.observed_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0),
         suggested_qty = coalesce(k.suggested_qty, 0) + coalesce((
           select sum(d.suggested_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0),
         ordered_qty   = coalesce(k.ordered_qty, 0) + coalesce((
           select sum(d.ordered_qty) from public.vmi_checkin_items d
            where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
              and d.coffee_prep is not distinct from k.coffee_prep), 0)
   where k.product_id = p_keep_id
     and exists (select 1 from public.vmi_checkin_items d
                  where d.product_id = p_kill_id and d.vmi_checkin_id = k.vmi_checkin_id
                    and d.coffee_prep is not distinct from k.coffee_prep);
  delete from public.vmi_checkin_items d
   where d.product_id = p_kill_id
     and exists (select 1 from public.vmi_checkin_items k
                  where k.product_id = p_keep_id and k.vmi_checkin_id = d.vmi_checkin_id
                    and k.coffee_prep is not distinct from d.coffee_prep);
  update public.vmi_checkin_items set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('vmi_checkin_items', v_n);

  update public.shopify_product_mappings set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shopify_product_mappings', v_n);

  update public.shop_config set shipping_product_id = p_keep_id where shipping_product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shop_config', v_n);

  update public.product_filter set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('product_filter', v_n);

  -- Polymorphic, no FK: nothing in the database would ever catch this.
  -- UNIQUE (customer_id, scope, coalesce(scope_ref,'__all__')) WHERE is_active.
  -- If the customer already has an ACTIVE rate on the survivor, keep that one
  -- and retire the loser's: two negotiated rates for one product have no
  -- honest merge, and inventing an answer is worse than keeping the rate that
  -- survives with the product.
  update public.customer_discount d
     set is_active = false,
         note = concat_ws(' ', d.note, '(superseded by the merged product''s own rate)')
   where d.scope = 'variant' and d.scope_ref = p_kill_id and d.company_id = v_kill.company_id
     and d.is_active
     and exists (select 1 from public.customer_discount k
                  where k.customer_id = d.customer_id and k.scope = 'variant'
                    and k.scope_ref = p_keep_id and k.is_active);
  update public.customer_discount
     set scope_ref = p_keep_id
   where scope = 'variant' and scope_ref = p_kill_id and company_id = v_kill.company_id
     and is_active;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('customer_discount', v_n);

  -- ── The survivor must be able to sell and consume ─────────────────────
  -- A survivor with no BOM consumes nothing. Copy (never move) so the loser
  -- keeps its own — its order lines are still read through it.
  if not exists (select 1 from public.product_consumables where product_id = p_keep_id)
     and exists (select 1 from public.product_consumables where product_id = p_kill_id) then
    insert into public.product_consumables (product_consumable_id, product_id, consumable_id, quantity, company_id, facility_id)
    select gen_random_uuid()::text, p_keep_id, pc.consumable_id, pc.quantity, pc.company_id, pc.facility_id
      from public.product_consumables pc
     where pc.product_id = p_kill_id
       -- Never give a resold product a BOM line for the consumable it IS:
       -- update_consumable_metrics subtracts the BOM path and the resold path
       -- independently, so that product would double-deduct on every order.
       and pc.consumable_id is distinct from v_keep.source_consumable_id;
    get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('bom_copied', v_n);
  end if;

  -- ── Nothing may be left pointing at the retiring product ─────────────
  -- Every UPDATE above runs under the CALLER's RLS, and four of those policies
  -- demand a permission key of their own — two of them PLAN-gated:
  --   shopify_product_mappings -> config.shopify              (enterprise+ only)
  --   standing_order_lines     -> customer.account_management (not on starter)
  -- On a plan that lacks the key the UPDATE is not refused; it matches zero
  -- rows and reports success. The merge then completed with a Shopify mapping
  -- and a standing-order line still aimed at a product it had just deactivated,
  -- and said nothing. A half-done merge is worse than a refused one, and this
  -- one cannot be undone, so the transaction aborts instead.
  declare
    v_left text;
  begin
    select string_agg(t, ', ') into v_left from (
      select 'standing order lines' as t where exists (select 1 from public.standing_order_lines where product_id = p_kill_id)
      union all
      select 'VMI check-in items'        where exists (select 1 from public.vmi_checkin_items       where product_id = p_kill_id)
      union all
      select 'Shopify product mappings'  where exists (select 1 from public.shopify_product_mappings where product_id = p_kill_id)
      union all
      select 'the shop shipping product' where exists (select 1 from public.shop_config             where shipping_product_id = p_kill_id)
      union all
      select 'product filters'           where exists (select 1 from public.product_filter          where product_id = p_kill_id)
    ) x;
    if v_left is not null then
      raise exception 'This merge would leave % pointing at the retired product, and your plan or role cannot move them. Nothing was merged.', v_left
        using errcode = 'insufficient_privilege';
    end if;
  end;

  -- ── Retire ────────────────────────────────────────────────────────────
  update public.products
     set merge_into_id        = p_keep_id,
         canonical_product_id = v_keep.canonical_product_id,
         is_active            = false
   where product_id = p_kill_id;

  -- Anything already rolling up to the loser now rolls up to the survivor,
  -- so the graph never grows a second hop.
  update public.products
     set canonical_product_id = v_keep.canonical_product_id
   where canonical_product_id = p_kill_id and product_id <> p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('rechained', v_n);

  insert into public.product_merge_log (
    company_id, facility_id, merge_kind, kept_id, kept_name, retired_id, retired_name,
    order_lines_left, units_left, merged_by, notes)
  values (v_kill.company_id, v_kill.facility_id, 'variant', p_keep_id, v_keep.product_name,
          p_kill_id, v_kill.product_name, v_lines, v_units, auth.uid()::text, p_notes);

  return jsonb_build_object(
    'kept', p_keep_id, 'retired', p_kill_id,
    'order_lines_left_in_place', v_lines, 'units_left_in_place', v_units,
    'moved', v_moved);
end; $function$;

do $verify$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'merge_product_variant'
       and pg_get_functiondef(p.oid) ilike '%would leave % pointing at the retired product%'
       and pg_get_functiondef(p.oid) ilike '%auth_has_permission%')
  then
    raise exception 'merge_product_variant lost either its permission check or its leftover check';
  end if;
  raise notice 'a merge now refuses rather than half-completing';
end $verify$;

commit;
