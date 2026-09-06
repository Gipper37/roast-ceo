-- Prod rehearsal for a replay-function migration, fully ROLLED BACK: settles every MCR origin with the
-- current function, hashes ledger+stock per origin, applies the migration (own begin/commit stripped —
-- the DRY-RUN TRAP), replays again, and reports hash diffs. 2026-09-05: 23/23 identical for 20260906000001.
-- Run: sed 's/^begin;$//; s/^commit;$//' <migration> > /tmp/mig_norun.sql, then psql <prod> -f this file (it \\i's /tmp/mig_norun.sql).
\set ON_ERROR_STOP on
begin;
-- guard: no live roast right now
select count(*) as live_sessions from roast_sessions where started_at > now() - interval '30 minutes' and ended_at is null;
create temp table _pairs as
  select distinct cip.origin, cip.facility_id from coffee_inventory_purchased cip
   where cip.company_id = '9ShiyDAXhV' and cip.origin is not null;
select count(*) as mcr_origin_pairs from _pairs;
-- BEFORE: settle with the CURRENT function, then hash
select recompute_origin_lot_consumption(origin, facility_id) from _pairs;
create temp table _h_before as
  select p.origin, p.facility_id,
    md5(coalesce((select string_agg(rlc.roast_log_id||':'||rlc.origin_purchase_id||':'||round(rlc.lbs_consumed,4), ',' order by rlc.roast_log_id, rlc.origin_purchase_id)
                   from roast_log_lot_consumption rlc join coffee_inventory_purchased c using (origin_purchase_id)
                  where c.origin = p.origin and c.facility_id = p.facility_id), '')) as ledger,
    md5(coalesce((select string_agg(c.origin_purchase_id||':'||round(coalesce(c.remaining_lbs,-1),4), ',' order by c.origin_purchase_id)
                   from coffee_inventory_purchased c where c.origin = p.origin and c.facility_id = p.facility_id), '')) as stock
  from _pairs p;
\i /tmp/mig_norun.sql
-- AFTER: replay with the NEW function, then hash
select recompute_origin_lot_consumption(origin, facility_id) from _pairs;
create temp table _h_after as
  select p.origin, p.facility_id,
    md5(coalesce((select string_agg(rlc.roast_log_id||':'||rlc.origin_purchase_id||':'||round(rlc.lbs_consumed,4), ',' order by rlc.roast_log_id, rlc.origin_purchase_id)
                   from roast_log_lot_consumption rlc join coffee_inventory_purchased c using (origin_purchase_id)
                  where c.origin = p.origin and c.facility_id = p.facility_id), '')) as ledger,
    md5(coalesce((select string_agg(c.origin_purchase_id||':'||round(coalesce(c.remaining_lbs,-1),4), ',' order by c.origin_purchase_id)
                   from coffee_inventory_purchased c where c.origin = p.origin and c.facility_id = p.facility_id), '')) as stock
  from _pairs p;
select count(*) as pairs, count(*) filter (where b.ledger = a.ledger and b.stock = a.stock) as identical,
       count(*) filter (where b.ledger <> a.ledger) as ledger_diffs, count(*) filter (where b.stock <> a.stock) as stock_diffs
  from _h_before b join _h_after a using (origin, facility_id);
select b.origin, b.ledger <> a.ledger as ledger_changed, b.stock <> a.stock as stock_changed
  from _h_before b join _h_after a using (origin, facility_id)
 where b.ledger <> a.ledger or b.stock <> a.stock limit 20;
-- new RPC exists + ACL
select proname, proacl from pg_proc where proname = 'record_per_lot_count';
rollback;
