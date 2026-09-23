-- A supplier is a company, not an order number.
--
-- Five MCR suppliers carried a sales-order or invoice reference in the NAME:
--
--   Guittard - SO126396
--   Presto Labels - Strip Labels - INV 260126009
--   S&S Flavors - INV 97738 - Lavender
--   Santa Rosa - INV 29894
--   Savor Brands - SO 120
--
-- They came in that way from the consumable import, which took whatever the
-- paperwork said in the supplier field -- and the paperwork was a purchase
-- order, so it named the order. The result is a dropdown that offers the
-- operator "Santa Rosa - INV 29894" the next time they buy from Santa Rosa,
-- and a supplier list that grows one row per invoice instead of one per
-- company.
--
-- The ids are NOT touched. All five are referenced by shipments and
-- consumables, and an id is a handle, not a label; the slug in it will read
-- stale forever and that is the correct trade. Checked first: no supplier
-- already holds the cleaned name, so every one of these is a rename and none
-- is a merge.

begin;

update supplier s
   set supplier = v.clean
  from (values
    ('mcr-sup-guittard---so126396',                'Guittard'),
    ('mcr-sup-presto-labels---strip-labels---inv', 'Presto Labels'),
    ('mcr-sup-s-s-flavors---inv-97738---lavender', 'S&S Flavors'),
    ('mcr-sup-santa-rosa---inv-29894',             'Santa Rosa'),
    ('mcr-sup-savor-brands---so-120',              'Savor Brands')
  ) as v(id, clean)
 where s.supplier_id = v.id
   and s.company_id = '9ShiyDAXhV';

do $$
declare v_left int; v_dupes int;
begin
  -- Nothing left wearing an order reference, in ANY tenant.
  select count(*) into v_left from supplier
   where supplier ~* '\m(INV|SO|PO)\M[[:space:]]*#?[0-9]{2,}'
      or supplier ~ '\mSO[0-9]{3,}';
  if v_left > 0 then
    raise exception '% supplier name(s) still carry an order number', v_left;
  end if;

  -- A rename must not have collided with an existing company.
  select count(*) into v_dupes from (
    select company_id, lower(supplier) from supplier
     group by 1, 2 having count(*) > 1) x;
  if v_dupes > 0 then
    raise exception 'a rename created % duplicate supplier name(s)', v_dupes;
  end if;

  raise notice 'supplier names carry no order numbers, and none collided';
end $$;

commit;
