-- Verification for 20260906000001_counts_anchor_on_count_date — STAGING (demo tenant), rolled back.
-- Run: PGPASSWORD=$(security find-generic-password -s supabase-staging-db-pw -w) psql "<staging pooler url>" -f scripts/verify/20260906000001_counts_anchor_forward_tests.sql
-- Each scenario prints its expectation; (a) 50, (e) 50/90, (d) 50, (b) 30, (c) 40, (f) refused. Passed 2026-09-05.
-- Note: after 14:00 facility-local, running (d) AFTER a same-day count reproduces the pre-existing UTC-cast fallback defect (pass-3 #2) — hence its position.
-- Synthetic forward tests for 20260906000001 on STAGING (demo tenant), all in
-- one transaction that is ROLLED BACK. Times are facility-local (HST).
\set ON_ERROR_STOP on
begin;
set local search_path = public;
create temp table _t as select
  'demo-aloha-coffee-roasters'::text as co, 'demo-kailua-roastery'::text as fac, 'Pacific/Honolulu'::text as tz,
  (now() at time zone 'Pacific/Honolulu')::date as today;
-- origin + two lots (L1 older → FIFO first)
insert into coffee_inventory (origin_id, origin, facility_id, company_id, bag_size)
  select 'sim-anchor-test', 'SIM Anchor Test', fac, co, null from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, created_at, amount_manual)
  select 'sim-lot-1', 'sim-anchor-test', fac, co, 100, 100, 'baseline', false, 'L1', now() - interval '10 days', true from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, created_at, amount_manual)
  select 'sim-lot-2', 'sim-anchor-test', fac, co, 100, 100, 'baseline', false, 'L2', now() - interval '9 days', true from _t;
-- helper: a charged single-origin roast at a local time
create function pg_temp.mk_roast(p_id text, p_local timestamp, p_lbs numeric) returns void language plpgsql as $$
begin
  -- a roast_log trigger stamps roast_date to now() on insert; set the instant afterwards
  insert into roast_log (roast_log_id, company_id, facility_id, origin_id, "charged?", charge_weight, charge_weight_lbs, roast_date, roast_date_utc, created_at)
  select p_id, co, fac, 'sim-anchor-test', true, p_lbs::text, p_lbs, p_local, p_local at time zone tz, p_local at time zone tz from _t;
  update roast_log set roast_date = p_local, roast_date_utc = (select p_local at time zone tz from _t) where roast_log_id = p_id;
  if (select roast_date_utc from roast_log where roast_log_id = p_id) <> (select p_local at time zone tz from _t) then
    raise exception 'harness: roast time did not stick for %', p_id;
  end if;
end $$;
-- A: yesterday 17:00 (20 lb) ; B: today 09:00 (10 lb)
select pg_temp.mk_roast('sim-roast-A', (today - 1) + time '17:00', 20) from _t;
select pg_temp.mk_roast('sim-roast-B', today + time '09:00', 10) from _t;
select recompute_origin_lot_consumption('sim-anchor-test', fac) from _t;
select 'baseline (no counts): L1 expect 70, L2 100' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin='sim-anchor-test' order by 2;

-- (a) BACKDATE: at "2pm today" enter L1 = 60 dated YESTERDAY → B (today 09:00) replays → 50; A preserved pre-anchor.
select record_per_lot_count(fac, co, today - 1, '[{"origin_purchase_id":"sim-lot-1","counted_remaining_lbs":60}]'::jsonb, 'test') from _t;
select '(a) backdate: L1 expect 50 (old code 60); L2 expect 100' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin='sim-anchor-test' order by 2;
select '(a) sibling completion row for L2 (as-of anchor): expect 100' as step, origin_purchase_id, counted_remaining_lbs, count_date from coffee_lot_count where origin_purchase_id='sim-lot-2' order by created_at desc limit 1;

