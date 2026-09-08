-- Starting a recall, and telling the people who have the coffee.
--
-- Owner, 2026-09-07: "the other flow that we could add is a recall notice from
-- within strata that allows the user to initiate a recall. would be a flow that
-- populates all affected customers, forces/allows you to fill in missing emails,
-- and then sends a recall notice from within strata, obviously with the from
-- roaster template design on the email template."
--
-- Two records, and the distinction between them is the whole design:
--
--   recall         WHAT WAS DECIDED. Carries a FROZEN copy of the report as it
--                  read at the moment somebody pressed start. Never recomputed,
--                  because the scope of a recall is a decision taken at a point
--                  in time, and an auditor a year later is checking that
--                  decision — not what the same query would say today after the
--                  ledger was replayed and two orders were edited.
--
--   recall_notice  WHO WAS TOLD, and whether it arrived. One row per customer,
--                  with their name and address copied in, so the record still
--                  reads correctly after somebody merges a customer or fixes a
--                  typo. This is the evidence half: 3.5.1 wants contact lists
--                  and how affected customers are reached, 3.5.2 wants
--                  documented evidence of the communication.
--
-- A notice row with no email is created anyway, sitting at 'pending'. That is
-- deliberate and it is the point of the flow the owner described: the gap has to
-- be VISIBLE and countable, because "we emailed everyone we had an address for"
-- is not an answer to "did you reach all of them". The UI makes you deal with
-- each one — fill it in, or mark it reached another way with a note.

begin;

create table public.recall (
  recall_id     text primary key default (gen_random_uuid())::text,
  company_id    text not null references public.companies(company_id) on delete cascade,
  trigger_kind  text not null check (trigger_kind in ('packed_lot','green_lot')),
  trigger_ref   text not null,          -- the lot code, or the green purchase id
  reason        text not null,
  status        text not null default 'draft' check (status in ('draft','notified','closed')),
  -- The scope as it read when this started. See the header: frozen on purpose.
  report        jsonb not null,
  initiated_by_team_member text references public.team(team_member_id) on delete restrict,
  initiated_by_name text,
  initiated_at  timestamptz not null default now(),
  notified_at   timestamptz,
  closed_at     timestamptz,
  closed_by     text,
  closing_note  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_recall_company on public.recall (company_id, initiated_at desc);

comment on table public.recall is
  'A recall that was started, with the scope frozen as it read at the time. Never recomputed — an auditor is checking the decision that was taken, not what the same query would say today.';

alter table public.recall enable row level security;
create policy recall_read on public.recall
  for select using (company_id in (select auth_company_ids()));
create policy recall_write on public.recall
  for all using (company_id in (select auth_company_ids()) and public.auth_has_permission('recall.manage', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('recall.manage', company_id));

create table public.recall_notice (
  recall_notice_id text primary key default (gen_random_uuid())::text,
  recall_id     text not null references public.recall(recall_id) on delete cascade,
  customer_id   text,
  customer_name text,                    -- snapshot: survives a merge or a rename
  email         text,                    -- null until somebody fills it in
  phone         text,
  bags          numeric,
  lot_codes     text[],
  status        text not null default 'pending'
                check (status in ('pending','sent','failed','reached_another_way','not_required')),
  sent_at       timestamptz,
  message_id    text,
  error         text,
  note          text,                    -- how they were reached, when not by email
  updated_at    timestamptz not null default now()
);

create index idx_recall_notice_recall on public.recall_notice (recall_id);
create index idx_recall_notice_pending on public.recall_notice (recall_id) where status = 'pending';

comment on table public.recall_notice is
  'One row per affected customer: who was told, how, and whether it arrived. A row with no email still exists and stays pending — "we emailed everyone we had an address for" is not an answer to "did you reach all of them".';

alter table public.recall_notice enable row level security;
create policy recall_notice_read on public.recall_notice
  for select using (recall_id in (select recall_id from public.recall));
create policy recall_notice_write on public.recall_notice
  for all using (recall_id in (select recall_id from public.recall where public.auth_has_permission('recall.manage', company_id)))
  with check (recall_id in (select recall_id from public.recall where public.auth_has_permission('recall.manage', company_id)));

-- ── Start one ───────────────────────────────────────────────────────────────
-- Runs the report, freezes it, and lays out a row per affected customer. The
-- customer list comes from the frozen report rather than a second query, so the
-- notices can never cover a different set of people than the report says.
create or replace function public.start_recall(
  p_reason             text,
  p_lot_code           text default null,
  p_origin_purchase_id text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_report  jsonb;
  v_company text;
  v_recall  text;
  v_actor   record;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why you are recalling this. It goes on the record and in the notice.'
      using errcode = 'invalid_parameter_value';
  end if;

  v_report := public.recall_report(p_lot_code, p_origin_purchase_id);
  if not coalesce((v_report->>'found')::boolean, false) then
    raise exception 'Nothing found to recall.' using errcode = 'no_data_found';
  end if;

  select company_id into v_company
    from public.pack_run where lot_code = p_lot_code and company_id in (select auth_company_ids())
   union all
  select company_id from public.coffee_inventory_purchased
   where origin_purchase_id = p_origin_purchase_id and company_id in (select auth_company_ids())
   limit 1;

  if not public.auth_has_permission('recall.manage', v_company) then
    raise exception 'You do not have permission to start a recall.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_actor from public.actor_at();

  insert into public.recall (company_id, trigger_kind, trigger_ref, reason, report,
                             initiated_by_team_member, initiated_by_name)
  values (v_company,
          case when p_lot_code is not null then 'packed_lot' else 'green_lot' end,
          coalesce(p_lot_code, p_origin_purchase_id),
          trim(p_reason), v_report,
          v_actor.team_member_id, v_actor.actor_name)
  returning recall_id into v_recall;

  -- One row per affected customer, straight out of the frozen report.
  insert into public.recall_notice (recall_id, customer_id, customer_name, email, phone, lot_codes)
  select v_recall,
         cu.customer_id,
         c->>'customer',
         nullif(c->>'email', ''),
         nullif(c->>'phone', ''),
         (select array_agg(distinct l->>'lot_code')
            from jsonb_array_elements(v_report->'packed_lots') l)
    from jsonb_array_elements(v_report->'customers') c
    left join public.customers cu
           on cu.company_id = v_company and cu.name_company = c->>'customer';

  return v_recall;
end;
$$;

comment on function public.start_recall(text, text, text) is
  'Freeze the scope, then lay out one notice per affected customer — including the ones with no email address, which is the point.';

-- ── Permission ──────────────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values (
  'recall.manage', 'Roasting', 'Run a recall',
  'Trace a lot, start a recall, and send the notice to every affected customer. A serious act: it emails your customers in your name.',
  'You don''t have permission to do that. Contact your administrator if you need access.',
  true, 71, 'haccp')
on conflict (permission_id) do update set feature_key = excluded.feature_key;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
values
  ('starter','recall.manage',false,'Recalls — part of the enterprise_plus food-safety module'),
  ('pro','recall.manage',false,'Recalls — part of the enterprise_plus food-safety module'),
  ('enterprise','recall.manage',false,'Recalls — part of the enterprise_plus food-safety module'),
  ('enterprise_plus','recall.manage',true,'Recalls — enterprise_plus')
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Narrower than packing on purpose: this one mails your customers in your name.
insert into public.role_permissions (role_id, permission_id, granted)
values ('company_admin','recall.manage',true),
       ('facility_admin','recall.manage',true),
       ('manager','recall.manage',true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

revoke all on function public.start_recall(text, text, text) from public;
grant execute on function public.start_recall(text, text, text) to authenticated;

commit;
