-- Merging two products into one.
--
-- Builds on 20260924000002, which installed the canonical pointers and removed
-- the old path. This adds the operation itself.
--
-- THE SHAPE. A merge retires the loser and points it at the survivor. It moves
-- NO order line, deletes NO BOM, and changes NO group_id. What it does move is
-- the FORWARD-LOOKING links — the things that decide what happens next:
-- standing orders, VMI check-ins, Shopify mappings, the shop's shipping
-- product, saved filters, and customer discounts. Those must follow the
-- survivor or the merge is cosmetic: a nightly standing-order cron would keep
-- drafting real recurring orders against a retired product at a stale price.
--
-- WHY canonical AND merge_into_id. merge_into_id is the existing "this row is
-- retired" marker that 16 read paths already filter on. canonical_product_id
-- is the new "roll me up to" pointer that reporting groups by. They are set
-- together and mean different things: one hides a row, the other attributes
-- its history.
--
-- CHAINS. Merging A into B when B is already merged into C must not leave a
-- chain nothing dereferences. Every merge resolves the target to its terminal
-- canonical first, AND re-points anything already pointing at the loser, so
-- the graph stays one hop deep forever.

begin;

-- ── Resolve a product to what it rolls up to ────────────────────────────
create or replace function public.canonical_product(p_product_id text)
returns text language sql stable as $function$
  select coalesce((select canonical_product_id from public.products where product_id = p_product_id), p_product_id);
$function$;

comment on function public.canonical_product(text) is
  'What this variant rolls up to. Its own id unless merged. For REPORTING only — an invoice line names the product the line names.';

-- ── Merge one variant into another ──────────────────────────────────────
create or replace function public.merge_product_variant(
  p_keep_id text,
  p_kill_id text,
  p_notes   text default null
) returns jsonb
language plpgsql
security invoker           -- runs as the caller, so RLS confines it to their tenant
as $function$
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

  -- What history stays behind, recorded before anything changes.
  select count(*), coalesce(sum(quantity), 0) into v_lines, v_units
    from public.order_details where product_id = p_kill_id;

  -- ── Forward-looking pointers follow the survivor ──────────────────────
  update public.standing_order_lines set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('standing_order_lines', v_n);

  update public.vmi_checkin_items set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('vmi_checkin_items', v_n);

  update public.shopify_product_mappings set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shopify_product_mappings', v_n);

  update public.shop_config set shipping_product_id = p_keep_id where shipping_product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('shop_config', v_n);

  update public.product_filter set product_id = p_keep_id where product_id = p_kill_id;
  get diagnostics v_n = row_count; v_moved := v_moved || jsonb_build_object('product_filter', v_n);

  -- Polymorphic, no FK: nothing in the database would ever catch this.
  update public.customer_discount
     set scope_ref = p_keep_id
   where scope = 'variant' and scope_ref = p_kill_id and company_id = v_kill.company_id;
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

comment on function public.merge_product_variant(text, text, text) is
  'Retire one variant into another. Moves no order line and deletes no BOM — history stays where it is and is resolved through canonical_product_id. Moves only the forward-looking links.';

revoke all on function public.merge_product_variant(text, text, text) from public, anon;

commit;
