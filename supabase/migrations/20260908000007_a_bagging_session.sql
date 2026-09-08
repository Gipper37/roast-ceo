-- A bagging run becomes a session you open, work, and close.
--
-- Owner, 2026-09-08: *"so they can open a bag session, close it and come back to
-- it. are bag sessions saved individually. like could they start a new one
-- without finishing the last one, have multiple sessions listed and then
-- finalized?"* — and, when asked whether the versatility was worth the
-- machinery: *"i'd say sessions would give it more versatility."*
--
-- 🔴 WHY THIS IS NOT JUST A DRAFT FLAG. The lot code has to exist BEFORE the
-- bags are filled, or the packer fills fifty unlabelled bags and labels them
-- afterwards from memory. record_pack_run minted the code at the END, in the
-- same statement that wrote the row, so labelling-as-you-go was impossible.
-- Opening a session mints the code first. That is the whole point.
--
-- ── THE BEST-BY INVARIANT ───────────────────────────────────────────────────
-- To print a label at open you need a best-by date, and best-by is measured
-- from the ROAST — which is not drawn until close. That looks circular and is
-- not, because pack_draw_plan takes the OLDEST batch first (20260908000006):
--
--   the oldest available batch is knowable at open,
--   and if someone else consumes it meanwhile, the next one is NEWER,
--   so a date printed at open is conservative or exact — never generous.
--
-- Shelf life is only ever understated by this, never overstated, which is the
-- only direction a printed food-safety claim is allowed to be wrong in. If the
-- draw at close lands on a newer roast the label still holds; the run records
-- what actually happened either way.
--
-- 🔴 AND IT FIXES A LIVE FALSE CLAIM. The modal seeded best-before as
-- today + shelf_life_days on mount, before any roast was picked, and never
-- recomputed it. The label screen then printed that under the caption
-- "183 days after roasting". A batch roasted ten days ago was sold with ten
-- extra days of claimed shelf life, in print, on a retail bag. Anchoring to
-- the roast is what the database comment and the label caption already said
-- was happening.
--
-- ── CORRECT vs VOID ─────────────────────────────────────────────────────────
-- Owner: *"ok should we make a void possible or an edit possible (that might
-- complicate things)"*. Both, split on one line: if it changes the TRACE, void
-- it; if it is a number, correct it. The lot code is printed on bags that are
-- physically in the world, so it can never be reused and must never stop
-- resolving — void keeps it reserved forever rather than freeing it. Void-only
-- would have been the more complicated answer, not the simpler one: every
-- fat-fingered bag count would force a re-record, and a re-record mints a NEW
-- lot code that does not match the bags already printed.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The session columns.
alter table public.pack_run
  add column if not exists opened_at             timestamptz,
  add column if not exists closed_at             timestamptz,
  add column if not exists opened_by_team_member text references public.team(team_member_id) on delete restrict,
  add column if not exists opened_by_name        text;

-- An open session has no bag count yet — that is the number the packer does not
-- have until they stop. It was NOT NULL with a > 0 check.
alter table public.pack_run alter column bags drop not null;
alter table public.pack_run drop constraint if exists pack_run_bags_check;

-- Everything that already exists was recorded in one shot, so it is closed.
update public.pack_run
   set opened_at             = coalesce(opened_at, packed_at),
       closed_at             = coalesce(closed_at, packed_at),
       opened_by_team_member = coalesce(opened_by_team_member, packed_by_team_member),
       opened_by_name        = coalesce(opened_by_name, packed_by_name)
 where closed_at is null or opened_at is null;

alter table public.pack_run alter column opened_at set default now();
alter table public.pack_run alter column opened_at set not null;

-- The count is required to CLOSE, not to open.
alter table public.pack_run add constraint pack_run_bags_when_closed
  check (closed_at is null or (bags is not null and bags > 0));

comment on column public.pack_run.opened_at is
  'When the session was opened and the lot code minted — before the bags were filled, so they can be labelled as they go.';
comment on column public.pack_run.closed_at is
  'When the packer entered the final bag count and the draw was applied. NULL = still open on the floor.';

create index if not exists idx_pack_run_open
  on public.pack_run (company_id, opened_at desc) where closed_at is null and voided_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The amendment log. An edit that silently overwrites a food-safety record
