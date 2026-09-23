-- A discount rule may only price its own tenant's orders.
--
-- resolve_customer_discount matched on customer_id and nothing else:
--
--   where d.customer_id = p_customer_id
--     and d.is_active ...
--
-- customer_discount's INSERT policy checks that the RULE carries your
-- company_id. It does not check that the CUSTOMER it names is yours. So a
-- member of one tenant holding customer.edit -- a permission most roles have --
-- could write a rule pointing at another tenant's customer, and the resolver
-- would apply it to that tenant's orders.
--
-- Replayed read-only against prod, with the resolver's own predicate:
--
--   rule owned by  demo-aloha-coffee-roasters
--   customer of    9ShiyDAXhV
--   product        Espresso - 5lbs - Wholesale, $63.25 x 8 = $506.00
--   result         100% off. Charged $0.00.
--
-- TWO BELTS, because either alone leaves a way in.
--
-- 1. The resolver now joins customers and requires the rule, the customer and
--    the PRODUCT to share a company. A rule that reaches across cannot be
--    read, so any already written is inert from this migration forward.
--
-- 2. A trigger refuses to write one at all. A foreign key cannot express
--    "same tenant as", so this is the only way to say it in the schema.
--
-- No such rule exists today -- customer_discount is empty in every tenant --
-- so this closes the door before anybody walks through it.

begin;

CREATE OR REPLACE FUNCTION public.resolve_customer_discount(p_customer_id text, p_product_id text, p_on_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(customer_discount_id text, kind text, value numeric, scope text)
 LANGUAGE sql
 STABLE
AS $function$
  select d.customer_discount_id, d.kind, d.value, d.scope
  from public.customer_discount d
  join public.products p on p.product_id = p_product_id
  left join public.product_groups pg on pg.group_id = p.group_id
  -- THE TENANT PREDICATE. Without this the resolver matched on customer_id
  -- alone, so a rule belonging to company A could price company B's order the
  -- moment it named one of B's customers -- and customer_discount's INSERT
  -- policy only checks that the RULE is yours, not the customer it names.
  join public.customers c
    on c.customer_id = d.customer_id
   and c.company_id  = d.company_id
   and c.company_id  = p.company_id
  where d.customer_id = p_customer_id
    and d.is_active
    and d.effective_from <= p_on_date
    and (d.effective_to is null or d.effective_to >= p_on_date)
    and (
         d.scope = 'all'
      -- Resold goods: the same derived test the Products page filter uses.
      -- Deliberately not the Consumable product type, which would also catch
      -- the internal supplies that are never resold.
      or (d.scope = 'distribution'  and p.source_consumable_id is not null)
      or (d.scope = 'product_type'  and d.scope_ref = p.product_type)
      or (d.scope = 'product'       and d.scope_ref = pg.group_id::text)
      -- A VARIANT is the thing a customer actually buys, and the only level
      -- at which a price exists: one group can hold 8 variants from $6.83 to
      -- $245, so "they pay $9" is not a statement the group can carry.
      or (d.scope = 'variant'       and d.scope_ref = p.product_id)
    )
  -- Most specific wins. Distribution sits above a plain type because "resold
  -- goods" is the narrower statement about the same item.
  order by case d.scope
             when 'variant' then 5
             when 'product' then 4
             when 'distribution' then 3
             when 'product_type' then 2
             else 1 end desc
  limit 1;
$function$;;

create or replace function public.guard_customer_discount_same_tenant()
returns trigger
language plpgsql
as $function$
declare
  v_customer_company text;
begin
  select company_id into v_customer_company
  from public.customers where customer_id = NEW.customer_id;

  if v_customer_company is null then
    raise exception 'That customer does not exist.';
  end if;
  if v_customer_company is distinct from NEW.company_id then
    -- Deliberately does not name the other tenant.
    raise exception 'That customer belongs to a different company.';
  end if;
  return NEW;
end;
$function$;

drop trigger if exists zzz_guard_customer_discount_tenant on public.customer_discount;
create trigger zzz_guard_customer_discount_tenant
  before insert or update of customer_id, company_id on public.customer_discount
  for each row execute function public.guard_customer_discount_same_tenant();

do $$
declare
  v_src text;
  v_bad int;
begin
  select prosrc into v_src from pg_proc
  where oid = 'public.resolve_customer_discount(text,text,date)'::regprocedure;
  if position('c.company_id  = p.company_id' in v_src) = 0 then
    raise exception 'the resolver still has no tenant predicate';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.customer_discount'::regclass
      and tgname = 'zzz_guard_customer_discount_tenant'
  ) then
    raise exception 'the same-tenant guard was not attached';
  end if;

  -- And nothing already written may cross a tenant line.
  select count(*) into v_bad
  from public.customer_discount d
  join public.customers c on c.customer_id = d.customer_id
  where c.company_id is distinct from d.company_id;
  if v_bad > 0 then
    raise warning '% existing discount rules name a customer in another company; they are now inert but should be deleted', v_bad;
  end if;
end $$;

commit;
