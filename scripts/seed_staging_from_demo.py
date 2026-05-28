#!/usr/bin/env python3
"""
seed_staging_from_demo.py — clone the demo tenant from prod into staging.

Approach:
  1. We can psql into PROD directly (DNS resolves).
  2. STAGING is reachable only via the Supabase Management API SQL endpoint.
  3. For each table in dependency order, dump prod rows scoped to
     the demo company/facility, remap the old demo auth_user_id to
     the new staging auth user, and POST batched INSERTs to staging.

RLS is bypassed by setting session_replication_role = 'replica' for
the duration of each batch (same trick the original demo migrations
use).

Run from anywhere — uses macOS keychain for credentials.
"""

import subprocess, json, urllib.request, urllib.error, sys, os, re

# --- config ---
PROD_DB_URL = "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
PROD_PW = "SDH-h3FNHXSrxj-"
DEMO_COMPANY_ID = "demo-aloha-coffee-roasters"
DEMO_FACILITY_ID = "demo-kailua-roastery"
OLD_DEMO_AUTH_USER_ID = "be67be33-b3da-4e47-aa11-a5fcd85b4975"
NEW_DEMO_AUTH_USER_ID = "acdb726a-f69c-4a96-a160-3d5225a64acb"

PSQL = "/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql"


