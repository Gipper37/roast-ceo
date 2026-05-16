#!/usr/bin/env python3
"""
Migrate post-Jan-15-2026 data from Google Sheets (published CSV) to Supabase.

Outputs SQL INSERT statements to stdout. Logs / stats to stderr.

Usage:
    python3 scripts/migrate_sheets.py > migration.sql
    # Then review migration.sql and execute with:
    #   psql "$DATABASE_URL" < migration.sql
    #   -- or --
    #   supabase db execute --file migration.sql
"""

import csv
import io
import sys
import uuid
from datetime import date, datetime
from urllib.request import urlopen, Request

# ── Constants ────────────────────────────────────────────────────────────────

COMPANY_ID  = "R7CbqHmA1j"
FACILITY_ID = "cc844abb-db0b-48db-9aeb-abd8df9117de"
CUTOFF_DATE = date(2026, 3, 17)        # consumable inventory / shipments / roast_log
ORDERS_CUTOFF_DATE = date(2026, 3, 17) # orders — must capture all since initial migration

# Published CSV base URLs
SHEET1_BASE = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vRmdQHwy5X3bojrBPopHxZpThjyG3H6vQ4KvZDpxpNRwpkD3Eivl_dD-"
    "ThjDdBK6JG5CmjSpcMrJyeP/pub"
)
SHEET2_BASE = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vQ3l7JyaWWgPH8iGC_pV9Su73juwyu9766OZIysGBQUUVGvC_U5JPc8"
    "ZgmUwUq37SAqE0T0dwA8uS6z/pub"
)
SHEET3_BASE = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vS8-oTvuW-jlKJ0qtHSLauI32pej4ylMGxTOVnaYPeCN3znIJM4dH3B"
    "CHnAf54lzI6qjza_y5i8b_Xw/pub"
)

BASES = {"sheet1": SHEET1_BASE, "sheet2": SHEET2_BASE, "sheet3": SHEET3_BASE}

# Tab GIDs
TABS = {
    "customers":                 ("sheet1", 315542530),
    "products":                  ("sheet1", 287902286),
    "orders":                    ("sheet1", 1297782048),
    "order_details":             ("sheet1", 1982362570),
    "roast_log":                 ("sheet2", 933493873),
    "roast_recipes":             ("sheet2", 1365186252),
    "recipe_components":         ("sheet2", 1246223539),
    "shipment_received":         ("sheet3", 414892364),
    "coffee_inventory_purchased":("sheet3", 958260969),
    "consumable_inventory":      ("sheet3", 291104737),
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def log(msg):
    print(msg, file=sys.stderr)


def fetch_csv(table_name):
    """Fetch a published Google Sheet tab as a list of dicts."""
    sheet_key, gid = TABS[table_name]
    url = f"{BASES[sheet_key]}?gid={gid}&single=true&output=csv"
    log(f"  Fetching {table_name} (gid={gid}) ...")
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    resp = urlopen(req)
    text = resp.read().decode("utf-8-sig")  # handle BOM
    reader = csv.DictReader(io.StringIO(text))
    rows = list(reader)
    log(f"    -> {len(rows)} total rows")
    return rows


def new_uuid():
    return str(uuid.uuid4())


def parse_date(val):
    """Parse various date formats into a date object, or None."""
    if not val or not val.strip():
        return None
    val = val.strip()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S",
                "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %I:%M:%S %p"):
        try:
            return datetime.strptime(val, fmt).date()
        except ValueError:
            continue
    return None


def parse_datetime(val):
    """Parse various date/datetime formats, preserving time. Returns datetime or None."""
    if not val or not val.strip():
        return None
    val = val.strip()
    for fmt in ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S",
                "%m/%d/%Y %I:%M %p",
                "%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y"):
        try:
            return datetime.strptime(val, fmt)
        except ValueError:
            continue
    return None


def sql_text(val):
    """Escape a text value for SQL, or return NULL."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().replace("'", "''")
    return f"'{val}'"


def sql_num(val):
    """Format a numeric value for SQL, or return NULL."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().replace(",", "")  # remove thousands separator
    val = val.replace("%", "")               # strip percentage sign
    val = val.replace("$", "")               # strip dollar sign
    try:
        float(val)
        return val
    except ValueError:
        return "NULL"


