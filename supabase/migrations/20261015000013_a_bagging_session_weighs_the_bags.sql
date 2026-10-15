-- A bagging session weighs the bags, not the boxes.
--
-- `products.weight_lbs` is the weight of one thing SOLD, and for a case that is
-- the BOX: a case of twelve 8 oz bags carries 6, not 0.5. `pack_run.bags` is a
-- count of BAGS -- the column is named bags, every refusal in these functions
-- says "How many bags did you fill?", and a label is printed per bag. Three
-- functions multiplied one by the other:
--
--   record_pack_run    total_lbs = p_bags * weight_lbs
--   close_pack_run     v_total   = p_bags * unit_weight_lbs   <- AND THE DRAW
--   correct_pack_run   total_lbs = bags   * unit_weight_lbs
--
-- So fifty 8 oz bags of a case-of-12 variant read as 300 lb instead of 25. In
-- `close_pack_run` that number is not a display figure: `v_total` is what the
-- draw is planned from, so it pulled twelve times the green coffee off the
-- shelf and consumed real batches. In the other two it is the yield the shelf
-- is reconciled against.
--
-- `unit_weight_lbs` is deliberately UNCHANGED. It is the weight of one sold
-- unit and `_label_data_core` divides it by `units_per_case` to print one bag's
-- net weight (20261015000010). Moving it here would break the labels that fix
-- just corrected. Only the arithmetic that turns a BAG COUNT into pounds moves.
--
-- `open_pack_run` is correct as it stands: it snapshots `unit_weight_lbs` with
-- `bags` null, which is the contract rather than a multiplication.
--
-- ONE DEFINITION, because three call sites got it wrong three times:
-- `product_bag_weight_lbs(product_id, sold_unit_weight)` is the only place the
-- division lives, the same way `product_consumables_effective` is the only
-- place the BOM multiplication lives.
--
-- 🔴 All three bodies are patched from `pg_get_functiondef`, not retyped. Each
-- carries work that is not this change's: close_pack_run holds the advisory
-- lock and the named-batch draw planner, correct_pack_run writes the correction
-- log before it applies anything, record_pack_run resolves the actor and mints
-- the lot code. The arithmetic is the only line that differs in each.
--
-- NOTHING TO REPAIR: prod has 0 pack_run rows (bagging is off for every tenant
-- there), so this is a bug fixed before its first use rather than a backfill.

begin;

-- One bag's weight, for a product whose sold unit may be a case.
--
-- `p_sold_unit_weight` is the snapshot a caller already holds (pack_run's own
-- unit_weight_lbs, taken when the session opened) and falls back to the
-- product's current weight. Returns 0 rather than NULL for an unknown product,
-- matching the coalesce every caller had inline: a session on a deleted product
-- should total nothing, not NULL out a numeric column.
create or replace function public.product_bag_weight_lbs(
  p_product_id        text,
  p_sold_unit_weight  numeric default null
)
returns numeric
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(
    (select coalesce(p_sold_unit_weight, p.weight_lbs, 0)
            -- greatest(): a stray units_per_case of 0 or a negative one would
            -- divide by zero or flip the sign. The table's own check says it is
            -- null or > 1, so this is a belt on top of a brace.
            / greatest(coalesce(s.units_per_case, 1), 1)
       from public.products p
       left join public.size s on s.size_id = p.size
      where p.product_id = p_product_id),
    coalesce(p_sold_unit_weight, 0))
$$;

comment on function public.product_bag_weight_lbs(text, numeric) is
  'One BAG''s weight for a product whose sold unit may be a case: the sold-unit weight divided by units_per_case. The single definition of that division, used by record_pack_run, close_pack_run and correct_pack_run.';

-- Not for the browser. Nothing calls this from PostgREST, and a function that
-- reads products should not be reachable just because Postgres grants EXECUTE
-- to PUBLIC by default. The three callers are SECURITY DEFINER and run as the
-- owner, which keeps its own access regardless.
revoke all on function public.product_bag_weight_lbs(text, numeric) from public;

