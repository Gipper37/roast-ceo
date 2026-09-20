-- Naming a drum has to bind the draw, not just reorder it.
--
-- Owner, testing the bin-lot picker: *"if i say im bagging 50 it doesn't stop
-- me from going over the 20.5 of that bin and it doesn't give the option to
-- add more bins to this bagging session and didn't give me that option on the
-- first window either"*.
--
-- Two separate faults sat behind that, and the second is the serious one.
--
-- 1. p_pin_roast_log_id was only ever a SORT KEY. 20260920000001 says so in
--    its own header: the pinned batch sorts first and "FIFO then covers only
--    what the batch could not". So asking for 50 bags (37.5 lbs) against a
--    20.5 lb drum took that drum first and then quietly pulled the remaining
--    17 lbs out of two OTHER drums. No shortfall, no warning, and a finished
--    lot whose bags carry one bin code but three batches of coffee. That is
--    precisely the traceability the bin pick exists to provide, inverted.
--
-- 2. The pin never reached the write at all. close_pack_run recomputes the
--    draw from scratch and the frontend passed neither the pin nor p_sources,
--    so the recorded draw was always plain oldest-first. The picker changed
--    the PREVIEW and nothing else. Nobody would have caught this from the
--    screen, because the preview it showed was correct.
--
-- The fix is one idea instead of two: p_only_roast_log_ids. When the bagger
-- names drums, those drums ARE the shelf for this run -- the draw is FIFO
-- within them and stops when they run dry, reporting a real shortfall instead
-- of wandering onto coffee nobody named. When they name nothing, it is FIFO
-- over everything, exactly as before.
--
-- Why a list of ids and not the existing p_sources jsonb override: p_sources
-- makes the CLIENT compute lbs per batch, and it is the one path with no
-- remaining-lbs check (20260908000017 validates ownership and that each
-- figure is positive, but not that the batch actually holds it). A browser
-- could draw a drum past zero, and every later draw filters remaining_lbs >
-- 0.01, so the overdrawn batch would silently vanish off the shelf. Handing
-- the server a list of ids and letting it do the arithmetic removes that
-- whole class of bug: least(remaining, need) still applies to every batch.
-- p_sources has no caller today, so it goes rather than lingering as a second
-- way to do the same thing with worse guarantees.
--
-- 'pinned' is replaced by 'unavailable': the ids that were named and are not
-- on the shelf. A boolean could only say something went wrong; the array says
-- which drum, which is what the screen needs to name it.

begin;

-- ── The planner ────────────────────────────────────────────────────────────
-- Dropped, not replaced: the last argument changes type, so CREATE OR REPLACE
-- would leave a second overload behind and PostgREST refuses to choose between
-- ambiguous candidates.
drop function if exists public.pack_draw_plan(text, text, numeric, integer, text, text);