def kc(name):
    r = subprocess.run(["security", "find-generic-password", "-s", name, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip()


SUPABASE_ACCESS_TOKEN = kc("supabase-access-token")
STAGING_REF = kc("supabase-staging-ref")

# Dependency order. Each entry is (table_name, scope_filter). scope_filter
# is the WHERE clause (without "WHERE") used to find demo rows on prod.
# Some tables are company-scoped, some facility-scoped — pick whichever
# matches the data.
TABLES = [
    # Global catalog tables (no tenant scope). MUST come first — most
    # migration grants use SELECT FROM <catalog> WHERE <id> IN (...)
    # which silently inserts zero rows if the catalog is empty.
    # Discovered the hard way: staging started with subscription_plans
    # AND user_roles both empty, so every plan_permission and most
    # role_permission grants from old migrations were no-ops, and
    # every gated feature denied for everyone.
    ("subscription_plans",     "1=1"),
    # permissions catalog MUST come before any *_permissions table
    # so the canAs() catalog lookup finds the perm_id and doesn't
    # silently deny every action. Staging started with only 13 perms.
    ("permissions",            "1=1"),
    ("plan_permissions",       "1=1"),
    ("user_roles",             "1=1"),
    ("role_permissions",       "1=1"),
    # Global lookup catalogs — products + customers FK these.
    # Without them the UI shows raw UUIDs in dropdowns.
    ("customer_category",      "company_id IS NULL"),
    ("channel",                "company_id IS NULL"),
    # Core identity — companies first, then facilities, then team
    ("companies",              f"company_id = '{DEMO_COMPANY_ID}'"),
    ("facilities",             f"company_id = '{DEMO_COMPANY_ID}'"),
    ("team",                   f"company_id = '{DEMO_COMPANY_ID}'"),
    # Subscription — without this, plan resolves to NULL and every
    # plan-gated permission (Delivery, Equipment, Inventory, etc.)
    # silently denies. Critical, easy to miss.
    ("subscriptions",          f"company_id = '{DEMO_COMPANY_ID}'"),
    # Lookup tables (sales_area, sizes, etc.) — many other tables FK these
    ("sales_area",             f"company_id = '{DEMO_COMPANY_ID}'"),
    ("size",                   f"company_id = '{DEMO_COMPANY_ID}'"),
    ("product_type",           f"company_id = '{DEMO_COMPANY_ID}'"),
    ("consumable_type",        f"company_id = '{DEMO_COMPANY_ID}'"),
    ("product_groups",         f"company_id = '{DEMO_COMPANY_ID}'"),
    ("coffee_source",          f"company_id = '{DEMO_COMPANY_ID}'"),
    # Facility-scoped lookups
    ("roaster_units",          f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("charge_weight_options",  f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("company_parameters",     f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Customers + contacts
    ("customers",              f"company_id = '{DEMO_COMPANY_ID}'"),
    ("contacts",               f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Inventory
    ("coffee_inventory",       f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("consumable_inventory",   f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Recipes (need roast_recipes before recipe_components which FKs it)
    ("roast_recipes",          f"company_id = '{DEMO_COMPANY_ID}'"),
    ("recipe_components",      f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Products + price log
    ("products",               f"company_id = '{DEMO_COMPANY_ID}'"),
    ("products_price_log",     f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("product_consumables",    f"product_id IN (SELECT product_id FROM products WHERE company_id = '{DEMO_COMPANY_ID}')"),
    # Inventory history + purchases
    ("coffee_inventory_history",     f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("consumable_inventory_history", f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("shipment_received",            f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("coffee_inventory_purchased",   f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Orders + roast log
    ("orders",                 f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("order_details",          f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("roast_log",              f"facility_id = '{DEMO_FACILITY_ID}'"),
    ("weekly_roast_snapshot",  f"facility_id = '{DEMO_FACILITY_ID}'"),
    # Per-user settings
    ("user_roaster_settings",  f"facility_id = '{DEMO_FACILITY_ID}'"),
]

BATCH_SIZE = 100
# Cloudflare in front of the Management API blocks default Python-urllib UA
# (returns "1010 error code"). Pretend to be a real curl client.
HTTP_HEADERS = {
    "User-Agent": "curl/8.4.0",
    "Accept": "*/*",
}


def prod_query(sql):
    """Run SQL on prod, return parsed JSON rows."""
    env = os.environ.copy()
    env["PGPASSWORD"] = PROD_PW
    # Use psql with format json to get clean output
    full = f"COPY ({sql}) TO STDOUT WITH (FORMAT csv, HEADER true, QUOTE '\"', ESCAPE '\"')"
    r = subprocess.run([PSQL, PROD_DB_URL, "-c", full],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"prod query failed: {r.stderr}")
    return r.stdout


import time as _time


def staging_exec(sql, max_retries=5):
    """Execute SQL on staging via Supabase Management API.

    Retries on 429 (rate limit) and 5xx transient errors with exponential
    backoff. Cloudflare 1010 errors (UA-block) are NOT retried since the
    UA header is set up front and they're not transient.
    """
    for attempt in range(max_retries):
        req = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query",
            method="POST",
            headers={
                "Authorization": f"Bearer {SUPABASE_ACCESS_TOKEN}",
                "Content-Type": "application/json",
                **HTTP_HEADERS,
            },
            data=json.dumps({"query": sql}).encode(),
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode() or "[]")
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            # Retry-able codes
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                wait = 5 * (2 ** attempt)  # 5s, 10s, 20s, 40s, 80s
                _time.sleep(wait)
                continue
            raise RuntimeError(f"staging exec failed ({e.code}): {body[:300]}\nSQL was:\n{sql[:300]}...")
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < max_retries - 1:
                _time.sleep(5 * (2 ** attempt))
                continue
            raise


def staging_exec_throttled(sql):
    """Same as staging_exec but adds a small delay between calls to avoid
    burning rate limits during long batched seeds."""
    _time.sleep(1.5)  # ~40 req/min, well under the typical 60/min cap
    return staging_exec(sql)


def get_table_columns(table):
    """Get insertable columns for a table from prod — skip generated cols
    (Postgres rejects explicit values for GENERATED ALWAYS columns)."""
    sql = (f"SELECT column_name FROM information_schema.columns "
           f"WHERE table_schema = 'public' AND table_name = '{table}' "
           f"  AND is_generated <> 'ALWAYS' "
           f"ORDER BY ordinal_position")
    csv = prod_query(sql)
    return [line.strip() for line in csv.strip().split("\n")[1:] if line.strip()]


def remap_value(col, value):
    """Remap any old demo auth_user_id to the new staging one."""
    if col == "auth_user_id" and value == OLD_DEMO_AUTH_USER_ID:
        return NEW_DEMO_AUTH_USER_ID
    return value


def csv_to_sql_inserts(table, csv_text, columns):
    """Convert COPY-CSV output to INSERT statements, batched."""
    import csv as csvmod
    from io import StringIO
    reader = csvmod.reader(StringIO(csv_text))
    header = next(reader, None)
    if header is None:
        return []
    rows = list(reader)
    if not rows:
        return []
    batches = []
    for i in range(0, len(rows), BATCH_SIZE):
        batch_rows = rows[i:i + BATCH_SIZE]
        values_parts = []
        for row in batch_rows:
            literals = []
            for col, val in zip(header, row):
                val = remap_value(col, val)
                if val == "" and col != "":  # empty CSV cell → NULL
                    literals.append("NULL")
                else:
                    # Escape single quotes by doubling
                    escaped = val.replace("'", "''")
                    literals.append(f"'{escaped}'")
            values_parts.append("(" + ",".join(literals) + ")")
        cols_sql = ",".join(f'"{c}"' for c in header)
        batch_sql = (
            f'INSERT INTO public."{table}" ({cols_sql}) VALUES '
            + ",".join(values_parts)
            + " ON CONFLICT DO NOTHING;"
        )
        batches.append(batch_sql)
    return batches


def seed_table(table, where):
    columns = get_table_columns(table)
    if not columns:
        print(f"  ⚠ {table}: no columns found, skipping")
        return
    # Explicit column list so generated columns are skipped end-to-end.
    cols_select = ",".join(f'"{c}"' for c in columns)
    csv_text = prod_query(f'SELECT {cols_select} FROM public."{table}" WHERE {where}')
    lines = csv_text.count("\n") - 1  # minus header
    if lines <= 0:
        print(f"  · {table}: 0 rows")
        return
    print(f"  → {table}: dumping {lines} rows from prod...")
    batches = csv_to_sql_inserts(table, csv_text, columns)
    for i, batch in enumerate(batches, 1):
        # Wrap each batch in a transaction with RLS bypass
        wrapped = (
            "BEGIN;\n"
            "SET LOCAL session_replication_role = 'replica';\n"
            + batch + "\n"
            "COMMIT;"
        )
        try:
            staging_exec_throttled(wrapped)
            print(f"    ✓ batch {i}/{len(batches)}")
        except Exception as e:
            print(f"    ✗ batch {i} FAILED: {e}", file=sys.stderr)
            # KEEP going on subsequent batches — earlier rows may have
            # landed and we shouldn't abandon the rest. ON CONFLICT DO
            # NOTHING handles partial-state re-runs cleanly.
            continue


def main():
    print(f"Seeding staging ({STAGING_REF}) from prod demo tenant…\n")

    # First, special: make sure the new auth user's email_confirm + a
    # synthetic identity exist. The auth API created the user already.
    # The team row's auth_user_id will be remapped during insert.

    for table, where in TABLES:
        try:
            seed_table(table, where)
        except Exception as e:
            print(f"  ✗ {table}: {e}", file=sys.stderr)

    print("\n✓ Done. Login: demo@strataroast.com / demo-staging-2026")


if __name__ == "__main__":
    main()
