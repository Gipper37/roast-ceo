-- A shop order ref is unique PER ROASTERY, not across the whole table.
--
-- 🔴 THIS TOOK A LIVE CHECKOUT DOWN. 2026-11-02 22:40 HST, Maui Coffee
-- Roasters, prod: "We could not record your order, so nothing was charged."
-- The gateway never saw it -- payment_transactions recorded
--
--     Not sent to the gateway: duplicate key value violates unique
--     constraint "idx_orders_shop_order_ref"
--
-- `allocate_shop_order_ref` keeps its counter in shop_order_ref_counter,
-- keyed BY COMPANY, and hands back 'SH-' || lpad(n, 6, '0'). The index it
-- writes into was unique on shop_order_ref ALONE. So every tenant mints the
-- same sequence of strings and the second one to reach any given number is
-- refused. It is not a race and not bad luck: both counters start at 1, so
-- the collision is certain, and the only reason the shop ever worked is that
-- two tenants had each sold exactly once.
--
--     Social Hour Coffee Roasters   SH-000002   2026-06-11   (written first)
--     Maui Coffee Roasters          SH-000002   2026-11-02   (refused)
--
-- The sibling column got this right three releases ago:
-- orders_company_invoice_number_uidx is (company_id, invoice_number). A shop
-- ref is the same kind of thing -- a human-facing number one roastery prints
-- on one buyer's receipt -- so it is scoped the same way.
--
-- Nothing reads it unscoped. The single lookup by this column is
-- resolveOrderByRef in app/(shop)/[slug]/order/[ref]/page.tsx, whose comment
-- already states the rule ("build() must return a fresh query carrying the
-- caller's own scope"): the guest branch filters company_id, the auth'd
-- branch filters the customer set of this shop's company. No RPC touches it
-- (the one prosrc hit in propagate_price_log_to_orders is a comment).

drop index if exists idx_orders_shop_order_ref;

create unique index if not exists orders_company_shop_order_ref_uidx
  on public.orders (company_id, shop_order_ref)
  where shop_order_ref is not null;

do $$
begin
  -- The old index must be gone and the new one present. Both halves can fail,
  -- so this can report a real problem rather than only ever passing.
  if exists (select 1 from pg_indexes
             where schemaname = 'public' and indexname = 'idx_orders_shop_order_ref') then
    raise exception 'idx_orders_shop_order_ref still exists: the global uniqueness is still in force';
  end if;
  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and indexname = 'orders_company_shop_order_ref_uidx') then
    raise exception 'orders_company_shop_order_ref_uidx was not created';
  end if;
end $$;
