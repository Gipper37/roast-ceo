-- The bag size par was actually derived from, per coffee, in one call.
--
-- 🔴 WHY THIS EXISTS. calculate_par() divides the lbs target by
-- get_effective_bag_size(), which prefers, in order:
--     a) the ACTIVE SOURCE's bag size
--     b) the newest in-stock lot's bag size
--     c) the most common lot bag size for the group
--     d) the group's own bag_size
--
-- The inventory table reconstructed that number client-side and only
-- implemented (b) onward — it never looked at the active source. For Chocolate
-- the active source is 132 while the newest in-stock lot is 152, so the table
-- rebuilt the target as par × 152 = 20,824 lbs when the true target was
-- par × 132 = 18,084 — 15% high, and the recommendation with it.
--
-- Guessing was the mistake. The server knows; now it says. One row per coffee,
-- so a page can join it and both the table and the order form use exactly the
-- number par was built from.
--
-- Read-only. STABLE so a single page render can cache it.

begin;

create or replace function public.effective_bag_sizes(p_facility_id text)
returns table (origin_id text, bag_size numeric)
language sql
stable
as $$
  select ci.origin_id,
         public.get_effective_bag_size(ci.origin_id, ci.facility_id) as bag_size
    from public.coffee_inventory ci
   where ci.facility_id = p_facility_id
$$;

comment on function public.effective_bag_sizes(text) is
  'Per-coffee effective bag size for a facility — the exact divisor calculate_par() used. Clients must NOT recompute this; the precedence (active source → newest in-stock lot → most common lot → group) is not reproducible from the columns a page selects.';

revoke all on function public.effective_bag_sizes(text) from public, anon;
grant execute on function public.effective_bag_sizes(text) to authenticated;

commit;

notify pgrst, 'reload schema';
