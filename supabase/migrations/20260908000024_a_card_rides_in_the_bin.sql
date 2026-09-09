-- A card the roaster drops in the bin, so the packer can name the exact batch.
--
-- Owner: *"the option for the roaster to print route sheets (lot cards) to drop
-- in the bin with the roasted batches"* and *"the packer doesn't necessarily know
-- the batch, it would have to be written on paper and dropped in that bin,
-- printed route sheet. that would be fine if that's how we want to build it,
-- that is the most accurate but not the simple. could maybe allow for either."*
--
-- So FIFO stays the default and the card is the accurate override. close_pack_run
-- already takes p_sources for exactly this, and as of 20260908000017 that path
-- validates ownership and arithmetic, which is what makes it safe to point real
-- paper at.
--
-- ── Printed at CHARGE ──────────────────────────────────────────────────────
-- Owner: *"the bin card print flow should be initiated on charge."* Everything
-- the card needs exists at charge — the recipe, the green the plan named, the
-- charge weight, the roaster, the person — and charge is the dead minute before
-- first crack rather than the scramble at the drop. What does NOT exist yet is
-- the yield, so the card states the CHARGE weight and says so.
--
-- ── The code is minted, not derived ────────────────────────────────────────
-- The obvious identifier is roast_log_id, and it does not work. 7,710 of 17,796
-- roast_log_id values on prod are 8 hex characters and 10,084 are 36-character
-- UUIDs, so there is no one shape to print; and a 36-char Code 128B payload is
-- 451 modules, which is 114 mm at a readable 10 mil — wider than a 4x6 card.
-- A minted 10-character code is 165 modules, about 30 mm. It also reads as part
-- of the same system as the bag's lot code (260908-001) while staying
-- distinguishable from it by the B, so one scan field can accept either.
--
-- It reuses lot_code_sequence with seq_key 'B'||YYMMDD — a separate key space,
-- so bin cards burn no lot numbers and need no new counter table.
--
-- ── A card is a SET ────────────────────────────────────────────────────────
-- One card carries one batch at charge, but the table models a set from the
-- start, because a roaster pours two batches into one bin often enough that
-- discovering it later would mean a migration. A set is also idempotent: the
-- packer scanning the same card twice adds the same batches.

begin;

-- ── 1. Who roasted it, at charge ───────────────────────────────────────────
-- roasted_by_* has lived on roast_sessions since 20260907000013, written by
-- saveRoastSession at the DROP. Two consequences: at charge, when the card
-- prints, there is nobody to name; and a batch charged without the profiler
-- gets no session and so is never attributed at all. Measured on prod: Maui
-- profiles everything (0 of 210 sessionless) but Social Hour UK is 158 of 158,
-- so that tenant currently names nobody on any roast.
alter table public.roast_log
  add column if not exists roasted_by_team_member text,
  add column if not exists roasted_by_name        text;

alter table public.roast_log drop constraint if exists roast_log_roasted_by_fkey;
alter table public.roast_log
  add constraint roast_log_roasted_by_fkey
  foreign key (roasted_by_team_member) references public.team(team_member_id) on delete restrict;

comment on column public.roast_log.roasted_by_team_member is
  'Who charged it — actor_at(charge time), the person PIN''d in at that instant on a terminal, else the signed-in member. Stamped at CHARGE so the bin card can name them and so a batch roasted without the profiler is still attributed.';
comment on column public.roast_log.roasted_by_name is
  'Their name as it read at the time. What an auditor reads years later.';

-- ── 2. The card ────────────────────────────────────────────────────────────
create table if not exists public.bin_card (
  bin_card_id  text primary key default (gen_random_uuid())::text,
  company_id   text not null references public.companies(company_id) on delete cascade,
  facility_id  text references public.facilities(facility_id),
  card_code    text not null,
  recipe_id    text,
  -- Snapshots, so a card reprinted in a year still reads the way it was printed.
  coffee_label text,
  recipe_label text,
  printed_at   timestamptz not null default now(),
  printed_by_team_member text references public.team(team_member_id) on delete restrict,
  printed_by_name text,
  voided_at    timestamptz,
  voided_by    text references public.team(team_member_id) on delete restrict,
  void_reason  text
);

