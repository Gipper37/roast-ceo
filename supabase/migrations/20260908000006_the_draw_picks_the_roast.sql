-- The bagger stops choosing the roast, because the system already knows.
--
-- Owner, 2026-09-08: *"the roaster selects what recipe theyre roasting for. the
-- bagger chooses the product they are bagging. the product knows what the
-- recipe is, the bagger doesn't need to select it. that would be them doing the
-- work the software already does. then the system just links the lots via fifo
-- from the roasts."* And, when I argued the packer should still confirm the
-- batch: *"that's the whole basis of what we're doing. we said it before, we're
-- already tracking exact lots when roasting."*
--
-- He is right, and the data says so. A roast_log already carries the exact
-- green lots that went into it — planned_lots is {origin_id: coffee_source_id}
-- and it is non-null on every one of MCR's 2,991 roasts in the last 90 days.
-- The green->roast link is exact. Bagging only has to add roast->bag, and the
-- product's recipe already determines which roasts are eligible. Asking the
-- packer to pick was asking a human to be a foreign key.
--
-- ── THREE ROAST TYPES, TWO BEHAVIOURS ────────────────────────────────────────
-- Verified against MCR production, last 90 days:
--   Single Origin  1,916 roasts, every one carries origin_id.        1 batch.
--   Pre-Blend        442 roasts, origin_id null on 441 of them —
--                    the greens were blended BEFORE roasting, and the
--                    components live in planned_lots (2.77 of them on
--                    average). One batch is already the finished blend.
--   Post-Blend       633 roasts, every one carries origin_id — each batch
--                    is ONE component, roasted separately and combined in
--                    the bag. 2 components on the recipe.
-- So Single Origin and Pre-Blend are the same problem: FIFO across the recipe's
-- batches. Only Post-Blend needs the ratio split.
--
-- ── THE RULE ────────────────────────────────────────────────────────────────
-- Ratio as the target, FIFO as the mechanism, and it NEVER fails.
--   1. Post-blend: split the weight by recipe_components.percentage.
--   2. FIFO oldest-first WITHIN each component.
--   3. Whatever a component cannot cover, take from anything else roasted
--      under that recipe, oldest first.
--   4. Still short? Return the shortfall. Do not raise.
--
-- Step 3 is not defensive padding. Of the 11 post-blends MCR actually roasted
-- in the last 90 days, 8 had every spec component roasted and 3 did not
-- (Dear Wanderlust, Et Al, NOLA) — a recipe can name a component the roastery
-- has not run lately, and a strict split would come up short on good data.
-- Step 4 is the same doctrine allocate_line_from_stock already applies one step
-- downstream (20260907000027): never fail the run, report the gap.
--
-- 🔴 FIFO IS WHAT MAKES THE PRINTED BEST-BY SAFE. Because the draw always takes
-- the oldest batch first, the oldest roast in a run is knowable before the run
-- is finished — which is what lets a session mint its lot code and print its
-- labels up front (20260908000007). If the pinned batch is consumed by someone
-- else meanwhile, the next one is NEWER, so the printed date is conservative,
-- never generous. That invariant only holds while this is oldest-first.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tell the batches apart.
--
-- 🔴 THE POST-BLEND LABEL COLLISION. roasts_available_to_pack collapsed the
-- name into ONE column via a coalesce the recipe name always wins. For a
-- post-blend that is exactly backwards: the recipe name is what the components
-- SHARE, and the origin is the only thing that separates them. So both halves
-- of Analog rendered the identical string "Analog" and a packer could not tell
-- the 33% High Acidity batch from the 67% Low Acidity one. On prod, 291 of 328
-- post-blend rows in the window are label-identical to a row that is a
-- different component coffee.
--
-- 20260907000028's own header promised "The origin is appended when it adds
-- something the recipe name does not" and shipped SQL containing no
-- concatenation at all. This returns the parts separately and lets the caller
-- decide, which is the only way the three roast types can each read correctly.
--
-- ADDITIVE: `coffee` keeps its old meaning so nothing in flight breaks.
drop function if exists public.roasts_available_to_pack(text, int);