create or replace function public.pack_draw_plan(
  p_company_id         text,
  p_recipe_id          text,
  p_lbs                numeric,
  p_days               integer  default 180,
  p_facility_id        text     default null,
  p_only_roast_log_ids text[]   default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_type        text;
  v_draw        jsonb := '[]'::jsonb;
  v_taken       numeric := 0;
  v_need        numeric;
  v_basis       text := 'fifo';
  v_restricted  boolean := p_only_roast_log_ids is not null
                           and cardinality(p_only_roast_log_ids) > 0;
  v_unavailable jsonb := '[]'::jsonb;
  c             record;
  b             record;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_lbs, 0) <= 0 or p_recipe_id is null then
    return jsonb_build_object('draw', '[]'::jsonb, 'taken', 0,
                              'shortfall', greatest(coalesce(p_lbs, 0), 0), 'basis', 'none',
                              'restricted', v_restricted, 'unavailable', '[]'::jsonb);
  end if;

  select roast_type into v_type from public.roast_recipes
   where recipe_id = p_recipe_id and company_id = p_company_id;

  -- Resolved here, once, rather than handed out as an id for a caller to look
  -- up: coffee_inventory.origin is the name, rl.origin_id is a foreign key.
  --
  -- The restriction lands HERE, on the shelf itself, rather than on the two
  -- selection loops below. Filtering the shelf is what makes "these drums and
  -- no others" true for every path through this function at once -- the ratio
  -- loop, the top-up loop, and the shortfall that falls out of both.
  create temp table _avail on commit drop as
    select r.roast_log_id, r.roast_date, r.remaining_lbs, rl.origin_id,
           coalesce(ci.origin, nullif(rl.coffee_name_snapshot, '')) as origin_name
      from public.roasts_available_to_pack(p_company_id, p_days, p_facility_id) r
      join public.roast_log rl on rl.roast_log_id = r.roast_log_id
      left join public.coffee_inventory ci on ci.origin_id = rl.origin_id
     where r.recipe_id = p_recipe_id and r.remaining_lbs > 0.01
       and (not v_restricted or r.roast_log_id = any(p_only_roast_log_ids))
     order by r.roast_date asc;

  -- Named and not on the shelf: already bagged, emptied, out of the p_days
  -- window, at another facility, on another recipe, or not this company's at
  -- all. The screen needs to say WHICH, so return the ids rather than a flag.
  if v_restricted then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_unavailable
      from unnest(p_only_roast_log_ids) x
     where x not in (select roast_log_id from _avail);
  end if;

  if v_type = 'Post-Blend' and exists (
      select 1 from public.recipe_components
       where recipe_id = p_recipe_id and coalesce(percentage, 0) > 0) then
    v_basis := 'ratio';
    for c in
      select coffee_item, percentage from public.recipe_components
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
            'roast_date', b.roast_date, 'origin_id', b.origin_id,
            'origin_name', b.origin_name,
            'share', round(c.percentage * 100)::int,
            'reason', 'ratio');
          update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
          v_need  := v_need - v_take;
          v_taken := v_taken + v_take;
        end;
      end loop;
    end loop;
  end if;

  v_need := round(p_lbs - v_taken, 2);
  if v_need > 0.001 then
    for b in select * from _avail where remaining_lbs > 0.01
                order by roast_date asc
    loop
      exit when v_need <= 0.001;
      declare v_take numeric := least(b.remaining_lbs, v_need);
      begin
        v_draw := v_draw || jsonb_build_object(
          'roast_log_id', b.roast_log_id, 'lbs_used', v_take,
          'roast_date', b.roast_date, 'origin_id', b.origin_id,
          'origin_name', b.origin_name,
          'reason', case when v_restricted then 'named'
                         when v_basis = 'ratio' then 'topped up' else 'fifo' end);
        update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
        v_need  := v_need - v_take;
        v_taken := v_taken + v_take;
      end;
    end loop;
  end if;

  drop table if exists _avail;

  select coalesce(jsonb_agg(d order by d->>'roast_date'), '[]'::jsonb) into v_draw
    from (
      select jsonb_build_object(
               'roast_log_id', e->>'roast_log_id',
               'lbs_used',     round(sum((e->>'lbs_used')::numeric), 2),
               'roast_date',   min(e->>'roast_date'),
               'origin_id',    min(e->>'origin_id'),
               'origin_name',  min(e->>'origin_name'),
               'share',        max((e->>'share')::int),
               -- max(): 'topped up' beats 'ratio' beats 'named' beats 'fifo',
               -- so a folded row names the weaker basis rather than flattering
               -- itself.
               'reason',       max(e->>'reason')) as d
        from jsonb_array_elements(v_draw) e
       group by e->>'roast_log_id'
    ) folded;

  return jsonb_build_object(
    'draw', v_draw, 'taken', round(v_taken, 2),
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2), 'basis', v_basis,
    -- True when the bagger named drums, so the screen can explain a shortfall
    -- as "you named 20.5 lbs" rather than "the shelf is empty".
    'restricted', v_restricted,
    'unavailable', v_unavailable);
