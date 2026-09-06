-- Verification for 20260906000002_here_first_lots_counts_are_truth — STAGING (demo tenant), rolled back.
-- Run like 20260906000001_counts_anchor_forward_tests.sql. Passed 2026-09-05: (h) attach-to-unreceived keeps stock + receives order,
-- (i) void releases the lot to the queue, (k) receipt dated after a here-first count keeps the count, (j) June-30 protection,
-- (l) duplicate question on edit + confirm, (m) dismissed lot matched, (o) atomic merge + refusal, (n) roast_detail component filter. Round 2 adds (q) unchanged re-save + blank-lot reorder, (r) void with post-anchor roasts, (s) attach warning.
-- Forward tests for 20260906000002 on STAGING (demo tenant), one transaction, ROLLED BACK.
\set ON_ERROR_STOP on
begin;
create temp table _t as select 'demo-aloha-coffee-roasters'::text as co, 'demo-kailua-roastery'::text as fac, 'Pacific/Honolulu'::text as tz, (now() at time zone 'Pacific/Honolulu')::date as today;
insert into coffee_inventory (origin_id, origin, facility_id, company_id) select 'sim-hf-test','SIM HF',fac,co from _t;
insert into coffee_source (coffee_source_id, coffee_name, origin_id, company_id, bag_size) select 'sim-src-hf', 'SIM Source HF', 'sim-hf-test', co, '100' from _t;

-- (h) here-first counted lot recorded INTO an unreceived order → order becomes received, stock intact
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, amount_manual)
  select 'hf-lot-1','sim-hf-test',fac,co,100,100,'roast_quick_add',true,'HF1','sim-src-hf',true from _t;
select '(h) trigger stamped here_first: expect t' as step, here_first from coffee_inventory_purchased where origin_purchase_id='hf-lot-1';
select record_per_lot_count(fac, co, today, '[{"origin_purchase_id":"hf-lot-1","counted_remaining_lbs":100}]'::jsonb, null) from _t;
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date) select 'hf-ship-1', co, fac, 'po_sent', false, today from _t;
select record_lot_receipt('hf-lot-1', 4.25, null, today, 0, 'hf-ship-1', false, 1) from _t;
select '(h) order received? expect date today / status received' as step, date_received, status from shipment_received where shipment_id='hf-ship-1';
select recompute_origin_lot_consumption('sim-hf-test', fac) from _t;
select '(h) stock intact: expect 100 (old code: NULL — blanked)' as step, remaining_lbs, here_first, receipt_pending from coffee_inventory_purchased where origin_purchase_id='hf-lot-1';

-- (i) voiding that order releases the lot: back in the queue, detached, stock intact
update shipment_received set voided = true where shipment_id='hf-ship-1';
select '(i) after void: expect receipt_pending t, shipment null, remaining 100' as step, receipt_pending, shipment_id, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='hf-lot-1';
select recompute_origin_lot_consumption('sim-hf-test', fac) from _t;
select '(i) after replay: expect 100' as step, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='hf-lot-1';

-- (k) here-first lot: count dated YESTERDAY, receipt recorded dated TODAY (confirmed) → count still truth
delete from coffee_lot_count where origin_purchase_id='hf-lot-1';
select record_per_lot_count(fac, co, today - 1, '[{"origin_purchase_id":"hf-lot-1","counted_remaining_lbs":80}]'::jsonb, null) from _t;
select '(k) warning without confirm: expect received_after_count' as step, (record_lot_receipt('hf-lot-1', 4.25, null, today, 0, null, false, 1))->>'warning' from _t;
select '(k) confirmed:' as step, (record_lot_receipt('hf-lot-1', 4.25, null, today, 0, null, true, 1))->>'ok' from _t;
select recompute_origin_lot_consumption('sim-hf-test', fac) from _t;
select '(k) count stays truth: expect 80 (old code: 100 — count excluded, amount used)' as step, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='hf-lot-1';

-- (j) paperwork-first lot "counted" at 0 while at sea, then received → June-30 protection: amount
insert into coffee_inventory (origin_id, origin, facility_id, company_id) select 'sim-pf-test','SIM PF',fac,co from _t;
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date) select 'pf-ship-1', co, fac, 'po_sent', false, today - 20 from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, shipment_id, amount_manual)
  select 'pf-lot-1','sim-pf-test',fac,co,500,null,'shipment',false,'PF1','pf-ship-1',true from _t;
select '(j) paperwork-first: expect here_first f' as step, here_first from coffee_inventory_purchased where origin_purchase_id='pf-lot-1';
insert into coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id, count_at) select 'pf-lot-1', today - 3, 0, co, now() - interval '3 days' from _t;
update shipment_received set date_received = (select today from _t), status = 'received' where shipment_id='pf-ship-1';
select recompute_origin_lot_consumption('sim-pf-test', fac) from _t;
select '(j) received: expect 500 (the at-sea zero is ignored)' as step, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='pf-lot-1';

