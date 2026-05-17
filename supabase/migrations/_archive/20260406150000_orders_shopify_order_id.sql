-- Add shopify_order_id to orders for idempotent webhook processing
alter table orders add column if not exists shopify_order_id text;

-- Unique per facility so the same Shopify order can't be imported twice
create unique index if not exists idx_orders_shopify_order_id
  on orders(facility_id, shopify_order_id)
  where shopify_order_id is not null;

-- Index for fast lookup on updates/cancellations
create index if not exists idx_orders_shopify_order_id_lookup
  on orders(shopify_order_id)
  where shopify_order_id is not null;
