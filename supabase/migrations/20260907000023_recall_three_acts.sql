-- Build it, finalise it, notify. Three acts, and the rails between them.
--
-- start_recall() did all three at once: it computed, froze and laid out notices
-- in a single call. That is wrong for the flow the owner asked for — "build the
-- recall, finalize/save recall. initiate recall notice" — and it is wrong for the
-- exercise, because Costco times the drill from when you start looking, not from
-- when you press a button that has already finished the work.
--
-- So it is replaced by three:
--
--   open_recall         starts the clock and nothing else. No trace, no scope,
--                       no notices. A draft can be walked away from.
--   set_recall_trigger  which lot, or which green, or which packaging lot —
--                       and whether the person chose it or STRATA did.
--   finalise_recall     the freeze. Report captured, clock stopped, mass balance
--                       computed, notices laid out. From here the scope cannot
--                       move under anybody.
--
-- ── The rails ───────────────────────────────────────────────────────────────
-- A DRAFT can never email anybody: the send gate refuses when finalised_at is
-- null. A PRACTICE RUN can never email anybody at all, whatever its state: the
-- send gate refuses kind='exercise'. Both are enforced here rather than in the
-- UI, because a modal is a suggestion and this path is reachable directly.
--
-- The exercise grade is computed, not claimed: elapsed against 120 minutes, and
-- bags accounted against Costco's stated 100%. A shortfall does not fail the
-- exercise by itself — it demands a sentence explaining it, which is the honest
-- outcome when a roastery is still catching up on data entry.

begin;

drop function if exists public.start_recall(text, text, text);
drop function if exists public.open_recall(text, text, text);

