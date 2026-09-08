-- The packed bag, and the code that leads back to the green.
--
-- The owner's original ask, in his words: "right now we can track lot from
-- shipment to roast but we can't track to packed bag per customer. so we need to
-- make a flow for the packers to choose roasted batches to pack."
--
-- This is that missing link, and it is where three of the eighteen
-- automatic-failure questions live:
--   3.5.4  a traceability system covering inputs AND outputs — ingredients,
--          primary packaging, work-in-progress, rework, finished goods — with
--          100% of a lot accounted for within two hours;
--   3.5.5  the auditor picks an item on the day and watches you do it;
--   5.2.8  finished product traceable to the lot numbers of every input.
-- None of them can be answered today, because nothing records that packing
-- happened at all. The app plans packing (the Pack tab, pack_totals_by_prep) and
-- then forgets.
--
-- ── Shape ───────────────────────────────────────────────────────────────────
--   pack_run             one packing session: this product, this many bags,
--                        this lot code, this day, this person.
--   pack_run_source      which roast batches went in, and how much of each.
--                        This is the "one step back".
--   pack_run_allocation  which order lines the bags went out on.
--                        This is the "one step forward", and the bag-per-customer
--                        the owner asked for.
--
-- ── Three things that are here on purpose, not later ────────────────────────
--  1. PACKAGING LOT. 5.2.8 and 3.5.4 both name primary packaging explicitly, so
--     a trace that covers coffee and not the bag it is in does not answer them.
--     consumable_inventory_purchased gains a lot_code and pack_run points at the
--     bag and label purchases it drew from.
--  2. A FROZEN CONSUMPTION SNAPSHOT. roast_log_lot_consumption is a FIFO
--     projection that replay_lot_consumption deletes and rebuilds. An auditor who
--     samples the same lot code twice must get the same answer both times, so the
--     green attribution as it read at pack time is copied onto the run and never
--     recomputed. (It is also, per the owner, incomplete on purpose while a
--     tenant catches up on data entry — so the snapshot records what was known,
--     including how much was NOT attributed, rather than pretending.)
--  3. LOCATION. 3.5.5 says track AND LOCATE within two hours. A lot code that
--     cannot tell you which cooler the pallet is in fails the second half.
--
-- ── The lot code ────────────────────────────────────────────────────────────
-- Per tenant, because this app is agnostic: prefix, date style, sequence width
-- (owner: "may need to have more the 2 digits possible especially for bagging"),
-- separator. Default 260907-001 — readable, and deliberately not Julian, which
-- auditors read as obfuscation. Minted server-side by a single atomic upsert so
-- two packers on two terminals cannot mint the same code.

begin;

-- ── How this tenant writes a lot code ───────────────────────────────────────
create table public.fs_lot_code_format (
  company_id      text primary key references public.companies(company_id) on delete cascade,
  prefix          text not null default '',
  -- 'ymd' 260907 · 'ymd_full' 20260907 · 'ywk' 26W36 · 'none' (sequence only)
  date_style      text not null default 'ymd' check (date_style in ('ymd','ymd_full','ywk','none')),
  sequence_width  int  not null default 3 check (sequence_width between 1 and 6),
  separator       text not null default '-',
  -- Restart the count each day, or run one unbroken series for the company.
  resets_daily    boolean not null default true,
  updated_at      timestamptz not null default now(),
  updated_by      text
);

comment on table public.fs_lot_code_format is
  'Per tenant, because the app is agnostic: how this roastery writes a lot code. Default 260907-001 — readable and deliberately not Julian, which auditors read as obfuscation.';

alter table public.fs_lot_code_format enable row level security;
create policy fs_lot_code_format_read on public.fs_lot_code_format
  for select using (company_id in (select auth_company_ids()));
