-- The recall register: build it, finalise it, then notify.
--
-- Owner: "initiating a recall should be its own view that shows all initiated
-- recalls. and the flow to initiate a recall should be built out for the user
-- step by step. build the recall, finalize/save recall. initiate recall notice."
-- Plus: admin only, and an explicit double confirmation before anything sends.
--
-- Research into how recall software and the regulations actually work changed
-- four things I had wrong. They are the reason this migration is large.
--
-- 1. MOST ROWS WILL BE PRACTICE RUNS. Costco 3.5.4 wants two self-run exercises a
--    year and the auditor tests a third live; a real recall may never happen. So
--    `kind` is the primary column, not an afterthought, and 21 CFR 7.3 makes the
--    four kinds legally different acts — filing a drill as a "recall" hands an
--    auditor a history that reads far worse than the facts.
--
-- 2. THE RULE IS PER CATEGORY, not a count of two. Two exercises on finished
--    product prove nothing about green or packaging. `exercise_category` is what
--    makes "are we covered this year" answerable.
--
-- 3. THE CLOCK STARTS BEFORE THE LOOKUP. Costco times the exercise, not the
--    query. An exercise record reading "elapsed: 4 seconds" is worse than none,
--    so `initiated_at` is stamped when the draft opens at step one and
--    `elapsed_minutes` is frozen at finalise.
--
-- 4. THE MODEL WAS OUTBOUND ONLY. Five notice statuses, all about whether a
--    message left the building. Everything a regulator actually asks for is on
--    the reply side — 21 CFR 7.53(b) counts consignees who responded, how much
--    they still had, and who never answered. Without it a recall can only ever
--    look finished, never be finished.
--
-- ── The rail ────────────────────────────────────────────────────────────────
-- A practice run can never email a customer, and a draft can never email a
-- customer. Both are enforced in the send gate, not in the UI, because the UI is
-- not the only way in. That is what makes "finalise" a real act rather than a
-- button that sets a flag.

begin;

-- ── What kind of thing this is ──────────────────────────────────────────────
alter table public.recall
  add column if not exists kind text not null default 'recall',
  add column if not exists exercise_category text,
  add column if not exists reference_no text,
  add column if not exists lot_selection text not null default 'user',
  add column if not exists completed_at timestamptz,
  add column if not exists elapsed_minutes int,
  add column if not exists finalised_at timestamptz,
  add column if not exists finalised_by_team_member text references public.team(team_member_id) on delete restrict,
  add column if not exists finalised_by_name text,
  add column if not exists bags_accounted numeric,
  add column if not exists accounted_pct numeric,
  add column if not exists variance_note text,
  add column if not exists hazard_summary text,
  add column if not exists disposition_instruction text,
  add column if not exists contact_name text,
  add column if not exists contact_phone text,
  add column if not exists depth text not null default 'wholesale',
  add column if not exists disposition text,
  add column if not exists disposition_qty numeric,
  add column if not exists disposition_at timestamptz,
  add column if not exists disposition_witnessed_by text;

alter table public.recall drop constraint if exists recall_kind_check;
alter table public.recall add constraint recall_kind_check
  -- 21 CFR 7.3: a drill, a bench catch, a quality pull-back and a safety recall
  -- are different acts. The send rail keys off this column.
  check (kind in ('exercise','stock_recovery','withdrawal','recall'));

alter table public.recall drop constraint if exists recall_exercise_category_check;
alter table public.recall add constraint recall_exercise_category_check
  check (exercise_category is null or exercise_category in ('finished_product','ingredient','primary_packaging'));

alter table public.recall drop constraint if exists recall_lot_selection_check;
alter table public.recall add constraint recall_lot_selection_check
  -- 'system' means STRATA picked the lot. Recorded because a tenant who always
  -- drills on a clean, simple, fully-shipped lot is what an auditor reads as staged.
  check (lot_selection in ('user','system'));

alter table public.recall drop constraint if exists recall_depth_check;
alter table public.recall add constraint recall_depth_check
  check (depth in ('wholesale','wholesale_and_consumer'));

alter table public.recall drop constraint if exists recall_disposition_check;
alter table public.recall add constraint recall_disposition_check
  check (disposition is null or disposition in ('destroyed','reworked','returned_to_supplier','released','held'));

alter table public.recall drop constraint if exists recall_status_check;
alter table public.recall add constraint recall_status_check
  check (status in ('draft','finalised','notified','closed'));

-- The report is no longer written at creation: a draft has none, and a finalised
-- record must. That is the freeze, expressed as a constraint rather than a habit.
alter table public.recall alter column report drop not null;
alter table public.recall drop constraint if exists recall_finalised_has_report;
alter table public.recall add constraint recall_finalised_has_report
  check (finalised_at is null or report is not null);

