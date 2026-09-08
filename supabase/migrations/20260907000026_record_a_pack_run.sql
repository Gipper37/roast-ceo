-- Recording that packing happened, in one call.
--
-- The run, the roasts that fed it, and who the bags went to are three tables,
-- and a half-written pack run is worse than none: a lot code with no sources is
-- a code an auditor can ask about and nobody can answer. So it is one function
-- and one transaction — either the whole record exists or none of it does.
--
-- The rules that live here rather than in the form, because the form is not the
-- only way in:
--
--   · the lot code is minted HERE, inside the same transaction as the row it
--     identifies, so a sequence number can never be burned by an abandoned form
--   · packing cannot be recorded in the future (Costco 5.1.11, falsification,
--     is an automatic-failure critical — the same rule the maintenance log got)
--   · you cannot give out more bags than you packed
--   · every id is checked to belong to the caller's company, one by one; a form
--     posting somebody else's product id gets a refusal, not a cross-tenant row
--
-- `green_snapshot` is frozen here on purpose. `roast_log_lot_consumption` is a
-- FIFO PROJECTION that `replay_lot_consumption` deletes and rebuilds, so the
-- green behind a bag can legitimately change months later. What the bag was
-- packed from is a fact about that day, and the recall report prefers this
-- snapshot over the live ledger for exactly that reason.

begin;

create or replace function public.record_pack_run(
  p_company_id        text,
  p_product_id        text,
  p_bags              numeric,
  p_sources           jsonb,                   -- [{roast_log_id, lbs_used}]
  p_coffee_prep       text    default 'whole_bean',
  p_packed_on         date    default null,
  p_unit_weight_lbs   numeric default null,
  p_best_before       date    default null,
  p_location          text    default null,
  p_bag_purchase_id   text    default null,
  p_label_purchase_id text    default null,
  p_notes             text    default null,
  p_allocations       jsonb   default '[]'::jsonb  -- [{order_detail_id?, customer_id?, bags}]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor       record;
  v_lot         text;
  v_run         text;
  v_day         date := coalesce(p_packed_on, current_date);
  v_product     record;
  v_alloc_total numeric;
  v_src_count   int;
  v_snapshot    jsonb;
  v_facility    text;
begin
  -- ── Who is asking, and may they ────────────────────────────────────────
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', p_company_id) then
    raise exception 'You do not have permission to record packing.' using errcode = 'insufficient_privilege';
  end if;

  -- ── What they are claiming ─────────────────────────────────────────────
  if coalesce(p_bags, 0) <= 0 then
    raise exception 'How many bags did you pack?' using errcode = 'invalid_parameter_value';
  end if;
  if v_day > current_date then
    raise exception 'Packing cannot be recorded for a day that has not happened yet.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_coffee_prep is not null and p_coffee_prep not in ('whole_bean','ground') then
    raise exception 'Coffee is either whole bean or ground.' using errcode = 'invalid_parameter_value';
  end if;

  select p.product_id, p.product_name, p.weight_lbs into v_product
    from public.products p
   where p.product_id = p_product_id and p.company_id = p_company_id;
  if v_product.product_id is null then
    raise exception 'That product is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  -- Sources: at least one, all real, all this company's.
  select count(*) into v_src_count
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) s
    join public.roast_log rl on rl.roast_log_id = s->>'roast_log_id'
   where rl.company_id = p_company_id;
  if v_src_count = 0 or v_src_count <> jsonb_array_length(coalesce(p_sources, '[]'::jsonb)) then
    raise exception 'Say which roast batches went into these bags. A lot code with nothing behind it cannot be traced.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Packaging, when given, has to be this company's too.
  if p_bag_purchase_id is not null and not exists (
    select 1 from public.consumable_inventory_purchased
     where consumable_purchase_id = p_bag_purchase_id and company_id = p_company_id) then
    raise exception 'That bag purchase is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if p_label_purchase_id is not null and not exists (
    select 1 from public.consumable_inventory_purchased
     where consumable_purchase_id = p_label_purchase_id and company_id = p_company_id) then
    raise exception 'That label purchase is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  -- You cannot give out more bags than you made.
  select coalesce(sum((a->>'bags')::numeric), 0) into v_alloc_total
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a;
  if v_alloc_total > p_bags then
    raise exception 'You have given out % bags but only packed %.', v_alloc_total, p_bags
      using errcode = 'invalid_parameter_value';
  end if;

  -- ── The green behind the bag, frozen as it reads today ─────────────────
  select coalesce(jsonb_agg(jsonb_build_object(
           'roast_log_id', c.roast_log_id,
           'origin_purchase_id', c.origin_purchase_id,
           'lbs_consumed', c.lbs_consumed,
           'origin', coalesce(ci.origin, cip.origin),
           'supplier_lot', cip.lot_id)), '[]'::jsonb)
    into v_snapshot
    from jsonb_array_elements(p_sources) s
    join public.roast_log_lot_consumption c on c.roast_log_id = s->>'roast_log_id'
    left join public.coffee_inventory_purchased cip on cip.origin_purchase_id = c.origin_purchase_id
    left join public.coffee_inventory ci on ci.origin_id = cip.origin;

  select facility_id into v_facility from public.team
   where auth_user_id = auth.uid() and company_id = p_company_id limit 1;

  select * into v_actor from public.actor_at();

  -- ── The code, minted inside the same transaction as the row it names ───
  v_lot := public.next_lot_code(p_company_id, v_day);

  insert into public.pack_run (
    company_id, facility_id, lot_code, product_id, product_name_snapshot, coffee_prep,
    packed_on, bags, unit_weight_lbs, total_lbs, best_before, location,
    bag_purchase_id, label_purchase_id, green_snapshot,
    packed_by_team_member, packed_by_name, notes, created_by)
  values (
    p_company_id, v_facility, v_lot, p_product_id, v_product.product_name,
    coalesce(p_coffee_prep, 'whole_bean'),
    v_day, p_bags,
    coalesce(p_unit_weight_lbs, v_product.weight_lbs),
    p_bags * coalesce(p_unit_weight_lbs, v_product.weight_lbs, 0),
    p_best_before, nullif(trim(p_location), ''),
    p_bag_purchase_id, p_label_purchase_id, v_snapshot,
    v_actor.team_member_id, v_actor.actor_name, nullif(trim(p_notes), ''), v_actor.actor_name)
  returning pack_run_id into v_run;

  insert into public.pack_run_source (pack_run_id, roast_log_id, lbs_used)
  select v_run, s->>'roast_log_id', nullif(s->>'lbs_used','')::numeric
    from jsonb_array_elements(p_sources) s;

  insert into public.pack_run_allocation (pack_run_id, order_detail_id, customer_id, bags)
  select v_run,
         nullif(a->>'order_detail_id',''),
         nullif(a->>'customer_id',''),
         (a->>'bags')::numeric
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a
   where coalesce((a->>'bags')::numeric, 0) > 0;

  return jsonb_build_object(
    'pack_run_id', v_run,
    'lot_code', v_lot,
    'bags', p_bags,
    'allocated', v_alloc_total,
    -- Reported, not hidden: what is still on your shelf is the number a recall
    -- has to explain, and the packer is the last person who can fix it cheaply.
    'unallocated', p_bags - v_alloc_total);