create unique index if not exists uq_bin_card_code on public.bin_card (company_id, card_code);
create index if not exists idx_bin_card_company on public.bin_card (company_id, printed_at desc);

comment on table public.bin_card is
  'A printed card that rides in the bin with roasted coffee so the packer can name the exact batches instead of relying on FIFO. Minted server-side; the paper is a rendering of this row, not of a query.';

create table if not exists public.bin_card_source (
  bin_card_id  text not null references public.bin_card(bin_card_id) on delete cascade,
  roast_log_id text not null references public.roast_log(roast_log_id) on delete restrict,
  -- What the batch was carrying when the card printed. At charge that is the
  -- charge weight and the yield is not known yet, which is why it is labelled.
  lbs_at_print numeric,
  lbs_basis    text not null default 'charge' check (lbs_basis in ('charge','roasted','measured')),
  primary key (bin_card_id, roast_log_id)
);

comment on column public.bin_card_source.lbs_basis is
  'Which weight lbs_at_print is. ''charge'' means the card printed before the drop and nobody has weighed anything — the card says "est." rather than stating a yield as fact.';

alter table public.bin_card enable row level security;
alter table public.bin_card_source enable row level security;

-- Read only. Cards are minted by the security-definer function below, the same
-- posture lot_code_sequence takes — a card nobody can forge is the whole point
-- of pointing close_pack_run's override at it.
create policy bin_card_read on public.bin_card
  for select using (company_id in (select auth_company_ids()));
create policy bin_card_source_read on public.bin_card_source
  for select using (bin_card_id in (select bin_card_id from public.bin_card));

grant select on public.bin_card to authenticated;
grant select on public.bin_card_source to authenticated;

-- ── 3. The code ────────────────────────────────────────────────────────────
create or replace function public.next_bin_card_code(p_company_id text, p_day date default null)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day  date := coalesce(p_day, current_date);
  v_date text := to_char(v_day, 'YYMMDD');
  v_seq  int;
begin
  if p_company_id is null or not exists (
    select 1 from unnest(array(select auth_company_ids())) c(id) where c.id = p_company_id
  ) then
    raise exception 'Not your company.' using errcode = 'insufficient_privilege';
  end if;

  -- 'B'||YYMMDD is its own key space in the shared counter, so bin cards never
  -- consume a lot number. One atomic upsert, so two roasters charging at the
  -- same instant cannot mint the same code.
  insert into public.lot_code_sequence (company_id, seq_key, last_seq)
  values (p_company_id, 'B' || v_date, 1)
  on conflict (company_id, seq_key) do update
    set last_seq = public.lot_code_sequence.last_seq + 1
  returning last_seq into v_seq;

  -- Past 99 in a day lpad simply widens; nothing breaks.
  return v_date || '-B' || lpad(v_seq::text, 2, '0');
end;
$$;

revoke all on function public.next_bin_card_code(text, date) from public;
grant execute on function public.next_bin_card_code(text, date) to authenticated;