def sql_bool(val):
    """Format a boolean value for SQL, or return NULL."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().lower()
    if val in ("true", "yes", "1", "y"):
        return "TRUE"
    if val in ("false", "no", "0", "n"):
        return "FALSE"
    return "NULL"


def sql_date(val):
    """Format a date value for SQL, or return NULL."""
    d = parse_date(val) if isinstance(val, str) else val
    if d is None:
        return "NULL"
    return f"'{d.isoformat()}'"


def sql_ts(val):
    """Format a timestamp value for SQL, or return NULL."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    return f"'{val.strip()}'"


def sql_timestamp(val, tz_offset="-10:00"):
    """Format a datetime value as a timestamptz SQL literal, or return NULL.
    Preserves time component unlike sql_date() which strips it."""
    dt = parse_datetime(val) if isinstance(val, str) else val
    if dt is None:
        return "NULL"
    return f"'{dt.strftime('%Y-%m-%d %H:%M:%S')}{tz_offset}'"


def g(row, key, default=""):
    """Get a value from a row dict, handling missing/None."""
    val = row.get(key, default)
    return val if val is not None else default


def is_after_cutoff(date_val):
    """Check if a date string is after the cutoff date."""
    d = parse_date(date_val)
    return d is not None and d > CUTOFF_DATE


# ── Table Processors ────────────────────────────────────────────────────────
# Each returns a list of SQL INSERT statements.

def process_customers(rows):
    """
    Sheet cols: Customer ID, Customer Category, Name/Company, Contact,
                Acct Management Interval (Wks), Management Type,
                Order Reminders Unsubscribed, Deal Open/Closed, Sales Area,
                Sales Person, Email, Phone, Street, City, State, Zip, Tags,
                Customer Since, Flag, created_at, created_by, updated_at,
                updated_by, company_id
    """
    stmts = []
    for r in rows:
        # Filter: created_at > cutoff OR customer_since > cutoff
        created = g(r, "created_at")
        since = g(r, "Customer Since")
        if not is_after_cutoff(created) and not is_after_cutoff(since):
            continue

        cid = g(r, "Customer ID")
        if not cid.strip():
            continue

        vals = ", ".join([
            sql_text(cid),                                          # customer_id
            sql_text(g(r, "Customer Category")),                    # customer_category
            sql_text(g(r, "Name/Company")),                         # name_company
            sql_num(g(r, "Acct Management Interval (Wks)")),        # acct_management_interval_wks
            sql_text(g(r, "Management Type")),                      # management_type
            sql_text(g(r, "Order Reminders Unsubscribed")),         # order_reminders_unsubscribed
            sql_bool(g(r, "Deal Open/Closed")),                     # deal_open_closed
            sql_text(g(r, "Sales Area")),                           # sales_area
            sql_text(g(r, "Sales Person")),                         # sales_person
            sql_text(g(r, "Email")),                                # email
            sql_text(g(r, "Phone")),                                # phone
            sql_text(g(r, "Street")),                               # street
            sql_text(g(r, "City")),                                 # city
            sql_text(g(r, "State")),                                # state
            sql_text(g(r, "Zip")),                                  # zip
            sql_text(g(r, "Tags")),                                 # tags
            sql_date(g(r, "Customer Since")),                       # customer_since
            sql_bool(g(r, "Flag")),                                 # flag
            sql_ts(g(r, "created_at")) if g(r, "created_at").strip() else "now()",  # created_at
            sql_text(g(r, "created_by")),                           # created_by
            sql_ts(g(r, "updated_at")) if g(r, "updated_at").strip() else "now()",  # updated_at
            sql_text(g(r, "updated_by")),                           # updated_by
            sql_text(COMPANY_ID),                                   # company_id
            sql_text(FACILITY_ID),                                  # facility_id
        ])
        stmts.append(
            f"INSERT INTO public.customers "
            f"(customer_id, customer_category, name_company, "
            f"acct_management_interval_wks, management_type, order_reminders_unsubscribed, "
            f"deal_open_closed, sales_area, sales_person, email, phone, street, city, "
            f"state, zip, tags, customer_since, flag, created_at, created_by, "
            f"updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (customer_id) DO NOTHING;"
        )
    return stmts


