-- A permission's category is a HEADING, not a slug.
--
-- 20260924000006 inserted product.merge with category 'products' while every
-- other key in that group carries 'Products'. The dev permissions matrix and
-- the plans matrix both group by this column verbatim, so the new key would
-- sit under a second, lowercase section of its own — the one place an admin
-- goes to answer "who can merge products" is the one place it would be
-- hiding.
--
-- Written as a general repair rather than a single UPDATE: any future key
-- inserted with the wrong casing gets pulled back into the heading its
-- siblings already use, and the migration is safe to re-run.

begin;

update public.permissions p
   set category = c.canonical
  from (
    -- The winning spelling per case-insensitive group is the one the MOST
    -- keys already use; ties break toward the capitalised form, which is the
    -- house style for every heading in this table.
    select distinct on (lower(category))
           lower(category) as folded,
           category        as canonical
      from public.permissions
     where category is not null
     group by category
     order by lower(category), count(*) desc, (category = initcap(category)) desc, category
  ) c
 where p.category is not null
   and lower(p.category) = c.folded
   and p.category <> c.canonical;

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from (select lower(category) from public.permissions
           where category is not null
           group by lower(category) having count(distinct category) > 1) x;
  if v_bad > 0 then
    raise exception 'still % category group(s) spelled more than one way', v_bad;
  end if;
  raise notice 'permission categories: % heading(s), all spelled one way',
    (select count(distinct category) from public.permissions);
end $$;

commit;
