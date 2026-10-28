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
--   Kihei, Wailea, Makena                       -> Kihei/Wailea
--   Lahaina, Olowalu, Kaanapali, Napili,
--     Kahana, Kapalua                           -> Lahaina/Olowalu
--   Wailuku, Kahului, Puunene, Waikapu          -> Wailuku/Kahului
--   Paia, Haiku, Kuau, Huelo, Haliimaile        -> North Shore
--   Makawao, Pukalani, Kula, Keokea, Ulupalakua -> Upcountry   (new, below)
--   Hana                                        -> Pick-Up     (owner's call)
--   any address outside Hawaii                  -> Ship
--
-- 🔴 Hana is the owner's decision and not a geographic one: it is a two hour
-- drive each way, so those customers collect. Recorded here because nothing in
-- the data says it and the next person to read this file would "fix" it.
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

begin;

-- MCR has Kihei/Wailea, North Shore, Lahaina/Olowalu, Wailuku/Kahului, Pick-Up
-- and Ship. Upcountry is the gap: 45 customers in Makawao, Kula and Pukalani,
-- which is a real route and has no area to be put on.
insert into public.sales_area (id, company_id, area_name, fulfillment_method, created_by, updated_by)
select gen_random_uuid(), '9ShiyDAXhV', 'Upcountry', 'delivery', 'backfill-20261027', 'backfill-20261027'
where not exists (
  select 1 from public.sales_area
   where company_id = '9ShiyDAXhV' and lower(btrim(area_name)) = 'upcountry'
);

with area as (
  select lower(btrim(area_name)) as name, id
    from public.sales_area
   where company_id = '9ShiyDAXhV'
),
mapped as (
  select c.customer_id,
         case lower(btrim(c.city))
           when 'kihei'      then 'kihei/wailea'
           when 'wailea'     then 'kihei/wailea'
           when 'makena'     then 'kihei/wailea'
           when 'lahaina'    then 'lahaina/olowalu'
           when 'olowalu'    then 'lahaina/olowalu'
           when 'kaanapali'  then 'lahaina/olowalu'
           when 'napili'     then 'lahaina/olowalu'
           when 'kahana'     then 'lahaina/olowalu'
           when 'kapalua'    then 'lahaina/olowalu'
           when 'wailuku'    then 'wailuku/kahului'
           when 'kahului'    then 'wailuku/kahului'
           when 'puunene'    then 'wailuku/kahului'
           when 'waikapu'    then 'wailuku/kahului'
           when 'paia'       then 'north shore'
           when 'haiku'      then 'north shore'
           when 'kuau'       then 'north shore'
           when 'huelo'      then 'north shore'
           when 'haliimaile' then 'north shore'
           when 'makawao'    then 'upcountry'
           when 'pukalani'   then 'upcountry'
           when 'kula'       then 'upcountry'
           when 'keokea'     then 'upcountry'
           when 'ulupalakua' then 'upcountry'
           when 'hana'       then 'pick-up'
           else case
             -- Outside Hawaii is the one non-town inference, and it is safe in
             -- the direction that matters: there is no route to Phoenix.
             when upper(btrim(coalesce(c.state, ''))) not in ('HI', '') then 'ship'
             else null
           end
         end as want
    from public.customers c
   where c.company_id = '9ShiyDAXhV'
     and c.sales_area is null
)
update public.customers c
   set sales_area = a.id,
       updated_at = now(),
       updated_by = 'backfill-20261027'
  from mapped m
  join area a on a.name = m.want
 where c.customer_id = m.customer_id
   and c.sales_area is null;

do $$
declare
  n_up      int;
  n_blank   int;
  n_set     int;
  n_outside int;
begin
  select count(*) into n_up from public.sales_area
   where company_id = '9ShiyDAXhV' and lower(btrim(area_name)) = 'upcountry';
  if n_up <> 1 then
    raise exception 'expected exactly one Upcountry area for MCR, found %', n_up;
  end if;

  select count(*) filter (where sales_area is not null),
         count(*) filter (where sales_area is null)
    into n_set, n_blank
    from public.customers where company_id = '9ShiyDAXhV';

  -- The towns this file knows must all be resolved now. A leftover means a
  -- name in the CASE does not match an area_name, which fails silently in the
  -- join and would otherwise look like a clean run.
  select count(*) into n_outside
    from public.customers
   where company_id = '9ShiyDAXhV'
     and sales_area is null
     and lower(btrim(city)) in (
       'kihei','wailea','makena','lahaina','olowalu','kaanapali','napili','kahana','kapalua',
       'wailuku','kahului','puunene','waikapu','paia','haiku','kuau','huelo','haliimaile',
       'makawao','pukalani','kula','keokea','ulupalakua','hana');
  if n_outside > 0 then
    raise exception
      '% customers in a mapped town still have no area; an area_name in the CASE does not match sales_area',
      n_outside;
  end if;

  -- Said out loud, because "how many did it skip" is the only interesting
  -- number here and a silent success hides it.
  raise notice 'MCR customers with an area: %, still blank: % (upcountry/hana towns now mapped; blanks are no-city and unrecognised-town rows)',
    n_set, n_blank;
end $$;

commit;