update coffee_lot_count set created_at = created_at - interval '1 minute' where origin_purchase_id like 'sim-lot-%';
-- (e) SIBLING DOUBLE-DEDUCT HAZARD: now count L2 = 90 dated YESTERDAY. L1 must stay 50 (as-of completion 60 → replay B → 50). Naive completion would give 40.
select record_per_lot_count(fac, co, today - 1, '[{"origin_purchase_id":"sim-lot-2","counted_remaining_lbs":90}]'::jsonb, 'test') from _t;
select '(e) sibling: L1 expect 50 (naive 40); L2 expect 90' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin='sim-anchor-test' order by 2;

-- (d) PRE-RECEIPT: shipment lot received TODAY; a count backdated 2 days must be excluded → lot re-seeds from amount (fallback).
insert into shipment_received (shipment_id, company_id, facility_id, date_received, status) select 'sim-ship-1', co, fac, today, 'received' from _t;
insert into coffee_inventory_purchased (origin_purchase_id, origin, facility_id, company_id, amount, remaining_lbs, entry_method, receipt_pending, lot_id, shipment_id, created_at, amount_manual)
  select 'sim-lot-3', 'sim-anchor-test', fac, co, 50, 50, 'shipment', false, 'L3', 'sim-ship-1', now(), true from _t;
insert into coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id)
  select 'sim-lot-3', today - 2, 7, co from _t;
select recompute_origin_lot_consumption('sim-anchor-test', fac) from _t;
select '(d) pre-receipt: L3 expect 50 (count of 7 excluded), not 7' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin_purchase_id='sim-lot-3';

-- (b) SAME-DAY: count L1 = 45 dated TODAY (anchor = now); roast C 15 lb one minute from now → 30; a roast at 08:00 today must NOT re-deduct.
select record_per_lot_count(fac, co, today, '[{"origin_purchase_id":"sim-lot-1","counted_remaining_lbs":45}]'::jsonb, null) from _t;
select pg_temp.mk_roast('sim-roast-C', (now() at time zone tz) + interval '1 minute', 15) from _t;
select pg_temp.mk_roast('sim-roast-D', today + time '08:00', 5) from _t;
select recompute_origin_lot_consumption('sim-anchor-test', fac) from _t;
select '(b) same-day: L1 expect 30 (C after count deducts; D before count does not)' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin='sim-anchor-test' order by 2;

-- (c) ORDERING: same-day count 40 entered an hour ago; backdated count 70 entered NOW (later). Latest-DATED must win → 40 (old code: count_at order → 70).
delete from coffee_lot_count where origin_purchase_id in ('sim-lot-1','sim-lot-2');
delete from roast_log where roast_log_id in ('sim-roast-C','sim-roast-D');
insert into coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id, count_at)
  select 'sim-lot-1', today, 40, co, now() - interval '1 hour' from _t;
insert into coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id, count_at)
  select 'sim-lot-1', today - 1, 70, co, now() from _t;
insert into coffee_lot_count (origin_purchase_id, count_date, counted_remaining_lbs, company_id, count_at)
  select 'sim-lot-2', today, 100, co, now() - interval '1 hour' from _t;
select recompute_origin_lot_consumption('sim-anchor-test', fac) from _t;
select '(c) ordering: L1 expect 40 (old code 70)' as step, origin_purchase_id, remaining_lbs from coffee_inventory_purchased where origin='sim-anchor-test' order by 2;

-- (f) CLOSED BOOKS: a count dated inside closed books is refused.
update companies set books_closed_through = (select today - 1 from _t) where company_id = 'demo-aloha-coffee-roasters';
savepoint sp_f;
do $$ begin
  perform record_per_lot_count('demo-kailua-roastery','demo-aloha-coffee-roasters', (now() at time zone 'Pacific/Honolulu')::date - 1, '[{"origin_purchase_id":"sim-lot-1","counted_remaining_lbs":1}]'::jsonb, null);
  raise exception 'FAIL: closed-books count was accepted';
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  raise notice '(f) closed books: refused as expected → %', sqlerrm;
end $$;
rollback to savepoint sp_f;
rollback;
