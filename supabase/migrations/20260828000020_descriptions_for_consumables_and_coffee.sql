-- A description on the things operators talk about.
--
-- Products (product_groups) have had a description column since the shop
-- needed one; consumables and coffee groups never got theirs. The owner wants
-- all three describable — what a thing is, which machine it fits, why it is
-- stocked — edited from each detail page.
--
-- Plain nullable text, no backfill: an empty description is simply absent.

begin;

alter table public.consumable_inventory add column if not exists description text;
alter table public.coffee_inventory     add column if not exists description text;

commit;

-- New columns are invisible to PostgREST until its schema cache reloads — and
-- the frontend selects them the moment it deploys, so don't leave a 10-minute
-- window of 500s to luck.
notify pgrst, 'reload schema';