def process_products(rows):
    """
    Sheet cols: Product Id, Product Name, Recipe Id, Product Type, Size, Image,
                Consumable Inventory ID 1-4, Archived?, created_at, created_by,
                updated_at, updated_by, company_id
    Note: Consumable IDs map to product_consumables table (skipped here).
    Note: Products sheet has NO created_at populated, so we insert all and
          rely on ON CONFLICT DO NOTHING to skip existing rows.
    """
    stmts = []
    for r in rows:
        pid = g(r, "Product Id")
        if not pid.strip():
            continue

        vals = ", ".join([
            sql_text(pid),                                          # product_id
            sql_text(g(r, "Product Name")),                         # product_name
            sql_text(g(r, "Recipe Id")),                            # recipe_id
            sql_text(g(r, "Product Type")),                         # product_type
            sql_text(g(r, "Size")),                                 # size
            sql_text(g(r, "Image")),                                # image
            "FALSE" if sql_bool(g(r, "Archived?")) == "TRUE" else "TRUE",  # is_active (inverted from Archived?)
            sql_ts(g(r, "created_at")) if g(r, "created_at").strip() else "now()",
            sql_text(g(r, "created_by")),
            sql_ts(g(r, "updated_at")) if g(r, "updated_at").strip() else "now()",
            sql_text(g(r, "updated_by")),
            sql_text(COMPANY_ID),
            sql_text(FACILITY_ID),
        ])
        stmts.append(
            f"INSERT INTO public.products "
            f"(product_id, product_name, recipe_id, product_type, size, image, "
            f"is_active, created_at, created_by, updated_at, updated_by, "
            f"company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (product_id) DO NOTHING;"
        )
    return stmts


def process_roast_recipes(rows):
    """
    Sheet cols: Recipe ID, Recipe Name, Image, Origin 1, Percentage,
                Origin 2, Percentage 2, ..., Origin 5, Percentage 5
    -> Insert header into roast_recipes
    -> Decompose origin/percentage pairs into recipe_components
    Only processes the LAST row (user confirmed 1 new recipe).
    Returns (recipe_stmts, component_stmts).
    """
    recipe_stmts = []
    component_stmts = []

    if not rows:
        return recipe_stmts, component_stmts

    # The new recipe is the last row
    r = rows[-1]
    rid = g(r, "Recipe ID")
    if not rid.strip():
        log("  WARNING: Last roast_recipes row has no Recipe ID, skipping")
        return recipe_stmts, component_stmts

    recipe_name = g(r, "Recipe Name")
    image = g(r, "Image")

    # Determine roast_type from component count
    origin_pairs = []
    for i in range(1, 6):
        origin_key = f"Origin {i}" if i == 1 else f"Origin {i}"
        pct_key = "Percentage" if i == 1 else f"Percentage {i}"
        origin_val = g(r, origin_key).strip()
        pct_val = g(r, pct_key).strip()
        if origin_val:
            origin_pairs.append((origin_val, pct_val))

    num_origins = len(origin_pairs)
    if num_origins == 0:
        roast_type = "'Single Origin/Post-Blend'"
    elif num_origins == 1:
        roast_type = "'Single Origin/Post-Blend'"
    else:
        roast_type = "'Pre-Blend'"

    vals = ", ".join([
        sql_text(rid),
        sql_text(recipe_name),
        sql_text(image),
        "NULL",                 # cost_lb_green  (computed by triggers)
        "NULL",                 # cost_lb_roasted (computed by triggers)
        "NULL",                 # shipping_lb
        "now()",                # created_at
        sql_text(COMPANY_ID),   # created_by (using company_id as placeholder)
        "now()",                # updated_at
        "NULL",                 # updated_by
        sql_text(COMPANY_ID),   # company_id
        roast_type,             # roast_type
        sql_text(FACILITY_ID),  # facility_id
    ])
    recipe_stmts.append(
        f"INSERT INTO public.roast_recipes "
        f"(recipe_id, recipe_name, image, cost_lb_green, cost_lb_roasted, "
        f"shipping_lb, created_at, created_by, updated_at, updated_by, "
        f"company_id, roast_type, facility_id)\n"
        f"VALUES ({vals})\n"
        f"ON CONFLICT (recipe_id) DO NOTHING;"
    )
    log(f"    New recipe: {recipe_name} ({rid}) with {num_origins} origin(s)")

    # Decompose into recipe_components
    for origin_val, pct_val in origin_pairs:
        comp_id = new_uuid()
        comp_vals = ", ".join([
            sql_text(comp_id),      # component_id
            sql_text(rid),          # recipe_id
            sql_text(origin_val),   # item_id (origin reference)
            sql_num(str(float(pct_val.replace("%","")) / 100)) if pct_val else "NULL",  # percentage (decimal 0-1)
            sql_text(origin_val),   # coffee_item (display name = origin)
            "NULL",                 # component_cost (computed by triggers)
            "now()",                # created_at
            "now()",                # updated_at
            sql_text(COMPANY_ID),   # created_by
            "NULL",                 # updated_by
            sql_text(COMPANY_ID),   # company_id
            sql_text(FACILITY_ID),  # facility_id
        ])
        component_stmts.append(
            f"INSERT INTO public.recipe_components "
            f"(component_id, recipe_id, item_id, percentage, coffee_item, "
            f"component_cost, created_at, updated_at, created_by, updated_by, "
            f"company_id, facility_id)\n"
            f"VALUES ({comp_vals})\n"
            f"ON CONFLICT (component_id) DO NOTHING;"
        )

    log(f"    Decomposed into {len(component_stmts)} recipe_components rows")
    return recipe_stmts, component_stmts