create policy fs_lot_code_format_write on public.fs_lot_code_format
  for all using (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.configure', company_id));

-- ── The counter ─────────────────────────────────────────────────────────────
create table public.lot_code_sequence (
  company_id text not null references public.companies(company_id) on delete cascade,
  seq_key    text not null,   -- the day, or '' when the series never resets
  last_seq   int  not null default 0,
  primary key (company_id, seq_key)
);

comment on table public.lot_code_sequence is
  'One row per company per counting period. Advanced by a single atomic upsert so two packers on two terminals cannot mint the same code.';

alter table public.lot_code_sequence enable row level security;  -- no policies: minted only by next_lot_code()
revoke all on public.lot_code_sequence from anon, authenticated;

create or replace function public.next_lot_code(p_company_id text, p_packed_on date default null)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fmt public.fs_lot_code_format;
  v_day date := coalesce(p_packed_on, current_date);
  v_key text;
  v_seq int;
  v_date_part text;
begin
  -- `null not in (…)` is NULL, not true, so a null company would slip past a
  -- bare NOT IN and fail later on a constraint. Say no explicitly.
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_fmt from public.fs_lot_code_format where company_id = p_company_id;
  if v_fmt.company_id is null then
    -- A tenant who never opened the settings still gets a working code.
    v_fmt := (p_company_id, '', 'ymd', 3, '-', true, now(), null)::public.fs_lot_code_format;
  end if;

  v_date_part := case v_fmt.date_style
    when 'ymd'      then to_char(v_day, 'YYMMDD')
    when 'ymd_full' then to_char(v_day, 'YYYYMMDD')
    when 'ywk'      then to_char(v_day, 'YY"W"IW')
    else '' end;

  v_key := case when v_fmt.resets_daily then v_date_part else '' end;

  insert into public.lot_code_sequence (company_id, seq_key, last_seq)
  values (p_company_id, v_key, 1)
  on conflict (company_id, seq_key) do update
    set last_seq = public.lot_code_sequence.last_seq + 1
  returning last_seq into v_seq;

  -- concat_ws over the parts that are actually present. Built this way because
  -- the obvious `nullif(prefix,'') || …` collapses the WHOLE code to NULL for
  -- every tenant without a prefix, which is the default — caught in testing.
  return concat_ws(
    v_fmt.separator,
    variadic array_remove(array[
      nullif(v_fmt.prefix, ''),
      nullif(v_date_part, ''),
      lpad(v_seq::text, v_fmt.sequence_width, '0')
    ], null)
  );
end;
$$;

-- ── Primary packaging carries a lot too ─────────────────────────────────────
alter table public.consumable_inventory_purchased
  add column if not exists lot_code text;

comment on column public.consumable_inventory_purchased.lot_code is
  'The supplier lot on this delivery of bags, labels or boxes. Costco 5.2.8 and 3.5.4 both name primary packaging, so a trace that covers only the coffee does not answer them.';

-- ── The pack run ────────────────────────────────────────────────────────────
create table public.pack_run (
  pack_run_id     text primary key default (gen_random_uuid())::text,
  company_id      text not null references public.companies(company_id) on delete cascade,
  facility_id     text references public.facilities(facility_id),
  lot_code        text not null,
  product_id      text references public.products(product_id),   -- the VARIANT (size x channel)
  product_name_snapshot text,                                    -- what it was called that day
  coffee_prep     text,                                          -- whole bean vs ground: decides the FM exemption
  packed_on       date not null default current_date,
  packed_at       timestamptz not null default now(),
  bags            numeric not null check (bags > 0),
  unit_weight_lbs numeric,
  total_lbs       numeric,
  best_before     date,
  -- 3.5.5 says track AND LOCATE. A code that cannot say which cooler the pallet
  -- is in only answers half the question.
  location        text,
  -- Primary packaging, by purchase, so the bag's own lot is on the record.
  bag_purchase_id   text references public.consumable_inventory_purchased(consumable_purchase_id),
  label_purchase_id text references public.consumable_inventory_purchased(consumable_purchase_id),
  -- Frozen at pack time and never recomputed. See the header.
  green_snapshot  jsonb,
  packed_by_team_member text references public.team(team_member_id) on delete restrict,
  packed_by_name  text,
  notes           text,
  voided_at       timestamptz,
  voided_by       text,
  void_reason     text,
  created_at      timestamptz not null default now(),
  created_by      text,
  updated_at      timestamptz not null default now(),
  updated_by      text
);

-- A lot code identifies one run within a company. Voided runs keep their code
-- so the number on bags already in the world still resolves to what happened.
create unique index uq_pack_run_lot on public.pack_run (company_id, lot_code);
create index idx_pack_run_company_day on public.pack_run (company_id, packed_on desc);
create index idx_pack_run_product on public.pack_run (product_id) where product_id is not null;

comment on table public.pack_run is
  'One packing session: this product, this many bags, this lot code, this day, this person. The link the owner asked for — "we can track lot from shipment to roast but we can''t track to packed bag per customer".';

alter table public.pack_run enable row level security;
create policy pack_run_read on public.pack_run
  for select using (company_id in (select auth_company_ids()));
create policy pack_run_write on public.pack_run
  for all using (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.run', company_id))
  with check (company_id in (select auth_company_ids()) and public.auth_has_permission('pack.run', company_id));

-- ── One step back: which roast batches went in ──────────────────────────────
create table public.pack_run_source (
  pack_run_source_id text primary key default (gen_random_uuid())::text,
  pack_run_id  text not null references public.pack_run(pack_run_id) on delete cascade,
  roast_log_id text not null references public.roast_log(roast_log_id) on delete restrict,
  lbs_used     numeric check (lbs_used >= 0),
  created_at   timestamptz not null default now()
);

create index idx_pack_run_source_run on public.pack_run_source (pack_run_id);
create index idx_pack_run_source_roast on public.pack_run_source (roast_log_id);

comment on table public.pack_run_source is
  'Which roast batches went into a run. ON DELETE RESTRICT on the roast: a batch that has been packed and shipped cannot be deleted out from under the bags carrying its lot code.';

alter table public.pack_run_source enable row level security;
create policy pack_run_source_read on public.pack_run_source
  for select using (pack_run_id in (select pack_run_id from public.pack_run));
create policy pack_run_source_write on public.pack_run_source
  for all using (pack_run_id in (select pack_run_id from public.pack_run where public.auth_has_permission('pack.run', company_id)))
  with check (pack_run_id in (select pack_run_id from public.pack_run where public.auth_has_permission('pack.run', company_id)));

-- ── One step forward: which customers got the bags ──────────────────────────
create table public.pack_run_allocation (
  pack_run_allocation_id text primary key default (gen_random_uuid())::text,
  pack_run_id     text not null references public.pack_run(pack_run_id) on delete cascade,
  order_detail_id text references public.order_details(order_detail_id) on delete restrict,
  customer_id     text,
  bags            numeric not null check (bags > 0),
  created_at      timestamptz not null default now()
);

create index idx_pack_run_alloc_run on public.pack_run_allocation (pack_run_id);
create index idx_pack_run_alloc_order on public.pack_run_allocation (order_detail_id) where order_detail_id is not null;
create index idx_pack_run_alloc_customer on public.pack_run_allocation (customer_id) where customer_id is not null;

comment on table public.pack_run_allocation is
  'Where the bags went. customer_id is denormalised beside the order line on purpose: a recall has to answer "who has it" in minutes, and an order line can be edited or moved after the fact.';

alter table public.pack_run_allocation enable row level security;
create policy pack_run_allocation_read on public.pack_run_allocation
  for select using (pack_run_id in (select pack_run_id from public.pack_run));
create policy pack_run_allocation_write on public.pack_run_allocation
  for all using (pack_run_id in (select pack_run_id from public.pack_run where public.auth_has_permission('pack.run', company_id)))
  with check (pack_run_id in (select pack_run_id from public.pack_run where public.auth_has_permission('pack.run', company_id)));

-- ── Permissions ─────────────────────────────────────────────────────────────
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values
  ('pack.run', 'Roasting', 'Record packing',
   'Record a packing run: which roasted batches went into which product, how many bags, and the lot code that leads back to the green.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 70, 'haccp'),
  ('pack.configure', 'Configuration', 'Set the lot code format',
   'Choose how this roastery writes a lot code — prefix, date style, and how many digits the daily count runs to.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 37, 'haccp')
on conflict (permission_id) do update set feature_key = excluded.feature_key;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, k.permission_id, p.plan_id = 'enterprise_plus', 'Packing records — part of the enterprise_plus food-safety module'
  from (values ('starter'),('pro'),('enterprise'),('enterprise_plus')) p(plan_id)
 cross join (values ('pack.run'),('pack.configure')) k(permission_id)
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

-- Packing is floor work: the roles who already log roasts can record it.
insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'pack.run', true),
  ('facility_admin',    'pack.run', true),
  ('manager',           'pack.run', true),
  ('roastmaster',       'pack.run', true),
  ('assistant_roaster', 'pack.run', true),
  ('staff',             'pack.run', true),
  ('company_admin',     'pack.configure', true),
  ('facility_admin',    'pack.configure', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

revoke all on function public.next_lot_code(text, date) from public;
grant execute on function public.next_lot_code(text, date) to authenticated;

commit;