create function public.roasts_available_to_pack(
  p_company_id  text,
  p_days        int  default 45,
  p_facility_id text default null
)
returns table (
  roast_log_id  text,
  roast_date    timestamp,
  coffee        text,
  roasted_lbs   numeric,
  packed_lbs    numeric,
  remaining_lbs numeric,
  roasted_by    text,
  recipe_id     text,
  -- New, so the caller can render each roast_type in its own words.
  origin_name   text,
  recipe_name   text,
  roast_type    text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select rl.roast_log_id,
         rl.roast_date,
         coalesce(
           nullif(rl.recipe_name_snapshot, ''),
           rr.recipe_name,
           nullif(rl.coffee_name_snapshot, ''),
           ci.origin,
           'Roast batch'),
         coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0)::numeric,
         coalesce(p.packed, 0)::numeric,
         (coalesce(rl.measured_roasted_weight, rl.roasted_weight, 0) - coalesce(p.packed, 0))::numeric,
         rs.roasted_by_name,
         rl.recipe_id,
         coalesce(ci.origin, nullif(rl.coffee_name_snapshot, '')),
         coalesce(nullif(rl.recipe_name_snapshot, ''), rr.recipe_name),
         rr.roast_type
    from public.roast_log rl
    left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
    left join public.coffee_inventory ci on ci.origin_id = rl.origin_id
    left join lateral (
      select sum(s.lbs_used) as packed
        from public.pack_run_source s
        join public.pack_run pr on pr.pack_run_id = s.pack_run_id
       where s.roast_log_id = rl.roast_log_id and pr.voided_at is null
    ) p on true
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where rl.company_id = p_company_id
     and rl.company_id in (select auth_company_ids())
     -- 🔴 A multi-facility tenant's packer could cite another site's batch.
     -- This function is SECURITY DEFINER so roast_log's RLS does not apply
     -- inside it, and it only ever re-checked company. record_pack_run stamps
     -- the run with the CALLER's facility, so the two disagreed.
     and (p_facility_id is null or rl.facility_id = p_facility_id)
     and rl.roast_date >= (current_date - p_days)
   order by rl.roast_date desc;
$$;

comment on function public.roasts_available_to_pack(text, int, text) is
  'Roasted weight minus what pack runs have already claimed, with the recipe, origin and roast_type kept as separate columns so a post-blend''s components can be told apart. Facility-scoped.';

revoke all on function public.roasts_available_to_pack(text, int, text) from public;
grant execute on function public.roasts_available_to_pack(text, int, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The draw itself.
--
-- Pure and read-only: it returns a PLAN, it writes nothing. That means the
-- session can show the packer what it intends to do before anything is
-- committed, and close_pack_run can call the identical function to do it —
-- one implementation, so what was shown is what is recorded.
create or replace function public.pack_draw_plan(
  p_company_id  text,
  p_recipe_id   text,
  p_lbs         numeric,
  p_days        int     default 180,
  p_facility_id text    default null
)
returns jsonb
language plpgsql
-- VOLATILE, not stable: it materialises a temp table to subtract from as it
-- walks. It still writes nothing durable — the plan is returned, not applied.
security definer
set search_path = public, pg_temp
as $$
declare
  v_type      text;
  v_draw      jsonb := '[]'::jsonb;
  v_taken     numeric := 0;
  v_need      numeric;
  v_basis     text := 'fifo';
  c           record;
  b           record;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_lbs, 0) <= 0 or p_recipe_id is null then
    return jsonb_build_object('draw', '[]'::jsonb, 'taken', 0,
                              'shortfall', greatest(coalesce(p_lbs, 0), 0), 'basis', 'none');
  end if;

  select roast_type into v_type from public.roast_recipes
   where recipe_id = p_recipe_id and company_id = p_company_id;

  -- Everything still on the shelf under this recipe, oldest first. Materialised
  -- once: the loops below subtract from it as they go.
  create temp table _avail on commit drop as
    select r.roast_log_id, r.roast_date, r.remaining_lbs, rl.origin_id
      from public.roasts_available_to_pack(p_company_id, p_days, p_facility_id) r
      join public.roast_log rl on rl.roast_log_id = r.roast_log_id
     where r.recipe_id = p_recipe_id and r.remaining_lbs > 0.01
     order by r.roast_date asc;

  -- ── Post-blend: the recipe's ratio decides each component's share ─────────
  -- Single Origin and Pre-Blend skip this entirely: one batch is already the
  -- whole coffee, so there is nothing to apportion.
  if v_type = 'Post-Blend' and exists (
      select 1 from public.recipe_components
       where recipe_id = p_recipe_id and coalesce(percentage, 0) > 0) then
    v_basis := 'ratio';
    for c in
      select coffee_item, percentage
        from public.recipe_components
       where recipe_id = p_recipe_id and coalesce(percentage, 0) > 0
       order by percentage desc
    loop
      v_need := round(p_lbs * c.percentage, 2);
      for b in select * from _avail where origin_id = c.coffee_item and remaining_lbs > 0.01
                order by roast_date asc
      loop
        exit when v_need <= 0.001;
        declare v_take numeric := least(b.remaining_lbs, v_need);
        begin
          v_draw := v_draw || jsonb_build_object(
            'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
            'roast_date', b.roast_date, 'origin_id', b.origin_id, 'reason', 'ratio');
          update _avail set remaining_lbs = remaining_lbs - v_take
           where roast_log_id = b.roast_log_id;
          v_need  := v_need - v_take;
          v_taken := v_taken + v_take;
        end;
      end loop;
    end loop;
  end if;

  -- ── Whatever is still owed, from anything left under this recipe ──────────
  -- Covers all of: single origin, pre-blend, a post-blend component the
  -- roastery has not run lately, and a recipe that was reformulated so old
  -- roasts carry a component no longer on the spec.
  v_need := round(p_lbs - v_taken, 2);
  if v_need > 0.001 then
    for b in select * from _avail where remaining_lbs > 0.01 order by roast_date asc
    loop
      exit when v_need <= 0.001;
      declare v_take numeric := least(b.remaining_lbs, v_need);
      begin
        v_draw := v_draw || jsonb_build_object(
          'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
          'roast_date', b.roast_date, 'origin_id', b.origin_id,
          'reason', case when v_basis = 'ratio' then 'topped up' else 'fifo' end);
        update _avail set remaining_lbs = remaining_lbs - v_take
         where roast_log_id = b.roast_log_id;
        v_need  := v_need - v_take;
        v_taken := v_taken + v_take;
      end;
    end loop;
  end if;

  drop table if exists _avail;

  -- One row per batch. The ratio pass can leave a component short and the
  -- top-up pass then reaches the SAME batch again; emitted raw that is two
  -- draw entries for one roast, and two pack_run_source rows the recall report
  -- would have to add up itself. Fold them, keeping the earlier reason.
  select coalesce(jsonb_agg(d order by d->>'roast_date'), '[]'::jsonb) into v_draw
    from (
      select jsonb_build_object(
               'roast_log_id', e->>'roast_log_id',
               'lbs_used',     round(sum((e->>'lbs_used')::numeric), 2),
               'roast_date',   min(e->>'roast_date'),
               'origin_id',    min(e->>'origin_id'),
               'reason',       min(e->>'reason')) as d
        from jsonb_array_elements(v_draw) e
       group by e->>'roast_log_id'
    ) folded;

  return jsonb_build_object(
    'draw',   v_draw,
    'taken',  round(v_taken, 2),
    -- Reported, never raised. A packer holding coffee the system thinks is not
    -- there must still be able to record what they bagged; a run that cannot be
    -- saved becomes a bag with no record, which is the worse outcome.
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2),
    'basis',  v_basis);