def process_roast_log(rows):
    """
    Sheet cols: Roast Log ID, Roast Date, Origin, Recipe ID, Charge Weight,
                Roasted Weight, Charged?, Chaff Cleaned?, created_at,
                created_by, updated_at, updated_by, company_id
    Supabase: origin_id (not Origin), "charged?" / "chaff_cleaned?" (quoted)
    """
    stmts = []
    for r in rows:
        roast_date = g(r, "Roast Date")
        created = g(r, "created_at")
        if not is_after_cutoff(roast_date) and not is_after_cutoff(created):
            continue

        rlid = g(r, "Roast Log ID")
        if not rlid.strip():
            continue

        vals = ", ".join([
            sql_text(rlid),                                         # roast_log_id
            sql_timestamp(roast_date),                              # roast_date (timestamptz)
            sql_text(g(r, "Origin")),                               # origin_id
            sql_text(g(r, "Recipe ID")),                            # recipe_id
            sql_num(g(r, "Charge Weight")),                         # charge_weight
            sql_num(g(r, "Roasted Weight")),                        # roasted_weight
            sql_bool(g(r, "Charged?")),                             # "charged?"
            sql_bool(g(r, "Chaff Cleaned?")),                       # "chaff_cleaned?"
            sql_ts(g(r, "created_at")) if g(r, "created_at").strip() else "now()",
            sql_text(g(r, "created_by")),
            sql_ts(g(r, "updated_at")) if g(r, "updated_at").strip() else "now()",
            sql_text(g(r, "updated_by")),
            sql_text(COMPANY_ID),
            sql_text(FACILITY_ID),
        ])
        stmts.append(
            f"INSERT INTO public.roast_log "
            f'(roast_log_id, roast_date, origin_id, recipe_id, charge_weight, '
            f'roasted_weight, "charged?", "chaff_cleaned?", created_at, created_by, '
            f"updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (roast_log_id) DO NOTHING;"
        )
    return stmts


def process_shipment_received(rows):
    """
    Sheet cols: Shipment ID, Supplier Id, Shipping Cost, Date Received, Order Date
    """
    stmts = []
    for r in rows:
        date_recv = g(r, "Date Received")
        order_dt = g(r, "Order Date")
        if not is_after_cutoff(date_recv) and not is_after_cutoff(order_dt):
            continue

        sid = g(r, "Shipment ID")
        if not sid.strip():
            continue

        vals = ", ".join([
            sql_text(sid),                          # shipment_id
            sql_text(g(r, "Supplier Id")),          # supplier_id
            sql_num(g(r, "Shipping Cost")),          # shipping_cost
            sql_date(date_recv),                     # date_received
            sql_date(order_dt),                      # order_date
            "now()",                                 # created_at
            "now()",                                 # updated_at
            sql_text(COMPANY_ID),                    # created_by
            "NULL",                                  # updated_by
            sql_text(COMPANY_ID),                    # company_id
            sql_text(FACILITY_ID),                   # facility_id
        ])
        stmts.append(
            f"INSERT INTO public.shipment_received "
            f"(shipment_id, supplier_id, shipping_cost, date_received, order_date, "
            f"created_at, updated_at, created_by, updated_by, company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (shipment_id) DO NOTHING;"
        )
    return stmts


