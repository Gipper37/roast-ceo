-- A merged product keeps its history.
--
-- A roastery ends up with the same product entered twice — MCR has six such
-- pairs, and thirteen duplicate-name clusters exist across six tenants, so this
-- is not one customer's mess. Each copy holds part of the truth: one has the
-- price, the other has the orders.
--
-- WHAT A MERGE MUST NOT DO, and what the two existing implementations both did:
--
--   * It must not move order lines. 94% of MCR's duplicate history carries an
--     invoice number, and a figure a customer has been sent does not move.
--     guard_posted_order_detail_immutable already refuses it outright, and on
--     the lines it would allow, handle_order_detail_logic treats a product
--     change as a repricing event — proven against production: a line went
--     $77.50 -> $74.75 and its COGS $44.54 -> $28.32.
--   * It must not delete the loser's BOM. That is what makes its history count
--     for anything: consumable usage is order_details JOIN product_consumables
--     ON product_id, and nothing in that chain reads the products table. The
--     old merge deleted it, and TODAY on production 64 units at Social Hour US
--     consume no bag and no label because of it.
--   * It must not move group_id. That fires products_inherit_group_type and
--     build_product_name, which retype and rename the variant.
--
-- SO: NOTHING IS REWRITTEN. The loser is retired and points at the survivor,
-- and READS resolve through the link. On screen one product with one history;
-- underneath, two rows and an arrow. Invoices still print what they printed,
-- because resolution is for ROLLUP ONLY — a rendered invoice line names the
-- product the line names, forever.
--
-- canonical_product_id / canonical_group_id are the mechanism: NOT NULL,
-- defaulting to the row's own id, so every product is its own canonical until
-- somebody merges it and nothing changes for anyone else. A rollup becomes
-- `group by p.canonical_product_id` on a join it already does.

begin;

-- ── 1. The canonical pointers ───────────────────────────────────────────
alter table public.products
  add column if not exists canonical_product_id text;
update public.products set canonical_product_id = product_id where canonical_product_id is null;
alter table public.products
  alter column canonical_product_id set not null;
alter table public.products
  alter column canonical_product_id set default null;

-- uuid, not text: product_groups.group_id is a uuid while products.product_id
-- is text. Matching each to its own table rather than picking one type is what
-- keeps the join free of casts.
alter table public.product_groups
  add column if not exists canonical_group_id uuid;
update public.product_groups set canonical_group_id = group_id where canonical_group_id is null;
alter table public.product_groups
  alter column canonical_group_id set not null;

comment on column public.products.canonical_product_id is
  'The product this variant ROLLS UP to. Its own id until merged. Reporting groups by this; invoices and pack runs must NOT resolve it — a rendered line names the product the line names.';
comment on column public.product_groups.canonical_group_id is
  'The product this group ROLLS UP to. Its own id until merged. See products.canonical_product_id.';

create index if not exists idx_products_canonical on public.products (canonical_product_id);
create index if not exists idx_product_groups_canonical on public.product_groups (canonical_group_id);

-- A new row is its own canonical. Done as a trigger rather than a DEFAULT
-- because a default cannot reference another column of the same row.
create or replace function public.trg_default_canonical_product()
returns trigger language plpgsql as $function$
begin
  if NEW.canonical_product_id is null then NEW.canonical_product_id := NEW.product_id; end if;
  return NEW;
end; $function$;

drop trigger if exists aaa_default_canonical_product on public.products;
create trigger aaa_default_canonical_product
  before insert on public.products
  for each row execute function public.trg_default_canonical_product();

create or replace function public.trg_default_canonical_group()
returns trigger language plpgsql as $function$
begin
  if NEW.canonical_group_id is null then NEW.canonical_group_id := NEW.group_id; end if;
  return NEW;
end; $function$;

drop trigger if exists aaa_default_canonical_group on public.product_groups;
create trigger aaa_default_canonical_group
  before insert on public.product_groups
  for each row execute function public.trg_default_canonical_group();