end;
$$;

comment on function public.pack_draw_plan(text, text, numeric, int, text) is
  'What a bagging run of p_lbs would draw from the shelf: post-blend split by recipe_components ratio then FIFO within each component, everything else FIFO oldest-first, remainder topped up from anything left under the recipe. Read-only, never raises, reports a shortfall instead.';

revoke all on function public.pack_draw_plan(text, text, numeric, int, text) from public;
grant execute on function public.pack_draw_plan(text, text, numeric, int, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. A backdated run names whoever was there, not whoever is here now.
--
-- record_pack_run called actor_at() bare, which defaults to now(), so a run
-- entered on Monday for Friday's bagging was stamped with Monday's PIN holder.
-- actor_at(p_when) exists for exactly this (20260907000013) and v_day was
-- already computed two lines above the call.
create or replace function public.record_pack_run(
  p_company_id        text,
  p_product_id        text,
  p_bags              numeric,
  p_sources           jsonb,
  p_coffee_prep       text    default 'whole_bean',
  p_packed_on         date    default null,
  p_unit_weight_lbs   numeric default null,
  p_best_before       date    default null,
  p_location          text    default null,
  p_bag_purchase_id   text    default null,
  p_label_purchase_id text    default null,
  p_notes             text    default null,
  p_allocations       jsonb   default '[]'::jsonb
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
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', p_company_id) then
    raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
  end if;

  if coalesce(p_bags, 0) <= 0 then
    raise exception 'How many bags did you fill?' using errcode = 'invalid_parameter_value';
  end if;
  if v_day > current_date then
    raise exception 'Bagging cannot be recorded for a day that has not happened yet.'
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

  select count(*) into v_src_count
    from jsonb_array_elements(coalesce(p_sources, '[]'::jsonb)) s
    join public.roast_log rl on rl.roast_log_id = s->>'roast_log_id'
   where rl.company_id = p_company_id;
  if v_src_count = 0 or v_src_count <> jsonb_array_length(coalesce(p_sources, '[]'::jsonb)) then
    raise exception 'Say which roast batches went into these bags. A lot code with nothing behind it cannot be traced.'
      using errcode = 'invalid_parameter_value';
  end if;

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

  select coalesce(sum((a->>'bags')::numeric), 0) into v_alloc_total
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a;
  if v_alloc_total > p_bags then
    raise exception 'You have set aside % bags but only filled %.', v_alloc_total, p_bags
      using errcode = 'invalid_parameter_value';
  end if;

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

  -- 🔴 THE FIX: name whoever was on the floor on the day being recorded.
  select * into v_actor from public.actor_at(v_day::timestamptz);

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
    'unallocated', p_bags - v_alloc_total);
end;
$$;

revoke all on function public.record_pack_run(text,text,numeric,jsonb,text,date,numeric,date,text,text,text,text,jsonb) from public;
grant execute on function public.record_pack_run(text,text,numeric,jsonb,text,date,numeric,date,text,text,text,text,jsonb) to authenticated;

commit;
