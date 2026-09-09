-- Give a broken trace its green back, without spending the stock a second time.
--
-- ── What 20260908000018 proved, on a live database ─────────────────────────
-- The owner's third scenario — "they may register a shipment received for that
-- lot later for an earlier date" — does not merely fail to repair the roast.
-- It is REVERSED. Measured on staging:
--
--     group anchor              2026-09-06
--     insert a 60 lb lot dated 5 days ago, uncounted
--     remaining_lbs BEFORE replay   60
--     remaining_lbs AFTER  replay    0
--
-- recompute_origin_lot_consumption re-seeds an uncounted lot received strictly
-- BEFORE the group's last count to zero, on the reasoning that a comprehensive
-- count already saw whatever was physically on the floor. For QUANTITY that is
-- right and must not change — the count is the physical truth. But it means no
-- back-dated receipt can ever feed a roast that came up short before the anchor,
-- and on MCR that is 445 roasts holding 26,901.7 lb of green with no lot behind it.
--
-- ── So the repair does not re-deduct. It names. ────────────────────────────
-- Quantity and identity are two different questions and only one of them is in
-- dispute. The count owns the pounds; nobody is arguing about the pounds. What
-- was lost is WHICH LOT the roast drew from — and that can be restored without
-- moving a single remaining_lbs, which is why this can run over sealed history
-- without disturbing the anchor, the replay, or a cent of valuation arithmetic.
--
-- Every row it writes is marked attribution_only, because an auditor is owed the
-- difference between "this green was deducted" and "this green was identified".
--
-- ── The one rule that stops this being fiction ─────────────────────────────
-- A lot may be named as a source only up to the pounds it actually held. The
-- cap is the lot's own `amount` minus everything already attributed to it, from
-- any roast, by any path. Without that this function would happily invent a
-- supply chain. With it, it can only ever say something the purchase record
-- already supports.
--
-- It also refuses to touch a WAIVED row. A waiver is somebody's signature saying
-- this gap is accepted and explained; a repair job may not quietly overwrite it.

begin;

-- ── 1. A gap can be accepted, by a person, with a reason ───────────────────
alter table public.roast_lot_shortfall
  add column if not exists waived_at        timestamptz,
  add column if not exists waived_by        text references public.team(team_member_id) on delete restrict,
  add column if not exists waived_by_name   text,
  add column if not exists waive_reason     text;

comment on column public.roast_lot_shortfall.waived_at is
  'When somebody accepted this gap as explained. A waived row stays in the ledger — it is answered, not deleted.';
comment on column public.roast_lot_shortfall.waived_by_name is
  'Their name as it read at the time, so the record still names them after a rename or a departure.';

create index if not exists idx_roast_lot_shortfall_open
  on public.roast_lot_shortfall (company_id, facility_id) where waived_at is null;

-- ── 2. Where the trace starts ──────────────────────────────────────────────
-- A roastery implementing STRATA has years of history that was never recorded
-- lot-by-lot, and that history is not a finding — it is what the system was
-- bought to end. Everything before this date is out of scope for the queue and
-- for a recall's completeness claim. Null means no window: report everything.
alter table public.fs_settings
  add column if not exists trace_start_date date;

comment on column public.fs_settings.trace_start_date is
  'The day lot traceability starts for this tenant. Roasts before it are out of scope — pre-implementation history, not an unanswered gap. Null = no window.';