-- (l) duplicate question on EDIT: a recorded line renamed to a lot # already waiting → raises; confirmable
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date, date_received) select 'hf-ship-2', co, fac, 'received', false, today, today from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, shipment_id, amount_manual)
  select 'hf-line-1','sim-hf-test',fac,co,200,200,'shipment',false,'X1','sim-src-hf','hf-ship-2',true from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, amount_manual)
  select 'hf-pend-1','sim-hf-test',fac,co,100,100,'roast_quick_add',true,'DUP','sim-src-hf',true from _t;
savepoint sp_l;
do $$ begin
  update coffee_inventory_purchased set lot_id = 'DUP' where origin_purchase_id = 'hf-line-1';
  raise exception 'FAIL: edit to a pending lot # was not questioned';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  raise notice '(l) edit questioned as expected → %', left(sqlerrm, 60);
end $$;
rollback to savepoint sp_l;
select set_config('app.allow_duplicate_lot', 'true', true);
update coffee_inventory_purchased set lot_id = 'DUP' where origin_purchase_id = 'hf-line-1';
select '(l) confirmed edit went through: expect DUP' as step, lot_id from coffee_inventory_purchased where origin_purchase_id='hf-line-1';
select set_config('app.allow_duplicate_lot', '', true);

-- (m) a DISMISSED lot still on hand is matched by the question
update coffee_inventory_purchased set receipt_pending = false, receipt_dismissed_at = now() where origin_purchase_id = 'hf-pend-1';   -- dismissed
savepoint sp_m;
do $$ begin
  insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, shipment_id, amount_manual)
    values ('hf-line-2','sim-hf-test','demo-kailua-roastery','demo-aloha-coffee-roasters',100,null,'shipment',false,'DUP','sim-src-hf','hf-ship-2',true);
  raise exception 'FAIL: dismissed lot was not matched';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  raise notice '(m) dismissed lot matched as expected → %', left(sqlerrm, 60);
end $$;
rollback to savepoint sp_m;

-- (o) merge in one transaction: keeper (pending, counted 60) + duplicate line (amount 60, no stock) on an UNRECEIVED order
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date) select 'hf-ship-3', co, fac, 'po_sent', false, today from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, amount_manual)
  select 'hf-keep','sim-hf-test',fac,co,60,60,'roast_quick_add',true,'M1','sim-src-hf',true from _t;
select record_per_lot_count(fac, co, today - 2, '[{"origin_purchase_id":"hf-keep","counted_remaining_lbs":60}]'::jsonb, null) from _t;
select set_config('app.allow_duplicate_lot', 'true', true);
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, shipment_id, cost_lb, amount_manual)
  select 'hf-dup','sim-hf-test',fac,co,60,null,'shipment',false,'M1','sim-src-hf','hf-ship-3',5.10,true from _t;
select set_config('app.allow_duplicate_lot', '', true);
select '(o) merge:' as step, merge_lot_into_shipment_line('hf-keep', 'hf-dup')->>'ok';
select '(o) keeper on order w/ cost, dup gone, order received on count date: expect hf-ship-3 / 5.10 / 0 / today-2' as step,
       k.shipment_id, k.cost_lb, (select count(*) from coffee_inventory_purchased where origin_purchase_id='hf-dup') as dup_rows, s.date_received
  from coffee_inventory_purchased k join shipment_received s on s.shipment_id = k.shipment_id where k.origin_purchase_id='hf-keep';
select recompute_origin_lot_consumption('sim-hf-test', fac) from _t;
select '(o) keeper stock intact: expect 60' as step, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='hf-keep';
savepoint sp_o;
do $$ begin
  perform merge_lot_into_shipment_line('hf-keep', 'hf-line-1');
  raise exception 'FAIL: merge accepted a line with stock';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  raise notice '(o) refusal as expected → %', left(sqlerrm, 70);
end $$;
rollback to savepoint sp_o;


-- (q) a saved line re-asserting its UNCHANGED key must not re-ask (UPDATE OF fires even when unchanged)
update coffee_inventory_purchased set receipt_pending = true, receipt_dismissed_at = null where origin_purchase_id = 'hf-pend-1';   -- pending again, lot DUP
select set_config('app.allow_duplicate_lot', 'true', true);
update coffee_inventory_purchased set lot_id = 'DUP' where origin_purchase_id = 'hf-line-1';   -- confirmed coexisting duplicate
select set_config('app.allow_duplicate_lot', '', true);
update coffee_inventory_purchased set lot_id = 'DUP', coffee_source_id = 'sim-src-hf' where origin_purchase_id = 'hf-line-1';   -- same key re-saved: no question
select '(q) unchanged re-save passed: expect DUP' as step, lot_id from coffee_inventory_purchased where origin_purchase_id='hf-line-1';
-- a blank-lot PO line for a source that has a DISMISSED lot is a normal reorder (pending only blocks blank lots)
update coffee_inventory_purchased set receipt_pending = false, receipt_dismissed_at = now() where origin_purchase_id = 'hf-pend-1';
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, shipment_id, amount_manual)
  select 'hf-line-3','sim-hf-test',fac,co,100,null,'shipment',false,'','sim-src-hf','hf-ship-2',true from _t;
