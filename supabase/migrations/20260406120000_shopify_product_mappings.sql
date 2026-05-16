create table if not exists shopify_product_mappings (
  id              uuid primary key default gen_random_uuid(),
  facility_id     text not null references facilities(facility_id) on delete cascade,
  company_id      text not null,
  shopify_variant_id   text not null,
  shopify_product_id   text not null,
  shopify_product_title text not null,
  shopify_variant_title text not null,
  product_id      text references products(product_id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (facility_id, shopify_variant_id)
);

create index idx_shopify_mappings_facility on shopify_product_mappings(facility_id);
create index idx_shopify_mappings_product  on shopify_product_mappings(product_id);
