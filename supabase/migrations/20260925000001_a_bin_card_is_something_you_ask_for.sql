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
-- A tenant that has ALREADY been printing bin cards keeps them. Expressed as
-- "has bin_card rows", not as a list of company ids: this migration has to run
-- on staging and on any future database, and a probe that needs one tenant's
-- data is one I have now written three times this week. MCR satisfies it
-- because it has 25 cards; Social Hour does not, because its 31 all landed on
-- the single day 20260924000005 gave it the plan.

begin;

insert into public.standard_parameters (parameters_id, parameter, amount)
values ('bin_card_surface', 'Bin card — when it appears', null)
on conflict (parameters_id) do update set parameter = excluded.parameter;

insert into public.company_parameters (company_id, facility_id, parameter_id, value, display_name)
select c.company_id, f.facility_id, 'bin_card_surface',
       case when exists (
              select 1 from public.bin_card b
               where b.company_id = c.company_id
                 and b.printed_at < date '2026-09-24'   -- before the plan change
            ) then 'charge' else 'off' end,
       'Bin card — when it appears'
  from public.companies c
  join public.facilities f on f.company_id = c.company_id
 where not exists (
   select 1 from public.company_parameters cp
    where cp.company_id = c.company_id and cp.facility_id = f.facility_id
      and cp.parameter_id = 'bin_card_surface');

do $verify$
declare v_bad int; v_on int; v_off int; v_missing int;
begin
  -- Only the four modes exist.
  select count(*) into v_bad from public.company_parameters
   where parameter_id = 'bin_card_surface'
     and value not in ('off','charge','drop','manual');
  if v_bad > 0 then raise exception '% facility row(s) hold an unknown bin-card mode', v_bad; end if;

  -- Every facility has an answer, so the default is stated rather than implied.
  select count(*) into v_missing
    from public.companies c join public.facilities f on f.company_id = c.company_id
   where not exists (select 1 from public.company_parameters cp
                      where cp.company_id=c.company_id and cp.facility_id=f.facility_id
                        and cp.parameter_id='bin_card_surface');
  if v_missing > 0 then raise exception '% facility(ies) have no bin-card setting', v_missing; end if;

  -- Nobody who was already printing has been switched off.
  select count(*) into v_bad
    from public.company_parameters cp
   where cp.parameter_id='bin_card_surface' and cp.value='off'
     and exists (select 1 from public.bin_card b
                  where b.company_id = cp.company_id and b.printed_at < date '2026-09-24');
  if v_bad > 0 then raise exception '% facility(ies) that were printing would lose the card', v_bad; end if;

  select count(*) into v_on  from public.company_parameters where parameter_id='bin_card_surface' and value='charge';
  select count(*) into v_off from public.company_parameters where parameter_id='bin_card_surface' and value='off';
  raise notice 'bin card: % facility(ies) keep it at charge, % default to off', v_on, v_off;
end $verify$;

commit;