--    is the falsification Costco 5.1.11 is about, so a correction keeps what it
--    replaced. Never updated, never deleted — append only.
create table if not exists public.pack_run_correction (
  correction_id  text primary key default gen_random_uuid()::text,
  pack_run_id    text not null references public.pack_run(pack_run_id) on delete cascade,
  company_id     text not null references public.companies(company_id) on delete cascade,
  field          text not null,
  old_value      text,
  new_value      text,
  reason         text,
  corrected_at   timestamptz not null default now(),
  corrected_by   text references public.team(team_member_id) on delete restrict,
  corrected_by_name text
);
create index if not exists idx_pack_run_correction_run on public.pack_run_correction (pack_run_id, corrected_at desc);

alter table public.pack_run_correction enable row level security;
create policy pack_run_correction_read on public.pack_run_correction
  for select using (company_id in (select auth_company_ids()));
-- Written only through correct_pack_run, which is SECURITY DEFINER.
revoke insert, update, delete on public.pack_run_correction from authenticated;
grant select on public.pack_run_correction to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Open a session: mint the code, anchor the date, print.
create or replace function public.open_pack_run(
  p_company_id  text,
  p_product_id  text,
  p_coffee_prep text default 'whole_bean'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor    record;
  v_product  record;
  v_facility text;
  v_lot      text;
  v_run      text;
  v_day      date := current_date;
  v_shelf    int;
  v_anchor   timestamp;
  v_best     date;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.run', p_company_id) then
    raise exception 'You do not have permission to record bagging.' using errcode = 'insufficient_privilege';
  end if;
  if p_coffee_prep is not null and p_coffee_prep not in ('whole_bean','ground') then
    raise exception 'Coffee is either whole bean or ground.' using errcode = 'invalid_parameter_value';
  end if;

  select p.product_id, p.product_name, p.weight_lbs, p.recipe_id into v_product
    from public.products p
   where p.product_id = p_product_id and p.company_id = p_company_id;
  if v_product.product_id is null then
    raise exception 'That product is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  select facility_id into v_facility from public.team
   where auth_user_id = auth.uid() and company_id = p_company_id limit 1;

  select coalesce(shelf_life_days, 183) into v_shelf
    from public.fs_settings where company_id = p_company_id;
  v_shelf := coalesce(v_shelf, 183);

  -- The date the label will carry, anchored to the batch FIFO will reach first.
  select min(r.roast_date) into v_anchor
    from public.roasts_available_to_pack(p_company_id, 180, v_facility) r
   where r.recipe_id = v_product.recipe_id and r.remaining_lbs > 0.01;

  -- No anchor means nothing is on the shelf under this recipe. Leave best-by
  -- NULL rather than guessing from today: today + shelf life would be GENEROUS
  -- for coffee roasted a week ago, and a generous date is the one kind of wrong
  -- a printed shelf-life claim must never be. The screen asks instead.
  v_best := case when v_anchor is null then null else (v_anchor::date + v_shelf) end;

  select * into v_actor from public.actor_at();
  v_lot := public.next_lot_code(p_company_id, v_day);

  insert into public.pack_run (
    company_id, facility_id, lot_code, product_id, product_name_snapshot, coffee_prep,
    packed_on, bags, unit_weight_lbs, best_before,
    opened_at, opened_by_team_member, opened_by_name,
    packed_by_team_member, packed_by_name, created_by)
  values (
    p_company_id, v_facility, v_lot, p_product_id, v_product.product_name,
    coalesce(p_coffee_prep, 'whole_bean'),
    v_day, null, v_product.weight_lbs, v_best,
    now(), v_actor.team_member_id, v_actor.actor_name,
    v_actor.team_member_id, v_actor.actor_name, v_actor.actor_name)
  returning pack_run_id into v_run;

  return jsonb_build_object(
    'pack_run_id',     v_run,
    'lot_code',        v_lot,
    'product_name',    v_product.product_name,
    'unit_weight_lbs', v_product.weight_lbs,
    'best_before',     v_best,
    'anchor_roast_date', v_anchor,
    'shelf_life_days', v_shelf,
    'opened_by',       v_actor.actor_name);
end;
$$;

comment on function public.open_pack_run(text, text, text) is
  'Start a bagging session: mints the lot code and anchors best-by to the oldest batch FIFO will draw, so labels can be printed and applied while the bags are being filled. Leaves the count for close_pack_run.';

revoke all on function public.open_pack_run(text, text, text) from public;
grant execute on function public.open_pack_run(text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Close it: the count comes in, the draw is applied.
create or replace function public.close_pack_run(
  p_pack_run_id     text,
  p_bags            numeric,
  p_location        text    default null,
  p_bag_purchase_id text    default null,
  p_label_purchase_id text  default null,
  p_notes           text    default null,
  p_best_before     date    default null,
  p_allocations     jsonb   default '[]'::jsonb,
  p_sources         jsonb   default null   -- override; null = let the draw decide
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
begin
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id;
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

  -- The draw. p_sources is the bin-card / override path: when the packer names
  -- the batch themselves, that is the record, and FIFO does not get a vote.
  if p_sources is not null and jsonb_array_length(p_sources) > 0 then
    v_draw := p_sources;
    v_plan := jsonb_build_object('basis', 'named', 'shortfall', 0);
  else
    v_plan := public.pack_draw_plan(v_run.company_id, v_recipe, v_total, 180, v_run.facility_id);
    v_draw := v_plan->'draw';
  end if;

  insert into public.pack_run_source (pack_run_id, roast_log_id, lbs_used)
  select p_pack_run_id, s->>'roast_log_id', nullif(s->>'lbs_used','')::numeric
    from jsonb_array_elements(coalesce(v_draw, '[]'::jsonb)) s;

  -- The green behind the bag, frozen as it reads today.
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
         -- Whoever CLOSED it did the bagging; the opener may have been someone
         -- else on an earlier shift.
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
    -- Reported, never fatal. A shortfall means the shelf disagrees with the
    -- floor, and that is the roastmaster's problem to look into — not a reason
    -- to refuse the packer a record of what they actually bagged.
    'shortfall',   coalesce((v_plan->>'shortfall')::numeric, 0),
    'allocated',   v_alloc_total,
    'unallocated', p_bags - v_alloc_total);
end;
$$;

revoke all on function public.close_pack_run(text,numeric,text,text,text,text,date,jsonb,jsonb) from public;
grant execute on function public.close_pack_run(text,numeric,text,text,text,text,date,jsonb,jsonb) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Void: it did not happen as recorded.
create or replace function public.void_pack_run(p_pack_run_id text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_run   record;
  v_actor record;
  v_alloc int;
begin
  select * into v_run from public.pack_run where pack_run_id = p_pack_run_id;
  if v_run.pack_run_id is null or v_run.company_id not in (select auth_company_ids()) then
    raise exception 'That bagging run is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.void', v_run.company_id) then
    raise exception 'You do not have permission to void a bagging run.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why this run is being voided. A voided food-safety record without a reason is worse than no record.'
      using errcode = 'invalid_parameter_value';
  end if;
  if v_run.voided_at is not null then
    return jsonb_build_object('pack_run_id', p_pack_run_id, 'already_voided', true);
  end if;

  select count(*) into v_alloc from public.pack_run_allocation where pack_run_id = p_pack_run_id;
  select * into v_actor from public.actor_at();

  -- 🔴 THE LOT CODE IS NOT RELEASED. Bags carrying it may be on a shelf, in a
  -- van, or in a customer's cafe. next_lot_code must never hand it out again
  -- and a recall must still resolve it — so the row stays, flagged, and
  -- uq_pack_run_lot keeps the number reserved for good.
  update public.pack_run
     set voided_at   = now(),
         voided_by   = v_actor.team_member_id,
         void_reason = trim(p_reason),
         updated_by  = v_actor.actor_name,
         updated_at  = now()
   where pack_run_id = p_pack_run_id;

  -- The roast goes back on the shelf: every read of remaining_lbs already
  -- filters on pr.voided_at is null, so this needs no further work.
  --
  -- Set-asides do NOT survive. An order line pointing at a run that never
  -- happened would show as covered by coffee that does not exist.
  delete from public.pack_run_allocation where pack_run_id = p_pack_run_id;

  return jsonb_build_object(
    'pack_run_id', p_pack_run_id,
    'lot_code',    v_run.lot_code,
    'released_allocations', v_alloc);
end;
$$;

revoke all on function public.void_pack_run(text, text) from public;
grant execute on function public.void_pack_run(text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Correct: it happened, a number was wrong.
--
-- Deliberately CANNOT touch product, roast sources or lot code. Changing any of
-- those changes what the bags in the world are, and that is a void plus a new
-- run — not an edit.
create or replace function public.correct_pack_run(
  p_pack_run_id text,
  p_reason      text,
  p_bags        numeric default null,
  p_best_before date    default null,
  p_location    text    default null,
  p_notes       text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
         total_lbs   = coalesce(p_bags, bags) * coalesce(unit_weight_lbs, 0),
         best_before = coalesce(p_best_before, best_before),
         location    = coalesce(nullif(trim(p_location),''), location),
         notes       = coalesce(nullif(trim(p_notes),''), notes),
         updated_by  = v_actor.actor_name,
         updated_at  = now()
   where pack_run_id = p_pack_run_id;

  return jsonb_build_object('pack_run_id', p_pack_run_id, 'changes', v_changed);
end;
$$;

revoke all on function public.correct_pack_run(text,text,numeric,date,text,text) from public;
grant execute on function public.correct_pack_run(text,text,numeric,date,text,text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Permissions for the new verb.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values
  ('pack.void', 'Roasting', 'Void a bagging run',
   'Mark a bagging run as never having happened, with a reason. The lot code stays reserved for good, because bags carrying it may already be out in the world.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 71, 'haccp')
on conflict (permission_id) do update
  set label = excluded.label, description = excluded.description, feature_key = excluded.feature_key;

-- The word this feature exists not to say. The modal header has said BAGGING IS
-- NOT PACKING since the day it shipped; the permission a roaster reads in
-- Settings said "Record packing".
update public.permissions
   set label = 'Record bagging',
       description = 'Record a bagging run: which product was bagged, how many bags, and the lot code that leads back through the roast to the green.'
 where permission_id = 'pack.run';

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, 'pack.void', p.plan_id = 'enterprise_plus', 'Bagging records — part of the enterprise_plus food-safety module'
  from (values ('starter'),('pro'),('enterprise'),('enterprise_plus')) p(plan_id)
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Voiding is not floor work: it unwinds a signed record. Staff and assistant
-- roasters can bag all day and cannot erase a run.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'pack.void', true),
  ('facility_admin', 'pack.void', true),
  ('manager',        'pack.void', true),
  ('roastmaster',    'pack.void', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. A folded draw row must own up to being topped up.
--    The fold in 20260908000006 took min(reason), and 'ratio' sorts before
--    'topped up' — so a row that was part ratio and part top-up called itself
--    pure ratio. The reason exists to explain the draw to a human; max() is the
--    honest one.
create or replace function public.pack_draw_plan(
  p_company_id  text,
  p_recipe_id   text,
  p_lbs         numeric,
  p_days        int     default 180,
  p_facility_id text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type  text;
  v_draw  jsonb := '[]'::jsonb;
  v_taken numeric := 0;
  v_need  numeric;
  v_basis text := 'fifo';
  c       record;
  b       record;
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

  create temp table _avail on commit drop as
    select r.roast_log_id, r.roast_date, r.remaining_lbs, rl.origin_id
      from public.roasts_available_to_pack(p_company_id, p_days, p_facility_id) r
      join public.roast_log rl on rl.roast_log_id = r.roast_log_id
     where r.recipe_id = p_recipe_id and r.remaining_lbs > 0.01
     order by r.roast_date asc;

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
            'roast_date', b.roast_date, 'origin_id', b.origin_id, 'reason', 'ratio');
          update _avail set remaining_lbs = remaining_lbs - v_take where roast_log_id = b.roast_log_id;
          v_need  := v_need - v_take;
          v_taken := v_taken + v_take;
        end;
      end loop;
    end loop;
  end if;

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
               -- max(): 'topped up' beats 'ratio' beats 'fifo', so a folded row
               -- names the weaker basis rather than flattering itself.
               'reason',       max(e->>'reason')) as d
        from jsonb_array_elements(v_draw) e
       group by e->>'roast_log_id'
    ) folded;

  return jsonb_build_object(
    'draw', v_draw, 'taken', round(v_taken, 2),
    'shortfall', round(greatest(p_lbs - v_taken, 0), 2), 'basis', v_basis);
end;
$$;

revoke all on function public.pack_draw_plan(text, text, numeric, int, text) from public;
grant execute on function public.pack_draw_plan(text, text, numeric, int, text) to authenticated;

commit;
