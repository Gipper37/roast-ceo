-- A deleted roast leaves a tombstone.
--
-- Today a completed production record can be removed with no trace. The row
-- delete button in S/app/app/(app)/roast/RoastLogTable.tsx calls deleteRoast →
-- the delete_roasts RPC, and the delete takes the whole record with it:
-- roast_log_recipes and roast_log_lot_consumption cascade, and
-- trg_cascade_delete_session removes the roast_sessions curve. It IS
-- permission-gated (roast.delete_completed, manager+, when the roast has real
-- content) — the defect is not an open door, it is that nothing survives.
--
-- Why this matters beyond tidiness: Costco Food Safety GMP V3.0 question
-- 5.1.11 ("THERE IS NO EVIDENCE OF FALSIFICATION OR FABRICATION OF DOCUMENTS
-- OR RECORDS") is one of eighteen automatic-failure criticals, and 21 CFR
-- 117.315 requires records to be kept for two years. A retention claim is not
-- true while a finished record can be erased inside the retention window. Note
-- this is NOT a HACCP feature and is not plan-gated: every tenant's records
-- deserve the same floor.
--
-- Shape. A BEFORE DELETE row trigger rather than an edit to delete_roasts, so
-- it catches EVERY path — the RPC, a direct PostgREST delete, a future bulk
-- action, a hand-run psql statement. It fires after trg_guard_closed_period_roast_del
-- (Postgres runs same-timing triggers in name order, and 'trg_t…' sorts after
-- 'trg_g…'), so a delete the closed-period guard rejects never writes a
-- tombstone for a delete that did not happen.
--
-- The trigger is SECURITY DEFINER so it can write a table the caller has no
-- INSERT on. The table is append-only by construction: RLS on, a SELECT policy
-- scoped to the caller's companies so a tenant and their auditor can read their
-- own history, and NO insert/update/delete policies at all — the definer
-- trigger is the only writer. Actor resolution follows the house pattern from
-- 20260906000003 (JWT email → sub → service_role → db:<session_user>).
--
-- Deliberately NOT captured: the curve readings. The session header carries the
-- weights, times and roaster unit that identify the batch; the sample series is
-- large and adds nothing an auditor asks for. If that changes, add a column.

begin;

create table public.roast_log_deleted (
  tombstone_id    text primary key default (gen_random_uuid())::text,
  roast_log_id    text not null,
  company_id      text not null,
  facility_id     text,
  roast_date      date,
  was_completed   boolean not null,   -- had a roast_date AND real content
  deleted_at      timestamptz not null default now(),
  deleted_by      text not null,      -- email | auth sub | 'service_role' | 'db:<session_user>'
  roast_log       jsonb not null,     -- the row as it stood
  recipes         jsonb,              -- roast_log_recipes rows (cascade-deleted)
  lot_consumption jsonb,              -- roast_log_lot_consumption rows (cascade-deleted)
  roast_session   jsonb               -- the session header (trg_cascade_delete_session removes it)
);

create index idx_roast_log_deleted_company_when
  on public.roast_log_deleted (company_id, deleted_at desc);
create index idx_roast_log_deleted_roast
  on public.roast_log_deleted (roast_log_id);

comment on table public.roast_log_deleted is
  'Append-only tombstone for every deleted roast_log row: the record, its recipes, its lot-consumption ledger and its session header, plus who deleted it and when. Written by trg_tombstone_roast_delete (security definer); readable by the owning company. No writer policies by design.';

create or replace function public.trg_roast_log_tombstone()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_claims jsonb;
  v_actor  text;
begin
  v_claims := auth.jwt();
  v_actor := coalesce(
    nullif(v_claims ->> 'email', ''),
    nullif(v_claims ->> 'sub', ''),
    case when v_claims ->> 'role' = 'service_role' then 'service_role' end,
    'db:' || session_user
  );

  insert into public.roast_log_deleted
    (roast_log_id, company_id, facility_id, roast_date, was_completed,
     deleted_by, roast_log, recipes, lot_consumption, roast_session)
  values (
    old.roast_log_id,
    old.company_id,
    old.facility_id,
    old.roast_date,
    -- the same test deleteRoast uses to decide which permission to demand
    old.roast_date is not null
      and (old.session_id is not null or old.recipe_id is not null
           or old.charge_weight is not null or old.roasted_weight is not null),
    v_actor,
    to_jsonb(old),
    (select jsonb_agg(to_jsonb(r)) from public.roast_log_recipes r
      where r.roast_log_id = old.roast_log_id),
    (select jsonb_agg(to_jsonb(c)) from public.roast_log_lot_consumption c
      where c.roast_log_id = old.roast_log_id),
    (select to_jsonb(s) from public.roast_sessions s
      where s.session_id = old.session_id)
  );

  return old;
end;
$$;

-- Named to sort AFTER trg_guard_closed_period_roast_del so the guard runs first.
create trigger trg_tombstone_roast_delete
  before delete on public.roast_log
  for each row execute function public.trg_roast_log_tombstone();

alter table public.roast_log_deleted enable row level security;

-- Read your own company's history. No INSERT/UPDATE/DELETE policies: the
-- security-definer trigger is the only writer, which is what makes it append-only.
create policy roast_log_deleted_select on public.roast_log_deleted
  for select using (company_id in (select auth_company_ids()));

revoke insert, update, delete, truncate on public.roast_log_deleted from anon, authenticated;
grant select on public.roast_log_deleted to authenticated;

commit;