-- ── 3. The two verbs ───────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values
  ('trace.reconcile', 'Inventory', 'Reconcile unassigned lots',
   'Work the queue of roasts with no green behind them: record the shipment or count that was missed, and name the lots those roasts actually drew from.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 46, null),
  ('trace.waive', 'Inventory', 'Accept a traceability gap',
   'Sign off a roast whose green cannot be identified, with a reason. The gap stays on the record as answered — it is never deleted.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 47, null)
on conflict (permission_id) do update
  set label = excluded.label, description = excluded.description,
      category = excluded.category, feature_key = excluded.feature_key;

-- Same plans as inventory.purchase: this is inventory integrity, not a
-- food-safety add-on, and a pro tenant's costing depends on it just as much.
insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, k.permission_id, p.plan_id <> 'starter', 'Lot reconciliation — tracks inventory.purchase'
  from (values ('starter'),('pro'),('enterprise'),('enterprise_plus')) p(plan_id)
 cross join (values ('trace.reconcile'),('trace.waive')) k(permission_id)
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Reconciling is bookkeeping — whoever records purchases can do it.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',    'trace.reconcile', true),
  ('facility_admin',   'trace.reconcile', true),
  ('manager',          'trace.reconcile', true),
  ('roastmaster',      'trace.reconcile', true),
  ('accounting_admin', 'trace.reconcile', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- Waiving is not bookkeeping. It is a signature saying a batch's green will
-- never be identified and that is acceptable — the one act here an auditor
-- reads as a decision rather than as data entry. Admins only.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',  'trace.waive', true),
  ('facility_admin', 'trace.waive', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ── 4. The surgical repair ─────────────────────────────────────────────────
create or replace function public.attribute_unsourced_roasts(
  p_company_id  text,
  p_facility_id text default null,
  p_origin_id   text default null,
  p_roast_ids   text[] default null,
  p_from        date default null,
  p_to          date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row     record;
  v_lot     record;
  v_take    numeric;
  v_left    numeric;
  v_named   numeric := 0;
  v_roasts  text[] := '{}';
  v_touched int := 0;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.reconcile', p_company_id) then
    raise exception 'You do not have permission to reconcile lots.' using errcode = 'insufficient_privilege';
  end if;

  for v_row in
    select s.roast_log_id, s.origin_id, s.facility_id, s.lbs_unmet, rl.roast_date
      from public.roast_lot_shortfall s
      join public.roast_log rl on rl.roast_log_id = s.roast_log_id
     where s.company_id = p_company_id
       and s.waived_at is null
       and (p_facility_id is null or s.facility_id  = p_facility_id)
       and (p_origin_id   is null or s.origin_id    = p_origin_id)
       and (p_roast_ids   is null or s.roast_log_id = any(p_roast_ids))
       and (p_from is null or rl.roast_date::date >= p_from)
       and (p_to   is null or rl.roast_date::date <= p_to)
     order by rl.roast_date asc
  loop
    -- Same lock the engine takes, so a repair and a live replay can never
    -- interleave on one origin.
    perform pg_advisory_xact_lock(hashtext(v_row.origin_id), hashtext(v_row.facility_id));

    v_left := v_row.lbs_unmet;

    for v_lot in
      select cip.origin_purchase_id,
             -- What this lot can still honestly account for: what was bought,
             -- less everything already attributed to it by any roast.
             cip.amount - coalesce((
               select sum(c.lbs_consumed) from public.roast_log_lot_consumption c
                where c.origin_purchase_id = cip.origin_purchase_id), 0) as headroom
        from public.coffee_inventory_purchased cip
        left join public.shipment_received sr on sr.shipment_id = cip.shipment_id
       where cip.facility_id = v_row.facility_id
         and cip.origin = v_row.origin_id
         and coalesce(cip.amount, 0) > 0
         -- It has to have been here. Same availability test the draw uses.
         and coalesce(sr.date_received, cip.created_at::date) <= v_row.roast_date::date
         and coalesce(sr.voided, false) = false
       order by coalesce(sr.date_received, cip.created_at::date) asc, cip.created_at asc
    loop
      exit when v_left <= 0.01;
      if coalesce(v_lot.headroom, 0) <= 0.01 then continue; end if;

      v_take := least(v_lot.headroom, v_left);
      insert into public.roast_log_lot_consumption
        (roast_log_id, origin_purchase_id, lbs_consumed, attribution_only)
      values (v_row.roast_log_id, v_lot.origin_purchase_id, round(v_take, 4), true);

      v_left  := v_left - v_take;
      v_named := v_named + v_take;
    end loop;

    if v_left < v_row.lbs_unmet then
      v_touched := v_touched + 1;
      if not (v_row.roast_log_id = any(v_roasts)) then
        v_roasts := v_roasts || v_row.roast_log_id;
      end if;
      if v_left <= 0.01 then
        delete from public.roast_lot_shortfall
         where roast_log_id = v_row.roast_log_id
           and origin_id    = v_row.origin_id
           and facility_id  = v_row.facility_id;
      else
        update public.roast_lot_shortfall
           set lbs_unmet = round(v_left, 4), as_of = now()
         where roast_log_id = v_row.roast_log_id
           and origin_id    = v_row.origin_id
           and facility_id  = v_row.facility_id;
      end if;
    end if;
  end loop;

  -- The green cost these batches were missing, now that they have lots.
  if array_length(v_roasts, 1) > 0 then
    perform public.value_roasts_lot_consumption(v_roasts);
  end if;

  return jsonb_build_object(
    'roasts_repaired', coalesce(array_length(v_roasts, 1), 0),
    'draws_repaired',  v_touched,
    'lbs_named',       round(v_named, 2));
end;
$$;

comment on function public.attribute_unsourced_roasts(text, text, text, text[], date, date) is
  'Name the lots a short roast actually drew from, without touching remaining_lbs. Restores the trace over history the count anchor has sealed; capped at each lot''s purchased amount so it can never invent a supply chain.';

revoke all on function public.attribute_unsourced_roasts(text, text, text, text[], date, date) from public;
grant execute on function public.attribute_unsourced_roasts(text, text, text, text[], date, date) to authenticated;

-- ── 5. Accepting a gap ─────────────────────────────────────────────────────
-- p_expected_count is the count the person just read on screen, re-checked here
-- — the same guard confirm_recall_send uses. If the queue moved under them
-- between reading and confirming, this refuses rather than signing off a set
-- they never saw.
create or replace function public.waive_roast_shortfall(
  p_company_id     text,
  p_rows           jsonb,
  p_reason         text,
  p_expected_count int
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor record;
  v_n     int;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.waive', p_company_id) then
    raise exception 'You do not have permission to accept a traceability gap.'
      using errcode = 'insufficient_privilege';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why this gap is being accepted. A waiver with no reason answers nothing.'
      using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_n
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
    join public.roast_lot_shortfall s
      on s.roast_log_id = r->>'roast_log_id'
     and s.origin_id    = r->>'origin_id'
     and s.facility_id  = r->>'facility_id'
   where s.company_id = p_company_id and s.waived_at is null;

  if v_n <> coalesce(p_expected_count, -1) then
    raise exception 'This list changed while you were reading it — % of the % you confirmed are still open. Look again.',
      v_n, p_expected_count using errcode = 'invalid_parameter_value';
  end if;

  select * into v_actor from public.actor_at(now());

  update public.roast_lot_shortfall s
     set waived_at      = now(),
         waived_by      = v_actor.team_member_id,
         waived_by_name = v_actor.actor_name,
         waive_reason   = trim(p_reason)
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where s.roast_log_id = r->>'roast_log_id'
     and s.origin_id    = r->>'origin_id'
     and s.facility_id  = r->>'facility_id'
     and s.company_id   = p_company_id
     and s.waived_at is null;

  get diagnostics v_n = row_count;
  return jsonb_build_object('waived', v_n, 'by', v_actor.actor_name);
end;
$$;

revoke all on function public.waive_roast_shortfall(text, jsonb, text, int) from public;
grant execute on function public.waive_roast_shortfall(text, jsonb, text, int) to authenticated;

create or replace function public.unwaive_roast_shortfall(
  p_company_id text,
  p_rows       jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  if p_company_id is null or p_company_id not in (select auth_company_ids()) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('trace.waive', p_company_id) then
    raise exception 'You do not have permission to reopen a waiver.' using errcode = 'insufficient_privilege';
  end if;

  update public.roast_lot_shortfall s
     set waived_at = null, waived_by = null, waived_by_name = null, waive_reason = null
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where s.roast_log_id = r->>'roast_log_id'
     and s.origin_id    = r->>'origin_id'
     and s.facility_id  = r->>'facility_id'
     and s.company_id   = p_company_id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.unwaive_roast_shortfall(text, jsonb) from public;
grant execute on function public.unwaive_roast_shortfall(text, jsonb) to authenticated;

commit;
