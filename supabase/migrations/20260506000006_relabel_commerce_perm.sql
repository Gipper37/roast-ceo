-- Relabel config.shopify → "Configure commerce integrations".
--
-- The Commerce sub-tab of Integrations covers more than Shopify
-- (QuickBooks live on the same page; Square / Lightspeed / future
-- accounting connectors will land here too). The permission_id stays
-- `config.shopify` for backward-compat with all the Phase B server
-- actions calling requirePermission('config.shopify') — only the
-- user-facing label and description change. Future commerce connectors
-- will reuse the same key rather than mint per-vendor permissions.

UPDATE permissions
SET label       = 'Configure commerce integrations',
    description = 'Shopify, QuickBooks, and other commerce connectors on the Integrations → Commerce sub-tab. Includes order sync, product sync, and accounting-side mappings.'
WHERE permission_id = 'config.shopify';