-- ── 2. Retire the legacy merge path ─────────────────────────────────────
-- It remaps order_details (which the posted guard refuses, so it aborts
-- mid-merge) and deletes the BOM. It is also the ONLY validation merge_into_id
-- has ever had, and the only thing deactivating the loser — both replaced
-- below. merge_products() additionally is SECURITY INVOKER, EXECUTE-granted to
-- `authenticated`, and gated by no permission key at all: any signed-in packer
-- or driver can call it over PostgREST today. Nothing in the frontend calls
-- either one.
drop trigger if exists trg_merge_product on public.products;
drop function if exists public.trg_do_product_merge();
revoke all on function public.merge_products(text, text) from authenticated, anon;
drop function if exists public.merge_products(text, text);

-- ── 3. The audit record ─────────────────────────────────────────────────
-- "Why does this month look different from the PDF I printed in August" needs
-- a better answer than somebody's word for it.
create table if not exists public.product_merge_log (
  product_merge_id  uuid primary key default gen_random_uuid(),
  company_id        text not null,
  facility_id       text,
  /** 'group' or 'variant' — what was merged. */
  merge_kind        text not null check (merge_kind in ('group', 'variant')),
  kept_id           text not null,
  kept_name         text,
  retired_id        text not null,
  retired_name      text,
  /** Counts at merge time, so the blast radius is recorded, not recomputed. */
  order_lines_left  integer not null default 0,
  units_left        numeric,
  merged_at         timestamptz not null default now(),
  merged_by         text,
  notes             text
);

comment on table public.product_merge_log is
  'One row per merge. Records what rolled into what and how much history came with it, so a changed report can be explained rather than argued about.';

alter table public.product_merge_log enable row level security;

drop policy if exists product_merge_log_tenant on public.product_merge_log;
create policy product_merge_log_tenant on public.product_merge_log
  for all to authenticated
  using (company_id in (select t.company_id from public.team t where t.auth_user_id = auth.uid() and coalesce(t.is_active, true)))
  with check (company_id in (select t.company_id from public.team t where t.auth_user_id = auth.uid() and coalesce(t.is_active, true)));

-- ── 4. Prove it ─────────────────────────────────────────────────────────
do $$
declare v_bad int; v_legacy int;
begin
  select count(*) into v_bad from public.products where canonical_product_id is distinct from product_id
    and merge_into_id is null;
  if v_bad > 0 then
    raise exception '% unmerged product(s) are not their own canonical', v_bad;
  end if;

  select count(*) into v_bad from public.product_groups where canonical_group_id is distinct from group_id;
  if v_bad > 0 then
    raise exception '% group(s) are not their own canonical before any merge has run', v_bad;
  end if;

  -- The five products the OLD path already merged keep canonical = their own
  -- id, which strands their history exactly where it is today. Pointing them
  -- at their survivors would roll their sales up -- and is probably right --
  -- but it is a data repair on somebody's live tenant (four of the five are
  -- Social Hour US), and it would NOT fix the thing that actually hurts: their
  -- BOMs were deleted, and consumable usage joins order_details to
  -- product_consumables on product_id directly, never through canonical. So
  -- rolling them up would make the sales read right while the packaging demand
  -- stayed short. Both repairs are deliberate decisions for their owner, not a
  -- side effect of installing this.
  raise notice '% product(s) merged by the old path are left stranded on purpose -- see the comment here',
    (select count(*) from public.products where merge_into_id is not null);

  select count(*) into v_legacy from pg_proc
   where pronamespace = 'public'::regnamespace and proname in ('merge_products', 'trg_do_product_merge');
  if v_legacy > 0 then
    raise exception 'the legacy merge path is still installed (% function(s))', v_legacy;
  end if;

  raise notice 'canonical pointers set on % product(s) and % group(s); legacy merge path removed',
    (select count(*) from public.products), (select count(*) from public.product_groups);
end $$;

commit;