-- trigger_ref is chosen at step two, so a step-one draft has neither.
alter table public.recall alter column trigger_kind drop not null;
alter table public.recall alter column trigger_ref  drop not null;

create unique index if not exists uq_recall_reference on public.recall (company_id, reference_no)
  where reference_no is not null;
create index if not exists idx_recall_kind on public.recall (company_id, kind, initiated_at desc);

comment on column public.recall.kind is
  'exercise (a practice run) · stock_recovery (caught before it left) · withdrawal (quality, not safety) · recall (a safety problem). Legally different acts under 21 CFR 7.3, and the send rail keys off this.';
comment on column public.recall.exercise_category is
  'finished_product · ingredient · primary_packaging. Costco 3.5.4 is a per-category rule: two exercises on the same category prove nothing.';
comment on column public.recall.elapsed_minutes is
  'Frozen at finalise from the real clock, which starts when the draft opens — before any lookup. Costco times the exercise, not the query.';

-- ── The reply side, which was missing entirely ──────────────────────────────
alter table public.recall_notice
  add column if not exists responded_at timestamptz,
  add column if not exists response_method text,
  add column if not exists has_product boolean,
  add column if not exists bags_on_hand numeric,
  add column if not exists bags_returned numeric,
  add column if not exists bags_destroyed numeric,
  add column if not exists further_distributed boolean,
  add column if not exists sub_consignee_note text,
  add column if not exists response_recorded_by text,
  add column if not exists reply_token text,
  add column if not exists sent_subject text,
  add column if not exists sent_body text,
  add column if not exists delivery_status text;

alter table public.recall_notice drop constraint if exists recall_notice_status_check;
alter table public.recall_notice add constraint recall_notice_status_check
  check (status in ('pending','sent','responded','failed','reached_another_way','not_required'));

alter table public.recall_notice drop constraint if exists recall_notice_response_method_check;
alter table public.recall_notice add constraint recall_notice_response_method_check
  check (response_method is null or response_method in ('link','phone','email','in_person'));

create unique index if not exists uq_recall_notice_token on public.recall_notice (reply_token)
  where reply_token is not null;

comment on column public.recall_notice.sent_body is
  'The words that actually went out, frozen per send. Not a template id: an auditor asking for evidence of communication wants to read what was sent, and the template will have changed by then.';
comment on column public.recall_notice.reply_token is
  '21 CFR 7.49(c)(1)(v) — the notice must give a ready means to report back. One click writes straight onto this row.';

-- ── What went wrong, and what is being done about it ────────────────────────
create table if not exists public.recall_finding (
  recall_finding_id text primary key default (gen_random_uuid())::text,
  recall_id      text not null references public.recall(recall_id) on delete cascade,
  what_happened  text not null,
  root_cause     text,
  corrective_action text,
  owner_team_member text references public.team(team_member_id) on delete restrict,
  owner_name     text,
  due_on         date,
  completed_at   timestamptz,
  verified_by    text,
  recorded_by    text,
  recorded_at    timestamptz not null default now()
);

create index if not exists idx_recall_finding_recall on public.recall_finding (recall_id);
create index if not exists idx_recall_finding_open on public.recall_finding (due_on) where completed_at is null;

comment on table public.recall_finding is
  'Costco 3.5.3 wants a procedure to investigate the cause and identify corrective actions. Required for a real event, and for an exercise that missed the two hours or fell short of 100% — the case everyone forgets, and the one that turns a failed drill into evidence of a working system.';

alter table public.recall_finding enable row level security;
create policy recall_finding_read on public.recall_finding
  for select using (recall_id in (select recall_id from public.recall));
create policy recall_finding_write on public.recall_finding
  for all using (recall_id in (select recall_id from public.recall where public.auth_has_permission('recall.manage', company_id)))
  with check (recall_id in (select recall_id from public.recall where public.auth_has_permission('recall.manage', company_id)));

-- ── A number people can say out loud ────────────────────────────────────────
create or replace function public.next_recall_reference(p_company_id text, p_kind text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_year int := extract(year from current_date); v_seq int; v_pre text;
begin
  v_pre := case when p_kind = 'exercise' then 'DRILL' else 'RECALL' end;
  select coalesce(max(substring(reference_no from '[0-9]+$')::int), 0) + 1
    into v_seq
    from public.recall
   where company_id = p_company_id
     and reference_no like v_pre || '-' || v_year || '-%';
  return v_pre || '-' || v_year || '-' || lpad(v_seq::text, 3, '0');
end;
$$;

commit;
