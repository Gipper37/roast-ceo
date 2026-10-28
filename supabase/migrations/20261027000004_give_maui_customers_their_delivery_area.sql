-- Give Maui Coffee Roasters' customers the delivery area their address implies.
--
-- 358 of MCR's 371 customers have no sales_area, which means the Area grouping
-- on the orders page puts almost everything in one Unassigned bucket and the
-- area filter is useless. The address is already on the customer row; nobody
-- has ever had a reason to type the area in a second time.
--
-- ── What is inferred, and what deliberately is not ────────────────────────
--
-- Only the town decides, and only where the town sits inside exactly one of
-- MCR's areas. The owner asked for "at least the ones you are 90% sure on",
-- so a town that could plausibly belong to two areas, or to none, is left
-- alone rather than guessed: a wrong area silently reroutes a delivery, and a
-- blank one is visibly blank.
--
-- 🔴 Hana -> Pick-Up is the owner's decision and NOT a geographic one: it is a
-- two hour drive each way, so those customers collect. Recorded here because
-- nothing in the data says it and the next person to read this file would
-- "fix" it.
--
-- 🔴 An address with no state and a town this file does not know is NOT
-- assumed to be mainland. "Not a town I recognise" and "far away" are
-- different facts, and only one of them is in the row.
--
-- ── What this does not touch ──────────────────────────────────────────────
--
-- A customer who already has an area keeps it, always. 13 do, two of them in
-- towns this file would have mapped differently, and a human typed those.
--
-- Nothing is written to orders.area. An order's area is a property of where it
-- went on the day, and back-filling history from today's customer record would
-- rewrite what actually happened on 4,168 past deliveries.
--
-- ── 🔴 Why the verification below is shaped the way it is ─────────────────
--
-- The first version of this migration asserted that NO customer in a mapped
-- town was left without an area, and it failed CI on staging with "146
-- customers in a mapped town still have no area". The mapping was right; the
-- assertion was wrong. Staging carries MCR's customers but only ONE of their
-- six sales areas, so five of the targets below simply do not exist there and
-- there was nothing to assign. An environment that lacks the data is not a
-- broken migration, and an assertion that cannot pass on staging destroys the
-- rehearsal that is supposed to catch real problems.
--
-- So the check now asks the question that actually matters -- "did any town
-- whose area EXISTS here fail to resolve?" -- which is the one that catches a
-- name in the map not matching a row in sales_area, silently, through the
-- join. Everything else is reported as a notice and counted.

begin;

-- MCR has Kihei/Wailea, North Shore, Lahaina/Olowalu, Wailuku/Kahului, Pick-Up
-- and Ship on production. Upcountry is the gap: 43 customers in Makawao, Kula
-- and Pukalani on a real route with no area to be put on.
insert into public.sales_area (id, company_id, area_name, fulfillment_method, created_by, updated_by)
select gen_random_uuid(), '9ShiyDAXhV', 'Upcountry', 'delivery', 'backfill-20261027', 'backfill-20261027'
where not exists (
  select 1 from public.sales_area
   where company_id = '9ShiyDAXhV' and lower(btrim(area_name)) = 'upcountry'
);

-- One source for the map. It was written twice before -- once to assign and
-- once to verify -- which is how the two drifted into disagreeing about what
-- "mapped" meant.
create temporary table _mcr_town_area (town text primary key, area_name text not null) on commit drop;
insert into _mcr_town_area (town, area_name) values
  ('kihei', 'kihei/wailea'), ('wailea', 'kihei/wailea'), ('makena', 'kihei/wailea'),
  ('lahaina', 'lahaina/olowalu'), ('olowalu', 'lahaina/olowalu'), ('kaanapali', 'lahaina/olowalu'),
  ('napili', 'lahaina/olowalu'), ('kahana', 'lahaina/olowalu'), ('kapalua', 'lahaina/olowalu'),
  ('wailuku', 'wailuku/kahului'), ('kahului', 'wailuku/kahului'), ('puunene', 'wailuku/kahului'),
  ('waikapu', 'wailuku/kahului'),
  ('paia', 'north shore'), ('haiku', 'north shore'), ('kuau', 'north shore'),
  ('huelo', 'north shore'), ('haliimaile', 'north shore'),
  ('makawao', 'upcountry'), ('pukalani', 'upcountry'), ('kula', 'upcountry'),
  ('keokea', 'upcountry'), ('ulupalakua', 'upcountry'),
  ('hana', 'pick-up');

-- What each unassigned customer SHOULD get: the town's area, or 'ship' for an
-- address outside Hawaii. The out-of-state rule is the one non-town inference
-- and it is safe in the direction that matters: there is no route to Phoenix.
create temporary table _mcr_want (customer_id text primary key, area_name text not null) on commit drop;
insert into _mcr_want (customer_id, area_name)
select c.customer_id,
       coalesce(
         m.area_name,
         case when upper(btrim(coalesce(c.state, ''))) not in ('HI', '') then 'ship' end
       )
  from public.customers c
  left join _mcr_town_area m on m.town = lower(btrim(c.city))
 where c.company_id = '9ShiyDAXhV'
   and c.sales_area is null
   and coalesce(
         m.area_name,
         case when upper(btrim(coalesce(c.state, ''))) not in ('HI', '') then 'ship' end
       ) is not null;

update public.customers c
   set sales_area = a.id,
       updated_at = now(),
       updated_by = 'backfill-20261027'
  from _mcr_want w
  join public.sales_area a
    on a.company_id = '9ShiyDAXhV'
   and lower(btrim(a.area_name)) = w.area_name
 where c.customer_id = w.customer_id
   and c.sales_area is null;

do $$
declare
  n_up        int;
  n_assigned  int;
  n_no_area   int;
  n_unmatched int;
  n_blank     int;
begin
  select count(*) into n_up from public.sales_area
   where company_id = '9ShiyDAXhV' and lower(btrim(area_name)) = 'upcountry';
  if n_up <> 1 then
    raise exception 'expected exactly one Upcountry area for MCR, found %', n_up;
  end if;

  -- 🔴 THE ONE THING WORTH RAISING ON: a customer this file decided on, whose
  -- target area EXISTS in this database, that still has no area. That can only
  -- mean the name in the map did not match the row, which the join swallows
  -- silently and which would otherwise look like a clean run.
  select count(*) into n_unmatched
    from _mcr_want w
    join public.customers c on c.customer_id = w.customer_id
   where c.sales_area is null
     and exists (
       select 1 from public.sales_area a
        where a.company_id = '9ShiyDAXhV'
          and lower(btrim(a.area_name)) = w.area_name
     );
  if n_unmatched > 0 then
    raise exception
      '% customers were mapped to an area that exists here and still have none; the join is not matching',
      n_unmatched;
  end if;

  -- Everything else is reported, not raised. An environment that does not
  -- carry MCR's areas (staging has one of six) has nothing to assign, and
  -- that is a fact about the environment rather than a fault in this file.
  select count(*) into n_no_area
    from _mcr_want w
    join public.customers c on c.customer_id = w.customer_id
   where c.sales_area is null;

  select count(*) filter (where sales_area is not null),
         count(*) filter (where sales_area is null)
    into n_assigned, n_blank
    from public.customers where company_id = '9ShiyDAXhV';

  raise notice
    'MCR areas: % customers now have one, % still blank. % were decided but their area does not exist in this database.',
    n_assigned, n_blank, n_no_area;
end $$;

commit;
