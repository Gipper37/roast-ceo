-- A pre-cutover invoice is not a receivable.
--
-- THE RULE THIS RESTORES. A QuickBooks-era document was always meant to sit at
-- `posted = false, invoice_state = NULL`. That is not a convention, it is how
-- the exclusion is MECHANISED: `invoice_ar_balances` -- the view behind the pay
-- page, the card terminal, the record-payment cap, the credit-memo cap, aging,
-- the dashboard and the register's balances -- is defined
-- `WHERE o.posted AND o.invoice_state IS NOT NULL`. An unposted document is
-- therefore invisible to every money surface at once, with no filter to add
-- anywhere and nothing to remember.
--
-- `apply_open_ar` broke that rule. It promoted imported history to
-- `posted = true, invoice_state = 'open'`, which is how 201 QuickBooks invoices
-- became live STRATA receivables. That function is dropped (20261103000004);
-- this undoes what it did.
--
-- AND THE CUTOVER DATE WAS WRONG. Maui Coffee Roasters' cutover_date says
-- 2026-07-06, the day they chose STRATA, but STRATA did not actually become
-- their invoicer until late October: 74 of the 80 invoices it has ever issued
-- for them are dated 2026-10-26 or later. The six issued before that date are
-- stragglers from the build period, and they are treated exactly like imported
-- history -- not collectable, not shown in A/R.
--
-- WHAT THIS DOES NOT DO. It does not void, delete or re-date anything, and it
-- does not touch a single line. Orders keep their lines, their totals, their
-- tax and their invoice numbers. REVENUE IS UNAFFECTED: customer_revenue,
-- customer_profitability, order_profitability and revenue_recognized key on
-- order_status / order_date / paid_at, never on `posted` or `invoice_state`.
-- The only thing these documents lose is the ability to be collected.
--
-- WHY IT IS SAFE TO UN-POST. Every trigger on `orders` that fires on a plain
-- UPDATE was read, not assumed:
--   * `guard_posted_order_immutable` locks customer_id, order_date, the six tax
--     columns, the three discount columns, invoice_number, invoice_sequence and
--     the nine bill_to_* columns. `posted`, `invoice_state`, `due_date` and
--     `is_legacy_import` are NOT among them, so this UPDATE is permitted.
--     invoice_number is deliberately left alone -- it IS locked, and keeping it
--     means finalize_invoice's not-null early return can never re-issue these.
--   * `guard_order_invoice_columns` refuses ANY is_legacy_import change after
--     insert ('Whether an order is imported history is fixed when it is
--     created'), for every caller regardless of permission -- but its first
--     line is `if auth.uid() is null then return new; end if`, and a migration
--     runs as postgres with no JWT (verified: auth.uid() is null, auth.role()
--     is empty). So this is a write only a migration can make, and one the app
--     can never undo. That is the intent: imported history is permanent.
--   * `trigger_update_order_metrics` is BEFORE INSERT OR UPDATE FOR EACH ROW
--     with no WHEN clause, so it WILL fire and re-derive four things. Measured
--     per column across all 209 rows rather than asserted in one breath:
--       - `order_total`: **0 of 209 change, net drift $0.00.** The stored total
--         already equals the sum of its lines' total_price exactly. A true
--         no-op, and the only one of the four.
--       - `total_weight`: **6 of 209 change, net +67.50 lbs.** All six are
--         `qbimp-` imports whose stored weight already disagreed with their own
--         lines (32→50, 11→20, 15.5→20, 53→80, 10.5→15, 5.5→10); the recompute
--         corrects them to the line truth. No view or matview reads
--         total_weight. Four functions name it -- calculate_shipment_totals_for,
--         calculate_shipping_per_unit, update_order_aggregates and
--         update_order_metrics itself -- and whether a future freight-per-unit
--         recalculation on these six historical orders would shift an
--         allocation is NOT traced here.
--       - `area`: **192 of 209 change, every one NULL -> value.** 0 nulled out,
--         0 changed from one value to another, so nothing is lost; it is a
--         fill-in from the customer's current sales_area.
--       - `customer_category`: 0 of 209 change.
--     None of the rows carries is_opening_balance, so no line-less stub is
--     clobbered.
--   * `update_customer_metrics_on_order` recomputes customer cadence from
--     orders filtered on order_status and is_opening_balance. It never reads
--     `posted` or `invoice_state`, so its output cannot move.
--   * `roast_plan_touch` queues one roast_plan_dirty row per facility per
--     order. That table's PK is a sequence, not facility_id, so 209 rows just
--     enqueue (one MCR facility) and the worker drains them.
--   * Two more BEFORE UPDATE FOR EACH ROW triggers have no `UPDATE OF` and no
--     WHEN clause, so they fire too, and both are no-ops here:
--     `trg_audit_update` (`handle_updated_record`) stamps `updated_at`, and
--     `trg_order_status_changed_at` (`set_order_status_changed_at`) guards its
--     whole body on `NEW.order_status IS DISTINCT FROM OLD.order_status`,
--     which is false in this statement.
--   * The triggers that really are `UPDATE OF` a column are
--     `trg_order_status_consumable_sync` and
--     `trg_sync_item_status_on_order_status` (order_status),
--     `trg_propagate_order_date` (order_date) and
--     `orders_payment_terms_available` (payment_terms). None of those columns
--     is in this SET list, so none of the four fires.
--   * `guard_demo_readonly` early-returns on a null uid, and MCR is not a demo.
--
-- AND IT CANNOT BE UNDONE BY THE CRON. `recompute_overdue_invoices` moves rows
-- only `WHERE invoice_state = 'open'` or `= 'overdue'`. A NULL state matches
-- neither, so the hourly sweep cannot re-stamp these.

begin;

-- 1. The date first, so the rule below reads the corrected line.
update public.billing_settings
   set cutover_date = date '2026-10-26',
       updated_at   = now()
 where company_id = '9ShiyDAXhV'
   and cutover_date is distinct from date '2026-10-26';

-- 2. Retire every posted invoice that predates its own company's cutover, and
--    mark it as carried-over history. Driven by each tenant's own cutover_date
--    rather than one tenant's values: a company with no cutover_date is
--    untouched. is_legacy_import is SET rather than tested, so the 201 that
--    already carry it and the handful that do not are retired by one rule.
do $$
declare v_n integer;
begin
  update public.orders o
     set posted           = false,
         invoice_state    = null,
         due_date         = null,
         is_legacy_import = true
    from public.billing_settings b
   where b.company_id     = o.company_id
     and b.cutover_date  is not null
     and o.order_date    is not null
     and o.order_date     < b.cutover_date
     and o.posted
     and o.invoice_state is not null;
  get diagnostics v_n = row_count;
  raise notice 'retired % pre-cutover invoice(s) to imported history', v_n;
end $$;

-- 3. The invariant this exists to establish: nothing posted may predate the
--    line. finalize_invoice already refuses to mint one; this asserts that
--    none survives.
do $$
declare v_left integer;
begin
  select count(*) into v_left
    from public.orders o
    join public.billing_settings b on b.company_id = o.company_id
   where b.cutover_date is not null
     and o.order_date is not null
     and o.order_date < b.cutover_date
     and o.posted
     and o.invoice_state is not null;
  if v_left <> 0 then
    raise exception 'still % posted invoice(s) dated before their company cutover', v_left;
  end if;
end $$;

commit;
