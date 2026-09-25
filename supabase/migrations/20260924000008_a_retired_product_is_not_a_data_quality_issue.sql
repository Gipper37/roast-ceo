-- A product you retired is not a data-quality problem.
--
-- data_quality_issues' last branch flags any product with no products_price_log
-- row as "Missing product price", with no is_active and no merge_into_id
-- filter. All five products the old merge already retired are listed on
-- production right now.
--
-- It is not a coincidence, it is structural: a merge happens BECAUSE one copy
-- holds the price and the other holds the orders, so the retired copy almost
-- always has no price-log row. Left alone, every merge would add a permanent
-- nag about a row somebody retired on purpose — training people to ignore the
-- one list whose whole job is to be worth reading.
--
-- Only that branch changes. The first reads product_margins, which already
-- filters is_active.
--
-- View definition read from pg_get_viewdef and patched in one place, never
-- retyped.
--
-- 🔴 `with (security_invoker = true)` is NOT optional and is NOT returned by
-- pg_get_viewdef. The view already had it; CREATE OR REPLACE VIEW without a
-- WITH clause RESETS reloptions, so the first version of this migration
-- silently turned a tenant-scoped view into one that runs as its owner and
-- bypasses RLS on every table it reads. On staging it then returned 766 rows
-- across every tenant. Caught by scripts/rls-cross-tenant-test.sh, not by
-- anything in this file.
--
-- The lesson generalises past this view: pg_get_functiondef carries a
-- function's whole definition, pg_get_viewdef carries only a view's SELECT.
-- Options live in pg_class.reloptions and have to be copied by hand.

begin;

create or replace view public.data_quality_issues
with (security_invoker = true) as
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    p.margin_pct,
        CASE
            WHEN p.margin_pct < 0::numeric THEN 'Selling below cost'::text
            WHEN p.margin_pct > 90::numeric THEN 'Suspiciously high margin'::text
            ELSE NULL::text
        END AS issue
   FROM product_margins p
  WHERE p.data_warning = true AND p.total_unit_cogs > 0::numeric
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Missing coffee cost'::text AS issue
   FROM coffee_inventory ci
  WHERE COALESCE(ci.latest_cost, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'coffee'::text AS entity_type,
    ci.origin_id AS entity_id,
    ci.origin AS entity_name,
    ci.company_id,
    ci.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM coffee_inventory ci
  WHERE ci.latest_cost > 0::numeric AND COALESCE(ci.last_cost_lb, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Missing consumable cost'::text AS issue
   FROM consumable_inventory c
  WHERE COALESCE(c.last_cost_unit, 0::numeric) = 0::numeric
UNION ALL
 SELECT 'consumable'::text AS entity_type,
    c.consumable_inventory_id AS entity_id,
    c.consumable_inventory_item AS entity_name,
    c.company_id,
    c.facility_id,
    NULL::numeric AS margin_pct,
    'Fallback cost only – add item to a shipment'::text AS issue
   FROM consumable_inventory c
  WHERE COALESCE(c.fallback_unit_cost, 0::numeric) > 0::numeric AND COALESCE(c.last_cost_unit, 0::numeric) > 0::numeric AND NOT (EXISTS ( SELECT 1
           FROM consumable_inventory_purchased cip
          WHERE cip.consumable_inventory_item = c.consumable_inventory_id AND cip.facility_id = c.facility_id AND cip.cost_unit IS NOT NULL AND cip.cost_unit::text <> ''::text AND cip.cost_unit > 0::numeric))
UNION ALL
 SELECT 'product'::text AS entity_type,
    p.product_id AS entity_id,
    p.product_name AS entity_name,
    p.company_id,
    p.facility_id,
    NULL::numeric AS margin_pct,
    'Missing product price'::text AS issue
   FROM products p
  WHERE p.is_active AND p.merge_into_id IS NULL AND NOT (EXISTS ( SELECT 1
           FROM products_price_log ppl
          WHERE ppl.product_id = p.product_id));

do $$
declare v_retired int;
begin
  select count(*) into v_retired
    from public.data_quality_issues d
    join public.products p on p.product_id = d.entity_id
   where d.entity_type = 'product'
     and (p.merge_into_id is not null or not p.is_active);
  if v_retired > 0 then
    raise exception '% retired product(s) still listed as a data-quality issue', v_retired;
  end if;
  raise notice 'retired products no longer appear; % issue(s) remain in total',
    (select count(*) from public.data_quality_issues);
end $$;

do $$
declare v text;
begin
  select c.reloptions::text into v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'data_quality_issues';
  if v is null or v not ilike '%security_invoker=true%' then
    raise exception 'data_quality_issues lost security_invoker — it would leak every tenant (reloptions: %)', coalesce(v,'none');
  end if;
  raise notice 'data_quality_issues still runs as the invoker';
end $$;

commit;
