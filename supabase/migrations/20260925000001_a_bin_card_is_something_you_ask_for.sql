-- A bin card is something a roastery asks for, not something a plan hands them.
--
-- WHAT HAPPENED. `pack.bin_card` is plan-gated to enterprise_plus and granted to
-- every roasting role, and it carries NO feature_key — so unlike pack.run it is
-- not behind the haccp module toggle. 20260924000005 put both Social Hour
-- companies on enterprise_plus, and the bin card immediately started popping on
-- every charge for a roastery that has never switched food safety on:
--
--     company     first card   last card    cards
--     R7CbqHmA1j  2026-09-24   2026-09-24      31     <- the day of that migration
--     9ShiyDAXhV  2026-09-22   2026-09-24      25     <- deliberate, ongoing
--
-- Thirty-one cards in one day for a tenant that did not ask for the feature.
--
-- THE DECISION (owner, this session): a bin card is a production record — a route
-- sheet naming the roaster and the batch — and it is genuinely useful with no
-- HACCP at all. So it is NOT moved behind the haccp feature_key. Instead it
-- becomes opt-in, and the choice of WHEN it appears is a roast setting rather
-- than a food-safety one. HACCP adds traceability meaning to the card; it does
-- not own it.
--
--   off     never surfaces (the default, and what every tenant but MCR gets)
--   charge  when the batch is charged — what MCR does today
--   drop    when the roast finishes, so the card can carry the real weight
--   manual  only from the roast row, on demand
--
-- MCR is seeded to `charge` explicitly. They have been printing since 09-22 and
-- silently taking a working feature away would be the same discourtesy in the
-- other direction.

begin;

insert into public.standard_parameters (parameters_id, parameter, amount)
values ('bin_card_surface', 'Bin card — when it appears', null)
on conflict (parameters_id) do update set parameter = excluded.parameter;

-- Default off, for everyone, stated once here rather than implied by absence.
insert into public.company_parameters (company_id, facility_id, parameter_id, value, display_name)
select c.company_id, f.facility_id, 'bin_card_surface', 'off', 'Bin card — when it appears'
  from public.companies c
  join public.facilities f on f.company_id = c.company_id
 where not exists (
   select 1 from public.company_parameters cp
    where cp.company_id = c.company_id and cp.facility_id = f.facility_id
      and cp.parameter_id = 'bin_card_surface');

-- MCR keeps what it has been using since 2026-09-22.
update public.company_parameters
   set value = 'charge'
 where parameter_id = 'bin_card_surface'
   and company_id = '9ShiyDAXhV';

do $verify$
declare v_mcr text; v_sh text; v_off int;
begin
  select value into v_mcr from public.company_parameters
   where parameter_id='bin_card_surface' and company_id='9ShiyDAXhV' limit 1;
  select value into v_sh  from public.company_parameters
   where parameter_id='bin_card_surface' and company_id='R7CbqHmA1j' limit 1;
  select count(*) into v_off from public.company_parameters
   where parameter_id='bin_card_surface' and value='off';

  if v_mcr is distinct from 'charge' then
    raise exception 'MCR would lose the bin card it has been printing (got %)', coalesce(v_mcr,'no row');
  end if;
  if v_sh is distinct from 'off' then
    raise exception 'Social Hour would keep getting a bin card nobody asked for (got %)', coalesce(v_sh,'no row');
  end if;
  raise notice 'bin card: MCR=charge, everyone else off (% facilities)', v_off;
end $verify$;

commit;
