-- Migration 00090: Add fallback cost columns for pre-history orders
--
-- Problem: This company has 5 years of order history (back to 2019) but
--          shipment cost data only goes back to June 2023. For orders placed
--          before any shipment was ever received, get_coffee_cost_on_date()
--          and get_consumable_cost_on_date() (added in 00091) have no price
--          to reference — leaving unit_cost_at_sale permanently at 0.
--
-- Fix: Add a user-enterable fallback cost per coffee origin and per
--      consumable item. If no shipment history exists at all, these values
--      become the last resort before leaving the cost as NULL (no update).
--
-- Usage: In AppSheet, expose these columns on the Coffee Inventory and
--        Consumable Inventory forms. Users enter a rough historical baseline
--        cost (e.g. "~$6.50/lb for Maui Sunrise before we started tracking").
--        The get_*_cost_on_date() functions (00091) fall back to these values
--        only after exhausting all shipment history lookups.

ALTER TABLE public.coffee_inventory
    ADD COLUMN IF NOT EXISTS fallback_cost numeric DEFAULT NULL;

ALTER TABLE public.consumable_inventory
    ADD COLUMN IF NOT EXISTS fallback_unit_cost numeric DEFAULT NULL;

COMMENT ON COLUMN public.coffee_inventory.fallback_cost IS
    'User-entered baseline cost ($/lb roasted, loss-adjusted) used when no shipment history exists for this origin. Last resort for backfilling pre-history orders.';

COMMENT ON COLUMN public.consumable_inventory.fallback_unit_cost IS
    'User-entered baseline cost per unit used when no shipment history exists for this consumable. Last resort for backfilling pre-history orders.';
