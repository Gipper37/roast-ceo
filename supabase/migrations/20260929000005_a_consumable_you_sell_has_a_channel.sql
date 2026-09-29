-- A consumable you sell has a channel.
--
-- Price lives on the VARIANT, and a variant carries exactly one channel, so a
-- variant with no channel has no honest place in a price list. It is still
-- orderable: 174 order lines and $12,932 have gone through null-channel
-- variants, most recently 2026-08-03. It is simply invisible to the shop and
-- ambiguous everywhere a channel is asked for.
--
-- ── THE BACKFILL, AND WHY WHOLESALE IS NOT A GUESS ─────────────────────
-- Measured on prod, consumable variants by channel:
--   9ShiyDAXhV  wholesale  97
--   9ShiyDAXhV  (none)     24
-- Nothing else. No other tenant has a consumable variant at all. So wholesale
-- is not a default chosen for the sake of having one; it is the only channel
-- any consumable has ever been sold on, and the 24 are the ones that came in
-- from QuickBooks (23) plus one made in-app through a form that renders its
-- channel picker conditionally and never validates it.
--
-- Scoped to CONSUMABLES. The other 30 null-channel variants across coffee,
-- service, equipment and discount are a separate question with a different
-- answer -- a discount line has no business carrying a sales channel -- and
-- backfilling them on this evidence would be inventing a fact.
--
-- ── WHY THERE IS NO DATABASE REFUSAL HERE ──────────────────────────────
-- Requiring it belongs in the form, and that lands in the same release. A
-- trigger refusing a null channel would have to go in AFTER that frontend is
-- live: on a release, CI pushes migrations on the tag and the frontend is
-- promoted separately, so a refusal shipped now would meet an old
-- createResoldProductForConsumable -- which passes `channel: channelId || null`
-- -- and break consumable creation on prod for the length of that window. The
-- guard is a follow-up once the form is deployed, not a thing to race.

begin;

update public.products p
   set channel = '6e6f4b92-8d17-4858-913a-b38b85b178a6'   -- wholesale, a global channel
  from public.product_groups pg
 where pg.group_id = p.group_id
   and pg.product_type = 'ptype_consumable'
   and p.channel is null
   and p.merge_into_id is null;

do $verify$
declare v_bad int; v_moved int;
begin
  select count(*) into v_bad
    from public.products p join public.product_groups pg on pg.group_id = p.group_id
   where pg.product_type = 'ptype_consumable' and p.channel is null and p.merge_into_id is null;
  if v_bad > 0 then
    raise exception '% consumable variant(s) still have no channel', v_bad;
  end if;

  -- Every consumable is on ONE channel, which is the invariant the form will
  -- enforce from now on. A consumable that suddenly had two would mean the
  -- backfill had collided with a real second channel somewhere.
  select count(*) into v_bad from (
    select p.group_id
      from public.products p join public.product_groups pg on pg.group_id = p.group_id
     where pg.product_type = 'ptype_consumable' and p.merge_into_id is null and p.is_active
     group by p.group_id having count(distinct p.channel) > 1) x;
  if v_bad > 0 then
    raise exception '% consumable product(s) now sit on more than one channel', v_bad;
  end if;

  -- And nothing outside consumables was touched.
  select count(*) into v_moved
    from public.products p join public.product_groups pg on pg.group_id = p.group_id
   where pg.product_type is distinct from 'ptype_consumable'
     and p.channel = '6e6f4b92-8d17-4858-913a-b38b85b178a6'
     and p.updated_at > now() - interval '1 minute';
  if v_moved > 0 then
    raise exception 'this migration changed % non-consumable variant(s)', v_moved;
  end if;
end;
$verify$;

commit;
