-- prep_type is seeded with a vocabulary nobody uses (plan Phase 1.11).
--
-- Four hardcoded arrays and one seeded table, all disagreeing:
--
--   prep_type (seeded)      Whole Bean · Ground · Drip · Espresso · Cold Brew
--   NewOrderForm            Whole Bean · Drip Ground · Cold Brew Ground
--   EditOrderModal          Whole Bean · Drip Ground · Cold Brew Ground · Other Ground
--   StandingOrderSection    Whole Bean · Pre-Ground · Espresso Ground
--   VmiCheckinSection       Whole Bean · Drip Ground · Cold Brew Ground
--
-- And what operators have ACTUALLY recorded on 26,000+ order lines:
--
--   Whole Bean         24,489
--   (null)              9,830
--   Drip Ground         1,491
--   Cold Brew Ground       58
--   Other Ground           52
--   'Cold Brew Ground '    52   ← same value, trailing space
--   Cafetiere              46
--   Turkish Grind          15
--
-- Only "Whole Bean" appears in both the table and the data. 'Ground', 'Drip',
-- 'Espresso' and 'Cold Brew' have never been used once; 'Pre-Ground' and
-- 'Espresso Ground' — the only options the standing-order screen offers besides
-- Whole Bean — have never been used either (standing_order_lines and
-- vmi_checkin_items are both empty). So pointing the dropdowns at the table as it
-- stands would have REMOVED the three preps that carry 1,600 real lines and offered
-- five that carry none.
--
-- This makes the table match reality first, so the UI can then be driven from it.

begin;

-- ── 1. Merge the whitespace twin ───────────────────────────────────────────
-- 'Cold Brew Ground ' and 'Cold Brew Ground' are the same prep split across two
-- values by free-text entry, which is exactly what a shared vocabulary prevents.
-- Trim every prep column so the split cannot survive.
update public.order_details
   set coffee_prep = btrim(coffee_prep)
 where coffee_prep IS NOT NULL
   and coffee_prep <> btrim(coffee_prep);

update public.standing_order_lines
   set coffee_prep = btrim(coffee_prep)
 where coffee_prep IS NOT NULL
   and coffee_prep <> btrim(coffee_prep);

update public.vmi_checkin_items
   set coffee_prep = btrim(coffee_prep)
 where coffee_prep IS NOT NULL
   and coffee_prep <> btrim(coffee_prep);

-- ── 2. The vocabulary operators actually use ───────────────────────────────
-- Global rows (company_id NULL) so every tenant inherits them; a roaster can still
-- add its own. sort_order puts the common ones first — Whole Bean is 93% of lines.
--
-- prep_type_id is a uuid, so the ids are DERIVED from the name (md5 → uuid) rather
-- than random: that makes this insert idempotent, and makes the same prep carry the
-- same id in every environment, which a gen_random_uuid() seed cannot promise.
insert into public.prep_type (prep_type_id, prep_type, company_id, is_active, sort_order)
select md5('prep:' || v.name)::uuid, v.name, null, true, v.ord
from (values
  ('Whole Bean',       1),
  ('Drip Ground',      2),
  ('Cold Brew Ground', 3),
  ('Espresso Ground',  4),
  ('Cafetiere',        5),
  ('Turkish Grind',    6),
  ('Other Ground',     7)
) as v(name, ord)
on conflict (prep_type_id) do update
   set prep_type  = excluded.prep_type,
       is_active  = excluded.is_active,
       sort_order = excluded.sort_order;

-- ── 3. Retire the seeded values nobody ever used ───────────────────────────
-- Deactivated, NOT deleted: is_active is the documented off-switch, a delete would
-- be unrecoverable, and a tenant that did somehow record one keeps it readable.
-- Any GLOBAL row that is not one of the seven canonical ids above goes quiet —
-- including the original 'Whole Bean' row, which would otherwise appear twice in
-- every dropdown alongside its derived-id replacement.
update public.prep_type
   set is_active = false
 where company_id is null
   and prep_type_id not in (
     select md5('prep:' || name)::uuid
     from (values ('Whole Bean'),('Drip Ground'),('Cold Brew Ground'),
                  ('Espresso Ground'),('Cafetiere'),('Turkish Grind'),('Other Ground')
     ) as v(name)
   );

commit;

notify pgrst, 'reload schema';