end;
$function$;

comment on function public.pack_draw_plan(text, text, numeric, integer, text, text[]) is
  'Work out which roast batches a bagging run draws from. FIFO, or ratio-by-recipe for a post-blend. p_only_roast_log_ids restricts the shelf to the drums the bagger named: the draw is FIFO within them and stops when they run dry, returning a real shortfall rather than spilling onto coffee nobody named.';

revoke all on function public.pack_draw_plan(text, text, numeric, integer, text, text[]) from public;
grant execute on function public.pack_draw_plan(text, text, numeric, integer, text, text[]) to authenticated;

-- ── The write ──────────────────────────────────────────────────────────────
-- Same reason as above: the last argument changes type, so the old one has to
-- go rather than gain a sibling.
drop function if exists public.close_pack_run(text, numeric, text, text, text, text, date, jsonb, jsonb);

create or replace function public.close_pack_run(
  p_pack_run_id     text,
  p_bags            numeric,
  p_location        text    default null,
  p_bag_purchase_id text    default null,
  p_label_purchase_id text  default null,
  p_notes           text    default null,
  p_best_before     date    default null,
  p_allocations     jsonb   default '[]'::jsonb,
  p_only_roast_log_ids text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run         record;
  v_recipe      text;
  v_total       numeric;
  v_plan        jsonb;
  v_draw        jsonb;
  v_alloc_total numeric;
  v_snapshot    jsonb;
  v_actor       record;
  v_bad         int;
begin
  -- FOR UPDATE: two clicks on Record it cannot both pass the closed_at check.
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id for update;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging session is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', v_run.company_id) then
    raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
  end if;
  if v_run.voided_at is not null then
    raise exception 'That session was voided.' using errcode = 'invalid_parameter_value';
  end if;
  if v_run.closed_at is not null then
    raise exception 'That session is already closed. Correct it instead.' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_bags, 0) <= 0 then
    raise exception 'How many bags did you fill?' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(sum((a->>'bags')::numeric), 0) into v_alloc_total
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a;
  if v_alloc_total > p_bags then
    raise exception 'You have set aside % bags but only filled %.', v_alloc_total, p_bags
      using errcode = 'invalid_parameter_value';
  end if;

  v_total := p_bags * coalesce(v_run.unit_weight_lbs, 0);
  select recipe_id into v_recipe from public.products where product_id = v_run.product_id;

  -- 🔴 SERIALISE THE DRAW ON THE COFFEE, not on this run. The contention is two
  -- different runs reaching for one batch, so locking pack_run would not help.
  -- Transaction-scoped: released at commit or rollback, no matter what follows.
  -- A named batch that belongs to somebody else is a different thing from one
  -- that is merely empty, and the planner cannot tell them apart: its shelf is
  -- company-scoped, so a foreign id simply fails to appear and would surface
  -- as an ordinary shortfall. Refused outright here instead. Before the lock,
  -- because it is an argument error and not a draw.
  if p_only_roast_log_ids is not null and cardinality(p_only_roast_log_ids) > 0 then
    select count(*) into v_bad
      from unnest(p_only_roast_log_ids) x
      left join public.roast_log rl
             on rl.roast_log_id = x and rl.company_id = v_run.company_id
     where rl.roast_log_id is null;
    if v_bad > 0 then
      raise exception 'A batch named here is not one of yours.' using errcode = 'insufficient_privilege';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext(v_run.company_id || ':' || coalesce(v_recipe, '-')));

  -- One path now, named or not. The planner owns the arithmetic either way,
  -- so least(remaining, need) applies to every batch and no caller can draw a
  -- drum past zero. The override this replaces took a client-computed weight
  -- per batch on trust, which is exactly how a drum goes negative and then
  -- vanishes from every later draw (they all filter remaining_lbs > 0.01).
  v_plan := public.pack_draw_plan(v_run.company_id, v_recipe, v_total, 180,
                                  v_run.facility_id, p_only_roast_log_ids);
  v_draw := v_plan->'draw';

  insert into public.pack_run_source (pack_run_id, roast_log_id, lbs_used)
  select p_pack_run_id, s->>'roast_log_id', nullif(s->>'lbs_used','')::numeric
    from jsonb_array_elements(coalesce(v_draw, '[]'::jsonb)) s
  on conflict (pack_run_id, roast_log_id) do update
    set lbs_used = coalesce(public.pack_run_source.lbs_used, 0) + coalesce(excluded.lbs_used, 0);

  select coalesce(jsonb_agg(jsonb_build_object(
           'roast_log_id', c.roast_log_id,
           'origin_purchase_id', c.origin_purchase_id,
           'lbs_consumed', c.lbs_consumed,
           'origin', coalesce(ci.origin, cip.origin),
           'supplier_lot', cip.lot_id)), '[]'::jsonb)
    into v_snapshot
    from jsonb_array_elements(coalesce(v_draw, '[]'::jsonb)) s
    join public.roast_log_lot_consumption c on c.roast_log_id = s->>'roast_log_id'
    left join public.coffee_inventory_purchased cip on cip.origin_purchase_id = c.origin_purchase_id
    left join public.coffee_inventory ci on ci.origin_id = cip.origin;

  select * into v_actor from public.actor_at();

  update public.pack_run
     set bags              = p_bags,
         total_lbs         = v_total,
         location          = coalesce(nullif(trim(p_location), ''), location),
         bag_purchase_id   = coalesce(p_bag_purchase_id, bag_purchase_id),
         label_purchase_id = coalesce(p_label_purchase_id, label_purchase_id),
         notes             = coalesce(nullif(trim(p_notes), ''), notes),
         best_before       = coalesce(p_best_before, best_before),
         green_snapshot    = v_snapshot,
         closed_at         = now(),
         packed_by_team_member = v_actor.team_member_id,
         packed_by_name        = v_actor.actor_name,
         updated_by            = v_actor.actor_name,
         updated_at            = now()
   where pack_run_id = p_pack_run_id;

  insert into public.pack_run_allocation (pack_run_id, order_detail_id, customer_id, bags)
  select p_pack_run_id,
         nullif(a->>'order_detail_id',''),
         nullif(a->>'customer_id',''),
         (a->>'bags')::numeric
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a
   where coalesce((a->>'bags')::numeric, 0) > 0;

  return jsonb_build_object(
    'pack_run_id', p_pack_run_id,
    'lot_code',    v_run.lot_code,
    'bags',        p_bags,
    'total_lbs',   v_total,
    'basis',       v_plan->>'basis',
    'shortfall',   coalesce((v_plan->>'shortfall')::numeric, 0),
    'allocated',   v_alloc_total,
    'unallocated', p_bags - v_alloc_total,
    -- So a shortfall can read "you named 20.5 lbs" rather than "the shelf is
    -- empty", and can say which drum was gone.
    'restricted',  coalesce((v_plan->>'restricted')::boolean, false),
    'unavailable', coalesce(v_plan->'unavailable', '[]'::jsonb));
end;
$$;

comment on function public.close_pack_run(text, numeric, text, text, text, text, date, jsonb, text[]) is
  'Finish a bagging session: the bag count comes in, the draw is applied and the green behind it is frozen. p_only_roast_log_ids names the drums the bagger actually pulled from; the draw is confined to them. Replaces p_sources, which made the client compute per-batch pounds with no remaining-lbs check.';

revoke all on function public.close_pack_run(text, numeric, text, text, text, text, date, jsonb, text[]) from public;
grant execute on function public.close_pack_run(text, numeric, text, text, text, text, date, jsonb, text[]) to authenticated;

commit;