-- ── Act 1: open it, and start the clock ─────────────────────────────────────
create or replace function public.open_recall(
  p_company_id        text,
  p_kind              text,
  p_reason            text,
  p_exercise_category text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_actor record; v_id text; v_needed text;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why you are doing this. It goes on the record, and into the notice if one goes out.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_kind not in ('exercise','stock_recovery','withdrawal','recall') then
    raise exception 'Unknown kind.' using errcode = 'invalid_parameter_value';
  end if;
  if p_kind = 'exercise' and p_exercise_category is null then
    raise exception 'Say what this practice run covers: finished product, an ingredient, or packaging. Costco counts them separately.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The company is passed, not guessed. Resolving it as "the first team row for
  -- this uid" silently picks the wrong tenant for anybody who belongs to two —
  -- which is how this first failed in testing, opening a recall against a
  -- company where the module was not even switched on.
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;
  v_company := p_company_id;

  -- Running a drill and emailing your accounts are not the same authority.
  v_needed := case when p_kind = 'exercise' then 'recall.exercise' else 'recall.manage' end;
  if not public.auth_has_permission(v_needed, v_company) then
    raise exception 'You do not have permission to do that.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_actor from public.actor_at();

  insert into public.recall (company_id, kind, exercise_category, reason, status,
                             reference_no, initiated_by_team_member, initiated_by_name)
  values (v_company, p_kind, p_exercise_category, trim(p_reason), 'draft',
          public.next_recall_reference(v_company, p_kind),
          v_actor.team_member_id, v_actor.actor_name)
  returning recall_id into v_id;
  return v_id;
end;
$$;

comment on function public.open_recall(text, text, text, text) is
  'Act 1. Starts the clock and nothing else — Costco times the exercise from when you start looking, not from when you press a button that has already done the work.';

-- ── Act 2: what set it off ──────────────────────────────────────────────────
create or replace function public.set_recall_trigger(
  p_recall_id          text,
  p_lot_code           text default null,
  p_origin_purchase_id text default null,
  p_system_picked      boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_company text; v_status text;
begin
  select company_id, status into v_company, v_status
    from public.recall where recall_id = p_recall_id and company_id in (select auth_company_ids());
  if v_company is null then raise exception 'No such recall.' using errcode = 'no_data_found'; end if;
  if v_status <> 'draft' then
    raise exception 'That recall is already finalised. Its scope cannot be changed.'
      using errcode = 'invalid_parameter_value';
  end if;
  if (p_lot_code is null) = (p_origin_purchase_id is null) then
    raise exception 'Give exactly one starting point: a lot code or a green purchase.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.recall
     set trigger_kind = case when p_lot_code is not null then 'packed_lot' else 'green_lot' end,
         trigger_ref  = coalesce(p_lot_code, p_origin_purchase_id),
         lot_selection = case when p_system_picked then 'system' else 'user' end,
         updated_at = now()
   where recall_id = p_recall_id;
end;
$$;

-- ── Act 3: the freeze ───────────────────────────────────────────────────────
create or replace function public.finalise_recall(p_recall_id text, p_variance_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_rec public.recall;
  v_report jsonb;
  v_packed numeric; v_shipped numeric; v_unacc numeric; v_pct numeric;
  v_actor record; v_elapsed int; v_needed text;
begin
  select * into v_rec from public.recall
   where recall_id = p_recall_id and company_id in (select auth_company_ids());
  if v_rec.recall_id is null then raise exception 'No such recall.' using errcode = 'no_data_found'; end if;
  if v_rec.status <> 'draft' then
    raise exception 'That recall is already finalised.' using errcode = 'invalid_parameter_value';
  end if;
  if v_rec.trigger_ref is null then
    raise exception 'Choose what set this off before finalising it.' using errcode = 'invalid_parameter_value';
  end if;

  v_needed := case when v_rec.kind = 'exercise' then 'recall.exercise' else 'recall.manage' end;
  if not public.auth_has_permission(v_needed, v_rec.company_id) then
    raise exception 'You do not have permission to finalise this.' using errcode = 'insufficient_privilege';
  end if;

  v_report := public.recall_report(
    case when v_rec.trigger_kind = 'packed_lot' then v_rec.trigger_ref end,
    case when v_rec.trigger_kind = 'green_lot'  then v_rec.trigger_ref end);
  if not coalesce((v_report->>'found')::boolean, false) then
    raise exception 'Nothing found for that starting point.' using errcode = 'no_data_found';
  end if;

  v_packed  := coalesce((v_report#>>'{totals,bags_packed}')::numeric, 0);
  v_shipped := coalesce((v_report#>>'{totals,bags_shipped}')::numeric, 0);
  v_unacc   := coalesce((v_report#>>'{totals,bags_unaccounted}')::numeric, 0);
  -- "Accounted for", never "recovered": a drill proves you can find it, not that
  -- you got it back. It is also Costco's own wording.
  v_pct := case when v_packed > 0 then round(((v_packed - v_unacc) / v_packed) * 100, 1) else null end;

  if v_pct is not null and v_pct < 100 and coalesce(trim(p_variance_note), '') = '' then
    -- '%%' is a literal percent in RAISE, so spelling the word avoids a format
    -- string that reads correctly and throws at compile time.
    raise exception 'Only % percent of the coffee is accounted for. Write one line saying why before finalising — it prints beside the number.', v_pct
      using errcode = 'invalid_parameter_value';
  end if;

  v_elapsed := greatest(round(extract(epoch from (now() - v_rec.initiated_at)) / 60)::int, 0);
  select * into v_actor from public.actor_at();

  update public.recall
     set report = v_report,
         status = 'finalised',
         finalised_at = now(),
         finalised_by_team_member = v_actor.team_member_id,
         finalised_by_name = v_actor.actor_name,
         completed_at = now(),
         elapsed_minutes = v_elapsed,
         bags_accounted = v_packed - v_unacc,
         accounted_pct = v_pct,
         variance_note = nullif(trim(p_variance_note), ''),
         updated_at = now()
   where recall_id = p_recall_id;

  -- Notices are laid out even for a practice run: the exercise has to prove the
  -- contact list is current (Costco 3.5.2), and a drill that never looks at who
  -- would be told proves nothing about reaching them. They simply cannot be sent.
  insert into public.recall_notice (recall_id, customer_id, customer_name, email, phone, lot_codes, reply_token)
  select p_recall_id, cu.customer_id, c->>'customer',
         nullif(c->>'email',''), nullif(c->>'phone',''),
         (select array_agg(distinct l->>'lot_code') from jsonb_array_elements(v_report->'packed_lots') l),
         encode(extensions.gen_random_bytes(18), 'hex')   -- pgcrypto lives in `extensions`, not public
    from jsonb_array_elements(v_report->'customers') c
    left join public.customers cu on cu.company_id = v_rec.company_id and cu.name_company = c->>'customer';

  return jsonb_build_object(
    'recall_id', p_recall_id,
    'reference_no', v_rec.reference_no,
    'elapsed_minutes', v_elapsed,
    'within_two_hours', v_elapsed <= 120,
    'accounted_pct', v_pct,
    'bags_packed', v_packed,
    'bags_shipped', v_shipped,
    'bags_unaccounted', v_unacc,
    'customers', (select count(*) from public.recall_notice where recall_id = p_recall_id),
    'without_email', (select count(*) from public.recall_notice where recall_id = p_recall_id and nullif(email,'') is null)
  );
end;
$$;

comment on function public.finalise_recall(text, text) is
  'Act 3. Freezes the report, stops the clock, computes the mass balance and lays out the notices. A shortfall does not fail the exercise by itself — it demands a sentence, which is the honest outcome while a roastery is still catching up on entry.';

-- ── The send gate, now with both rails ──────────────────────────────────────
create or replace function public.confirm_recall_send(p_recall_id text, p_expected_count int)
returns setof public.recall_notice
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_rec public.recall; v_actual int;
begin
  select * into v_rec from public.recall
   where recall_id = p_recall_id and company_id in (select auth_company_ids());
  if v_rec.recall_id is null then raise exception 'No such recall.' using errcode = 'no_data_found'; end if;

  if not public.auth_has_permission('recall.manage', v_rec.company_id) then
    raise exception 'Only an admin can send a recall notice.' using errcode = 'insufficient_privilege';
  end if;
  -- Rail 1: a practice run reaches nobody outside the building. Ever.
  if v_rec.kind = 'exercise' then
    raise exception 'This is a practice run. It cannot email a customer.' using errcode = 'insufficient_privilege';
  end if;
  -- Rail 2: a half-built recall cannot email anybody.
  if v_rec.finalised_at is null then
    raise exception 'Finalise this recall before sending anything.' using errcode = 'invalid_parameter_value';
  end if;
  if v_rec.status = 'closed' then
    raise exception 'That recall is closed. Reopen it before sending anything.' using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_actual from public.recall_notice
   where recall_id = p_recall_id and status = 'pending' and nullif(email,'') is not null;

  if v_actual = 0 then
    raise exception 'Nobody on this recall has an email address yet. Add addresses, or mark those customers as reached another way.'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_expected_count is distinct from v_actual then
    raise exception 'This would email % customer(s), not %. The list changed since you reviewed it — check it again.',
      v_actual, p_expected_count using errcode = 'invalid_parameter_value';
  end if;

  return query select * from public.recall_notice
    where recall_id = p_recall_id and status = 'pending' and nullif(email,'') is not null;
end;
$$;

-- ── Running a drill is not the same authority as emailing your customers ────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values (
  'recall.exercise', 'Roasting', 'Run a practice recall',
  'Run the traceability exercises Costco asks for twice a year. A practice run reaches nobody outside the building and cannot email a customer.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  true, 72, 'haccp')
on conflict (permission_id) do update set feature_key = excluded.feature_key;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values ('starter','recall.exercise',false,'Practice recalls — enterprise_plus food-safety module'),
       ('pro','recall.exercise',false,'Practice recalls — enterprise_plus food-safety module'),
       ('enterprise','recall.exercise',false,'Practice recalls — enterprise_plus food-safety module'),
       ('enterprise_plus','recall.exercise',true,'Practice recalls — enterprise_plus')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Wider than recall.manage on purpose: a production manager should be able to
-- run the drill every six months without waiting for an owner.
insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin','recall.exercise',true),
       ('facility_admin','recall.exercise',true),
       ('manager','recall.exercise',true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

revoke all on function public.open_recall(text, text, text, text)                 from public;
revoke all on function public.set_recall_trigger(text, text, text, boolean)       from public;
revoke all on function public.finalise_recall(text, text)                         from public;
grant execute on function public.open_recall(text, text, text, text)           to authenticated;
grant execute on function public.set_recall_trigger(text, text, text, boolean) to authenticated;
grant execute on function public.finalise_recall(text, text)                   to authenticated;

commit;