-- ── 4. Minting a card ──────────────────────────────────────────────────────
create or replace function public.create_bin_card(
  p_roast_log_ids text[],
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company  text;
  v_facility text;
  v_bad      int;
  v_id       text;
  v_code     text;
  v_actor    record;
  v_recipe   text;
begin
  if p_roast_log_ids is null or array_length(p_roast_log_ids, 1) is null then
    raise exception 'Nothing to print — no batch was named.' using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_bad
    from unnest(p_roast_log_ids) id
    left join public.roast_log rl
           on rl.roast_log_id = id
          and rl.company_id in (select auth_company_ids())
   where rl.roast_log_id is null;
  if v_bad > 0 then
    raise exception 'A batch named here is not one of yours.' using errcode = 'insufficient_privilege';
  end if;

  select rl.company_id, rl.facility_id into v_company, v_facility
    from public.roast_log rl where rl.roast_log_id = p_roast_log_ids[1];

  if not public.auth_has_permission('pack.bin_card', v_company) then
    raise exception 'You do not have permission to print bin cards.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_actor from public.actor_at(now());
  select mode() within group (order by rl.recipe_id)
    into v_recipe
    from public.roast_log rl where rl.roast_log_id = any(p_roast_log_ids);

  v_code := public.next_bin_card_code(v_company, current_date);

  insert into public.bin_card
    (company_id, facility_id, card_code, recipe_id, coffee_label, recipe_label,
     printed_by_team_member, printed_by_name)
  select v_company, v_facility, v_code, v_recipe,
         (select coalesce(rl.coffee_name_snapshot, ci.origin)
            from public.roast_log rl
            left join public.coffee_inventory ci
                   on ci.origin_id = rl.origin_id and ci.facility_id = rl.facility_id
           where rl.roast_log_id = p_roast_log_ids[1]),
         (select coalesce(rl.recipe_name_snapshot, rr.recipe_name)
            from public.roast_log rl
            left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
           where rl.roast_log_id = p_roast_log_ids[1]),
         v_actor.team_member_id, v_actor.actor_name
  returning bin_card_id into v_id;

  -- At charge there is no yield yet, so the honest number is the charge weight
  -- and the card labels it. A card printed after a real drop weight says so.
  insert into public.bin_card_source (bin_card_id, roast_log_id, lbs_at_print, lbs_basis)
  select v_id, rl.roast_log_id,
         coalesce(rl.measured_roasted_weight, rl.roasted_weight, rl.charge_weight_lbs),
         case when rl.measured_roasted_weight is not null then 'measured'
              when rl.roasted_weight is not null and rl."charged?" and rl.roasted_weight > 0
                   and rl.session_id is not null then 'roasted'
              else 'charge' end
    from public.roast_log rl
   where rl.roast_log_id = any(p_roast_log_ids)
  on conflict (bin_card_id, roast_log_id) do nothing;

  return jsonb_build_object('bin_card_id', v_id, 'card_code', v_code);
end;
$$;

revoke all on function public.create_bin_card(text[], text) from public;
grant execute on function public.create_bin_card(text[], text) to authenticated;

-- ── 5. Reading one, for the print page and for the scan ────────────────────
create or replace function public.bin_card_data(p_bin_card_id text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'bin_card_id', c.bin_card_id,
    'card_code',   c.card_code,
    'company_id',  c.company_id,
    'coffee',      c.coffee_label,
    'recipe',      c.recipe_label,
    'printed_at',  c.printed_at,
    'printed_by',  c.printed_by_name,
    'voided_at',   c.voided_at,
    'facility',    (select f.facility_name from public.facilities f where f.facility_id = c.facility_id),
    'batches', coalesce((
      select jsonb_agg(jsonb_build_object(
               'roast_log_id', s.roast_log_id,
               'roast_date',   rl.roast_date,
               'roast_type',   rl.roast_type,
               'coffee',       coalesce(rl.coffee_name_snapshot, ci.origin),
               'recipe',       coalesce(rl.recipe_name_snapshot, rr.recipe_name),
               'roaster',      ru.name,
               -- Who charged it. roast_log first (stamped at charge, so a batch
               -- with no profiler session still names somebody), then the
               -- session's own stamp for batches charged before this shipped.
               'roasted_by',   coalesce(rl.roasted_by_name, rs.roasted_by_name),
               'lbs',          s.lbs_at_print,
               'lbs_basis',    s.lbs_basis,
               -- The green the plan named. Not the consumption ledger: at charge
               -- the deduct may not have resolved, and the card must print.
               'lots', coalesce((
                  select jsonb_agg(distinct jsonb_build_object(
                           'lot', cip.lot_id, 'coffee', cs.coffee_name))
                    from public.roast_log_lot_consumption lc
                    join public.coffee_inventory_purchased cip
                      on cip.origin_purchase_id = lc.origin_purchase_id
                    left join public.coffee_source cs on cs.coffee_source_id = cip.coffee_source_id
                   where lc.roast_log_id = s.roast_log_id), '[]'::jsonb)
             ) order by rl.roast_date)
        from public.bin_card_source s
        join public.roast_log rl on rl.roast_log_id = s.roast_log_id
        left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
        left join public.coffee_inventory ci
               on ci.origin_id = rl.origin_id and ci.facility_id = rl.facility_id
        left join public.roaster_units ru on ru.roaster_unit_id = rl.roaster_unit_id
        left join public.roast_sessions rs on rs.session_id = rl.session_id
       where s.bin_card_id = c.bin_card_id), '[]'::jsonb))
    from public.bin_card c
   where c.bin_card_id = p_bin_card_id
     and c.company_id in (select auth_company_ids());
$$;

revoke all on function public.bin_card_data(text) from public;
grant execute on function public.bin_card_data(text) to authenticated;

-- Scanning: the packer's field takes a card code and gets back the batches,
-- plus the reasons not to trust it. A deleted or voided card must answer
-- DIFFERENTLY from an unknown one — "not found" invites scanning another card
-- and recording the wrong coffee.
create or replace function public.resolve_bin_card(p_card_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_c public.bin_card;
begin
  select * into v_c from public.bin_card
   where upper(trim(p_card_code)) = upper(card_code)
     and company_id in (select auth_company_ids())
   limit 1;

  if v_c.bin_card_id is null then
    return jsonb_build_object('found', false,
      'message', 'No card with that code. Check the number on the card.');
  end if;
  if v_c.voided_at is not null then
    return jsonb_build_object('found', false, 'voided', true,
      'message', 'That card was voided. Do not bag from it.');
  end if;

  return public.bin_card_data(v_c.bin_card_id) || jsonb_build_object('found', true);
end;
$$;

revoke all on function public.resolve_bin_card(text) from public;
grant execute on function public.resolve_bin_card(text) to authenticated;

-- ── 6. The verb ────────────────────────────────────────────────────────────
-- Printing the card is part of logging the roast, so this tracks roast.log's
-- roles rather than the packing family's. It is NOT feature_key'd to haccp:
-- a roaster on any plan should be able to put a piece of paper in a bin.
insert into public.permissions
  (permission_id, category, label, description, default_deny_message, is_plan_gated, sort_order, feature_key)
values
  ('pack.bin_card', 'Roasting', 'Print a bin card',
   'Print the card that rides in the bin with roasted coffee, so whoever bags it can record the exact batch instead of relying on first-in-first-out.',
   'You don''t have permission to do that. Contact your administrator if you need access.', true, 72, null)
on conflict (permission_id) do update
  set label = excluded.label, description = excluded.description, feature_key = excluded.feature_key;

insert into public.plan_permissions (plan_id, permission_id, granted, updated_reason)
select p.plan_id, 'pack.bin_card', true, 'Printing a bin card is part of logging a roast'
  from (values ('starter'),('pro'),('enterprise'),('enterprise_plus')) p(plan_id)
on conflict (plan_id, permission_id) do update
  set granted = excluded.granted, updated_reason = excluded.updated_reason;

insert into public.role_permissions (role_id, permission_id, granted)
values
  ('company_admin',     'pack.bin_card', true),
  ('facility_admin',    'pack.bin_card', true),
  ('manager',           'pack.bin_card', true),
  ('roastmaster',       'pack.bin_card', true),
  ('assistant_roaster', 'pack.bin_card', true),
  ('staff',             'pack.bin_card', true)
on conflict (role_id, permission_id) do update set granted = excluded.granted;

-- ── 7. Auto-print on charge ────────────────────────────────────────────────
-- Owner: *"we should have a toggle somewhere, maybe on that flow (which will pop
-- up on charge whether the feature i'm about to mention is on or off), that sets
-- an autoprint on charge on/off."* Resolved user -> facility -> standard by
-- getUserParameter, exactly like smartroast_autoload, so a roaster's preference
-- follows them between the tablet at the roaster and the desktop while a
-- facility can still set the house default.
insert into public.standard_parameters (parameters_id, parameter, text_value, data_type)
values ('bin_card_autoprint', 'Bin card — print automatically on charge', 'off', 'boolean')
on conflict (parameters_id) do update
  set parameter = excluded.parameter, data_type = excluded.data_type;

commit;
