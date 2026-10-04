-- products.in_shop was a model we did not take.
--
-- Added 2026-06-12 by 20260612000003 as "Model B": decouple shop membership
-- from channel, with channel "reverting to pricing-tier only" and in_shop
-- becoming "the single explicit this-product-is-listed-in-the-shop fact". Its
-- own comment called it DORMANT, waiting on a shop-membership redesign that
-- would wire it into the shop query and build a tabbed management UI.
--
-- That redesign never happened, and the premise under it has since reversed.
-- The roaster uses channel as more than a pricing tier -- Costco and Safeway
-- are channels, carrying their own prices and their own case make-ups -- and
-- confirmed on 2026-10-02 that he is keeping it that way. Model B assumed the
-- opposite.
--
-- 🔴 PROVED DEAD BEFORE DROPPING, which is the whole reason this is safe:
--   frontend reads ........ 0   (only the generated database.ts type)
--   frontend writes ....... 0
--   views ................. 0
--   functions ............. 0
--   indexes ............... 0
--   materialized views .... 0
-- Nothing has ever read it and nothing has ever written it since the backfill
-- in the migration that created it.
--
-- WHAT IT WAS DOING INSTEAD. The storefront ignores it, so the column had
-- drifted into a lie: 379 of MCR's 608 products say in_shop, 229 say not, and
-- all of them are treated identically. 74 variants currently on the shop are
-- flagged false, including ordinary wholesale coffee like Hawaiian Blend 1lb
-- and Hoala Blend 8oz. An operator reading that column would conclude those
-- products are not for sale online. They are.
--
-- Enforcing it instead of dropping it was the other option and it was worse:
-- the false values are a DEFAULT nobody chose (the column defaults false and
-- no UI has ever set it), not a curation, so switching it on would have pulled
-- 74 products off the shop that nobody decided to remove.
--
-- What it would have provided is already covered. Who may see a variant is
-- channel; whether a product shows at all is product_groups.is_visible. If a
-- per-variant "not sold online" switch is wanted later it should be designed
-- against how the shop actually works now, not inherited from a model that was
-- superseded before it was ever wired up.
--
-- Closes the in_shop half of memory/project_product_taxonomy.md.

begin;

do $verify$
declare v_bad int;
begin
  -- Refuse to drop a column something started using while we were not looking.
  select count(*) into v_bad from information_schema.views
   where table_schema='public' and view_definition ilike '%in_shop%';
  if v_bad > 0 then raise exception '% view(s) reference in_shop', v_bad; end if;

  select count(*) into v_bad from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosrc ilike '%in_shop%';
  if v_bad > 0 then raise exception '% function(s) reference in_shop', v_bad; end if;

  select count(*) into v_bad from pg_indexes
   where schemaname='public' and indexdef ilike '%in_shop%';
  if v_bad > 0 then raise exception '% index(es) reference in_shop', v_bad; end if;

  select count(*) into v_bad from pg_matviews
   where schemaname='public' and definition ilike '%in_shop%';
  if v_bad > 0 then raise exception '% materialized view(s) reference in_shop', v_bad; end if;
end;
$verify$;

alter table public.products drop column if exists in_shop;

do $verify$
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='products' and column_name='in_shop') then
    raise exception 'products.in_shop is still there';
  end if;

  -- The two things that DO decide what a buyer sees are untouched.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='products' and column_name='channel') then
    raise exception 'products.channel is gone; that is what gates who sees a variant';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='product_groups' and column_name='is_visible') then
    raise exception 'product_groups.is_visible is gone; that is what gates whether a product shows';
  end if;
end;
$verify$;

commit;
