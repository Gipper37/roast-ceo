-- Migration 00207: Shopify Integration Phase 1 — Connection & OAuth
-- Creates shopify_connections table for storing per-facility Shopify OAuth tokens.

CREATE TABLE shopify_connections (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      text NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
  facility_id     text NOT NULL REFERENCES facilities(facility_id) ON DELETE CASCADE,
  shop_domain     text NOT NULL,          -- e.g. "roaster-co.myshopify.com"
  access_token    text NOT NULL,          -- encrypted at rest (Supabase vault / env-level encryption)
  webhook_secret  text NOT NULL,          -- HMAC-SHA256 secret for webhook verification
  auto_accept     boolean NOT NULL DEFAULT false,
  is_active       boolean NOT NULL DEFAULT true,
  connected_at    timestamptz NOT NULL DEFAULT now(),
  connected_by    text,                   -- user email who connected
  UNIQUE(facility_id)                     -- one Shopify store per facility
);

CREATE INDEX idx_shopify_connections_company   ON shopify_connections(company_id);
CREATE INDEX idx_shopify_connections_domain    ON shopify_connections(shop_domain);

COMMENT ON TABLE shopify_connections IS 'Per-facility Shopify OAuth connections for STRATA integration';
COMMENT ON COLUMN shopify_connections.shop_domain    IS 'myshopify.com subdomain, e.g. roaster-co.myshopify.com';
COMMENT ON COLUMN shopify_connections.access_token   IS 'Shopify offline access token — store encrypted';
COMMENT ON COLUMN shopify_connections.webhook_secret IS 'Random secret used to verify HMAC-SHA256 webhook signatures';
COMMENT ON COLUMN shopify_connections.auto_accept    IS 'When true, incoming orders with all variants mapped auto-create in STRATA';
