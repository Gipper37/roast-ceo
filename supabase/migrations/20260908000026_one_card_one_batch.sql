-- One card, one batch.
--
-- Owner, on seeing a preview with two batches on it: *"why does that have two
-- roasts on it. a route sheet bin card is for one batch isn't it"*. It is, and
-- the card is printed at CHARGE, when exactly one batch exists and nobody yet
-- knows what else will go in that bin. Modelling a set was borrowed caution
-- from a design that printed at the drop, and it bought nothing: it made the
-- card ambiguous to read and the code harder to follow.
--
-- Two batches in one bin means two cards in the bin. The packer scans both, and
-- close_pack_run gets both batches — which is the same answer the set would have
-- given, reached by a route a packer can see with their own eyes.
--
-- bin_card_source held no data worth keeping: cards have only existed since
-- 20260908000024 today, on staging.

begin;

alter table public.bin_card
  add column if not exists roast_log_id text references public.roast_log(roast_log_id) on delete restrict,
  add column if not exists lbs_at_print numeric,
  add column if not exists lbs_basis    text default 'charge';

-- Carry across anything printed while the set model was live.
update public.bin_card c
   set roast_log_id = s.roast_log_id,
       lbs_at_print = s.lbs_at_print,
       lbs_basis    = s.lbs_basis
  from public.bin_card_source s
 where s.bin_card_id = c.bin_card_id
   and c.roast_log_id is null;

alter table public.bin_card
  add constraint bin_card_lbs_basis_check check (lbs_basis in ('charge','roasted','measured'));

comment on column public.bin_card.lbs_basis is
  'Which weight lbs_at_print is. ''charge'' means the card printed before the drop and nobody has weighed anything — the card says "green" rather than stating a yield as fact.';

create index if not exists idx_bin_card_roast on public.bin_card (roast_log_id);

drop table if exists public.bin_card_source;

-- ── The mint now takes one batch ───────────────────────────────────────────
drop function if exists public.create_bin_card(text[], text);

create or replace function public.create_bin_card(
  p_roast_log_id text,
  p_note         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rl     record;
  v_id     text;
  v_code   text;
  v_actor  record;
begin
  select rl.*, coalesce(rl.coffee_name_snapshot, ci.origin) as coffee_label,
         coalesce(rl.recipe_name_snapshot, rr.recipe_name)  as recipe_label
    into v_rl
    from public.roast_log rl
    left join public.roast_recipes rr on rr.recipe_id = rl.recipe_id
    left join public.coffee_inventory ci
           on ci.origin_id = rl.origin_id and ci.facility_id = rl.facility_id
   where rl.roast_log_id = p_roast_log_id
     and rl.company_id in (select auth_company_ids());

  if v_rl.roast_log_id is null then
    raise exception 'That batch is not one of yours.' using errcode = 'insufficient_privilege';
  end if;
  if not public.auth_has_permission('pack.bin_card', v_rl.company_id) then
    raise exception 'You do not have permission to print bin cards.' using errcode = 'insufficient_privilege';
  end if;

  -- One card per batch. Charging is not the only way to reach this, and a
  -- second card for the same coffee would put two codes in one bin.
  select bin_card_id, card_code into v_id, v_code
    from public.bin_card
   where roast_log_id = p_roast_log_id and voided_at is null
   limit 1;
  if v_id is not null then
    return jsonb_build_object('bin_card_id', v_id, 'card_code', v_code, 'reprint', true);
  end if;

  select * into v_actor from public.actor_at(now());
  v_code := public.next_bin_card_code(v_rl.company_id, current_date);

  insert into public.bin_card
    (company_id, facility_id, card_code, recipe_id, coffee_label, recipe_label,
     roast_log_id, lbs_at_print, lbs_basis, printed_by_team_member, printed_by_name)
  values (
    v_rl.company_id, v_rl.facility_id, v_code, v_rl.recipe_id,
    v_rl.coffee_label, v_rl.recipe_label, p_roast_log_id,
    coalesce(v_rl.measured_roasted_weight, v_rl.roasted_weight, v_rl.charge_weight_lbs),
    case when v_rl.measured_roasted_weight is not null then 'measured'
         when v_rl.session_id is not null and coalesce(v_rl.roasted_weight, 0) > 0 then 'roasted'
         else 'charge' end,
    v_actor.team_member_id, v_actor.actor_name)
  returning bin_card_id into v_id;

  return jsonb_build_object('bin_card_id', v_id, 'card_code', v_code, 'reprint', false);
end;
$$;

revoke all on function public.create_bin_card(text, text) from public;
grant execute on function public.create_bin_card(text, text) to authenticated;

-- ── One batch to read back ─────────────────────────────────────────────────
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
    'roast_log_id', c.roast_log_id,
    'roast_date',  rl.roast_date,
    'roast_type',  rl.roast_type,
    'roaster',     ru.name,
    -- Who charged it: roast_log first (stamped at charge, so a batch with no
    -- profiler session still names somebody), then the session's own stamp.
    'roasted_by',  coalesce(rl.roasted_by_name, rs.roasted_by_name),
    'lbs',         c.lbs_at_print,
    'lbs_basis',   c.lbs_basis,
    'lots', coalesce((
       select jsonb_agg(distinct jsonb_build_object('lot', cip.lot_id, 'coffee', cs.coffee_name))
         from public.roast_log_lot_consumption lc
         join public.coffee_inventory_purchased cip
           on cip.origin_purchase_id = lc.origin_purchase_id
         left join public.coffee_source cs on cs.coffee_source_id = cip.coffee_source_id
        where lc.roast_log_id = c.roast_log_id), '[]'::jsonb))
    from public.bin_card c
    left join public.roast_log rl on rl.roast_log_id = c.roast_log_id
    left join public.roaster_units ru on ru.roaster_unit_id = rl.roaster_unit_id
    left join public.roast_sessions rs on rs.session_id = rl.session_id
   where c.bin_card_id = p_bin_card_id
     and c.company_id in (select auth_company_ids());
$$;

revoke all on function public.bin_card_data(text) from public;
grant execute on function public.bin_card_data(text) to authenticated;

commit;
