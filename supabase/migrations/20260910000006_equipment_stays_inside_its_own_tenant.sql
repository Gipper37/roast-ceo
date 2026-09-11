-- Equipment stays inside its own tenant.
--
-- Three ways in, found by both audits:
--
--   1. apply_program_to_equipment(p_equipment_id, p_program_id) and
--      seed_equipment_schedule(p_equipment_id) are SECURITY DEFINER, granted
--      to authenticated, and do `SELECT * INTO e FROM equipment WHERE
--      equipment_id = p_equipment_id` with no tenant test — so any signed-in
--      user could insert schedule rows stamped with another tenant's
--      company_id, using equipment ids the leaking equipment_due_status view
--      handed out (closed by 20260910000001). seed_equipment_schedule has no
--      caller anywhere; it is dropped rather than guarded.
--   2. equipment.customer_id / facility_id / linked_roaster_unit_id are plain
--      foreign keys with no company match. Link your machine to another
--      tenant's roaster and the hourly recompute_equipment_usage() copies
--      their lifetime roasted weight into your "Total ran"; link it to their
--      customer and the reminder cron addresses their contacts.
--   3. ensure_company_pricing_default(p_company_id) is SECURITY DEFINER and
--      inserts a defaults row for whatever company id it is handed.
--
-- The guard trigger uses the same idiom as 20260910000005: resolve the
-- pointed-at row as the caller, under that table's RLS, and refuse on "not
-- found" or a company mismatch. The two definer functions check
-- auth_company_ids() explicitly (a definer function sees every row, so RLS
-- cannot do it for them) and stay open to service-role and cron callers,
-- for whom auth.uid() is null — the same exemption guard_team_privileged_columns
-- uses.
--
-- Prod today: 0 equipment rows with a cross-company pointer, 0 injected
-- schedules or subscriptions (checked before writing this).

begin;

-- ── 1. equipment pointers must share the row's company ────────────────────
create or replace function public.guard_equipment_tenant()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_company text;
begin
  if new.customer_id is not null then
    select company_id into v_company from public.customers where customer_id = new.customer_id;
    if not found or v_company is distinct from new.company_id then
      raise exception 'That customer is not part of this company.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if new.facility_id is not null then
    select company_id into v_company from public.facilities where facility_id = new.facility_id;
    if not found or v_company is distinct from new.company_id then
      raise exception 'That facility is not part of this company.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if new.linked_roaster_unit_id is not null then
    select company_id into v_company from public.roaster_units where roaster_unit_id = new.linked_roaster_unit_id;
    if not found or v_company is distinct from new.company_id then
      raise exception 'That roaster is not part of this company.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists zz_guard_equipment_tenant on public.equipment;
create trigger zz_guard_equipment_tenant
  before insert or update of customer_id, facility_id, linked_roaster_unit_id, company_id on public.equipment
  for each row execute function public.guard_equipment_tenant();

comment on function public.guard_equipment_tenant() is
  'A piece of equipment may only point at a customer, facility or roaster of its own company. Looked up as the caller, so another tenant''s rows are not there.';

-- ── 2. apply_program_to_equipment: your machine, a program you may use ────
create or replace function public.apply_program_to_equipment(p_equipment_id text, p_program_id text)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  e record;
  inserted_count int := 0;
begin
  select * into e from public.equipment where equipment_id = p_equipment_id;
  if not found then return 0; end if;

  -- A definer function sees every tenant's rows; say whose machine this is.
  -- Service role and cron carry no JWT and are already trusted.
  if auth.uid() is not null and e.company_id not in (select public.auth_company_ids()) then
    raise exception 'That equipment is not yours.'
      using errcode = 'insufficient_privilege';
  end if;

  -- The program must be built-in or belong to the machine's own company.
  if not exists (
    select 1 from public.maintenance_program mp
     where mp.program_id = p_program_id
       and (mp.company_id is null or mp.company_id = e.company_id)
  ) then
    raise exception 'That maintenance program is not available to this company.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Record the subscription (idempotent)
  insert into public.equipment_program_subscription
    (company_id, equipment_id, program_id, subscribed_at)
  values (e.company_id, p_equipment_id, p_program_id, now())
  on conflict (equipment_id, program_id) do nothing;

  -- Seed schedule rows for every template in the program
  with ins as (
    insert into public.equipment_schedule
      (company_id, equipment_id, template_id, frequency_type, frequency_interval)
    select
      e.company_id,
      p_equipment_id,
      mpt.template_id,
      coalesce(mpt.frequency_type,     mt.frequency_type),
      coalesce(mpt.frequency_interval, mt.frequency_interval)
    from public.maintenance_program_template mpt
    join public.maintenance_template mt on mt.template_id = mpt.template_id
    where mpt.program_id = p_program_id
    on conflict (equipment_id, template_id) do nothing
    returning schedule_id
  )
  select count(*) into inserted_count from ins;

  return inserted_count;
end
$$;

-- ── 3. seed_equipment_schedule: no caller, no reason to exist ─────────────
drop function if exists public.seed_equipment_schedule(text);

-- ── 4. ensure_company_pricing_default: only for a company you belong to ───
create or replace function public.ensure_company_pricing_default(p_company_id text)
returns public.company_pricing_default
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r public.company_pricing_default;
begin
  if auth.uid() is not null and p_company_id not in (select public.auth_company_ids()) then
    raise exception 'That company is not yours.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.company_pricing_default (company_id)
  values (p_company_id)
  on conflict (company_id) do nothing;

  select * into r from public.company_pricing_default where company_id = p_company_id;
  return r;
end
$$;

commit;