def process_coffee_inventory_purchased(rows, new_shipment_ids):
    """
    Sheet cols: Origin Purchase ID, Shipment ID, Origin, Coffee Name, Lot ID,
                Cost/LB, Amount
    Filter: rows whose Shipment ID is in the set of newly-imported shipments.
    """
    stmts = []
    for r in rows:
        ship_id = g(r, "Shipment ID").strip()
        # Include if shipment is new, or if no shipment filter is available
        if new_shipment_ids and ship_id not in new_shipment_ids:
            continue

        opid = g(r, "Origin Purchase ID")
        if not opid.strip():
            continue

        vals = ", ".join([
            sql_text(opid),                             # origin_purchase_id
            sql_text(ship_id),                          # shipment_id
            sql_text(g(r, "Origin")),                   # origin
            sql_text(g(r, "Lot ID")),                   # lot_id
            sql_num(g(r, "Cost/LB")),                   # cost_lb
            sql_num(g(r, "Amount")),                     # amount
            "now()",                                     # created_at
            "now()",                                     # updated_at
            sql_text(COMPANY_ID),                        # created_by
            "NULL",                                      # updated_by
            sql_text(COMPANY_ID),                        # company_id
            sql_text(FACILITY_ID),                       # facility_id
        ])
        stmts.append(
            f"INSERT INTO public.coffee_inventory_purchased "
            f"(origin_purchase_id, shipment_id, origin, lot_id, "
            f"cost_lb, amount, created_at, updated_at, created_by, updated_by, "
            f"company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (origin_purchase_id) DO NOTHING;"
        )
    return stmts


def process_consumable_inventory(rows):
    """
    Sheet cols: Consumable Inventory ID, Consumable Inventory Item,
                Last Inventory Date, Inventory Count
    1. UPSERTs last_inventory_date + inventory_count on main consumable_inventory table.
    2. Inserts a real inventory count entry into consumable_inventory_history
       (ON CONFLICT DO NOTHING so re-running is safe).
    """
    stmts = []
    for r in rows:
        ciid = g(r, "Consumable Inventory ID")
        if not ciid.strip():
            continue

        inv_date = g(r, "Last Inventory Date")
        item_name = g(r, "Consumable Inventory Item")
        inv_count = g(r, "Inventory Count")

        # 1. Upsert main table
        vals = ", ".join([
            sql_text(ciid),
            sql_text(item_name),
            sql_date(inv_date),
            sql_num(inv_count),
            "now()",
            "now()",
            sql_text(COMPANY_ID),
            "NULL",
            sql_text(COMPANY_ID),
            sql_text(FACILITY_ID),
        ])
        stmts.append(
            f"INSERT INTO public.consumable_inventory "
            f"(consumable_inventory_id, consumable_inventory_item, last_inventory_date, "
            f"inventory_count, created_at, updated_at, created_by, updated_by, "
            f"company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (consumable_inventory_id) DO UPDATE SET\n"
            f"  consumable_inventory_item = EXCLUDED.consumable_inventory_item,\n"
            f"  last_inventory_date = EXCLUDED.last_inventory_date,\n"
            f"  inventory_count = EXCLUDED.inventory_count,\n"
            f"  updated_at = now();"
        )

        # 2. Insert into history table only when both date and count exist
        if not inv_date or not inv_date.strip() or not inv_count or not str(inv_count).strip():
            continue
        hist_vals = ", ".join([
            f"gen_random_uuid()",               # history_id
            sql_text(ciid),                     # consumable_id
            sql_date(inv_date),                 # inventory_date
            sql_num(inv_count),                 # inventory_count
            "'Manual inventory count'",         # notes
            sql_text(FACILITY_ID),              # facility_id
            sql_text(COMPANY_ID),               # company_id
            "now()",                            # created_at
            "now()",                            # updated_at
            sql_text(COMPANY_ID),               # created_by
            "NULL",                             # updated_by
        ])
        stmts.append(
            f"INSERT INTO public.consumable_inventory_history "
            f"(history_id, consumable_id, inventory_date, inventory_count, notes, "
            f"facility_id, company_id, created_at, updated_at, created_by, updated_by)\n"
            f"SELECT {hist_vals}\n"
            f"WHERE NOT EXISTS (\n"
            f"  SELECT 1 FROM public.consumable_inventory_history\n"
            f"  WHERE consumable_id = {sql_text(ciid)} AND inventory_date = {sql_date(inv_date)}\n"
            f");"
        )

    return stmts