end;
$$;

comment on function public.record_pack_run is
  'Records a packing run, its roast batches and its allocations in one transaction, minting the lot code inside it. A half-written pack run is worse than none: a lot code with no sources is a code an auditor can ask about and nobody can answer.';

revoke all on function public.record_pack_run(text, text, numeric, jsonb, text, date, numeric, date, text, text, text, text, jsonb) from public;
grant execute on function public.record_pack_run(text, text, numeric, jsonb, text, date, numeric, date, text, text, text, text, jsonb) to authenticated;

-- ── What is left to pack ────────────────────────────────────────────────────
-- The packer should never have to remember which batches they have already
-- bagged. Roasted weight minus what pack runs have already claimed, per roast.
create or replace function public.roasts_available_to_pack(p_company_id text, p_days int default 45)
returns table (
  roast_log_id text,
  roast_date   timestamp,
  coffee       text,
  roasted_lbs  numeric,
  packed_lbs   numeric,
  remaining_lbs numeric,
  roasted_by   text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select rl.roast_log_id,
         rl.roast_date,
         coalesce(nullif(rl.recipe_name_snapshot,''), nullif(rl.coffee_name_snapshot,''), 'Coffee'),
         coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0)::numeric,
         coalesce(p.packed, 0)::numeric,
         (coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0) - coalesce(p.packed, 0))::numeric,
         rs.roasted_by_name
    from public.roast_log rl
    left join lateral (
      select sum(s.lbs_used) as packed
        from public.pack_run_source s
        join public.pack_run pr on pr.pack_run_id = s.pack_run_id
       where s.roast_log_id = rl.roast_log_id and pr.voided_at is null
    ) p on true
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where rl.company_id = p_company_id
     and rl.company_id in (select auth_company_ids())
     and rl.roast_date >= (current_date - p_days)
   order by rl.roast_date desc;
$$;

comment on function public.roasts_available_to_pack is
  'Roasted weight minus what pack runs have already claimed. The packer should never have to remember which batches they have already bagged.';

revoke all on function public.roasts_available_to_pack(text, int) from public;
grant execute on function public.roasts_available_to_pack(text, int) to authenticated;

commit;
