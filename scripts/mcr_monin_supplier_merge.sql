-- Merge MCR's two Monin suppliers into one, named "Monin".
--
-- BEFORE: the QuickBooks import created a supplier per INVOICE, so the same
-- vendor arrived twice —
--   mcr-sup-monin---inv-i25  "Monin - INV I25"   8 consumables, 1 shipment
--   mcr-sup-monin---inv-i26  "Monin - INV I26"  19 consumables, 1 shipment
-- 27 distinct syrups split across two vendors that are the same company, and an
-- invoice number showing up in the supplier picker.
--
-- AFTER: one supplier "Monin" carrying all 27 items and both shipments.
--
-- NO ITEM COLLIDES. The two sets are disjoint (i25 = Coconut, Hibiscus, Lychee,
-- Raspeberry, Salted Caramel, SF Caramel, Toffee Nut, Ube; i26 = the other 19),
-- so this is a repoint, not a deduplicate. No stock is summed, moved or lost —
-- every row keeps its own in_stock, cost and history and only changes which
-- supplier it hangs from.
--
-- SURVIVOR is i25 purely because it sorts first. The supplier_id keeps its old
-- "inv-i25" spelling: it is an opaque key, never shown, and renaming a primary
-- key would mean rewriting every referencing row for a cosmetic gain.
--
-- consumable_inventory.supplier_id carries no FK constraint (only
-- coffee_inventory, coffee_inventory_purchased, coffee_source and
-- shipment_received do), which is exactly why it has to be repointed explicitly
-- rather than trusted to cascade.
--
-- Snapshot of the prior state: scripts/mcr_monin_merge_snapshot_2026-08-13.tsv
--
-- ⚠️ NO COMMIT IN THIS FILE — deliberately. A file carrying its own `commit;`
-- cannot be dry-run with BEGIN; \i file; ROLLBACK; because the inner COMMIT ends
-- the outer transaction and the changes land. Wrap this yourself.

\set survivor '''mcr-sup-monin---inv-i25'''
\set loser    '''mcr-sup-monin---inv-i26'''

-- 1. The survivor becomes plainly "Monin".
update supplier
   set supplier = 'Monin', updated_at = now()
 where supplier_id = :survivor
   and company_id = '9ShiyDAXhV';

-- 2. Items move across.
update consumable_inventory
   set supplier_id = :survivor, updated_at = now()
 where supplier_id = :loser;

-- 3. Received shipments move with them, so purchase history stays attached to
--    the vendor rather than to an invoice number.
update shipment_received
   set supplier_id = :survivor
 where supplier_id = :loser;

-- 4. The duplicate goes. Safe only because steps 2-3 left nothing pointing at
--    it; the verification below is what proves that before the delete.
delete from supplier
 where supplier_id = :loser
   and company_id = '9ShiyDAXhV';

-- ── Verification ─────────────────────────────────────────────────────────────
-- Expect: one supplier row named Monin, 27 consumables, 2 shipments, 0 orphans.
select 'suppliers named monin' as check, count(*)::text as value
  from supplier where company_id='9ShiyDAXhV' and supplier ilike '%monin%'
union all
select 'survivor name', supplier from supplier where supplier_id = :survivor
union all
select 'consumables on survivor', count(*)::text
  from consumable_inventory where supplier_id = :survivor
union all
select 'shipments on survivor', count(*)::text
  from shipment_received where supplier_id = :survivor
union all
select 'anything still on the loser', (
    (select count(*) from consumable_inventory where supplier_id = :loser)
  + (select count(*) from shipment_received     where supplier_id = :loser)
  + (select count(*) from coffee_inventory      where supplier_id = :loser)
  + (select count(*) from coffee_source         where supplier_id = :loser)
  + (select count(*) from staged_shipments      where supplier_id = :loser)
)::text;
