-- Say where a roasted weight came from.
--
-- Owner, 2026-10-23: *"it should indicate when a weight is auto generated or
-- manually input. so the user knows from that popup and maybe should even add
-- it to the table content in an editable way next to the charge weight. but
-- put that in the roast settings as an option to turn off or on. turn it on
-- for MCR but keep off for Social hours. off should be default."*
--
-- ── THE DISTINCTION ALREADY EXISTS IN THE DATA ────────────────────────────
--
-- `roast_log.measured_roasted_weight` is what somebody put on a scale.
-- `roast_log.roasted_weight` is charge x the recipe's retention factor, written
-- by a trigger. So a weight is MANUAL when measured_roasted_weight is not null
-- and AUTO otherwise -- no new column, nothing to backfill, and every roast
-- already in the database answers the question correctly.
--
-- What is missing is only that the screens do not SAY which one they are
-- showing, and that cost the owner a confused minute on the floor: the roast
-- header read 49.2 lbs at 82.0% (charge x planned retention) while the bin card
-- read the 51.1 he had just weighed.
--
-- ── WHY IT IS A SETTING AT ALL ────────────────────────────────────────────
--
-- A roastery that weighs every batch wants to see which figure it is looking
-- at. One that never weighs would be told "calculated" on every row forever,
-- which is noise. Off by default for that reason; the roasteries that want it
-- are the ones that weigh.
--
-- Not plan-gated and not permissioned: it changes nothing but a label, and
-- hiding a label behind a permission is how a screen ends up meaning different
-- things to two people standing at the same machine.

begin;

insert into public.standard_parameters (parameters_id, parameter, data_type)
values ('roast_weight_source', 'Roasted weight: say if it was weighed or worked out', 'text')
on conflict (parameters_id) do update set
  parameter  = excluded.parameter,
  data_type  = excluded.data_type,
  updated_at = now();

-- 🔴 No default row anywhere. An absent company_parameters row reads as 'off'
-- in the app, which is the owner's stated default, so seeding "off" for every
-- roastery would write 200 rows that all mean "nothing was chosen". The only
-- row written here is the one he asked for.
--
-- Scoped to the facility, because that is how company_parameters is read
-- everywhere else (`.eq('facility_id', ...)`). MCR has one.
insert into public.company_parameters (company_id, facility_id, parameter_id, value, created_by, updated_by)
select f.company_id, f.facility_id, 'roast_weight_source', 'on', 'migration 20261023000003', 'migration 20261023000003'
  from public.facilities f
 where f.company_id = '9ShiyDAXhV'   -- Maui Coffee Roasters: weighs every batch
on conflict (company_id, facility_id, parameter_id) do update set
  value      = excluded.value,
  updated_at = now(),
  updated_by = excluded.updated_by;

-- 🔴 Asserts only what this file wrote. Social Hour is checked by ABSENCE --
-- the owner asked for it to stay off, and off is "no row", so a row appearing
-- there would mean this file reached further than it was told to.
do $$
declare
  v_mcr int;
  v_others int;
begin
  if not exists (select 1 from public.standard_parameters where parameters_id = 'roast_weight_source') then
    raise exception 'the roast_weight_source parameter was not created';
  end if;

  select count(*) into v_mcr
    from public.company_parameters
   where parameter_id = 'roast_weight_source' and company_id = '9ShiyDAXhV' and value = 'on';
  select count(*) into v_others
    from public.company_parameters
   where parameter_id = 'roast_weight_source' and company_id <> '9ShiyDAXhV';

  -- Only assert MCR's row where MCR exists: staging has its own tenants.
  if exists (select 1 from public.facilities where company_id = '9ShiyDAXhV') and v_mcr = 0 then
    raise exception 'MCR was not switched on';
  end if;
  if v_others > 0 then
    raise exception 'this file wrote roast_weight_source for a company it was not asked about';
  end if;
end $$;

commit;
