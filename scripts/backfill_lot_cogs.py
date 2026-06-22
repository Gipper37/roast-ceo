#!/usr/bin/env python3
"""
Backfill lot-precise COGS for a company (default MCR).

  Phase A — replay the FIFO lot ledger: recompute_origin_lot_consumption(origin,
            facility) for every origin with charged roasts. The triggers from
            migrations 20260621000002/3 then value each roast (green_cost,
            roasted_cost_lb) and refresh coffee_inventory.latest_roasted_cost.
  Phase C — re-stamp order_details.unit_cost_at_sale via backfill_order_unit_costs
            (now lot-precise, since get_product_cogs_on_date was repointed).

REQUIRES migrations 20260621000002 + 20260621000003 LIVE on the target DB,
otherwise Phase A leaves the ledger unvalued and Phase C uses the old group cost.

DRY-RUN by default: runs everything inside a transaction and ROLLS BACK, printing
a before/after diff. Nothing persists. Use --apply to COMMIT (types a confirm).

Usage:
  python3 scripts/backfill_lot_cogs.py                 # dry-run on prod
  python3 scripts/backfill_lot_cogs.py --apply         # apply on prod (confirm)
  DBURL=... python3 scripts/backfill_lot_cogs.py       # dry-run on a custom URL
"""
import os, sys, subprocess

PSQL_BIN = "/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql"
PROD_URL = "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
PROD_REF = "pwpslalerytymorcodlv"
COMPANY  = "9ShiyDAXhV"
FACILITY = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"

def _prod_pw():
    # keychain (same entry db-push.sh uses), env fallback — never hardcoded
    import shutil
    pw = os.environ.get("SUPABASE_PROD_DB_PASSWORD", "")
    if pw:
        return pw
    try:
        return subprocess.check_output(
            ["security", "find-generic-password", "-s", "supabase-prod-db-pw", "-w"],
            text=True).strip()
    except Exception:
        return ""

APPLY = "--apply" in sys.argv
DBURL = os.environ.get("DBURL", PROD_URL)
PGPW  = os.environ.get("PGPASSWORD") or (_prod_pw() if DBURL == PROD_URL else "")

METRICS = f"""
SELECT 'roasts_charged'      AS metric, count(*)::text v FROM roast_log WHERE facility_id='{FACILITY}' AND "charged?"=true
UNION ALL SELECT 'roasts_with_ledger',  count(DISTINCT roast_log_id)::text FROM roast_log_lot_consumption rlc WHERE roast_log_id IN (SELECT roast_log_id FROM roast_log WHERE facility_id='{FACILITY}')
UNION ALL SELECT 'ledger_rows',         count(*)::text FROM roast_log_lot_consumption rlc JOIN roast_log rl ON rl.roast_log_id=rlc.roast_log_id WHERE rl.facility_id='{FACILITY}'
UNION ALL SELECT 'roasts_valued',       count(*)::text FROM roast_log WHERE facility_id='{FACILITY}' AND green_cost IS NOT NULL
UNION ALL SELECT 'origins_w_roastcost', count(*)::text FROM coffee_inventory WHERE facility_id='{FACILITY}' AND latest_roasted_cost IS NOT NULL
UNION ALL SELECT 'order_lines',         count(*)::text FROM order_details WHERE company_id='{COMPANY}'
UNION ALL SELECT 'zero_cost_lines',     count(*)::text FROM order_details WHERE company_id='{COMPANY}' AND COALESCE(unit_cost_at_sale,0)=0
UNION ALL SELECT 'total_cogs_stamped',  COALESCE(round(SUM(unit_cost_at_sale)::numeric,2),0)::text FROM order_details WHERE company_id='{COMPANY}'
;"""

def phase_sql(final):
    # final = 'ROLLBACK' (dry-run) or 'COMMIT' (apply)
    return f"""
\\set ON_ERROR_STOP on
\\timing off
BEGIN;
\\echo '======== BEFORE ========'
{METRICS}
-- Phase A: replay the FIFO ledger per origin (triggers value + cache-refresh)
DO $$
DECLARE o text;
BEGIN
  FOR o IN SELECT DISTINCT origin_id FROM public.roast_log
            WHERE facility_id='{FACILITY}' AND "charged?"=true AND origin_id IS NOT NULL
  LOOP
    PERFORM public.recompute_origin_lot_consumption(o, '{FACILITY}');
  END LOOP;
END $$;
-- Phase C: re-stamp order COGS lot-precise
SELECT public.backfill_order_unit_costs(NULL, NULL, '{FACILITY}') AS order_lines_restamped;
\\echo '======== AFTER ========'
{METRICS}
-- sample of newly-costed lines (were $0, now > 0)
\\echo '-- sample newly-costed lines --'
SELECT od.order_detail_id, p.product_name, od.quantity, round(od.unit_cost_at_sale::numeric,2) AS line_cost
FROM order_details od JOIN products p ON p.product_id=od.product_id
WHERE od.company_id='{COMPANY}' AND od.unit_cost_at_sale > 0
ORDER BY od.updated_at DESC LIMIT 8;
{final};
"""

def run(sql):
    env = {**os.environ, "PGPASSWORD": PGPW}
    p = subprocess.run([PSQL_BIN, DBURL, "-v", "ON_ERROR_STOP=1", "-f", "-"],
                       input=sql, text=True, env=env)
    return p.returncode

def main():
    tgt = "PROD" if DBURL == PROD_URL else DBURL
    print(f"target: {tgt}   mode: {'APPLY (commit)' if APPLY else 'DRY-RUN (rollback)'}")
    print("NOTE: requires migrations 20260621000002 + 20260621000003 live on target.\n")
    if APPLY:
        if DBURL == PROD_URL:
            ans = input(f"Type the project ref '{PROD_REF}' to APPLY to prod: ").strip()
            if ans != PROD_REF:
                print("aborted."); return
        rc = run(phase_sql("COMMIT"))
    else:
        rc = run(phase_sql("ROLLBACK"))
    sys.exit(rc)

if __name__ == "__main__":
    main()
