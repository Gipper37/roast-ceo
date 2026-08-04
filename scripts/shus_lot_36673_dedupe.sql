-- Social Hour USA (R7CbqHmA1j) — lot 36673 recorded twice.
--
-- WHAT HAPPENED
--   2026-07-10  PO-2026-002 drafted: 92 bags Costa Rica West Valley Palmares
--               SHB, lot 36673, 152 lb bags, $4.1634/lb.
--               origin_purchase_id 6edb206c-e155-479b-86b3-5f7c932479b3
--   ~late Jul   The coffee arrived. The draft was never received — at the time
--               there was NO WAY to receive a Purchase Draft (fixed 2026-08-03,
--               commit 5d4321a).
--   2026-07-30  Operator needed it to roast, so they used Quick Receive in the
--               roast logger: entry_method='roast_quick_add', no cost, and —
--               the actual bug — receipt_pending = FALSE.
--               origin_purchase_id 5acd8be5-7fca-478e-a75a-408c039a03e8
--   since       33 roasts, ~759 lbs, every one booked at zero green cost.
--
-- WHY IT COULD NEVER SELF-CORRECT
--   "Receipts to record" is `receipt_pending = true AND remaining_lbs > 0`
--   (inventory/page.tsx). addSourceLot — the floor-count path — sets that flag.
--   addQuickReceiveLot never did, so a quick-add was invisible to the queue and
--   record_lot_receipt refused it outright: "lot has no pending receipt to
--   record". Two doors meaning the same thing, one wired to the queue.
--   Code fix: addQuickReceiveLot now sets receipt_pending = true.
--
-- SCOPE — 36673 is the only one:
--   · The other two lines on PO-2026-002 (38664 Honduras, 38567 Mexico Decaf)
--     appear exactly once each, on the draft only.
--   · Tenant scan for a lot on both an unreceived shipment and a separate row:
--     this lot alone.
--   · Tenant scan for live roast_quick_add lots with no cost: this lot alone.
--
-- THIS SCRIPT ONLY UNBLOCKS THE UI. It sets the flag the quick-add should have
-- had. Nothing else — receipt_pending is read by exactly two DB functions
-- (guard_duplicate_pending_receipt, record_lot_receipt) and by no stock or FIFO
-- function, so the lot's stock and roast history are untouched.
--
-- THEN FINISH IT IN THE APP, which is safer than SQL because the shipped code
-- path does the bookkeeping:
--   1. Inventory → Orders & Shipments → PO-2026-002 → Edit Shipment.
--   2. "Receipts to record (1)" now lists lot 36673. Pull it in, cost $4.1634,
--      supplier Royal Coffee. record_lot_receipt attaches it to the shipment,
--      sets the cost and LEAVES remaining_lbs alone — the 33 roasts survive, and
--      trg_revalue_roasts_on_cost_change recosts them (~$3,160, dry-run verified).
--   3. Remove the original 92-bag draft line in the same modal — that is the
--      duplicate. PO-2026-002 is then Fruit (9) + Decaf (9), both still on order.
--
-- Worth confirming with the roaster that Fruit + Decaf really are still coming;
-- they were ordered 2026-07-10.
--
-- DRY RUN: no COMMIT in this file. Wrap it —
--   begin; \i shus_lot_36673_dedupe.sql   <then rollback; or commit;>

update coffee_inventory_purchased
set receipt_pending = true
where origin_purchase_id = '5acd8be5-7fca-478e-a75a-408c039a03e8'
  and company_id = 'R7CbqHmA1j'
  and lot_id = '36673'
  and entry_method = 'roast_quick_add'
  and shipment_id is null
  and coalesce(remaining_lbs, 0) > 0
  and receipt_pending = false;   -- no-op if already done

-- Expect 1 row, receipt_pending now true, stock and roasts unchanged.
select origin_purchase_id, lot_id, shipment_id, receipt_pending,
       bags_ordered, remaining_lbs, cost_lb, entry_method
from coffee_inventory_purchased
where company_id = 'R7CbqHmA1j' and lot_id = '36673';

-- ── Optional: same backfill for every other tenant ────────────────────────
-- Any live quick-add lot never attached to a shipment belongs in the queue.
-- Run the SELECT first and look at what it catches before running the UPDATE.
--
-- select company_id, facility_id, lot_id, bags_ordered, remaining_lbs,
--        created_at::date
--   from coffee_inventory_purchased
--  where entry_method = 'roast_quick_add' and shipment_id is null
--    and coalesce(remaining_lbs,0) > 0 and receipt_pending = false
--  order by company_id, created_at;
--
-- update coffee_inventory_purchased set receipt_pending = true
--  where entry_method = 'roast_quick_add' and shipment_id is null
--    and coalesce(remaining_lbs,0) > 0 and receipt_pending = false;