def process_orders(rows):
    """
    Sheet cols: Order Id, Customer Id, Order Date, Order Status, Order Notes,
                Previous Order, Next Order, Delivery Photo, Signature, update column
    """
    stmts = []
    new_order_ids = set()
    for r in rows:
        order_date = g(r, "Order Date")
        d = parse_date(order_date)
        if d is None or d <= ORDERS_CUTOFF_DATE:
            continue

        oid = g(r, "Order Id")
        if not oid.strip():
            continue

        new_order_ids.add(oid.strip())

        vals = ", ".join([
            sql_text(oid),                              # order_id
            sql_text(g(r, "Customer Id")),              # customer_id
            sql_date(order_date),                       # order_date
            sql_text(g(r, "Order Status")),             # order_status
            sql_text(g(r, "Order Notes")),              # order_notes
            sql_text(g(r, "Previous Order")),           # previous_order
            sql_text(g(r, "Next Order")),               # next_order
            sql_text(g(r, "Delivery Photo")),           # delivery_photo
            sql_text(g(r, "Signature")),                # signature
            sql_text(g(r, "update column")),            # "update column"
            "now()",                                     # created_at
            sql_text(COMPANY_ID),                        # created_by
            "now()",                                     # updated_at
            "NULL",                                      # updated_by
            sql_text(COMPANY_ID),                        # company_id
            sql_text(FACILITY_ID),                       # facility_id
        ])
        stmts.append(
            f"INSERT INTO public.orders "
            f"(order_id, customer_id, order_date, order_status, order_notes, "
            f'previous_order, next_order, delivery_photo, signature, "update column", '
            f"created_at, created_by, updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (order_id) DO NOTHING;"
        )
    return stmts, new_order_ids


