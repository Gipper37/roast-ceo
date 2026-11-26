-- ============================================================
-- An order keeps a log of who did what, from creation to payment.
-- ============================================================
--
-- Owner, 2026-11-25: "add to the order detail page a log of who did what. who
-- marked packed, who marked it delivered, who created it etc." Then, on the
-- shape: "for the log maybe we should just add a log section that can be
-- expanded. it would have all log data. times and by who. from creation to
-- payment etc."
--
-- 🔴 THE DATA DID NOT EXIST. Measured on prod before writing a line, across
-- 16,485 orders:
--   * `orders` has exactly TWO columns that name a person -- `created_by`
--     (4,874 set, 30%; MCR 3,799 of 4,770) and `updated_by` (71 set, 0.4%;
--     MCR 8). There is no `packed_by` and no `delivered_by` ANYWHERE.
--   * No order-history table exists. Every table carrying an `order_id` was
--     checked: chargebacks, invoice_payment_allocations, payment_transactions,
--     order_details, order_profitability, terminal_charge_holds,
--     equipment_visit, invoice_ar_balances. None of them is a log.
--   * `status_changed_at` is set on 70% but is a bare timestamp holding only
--     the LATEST change, with no person attached.
-- So "who marked it packed" was not a read that had been missed. It was never
-- recorded. This migration starts recording it.
--
-- 🔴 WHY `updated_by` IS AT 0.4%, SINCE THAT LOOKS LIKE A BUG TO FIX INSTEAD.
-- `orders` already carries `trg_audit_insert -> handle_new_record` and
-- `trg_audit_update -> handle_updated_record`. Both bodies were read off prod:
-- they set `created_at`/`updated_at` and defend `company_id`, and NEITHER
-- writes `created_by` or `updated_by`. The column is not neglected by its
-- writers; nothing stamps it. Widening that one slot would also give only the
-- LAST person, which is not a log.
--
-- WHY A TRIGGER AND NOT WRITES IN THE SERVER ACTIONS.
-- An order's state is moved from more places than the order screen: bulk
-- tools, the QuickBooks import (`created_by` literally holds 'mcr-qb-import'),
-- the shop checkout, SQL run by hand, and other triggers on this same table.
-- A log assembled by asking each writer to remember to log is a log with holes
-- in exactly the places nobody thought about, and the holes are invisible --
-- an empty section reads as "nothing happened". A trigger cannot be forgotten.
--
-- 🔴 AND WHY NOT `config_audit_log`, WHICH IS ALREADY THE RIGHT SHAPE.
-- It exists (520 rows), its columns are right, and a reusable trigger
-- `config_audit_row()` already drives it on nine CONFIG tables. Its actor is
--     coalesce(auth.jwt()->>'email', auth.jwt()->>'sub', new.updated_by, ...)
-- and at a shared terminal that is the MACHINE'S login -- "Wholesale Orders"
-- -- not the person who pressed the button. MCR runs one terminal login across
-- six devices with five clock-enabled staff who have no accounts at all, so
-- that resolution would name the terminal on every single row and the log
-- would answer "who" with the wrong answer, confidently. The shape is
-- borrowed; the actor resolution is not.
--
-- WHAT IT COSTS. One INSERT per tracked column movement, on a table with two
-- indexes, plus one `actor_at()` call -- which is one `current_terminal()`
-- lookup and at most one `terminal_actor_session` read. An UPDATE that moves
-- nothing tracked writes nothing and returns early. A bulk run over 201
-- invoices pays it 201 times, which is the point of having a log.
--
-- WHAT IT DOES NOT DO. It does not backfill. The 16,485 existing orders have
-- no history to recover -- it was never written down, and inventing it would
-- be worse than an honest gap. The page derives the two things that ARE
-- provable from columns that exist (created, from `created_by`/`created_at`;
-- the current status, from `status_changed_at`) and says plainly that the log
-- begins here.

begin;

-- ── 1. the table ─────────────────────────────────────────────────────────────