CREATE OR REPLACE FUNCTION public.record_pack_run(p_company_id text, p_product_id text, p_bags numeric, p_sources jsonb, p_coffee_prep text DEFAULT 'whole_bean'::text, p_packed_on date DEFAULT NULL::date, p_unit_weight_lbs numeric DEFAULT NULL::numeric, p_best_before date DEFAULT NULL::date, p_location text DEFAULT NULL::text, p_bag_purchase_id text DEFAULT NULL::text, p_label_purchase_id text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_allocations jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- unit_weight_lbs stays the weight of one SOLD unit, which for a case is
    -- the box. That is the established contract: _label_data_core divides this
    -- by units_per_case to print one bag's net weight (20261015000010), and
    -- changing it here would break the labels that fix just corrected.
    coalesce(p_unit_weight_lbs, v_product.weight_lbs),
    -- 🔴 But total_lbs is BAGS x ONE BAG, and p_bags is a count of BAGS: the
    -- column is named bags, the refusal above says "How many bags did you
    -- fill?", and a label is printed per bag. Multiplying a bag count by a
    -- CASE weight made the whole run read 12x heavy on a case of 12 -- the
    -- green coffee it claims to consume, the yield the shelf is reconciled
    -- against, and the draw the packer is shown before they commit.
    p_bags * public.product_bag_weight_lbs(p_product_id, p_unit_weight_lbs),
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
$function$;

CREATE OR REPLACE FUNCTION public.close_pack_run(p_pack_run_id text, p_bags numeric, p_location text DEFAULT NULL::text, p_bag_purchase_id text DEFAULT NULL::text, p_label_purchase_id text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_best_before date DEFAULT NULL::date, p_allocations jsonb DEFAULT '[]'::jsonb, p_only_roast_log_ids text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- 🔴 BAGS x ONE BAG, not bags x the box. p_bags is a count of BAGS -- the
  -- column is named bags, the refusal above says "How many bags did you fill?",
  -- and a label is printed per bag -- while unit_weight_lbs is the weight of
  -- one thing SOLD, which for a case IS the box. Multiplying the two pulled
  -- twelve times the green coffee off the shelf for a case of 12, and v_total
  -- is what the draw below is planned from, so the over-draw was not a display
  -- figure: it consumed real batches.
  v_total := p_bags * public.product_bag_weight_lbs(v_run.product_id, v_run.unit_weight_lbs);
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
$function$;

CREATE OR REPLACE FUNCTION public.correct_pack_run(p_pack_run_id text, p_reason text, p_bags numeric DEFAULT NULL::numeric, p_best_before date DEFAULT NULL::date, p_location text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run     record;
  v_actor   record;
  v_changed int := 0;
begin
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging run is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', v_run.company_id) then
    raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
  end if;
  if v_run.voided_at is not null then
    raise exception 'That run was voided. Record a new one instead.' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say what you are correcting and why. The original stays on the record either way.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_bags is not null and p_bags <= 0 then
    raise exception 'A run has to have filled at least one bag.' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_actor from public.actor_at();

  -- Every change is written down BEFORE it is applied. The log is the reason
  -- this is an amendment and not a rewrite.
  if p_bags is not null and p_bags is distinct from v_run.bags then
    insert into public.pack_run_correction (pack_run_id, company_id, field, old_value, new_value, reason, corrected_by, corrected_by_name)
    values (p_pack_run_id, v_run.company_id, 'bags', v_run.bags::text, p_bags::text, trim(p_reason), v_actor.team_member_id, v_actor.actor_name);
    v_changed := v_changed + 1;
  end if;
  if p_best_before is not null and p_best_before is distinct from v_run.best_before then
    insert into public.pack_run_correction (pack_run_id, company_id, field, old_value, new_value, reason, corrected_by, corrected_by_name)
    values (p_pack_run_id, v_run.company_id, 'best_before', v_run.best_before::text, p_best_before::text, trim(p_reason), v_actor.team_member_id, v_actor.actor_name);
    v_changed := v_changed + 1;
  end if;
  if p_location is not null and nullif(trim(p_location),'') is distinct from v_run.location then
    insert into public.pack_run_correction (pack_run_id, company_id, field, old_value, new_value, reason, corrected_by, corrected_by_name)
    values (p_pack_run_id, v_run.company_id, 'location', v_run.location, nullif(trim(p_location),''), trim(p_reason), v_actor.team_member_id, v_actor.actor_name);
    v_changed := v_changed + 1;
  end if;
  if p_notes is not null and nullif(trim(p_notes),'') is distinct from v_run.notes then
    insert into public.pack_run_correction (pack_run_id, company_id, field, old_value, new_value, reason, corrected_by, corrected_by_name)
    values (p_pack_run_id, v_run.company_id, 'notes', v_run.notes, nullif(trim(p_notes),''), trim(p_reason), v_actor.team_member_id, v_actor.actor_name);
    v_changed := v_changed + 1;
  end if;

  update public.pack_run
     set bags        = coalesce(p_bags, bags),
         -- Bags x ONE BAG, same correction as close_pack_run: a correction
         -- that re-derived the total from the box weight would put the 12x
         -- error back on a run that had been recorded correctly.
         total_lbs   = coalesce(p_bags, bags)
                       * public.product_bag_weight_lbs(product_id, unit_weight_lbs),
         best_before = coalesce(p_best_before, best_before),
         location    = coalesce(nullif(trim(p_location),''), location),
         notes       = coalesce(nullif(trim(p_notes),''), notes),
         updated_by  = v_actor.actor_name,
         updated_at  = now()
   where pack_run_id = p_pack_run_id;

  return jsonb_build_object('pack_run_id', p_pack_run_id, 'changes', v_changed);
end;
$function$;

do $verify$
DECLARE
  r_case  record;
  r_bag   record;
  v_one   numeric;
BEGIN
  -- 🔴 Evaluated against ROWS THAT ALREADY EXIST, and nothing is inserted.
  --
  -- The first draft of this block built its own product, which meant firing
  -- seven triggers on `products` (the name builder, the COGS recalc, two
  -- group-type adopters) to test one division -- and it got
  -- `product_groups.group_id`'s type and the `companies` table's name wrong on
  -- the way. Prod carries 33 case variants and 911 bag ones, so the rows to
  -- test on are already here. A database that has neither says so and skips,
  -- which is honest; the structural assertions below still run everywhere.
  --
  -- Calling the function with a made-up id would answer from its fallback
  -- branch and prove nothing, which is the hole 20261015000010's first verify
  -- block had.
  select p.product_id, p.weight_lbs, s.units_per_case
    into r_case
    from public.products p
    join public.size s on s.size_id = p.size
   where s.units_per_case > 1 and p.weight_lbs > 0
   limit 1;

  select p.product_id, p.weight_lbs
    into r_bag
    from public.products p
    join public.size s on s.size_id = p.size
   where s.units_per_case is null and p.weight_lbs > 0
   limit 1;

  if r_bag.product_id is not null then
    -- A BAG: one bag IS the sold unit, so the division is the identity. This
    -- is the property that matters most, because every roaster today is here.
    v_one := public.product_bag_weight_lbs(r_bag.product_id, null);
    if round(v_one, 9) is distinct from round(r_bag.weight_lbs, 9) then
      raise exception 'a bag''s bag weight came out % but the product weighs %',
        v_one, r_bag.weight_lbs;
    end if;
    -- And the snapshot a session carries wins over the product's weight.
    if round(public.product_bag_weight_lbs(r_bag.product_id, 7), 9) is distinct from 7 then
      raise exception 'the snapshot was ignored on a bag';
    end if;
  else
    raise notice 'no priced bag variant on this database, skipping the bag check';
  end if;

  if r_case.product_id is not null then
    -- A CASE: the sold unit is the box, so one bag is weight / pack count.
    v_one := public.product_bag_weight_lbs(r_case.product_id, null);
    if round(v_one, 9) is distinct from round(r_case.weight_lbs / r_case.units_per_case, 9) then
      raise exception 'a case of % gave a bag weight of %, expected %',
        r_case.units_per_case, v_one, r_case.weight_lbs / r_case.units_per_case;
    end if;
    -- And it really DIFFERS from what the three functions used to multiply by,
    -- so the assertion above is a test rather than a tautology.
    if round(v_one, 9) = round(r_case.weight_lbs, 9) then
      raise exception 'the new arithmetic agrees with the old on %, so this proves nothing',
        r_case.product_id;
    end if;
    -- 50 bags of it: the number close_pack_run plans the DRAW from.
    if round(50 * v_one, 9) is distinct from round(50 * r_case.weight_lbs / r_case.units_per_case, 9) then
      raise exception '50 bags did not scale';
    end if;
    -- The snapshot divides too: a box snapshotted at 12 lb is 12/pack a bag.
    if round(public.product_bag_weight_lbs(r_case.product_id, 12), 9)
       is distinct from round(12.0 / r_case.units_per_case, 9) then
      raise exception 'the snapshot was not divided by the pack count';
    end if;
  else
    raise notice 'no case variant on this database, skipping the case check';
  end if;

  -- An unknown product falls back rather than returning NULL into a numeric
  -- column that gets summed.
  if public.product_bag_weight_lbs('zzverify-no-such-product', 3) is distinct from 3 then
    raise exception 'an unknown product did not fall back to the snapshot';
  end if;
  if public.product_bag_weight_lbs('zzverify-no-such-product', null) is distinct from 0 then
    raise exception 'an unknown product with no snapshot did not come back 0';
  end if;

  -- The three bodies kept the work that is not this change's.
  if (select prosrc from pg_proc where oid = 'public.close_pack_run'::regproc)
     not like '%pg_advisory_xact_lock%' then
    raise exception 'close_pack_run lost its advisory lock';
  end if;
  if (select prosrc from pg_proc where oid = 'public.correct_pack_run'::regproc)
     not like '%pack_run_correction%' then
    raise exception 'correct_pack_run lost its correction log';
  end if;
  if (select prosrc from pg_proc where oid = 'public.record_pack_run'::regproc)
     not like '%next_lot_code%' then
    raise exception 'record_pack_run lost its lot code';
  end if;
  -- None of them still multiplies a bag count by the sold-unit weight.
  if (select count(*) from pg_proc
       where oid in ('public.record_pack_run'::regproc, 'public.close_pack_run'::regproc,
                     'public.correct_pack_run'::regproc)
         and prosrc ~ 'bags\)?\s*\*\s*coalesce\((p_unit_weight_lbs|unit_weight_lbs|v_run\.unit_weight_lbs)') > 0 then
    raise exception 'one of the three still multiplies a bag count by the sold-unit weight';
  end if;
  -- And all three reach the one definition of the division.
  if (select count(*) from pg_proc
       where oid in ('public.record_pack_run'::regproc, 'public.close_pack_run'::regproc,
                     'public.correct_pack_run'::regproc)
         and prosrc like '%product_bag_weight_lbs%') <> 3 then
    raise exception 'not all three functions call product_bag_weight_lbs';
  end if;

  raise notice 'a bag count now weighs bags, not boxes';
END;
$verify$;

commit;