def process_order_details(rows, new_order_ids):
    """
    Sheet cols: OrderDetail Id, Order Id, Product Id, Coffee Prep, Quantity,
                Item Status, Previous Order Details, Next Order Details
    Filter: rows whose Order Id is in the set of newly-imported orders.
    """
    stmts = []
    for r in rows:
        oid = g(r, "Order Id").strip()
        if new_order_ids and oid not in new_order_ids:
            continue

        odid = g(r, "OrderDetail Id")
        if not odid.strip():
            continue

        vals = ", ".join([
            sql_text(odid),                                 # order_detail_id
            sql_text(oid),                                  # order_id
            sql_text(g(r, "Product Id")),                   # product_id
            sql_text(g(r, "Coffee Prep")),                  # coffee_prep
            sql_num(g(r, "Quantity")),                       # quantity
            sql_text(g(r, "Item Status")),                  # item_status
            sql_text(g(r, "Previous Order Details")),       # previous_order_details
            sql_text(g(r, "Next Order Details")),           # next_order_details
            sql_text(COMPANY_ID),                            # company_id
            "now()",                                         # created_at
            sql_text(COMPANY_ID),                            # created_by
            "now()",                                         # updated_at
            "NULL",                                          # updated_by
            sql_text(FACILITY_ID),                           # facility_id
        ])
        stmts.append(
            f"INSERT INTO public.order_details "
            f"(order_detail_id, order_id, product_id, coffee_prep, quantity, "
            f"item_status, previous_order_details, next_order_details, "
            f"company_id, created_at, created_by, updated_at, updated_by, facility_id)\n"
            f"VALUES ({vals})\n"
            f"ON CONFLICT (order_detail_id) DO NOTHING;"
        )
    return stmts


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    log("=" * 60)
    log("Google Sheets -> Supabase Migration")
    log(f"Company: {COMPANY_ID}  Facility: {FACILITY_ID}")
    log(f"Cutoff:  rows after {CUTOFF_DATE}")
    log("=" * 60)

    all_sql = []
    stats = {}

    def emit(table, stmts):
        stats[table] = len(stmts)
        if stmts:
            all_sql.append(f"\n-- ── {table} ({len(stmts)} rows) " + "─" * 40)
            all_sql.extend(stmts)

    # ── 1. Fetch all CSVs ────────────────────────────────────────────────
    log("\n[1/3] Fetching CSVs from published Google Sheets ...")
    csv_data = {}
    for table_name in TABS:
        try:
            csv_data[table_name] = fetch_csv(table_name)
        except Exception as e:
            log(f"  ERROR fetching {table_name}: {e}")
            csv_data[table_name] = []

    # ── 2. Process tables in FK dependency order ─────────────────────────
    log("\n[2/3] Processing rows (filtering post-Jan-15, mapping columns) ...")

    # Clear bad "Initial History Backfill" entries from consumable_inventory_history
    log("\n  -- clearing Initial History Backfill entries --")
    emit("_clear_backfill_history", [
        "DELETE FROM public.consumable_inventory_history\n"
        "WHERE notes = 'Initial History Backfill';"
    ])

    # Pre-insert missing FK references (sales_area "Shipped")
    log("\n  -- pre-insert: sales_area 'Shipped' --")
    emit("_fk_sales_area", [
        f"INSERT INTO public.sales_area (id, area_name, company_id, created_at, updated_at)\n"
        f"VALUES ('b2faac39', 'Shipped', '{COMPANY_ID}', now(), now())\n"
        f"ON CONFLICT (id) DO NOTHING;"
    ])

    # Tables with no upstream FKs
    log("\n  -- customers --")
    emit("customers", process_customers(csv_data["customers"]))

    log("\n  -- products --")
    emit("products", process_products(csv_data["products"]))

    log("\n  -- roast_recipes + recipe_components (decomposition) --")
    recipe_stmts, component_stmts = process_roast_recipes(csv_data["roast_recipes"])
    emit("roast_recipes", recipe_stmts)
    emit("recipe_components", component_stmts)

    log("\n  -- roast_log --")
    emit("roast_log", process_roast_log(csv_data["roast_log"]))

    log("\n  -- shipment_received --")
    ship_stmts = process_shipment_received(csv_data["shipment_received"])
    new_shipment_ids = set()
    for r in csv_data["shipment_received"]:
        dr = g(r, "Date Received")
        od = g(r, "Order Date")
        if is_after_cutoff(dr) or is_after_cutoff(od):
            sid = g(r, "Shipment ID").strip()
            if sid:
                new_shipment_ids.add(sid)
    emit("shipment_received", ship_stmts)

    log("\n  -- coffee_inventory_purchased --")
    emit("coffee_inventory_purchased",
         process_coffee_inventory_purchased(csv_data["coffee_inventory_purchased"],
                                            new_shipment_ids))

    log("\n  -- consumable_inventory --")
    emit("consumable_inventory",
         process_consumable_inventory(csv_data["consumable_inventory"]))

    log("\n  -- orders --")
    order_stmts, new_order_ids = process_orders(csv_data["orders"])
    emit("orders", order_stmts)

    log("\n  -- order_details --")
    emit("order_details",
         process_order_details(csv_data["order_details"], new_order_ids))

    # ── 3. Output SQL ────────────────────────────────────────────────────
    log("\n[3/3] Generating SQL ...\n")

    print("-- =============================================================")
    print("-- Google Sheets -> Supabase Migration")
    print(f"-- Generated: {datetime.now().isoformat()}")
    print(f"-- Company:   {COMPANY_ID}")
    print(f"-- Facility:  {FACILITY_ID}")
    print(f"-- Cutoff:    rows after {CUTOFF_DATE}")
    print("-- =============================================================")
    print()
    print("BEGIN;")
    for line in all_sql:
        print(line)
    print()
    # Backfill snapshot columns for any rows inserted without them
    print("-- Backfill snapshot columns for newly inserted rows")
    print("""UPDATE public.roast_log rl
SET
  recipe_name_snapshot = rr.recipe_name,
  coffee_name_snapshot = ci.origin
FROM public.roast_recipes rr,
     public.coffee_inventory ci
WHERE rl.recipe_id = rr.recipe_id
  AND ci.origin_id = rl.origin_id
  AND ci.facility_id = rl.facility_id
  AND (rl.recipe_name_snapshot IS NULL OR rl.coffee_name_snapshot IS NULL);""")
    print()
    print("""UPDATE public.order_details od
SET product_name_snapshot = p.product_name
FROM public.products p
WHERE od.product_id = p.product_id
  AND od.product_name_snapshot IS NULL;""")
    print()
    print("COMMIT;")

    # ── Summary ──────────────────────────────────────────────────────────
    log("=" * 60)
    log("Summary:")
    total = 0
    for table, count in stats.items():
        log(f"  {table:35s}  {count:4d} rows")
        total += count
    log(f"  {'TOTAL':35s}  {total:4d} rows")
    log("=" * 60)
    log(f"\nSQL written to stdout. Review, then execute:")
    log(f"  psql \"$DATABASE_URL\" < migration.sql")
    log(f"  # or: supabase db execute --file migration.sql")


if __name__ == "__main__":
    main()