create table if not exists public.order_activity (
  order_activity_id  uuid primary key default gen_random_uuid(),
  company_id         text not null,
  order_id           text not null references public.orders(order_id) on delete cascade,
  -- 🔴 clock_timestamp(), NOT now(). `now()` is the TRANSACTION's start time,
  -- so every event written by one transaction gets the SAME instant and the
  -- page cannot order them: an order created and immediately packed would show
  -- "Marked Packed" above or below "Order created" at random, and one UPDATE
  -- moving two tracked columns writes two rows that tie outright. The log's
  -- whole claim is the sequence, so it records when each event actually
  -- happened. (`config_audit_log` uses now(), and can: it writes one row per
  -- statement and is read per table, not as a timeline.)
  happened_at        timestamptz not null default clock_timestamp(),
  event              text not null,
  -- 🔴 THE ID *AND* THE NAME, DELIBERATELY DENORMALISED. A log records what
  -- was true at the time. Resolving the name at READ time by joining `team`
  -- loses it the moment somebody leaves, is deactivated or is merged away --
  -- and in this app a name map built from an `is_active` read is precisely how
  -- a raw uuid reaches the screen. The id is kept for linking; the label is
  -- what renders, and it is captured here, once, and never recomputed.
  actor_team_member_id text,
  actor_label        text,
  -- 'terminal' (a PIN'd-in person), 'login' (an ordinary signed-in user),
  -- or 'system' (no JWT at all: a migration, psql, a CI job, an import).
  actor_via          text not null default 'system',
  detail             jsonb not null default '{}'::jsonb
);

comment on table public.order_activity is
  'Who did what to an order, and when. Written only by trg_order_activity; never by the app.';
comment on column public.order_activity.actor_label is
  'The actor''s name as it was AT THE TIME. Never recomputed -- see the table''s migration.';
comment on column public.order_activity.actor_via is
  'terminal = the PIN''d-in person, login = a signed-in user, customer = an online payment through the pay link, system = no JWT (import, psql, CI), unknown = the actor lookup itself failed and the event was logged anyway.';

-- The only read this table has: one order's log, newest first.
create index if not exists order_activity_order_idx
  on public.order_activity (order_id, happened_at desc);
-- RLS narrows by company on every read, so it earns its own index.
create index if not exists order_activity_company_idx
  on public.order_activity (company_id, happened_at desc);

-- ── 2. who is acting, and what to call them ──────────────────────────────────

create or replace function public.order_activity_actor()
returns table (team_member_id text, label text, via text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_actor record;
  v_claims jsonb;
begin
  -- 🔴 THE PIN'D-IN PERSON FIRST. At a terminal the JWT is the machine's, and
  -- a log that names the machine answers the owner's question wrongly. This is
  -- the one way this function differs from config_audit_row(), and it is the
  -- whole reason it exists.
  --
  -- 🔴 AND IT IS WRAPPED, FOR A REASON THE REHEARSAL FOUND. `actor_at()` CAN
  -- raise: it reaches `auth.uid()`, which casts the JWT's `sub` to uuid, and a
  -- malformed claim makes that throw. Unwrapped, the throw propagates out of
  -- the trigger and THE ORDER WRITE FAILS -- a shift in the warehouse lost
  -- because a log line could not name somebody. The WHAT is the log's job and
  -- stays unguarded below, so a structural failure is still loud; the WHO is
  -- enrichment, so it degrades to a name that admits it. "Production always
  -- sends a valid sub" is true today and is not a reason to let the business
  -- write depend on it.
  begin
    select a.team_member_id, a.actor_name, a.via
      into v_actor
      from public.actor_at(now()) a
     limit 1;
  exception when others then
    return query select null::text, 'Unknown'::text, 'unknown'::text;
    return;
  end;

  if v_actor.team_member_id is not null then
    return query select
      v_actor.team_member_id,
      -- A terminal account standing in for nobody is not a person. actor_at
      -- returns the terminal's own row with via='login' when no PIN is held,
      -- and naming it would read as "Wholesale Orders marked it packed".
      coalesce(nullif(v_actor.actor_name, ''), 'Someone at a terminal'),
      coalesce(nullif(v_actor.via, ''), 'login');
    return;
  end if;

  -- No team row resolved: an ordinary JWT we can still name, or nothing.
  v_claims := auth.jwt();
  if v_claims is not null then
    return query select
      null::text,
      coalesce(nullif(v_claims ->> 'email', ''), nullif(v_claims ->> 'sub', ''), 'Signed-in user'),
      'login'::text;
    return;
  end if;

  -- No JWT at all: a migration, psql, CI, or an import running as a service.
  return query select null::text, 'System'::text, 'system'::text;
end;
$$;

comment on function public.order_activity_actor() is
  'Who is acting on an order, preferring the PIN''d-in person over the JWT. See 20261125000002.';

-- ── 3. the trigger that cannot be forgotten ──────────────────────────────────

create or replace function public.order_activity_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  a record;
  -- Collected first, written once, so one UPDATE that moves three tracked
  -- columns costs one actor lookup rather than three.
  v_events jsonb[] := '{}';
  e jsonb;
begin
  if tg_op = 'INSERT' then
    v_events := array[jsonb_build_object(
      'event', 'created',
      'detail', jsonb_build_object('status', new.order_status))];

  else
    -- 🔴 NEWLY SET, not merely non-null. `x is distinct from y` on a
    -- timestamp that was already set and did not move writes nothing, which
    -- is what keeps an ordinary edit from filling the log with noise.
    if new.order_status is distinct from old.order_status then
      v_events := v_events || jsonb_build_object(
        'event', 'status_changed',
        'detail', jsonb_build_object('from', old.order_status, 'to', new.order_status));
    end if;

    if new.delivered_on is distinct from old.delivered_on then
      v_events := v_events || jsonb_build_object(
        'event', 'delivery_date_set',
        'detail', jsonb_build_object('from', old.delivered_on, 'to', new.delivered_on));
    end if;

    if new.shipped_at is distinct from old.shipped_at then
      v_events := v_events || jsonb_build_object('event', 'shipped', 'detail', '{}'::jsonb);
    end if;

    if new.invoice_state is distinct from old.invoice_state then
      v_events := v_events || jsonb_build_object(
        'event', 'invoice_state_changed',
        'detail', jsonb_build_object('from', old.invoice_state, 'to', new.invoice_state));
    end if;

    if new.invoice_sent_at is distinct from old.invoice_sent_at
       and new.invoice_sent_at is not null then
      v_events := v_events || jsonb_build_object('event', 'invoice_sent', 'detail', '{}'::jsonb);
    end if;

    if new.payment_status is distinct from old.payment_status then
      v_events := v_events || jsonb_build_object(
        'event', 'payment_status_changed',
        'detail', jsonb_build_object('from', old.payment_status, 'to', new.payment_status));
    end if;

    if new.paid_at is distinct from old.paid_at and new.paid_at is not null then
      v_events := v_events || jsonb_build_object('event', 'paid', 'detail', '{}'::jsonb);
    end if;

    if new.voided_at is distinct from old.voided_at and new.voided_at is not null then
      v_events := v_events || jsonb_build_object('event', 'voided', 'detail', '{}'::jsonb);
    end if;

    if new.written_off_at is distinct from old.written_off_at
       and new.written_off_at is not null then
      v_events := v_events || jsonb_build_object('event', 'written_off', 'detail', '{}'::jsonb);
    end if;

    if cardinality(v_events) = 0 then
      return null;                       -- nothing tracked moved: no row, no actor lookup
    end if;
  end if;

  select * into a from public.order_activity_actor() limit 1;

  foreach e in array v_events loop
    insert into public.order_activity
      (company_id, order_id, event, actor_team_member_id, actor_label, actor_via, detail)
    values
      (new.company_id, new.order_id, e ->> 'event',
       a.team_member_id, a.label, a.via, coalesce(e -> 'detail', '{}'::jsonb));
  end loop;

  return null;                           -- AFTER trigger: the return is ignored
end;
$$;

comment on function public.order_activity_row() is
  'Writes order_activity from whichever tracked columns moved. See 20261125000002.';

drop trigger if exists trg_order_activity on public.orders;
drop trigger if exists zzzz_order_activity on public.orders;
-- 🔴 AFTER, and named to sort last among this table's eighteen triggers. The
-- log must record what actually landed, so it runs after every BEFORE trigger
-- has had its say -- `set_order_status_changed_at` and
-- `sync_item_status_on_order_status_change` among them.
create trigger zzzz_order_activity
after insert or update on public.orders
for each row execute function public.order_activity_row();

-- ── 4. who may read it ───────────────────────────────────────────────────────

alter table public.order_activity enable row level security;

-- 🔴 EVERY PRIVILEGE OFF FIRST, AND EVERY ROLE NAMED. Naming the three writes
-- to revoke is not enough, and staging proved it: on a real Supabase project a
-- new table in `public` arrives with the default ACL already applied --
-- `authenticated` holds SELECT, INSERT, UPDATE, DELETE and REFERENCES, and
-- `anon` holds those plus TRUNCATE and TRIGGER. Revoking insert/update/delete
-- by name left REFERENCES on `authenticated` and left `anon` holding all seven,
-- and only RLS stood between a signed-out caller and this table. The verify
-- block below caught it on the staging push, which is what staging is for.
--
-- 🔴 `revoke ... from public, anon` does NOT revoke from `authenticated`
-- ([[gotcha_revoke_from_public_does_not_revoke_from_authenticated]]), so all
-- three are named -- the same line `config_audit_log` uses (20260906000003:178).
-- `service_role` keeps its default, as it does there: the dev portal reads
-- these tables and nothing in the app runs as that role by accident.
--
-- Then exactly one privilege back. Nothing may WRITE this table but the two
-- trigger functions, which are SECURITY DEFINER and need no grant of their
-- own. An app that cannot forge a log entry is the point.
revoke all on public.order_activity from public, anon, authenticated;
grant select on public.order_activity to authenticated;

drop policy if exists order_activity_read on public.order_activity;
create policy order_activity_read
on public.order_activity
for select
using (
  company_id in (select public.auth_company_ids())
  and public.auth_has_permission('order.activity_view', company_id)
);

-- ── 5. the key, its roles and its plans ──────────────────────────────────────
-- 🔴 AN UNKNOWN KEY IS DENIED SILENTLY HERE, so the key ships WITH the feature
-- or the section is invisible with nothing on screen to say why. Mirrors
-- `order.view` exactly -- same category, same ten roles, same four plans, not
-- plan-gated -- because anyone who may open the order may see who touched it.

insert into public.permissions
  (permission_id, category, label, description, is_plan_gated, sort_order, feature_key)
values
  ('order.activity_view', 'Orders', 'View an order''s activity log',
   'See who created, packed, delivered, invoiced and was paid for an order, and when.',
   false, 11, null)
on conflict (permission_id) do update
  set label = excluded.label,
      description = excluded.description,
      category = excluded.category,
      is_plan_gated = excluded.is_plan_gated;

-- sales_person is false and equipment_tech is false, matching order.view --
-- which omits equipment_tech entirely. Stated explicitly rather than left
-- absent: an absent row and a false row deny alike, but only one of them says
-- a person decided.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',      'order.activity_view', true),
  ('facility_admin',     'order.activity_view', true),
  ('manager',            'order.activity_view', true),
  ('roastery_manager',   'order.activity_view', true),
  ('roastmaster',        'order.activity_view', true),
  ('assistant_roaster',  'order.activity_view', true),
  ('staff',              'order.activity_view', true),
  ('accounting_admin',   'order.activity_view', true),
  ('accounting_view',    'order.activity_view', true),
  ('sales_person',       'order.activity_view', false),
  ('equipment_tech',     'order.activity_view', false)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

insert into public.plan_permissions (plan_id, permission_id, granted)
values
  ('starter',         'order.activity_view', true),
  ('pro',             'order.activity_view', true),
  ('enterprise',      'order.activity_view', true),
  ('enterprise_plus', 'order.activity_view', true)
on conflict (plan_id, permission_id) do update set granted = excluded.granted;

-- ── 5b. the money leg, because "to payment" does not touch `orders` ─────────
--
-- 🔴 MEASURED, and it changed this design. Watching `orders` alone gives a log
-- that stops before the money: `invoice_state` is NULL on 15,985 of 16,485
-- prod orders and `payment_status` has THREE rows in the whole table -- while
-- there are 79 `payment_transactions` and 130 `invoice_payment_allocations`.
-- A payment is recorded against the invoice ledger, and it moves an `orders`
-- column only when it happens to clear or reopen a balance. "Paid" here is two
-- columns and neither of them is where a payment lands.
--
-- `payment_transactions` already carries `created_by`. `invoice_payment_
-- allocations` carries `created_at` and an amount and NO actor at all, which
-- is the hole these triggers close going forward. The page reads the existing
-- rows for history, so an order paid last March still shows its payments; only
-- the WHO starts today, and the section says so rather than implying a name
-- was lost.

create or replace function public.order_activity_money_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_event  text;
  v_detail jsonb;
  v_source text;
  v_member text;
  v_label  text;
  v_via    text;
begin
  -- An allocation or a transaction with no order is not an order's business.
  if new.order_id is null then
    return null;
  end if;

  if tg_table_name = 'invoice_payment_allocations' then
    v_event  := 'payment_allocated';
    -- 🔴 WHERE THE MONEY CAME FROM, BECAUSE THE ACTOR CANNOT SAY IT. The pay
    -- link inserts allocations with an ADMIN client (app/(shop)/[slug]/pay/
    -- actions-pay.ts), so there is no JWT and the actor below resolves to
    -- 'System' for a payment the CUSTOMER made. Measured on prod: 13 of the
    -- 112 payments have source 'online', and every one of them has
    -- `created_by` null -- there is no second signal. The payment's own
    -- `source` is the fact that tells them apart, so read it here and let the
    -- customer be named for their own payment.
    select p.source into v_source
      from public.invoice_payments p
     where p.payment_id = new.payment_id
       and p.company_id = new.company_id;
    v_detail := jsonb_build_object('amount_cents', new.amount_cents,
                                   'source', v_source);
  else
    -- payment_transactions. A decline belongs in the log as much as a capture:
    -- "why does this order still owe" is the question the log is read for.
    v_event  := 'payment_attempted';
    v_detail := jsonb_build_object(
      'type', new.type, 'status', new.status,
      'amount_cents', new.gross_amount_cents,
      'response_text', nullif(new.response_text, ''));
  end if;

  select a.team_member_id, a.label, a.via into v_member, v_label, v_via
    from public.order_activity_actor() a limit 1;

  -- An online payment is the customer's doing whatever the connection looks
  -- like. Only when the actor came back anonymous: a staff member taking a
  -- card over the counter through the same screen is still that staff member.
  if v_source = 'online' and v_member is null then
    v_label := 'Customer, online';
    v_via   := 'customer';
  end if;

  insert into public.order_activity
    (company_id, order_id, event, actor_team_member_id, actor_label, actor_via, detail)
  values
    (new.company_id, new.order_id, v_event, v_member, v_label, v_via, v_detail);

  return null;
end;
$$;

comment on function public.order_activity_money_row() is
  'Logs a payment against an order. Separate from order_activity_row because payments do not move an orders column -- see 20261125000002.';

drop trigger if exists zzzz_order_activity_payment on public.invoice_payment_allocations;
create trigger zzzz_order_activity_payment
after insert on public.invoice_payment_allocations
for each row execute function public.order_activity_money_row();

drop trigger if exists zzzz_order_activity_charge on public.payment_transactions;
create trigger zzzz_order_activity_charge
after insert on public.payment_transactions
for each row execute function public.order_activity_money_row();

-- ── 6. prove the parts that could be silently wrong ──────────────────────────
-- 🔴 Each of these can FAIL on a broken apply and PASS on a good one. None of
-- them asserts something the design forbids, because a verify block that can
-- only raise rolls the whole release back.

do $$
declare n int;
begin
  -- The trigger is attached, and attached AFTER.
  select count(*) into n
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname = 'orders' and t.tgname = 'zzzz_order_activity' and not t.tgisinternal;
  if n <> 1 then
    raise exception 'order_activity: expected 1 trigger on orders, found %', n;
  end if;

  -- The key admits exactly the nine roles order.view admits (ten rows, one of
  -- them sales_person=false). A key and its policy must agree, and both
  -- directions fail silently.
  select count(*) into n
    from public.role_permissions rp
   where rp.permission_id = 'order.activity_view' and rp.granted;
  if n <> 9 then
    raise exception 'order_activity: expected 9 granted roles, found %', n;
  end if;

  -- All three triggers are attached, on their three different tables.
  select count(*) into n
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and t.tgname in ('zzzz_order_activity', 'zzzz_order_activity_payment',
                      'zzzz_order_activity_charge')
     and c.relname in ('orders', 'invoice_payment_allocations', 'payment_transactions');
  if n <> 3 then
    raise exception 'order_activity: expected 3 triggers, found %', n;
  end if;

  -- SELECT is granted and nothing else is.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'order_activity'
     and grantee = 'authenticated' and privilege_type <> 'SELECT';
  if n <> 0 then
    raise exception 'order_activity: authenticated holds % privileges beyond SELECT', n;
  end if;

  -- And `anon` holds nothing at all. It is a different role with its own
  -- default grant, and a revoke aimed at `authenticated` never touches it.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'order_activity'
     and grantee IN ('anon', 'PUBLIC');
  if n <> 0 then
    raise exception 'order_activity: anon still holds % privileges', n;
  end if;

  -- The one row that proves SELECT survived the revoke-all above: an empty
  -- ACL would pass both checks and leave the page unable to read its own log.
  select count(*) into n
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'order_activity'
     and grantee = 'authenticated' and privilege_type = 'SELECT';
  if n <> 1 then
    raise exception 'order_activity: authenticated cannot SELECT it (% rows)', n;
  end if;
end $$;

commit;