select '(q) blank-lot reorder with a dismissed lot on hand: expect 1 row (no question)' as step, count(*) from coffee_inventory_purchased where origin_purchase_id='hf-line-3';

-- (r) here-first lot with roasts after its count, on a shipment that gets VOIDED: no double deduction
insert into coffee_inventory (origin_id, origin, facility_id, company_id) select 'sim-hf2','SIM HF2',fac,co from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, amount_manual, created_at)
  select 'hf2-lot','sim-hf2',fac,co,100,100,'roast_quick_add',true,'R1',true, now() - interval '5 days' from _t;   -- FIFO never charges a roast dated before the lot existed
select record_per_lot_count(fac, co, today - 2, '[{"origin_purchase_id":"hf2-lot","counted_remaining_lbs":100}]'::jsonb, null) from _t;
insert into roast_log (roast_log_id, company_id, facility_id, origin_id, "charged?", charge_weight, charge_weight_lbs, roast_date, roast_date_utc, created_at)
  select 'hf2-roast', co, fac, 'sim-hf2', true, '30', 30, (today - 1) + time '10:00', ((today - 1) + time '10:00') at time zone tz, ((today - 1) + time '10:00') at time zone tz from _t;
update roast_log set roast_date = (select (today - 1) + time '10:00' from _t), roast_date_utc = (select ((today - 1) + time '10:00') at time zone tz from _t) where roast_log_id = 'hf2-roast';
select recompute_origin_lot_consumption('sim-hf2', fac) from _t;
select '(r) before void: expect 70' as step, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='hf2-lot';
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date, date_received) select 'hf2-ship', co, fac, 'received', false, today, today - 2 from _t;
select record_lot_receipt('hf2-lot', 3.0, null, today - 2, 0, 'hf2-ship', true, 1) from _t;
update shipment_received set voided = true where shipment_id = 'hf2-ship';
select recompute_origin_lot_consumption('sim-hf2', fac) from _t;
select '(r) after void + replay: expect 70 (double deduction would give 40)' as step, remaining_lbs, receipt_pending, shipment_id from coffee_inventory_purchased where origin_purchase_id='hf2-lot';

-- (s) recording INTO an order that already has a stock-less line for this coffee warns; confirm proceeds
insert into shipment_received (shipment_id, company_id, facility_id, status, voided, order_date) select 'hf-ship-4', co, fac, 'po_sent', false, today from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, shipment_id, amount_manual)
  select 'hf-line-4','sim-hf-test',fac,co,100,null,'shipment',false,'ORD1','sim-src-hf','hf-ship-4',true from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, coffee_source_id, amount_manual)
  select 'hf-pend-4','sim-hf-test',fac,co,100,100,'roast_quick_add',true,'','sim-src-hf',true from _t;
select '(s) warning: expect same_coffee_on_order' as step, (record_lot_receipt('hf-pend-4', 4.0, null, today, 0, 'hf-ship-4', false, 1))->>'warning' from _t;
select '(s) confirmed:' as step, (record_lot_receipt('hf-pend-4', 4.0, null, today, 0, 'hf-ship-4', true, 1))->>'ok' from _t;
select '(s) order received now: expect today' as step, date_received from shipment_received where shipment_id='hf-ship-4';

-- (n) roast_detail: component-tagged counts must not double-count or leak
insert into roast_stock_log (stock_log_id, stock_type, origin_id, facility_id, company_id, lbs_in_stock) select 'rsl-o', 'origin', 'demo-org-11', fac, co, 100 from _t;
insert into roast_stock_log (stock_log_id, stock_type, blend_id, facility_id, company_id, lbs_in_stock) select 'rsl-b', 'blend', 'demo-rcp-9', fac, co, 60 from _t;   -- 33% demo-org-11 → 19.8 ; 67% demo-org-9 → 40.2
insert into roast_stock_log (stock_log_id, stock_type, blend_id, origin_id, facility_id, company_id, lbs_in_stock) select 'rsl-c', 'component', 'demo-rcp-9', 'demo-org-11', fac, co, 30 from _t;
select '(n) in_stock_roasted demo-org-11: expect 119.8 (100 + 60×0.33); old view 100+30+19.8+9.9 = 159.7' as step, round(in_stock_roasted, 1) as org11
  from roast_detail where origin = 'demo-org-11' and facility_id = 'demo-kailua-roastery';
select '(n) sibling demo-org-9: expect 40.2 (no leak; old view +20.1)' as step, round(in_stock_roasted, 1) as org9
  from roast_detail where origin = 'demo-org-9' and facility_id = 'demo-kailua-roastery';
rollback;
