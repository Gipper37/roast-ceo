#!/usr/bin/env python3
"""
Migrate Social Hour Coffee Roasters UK data from Google Sheets to Supabase.

This is a FULL company onboarding migration — creates company, facility,
team members, and all operational data.

Usage:
    python3 scripts/migrate_social_hour_uk.py > scripts/migration_uk.sql
    # Review, then:
    #   PGPASSWORD='...' psql "$DATABASE_URL" < scripts/migration_uk.sql
"""

import csv
import io
import sys
import uuid
from datetime import date, datetime
from urllib.request import urlopen, Request

# ── Constants ────────────────────────────────────────────────────────────────

COMPANY_ID  = None   # generated below
FACILITY_ID = None   # generated below
ADMIN_TEAM_ID = None # generated below

KG_TO_LBS = 2.20462  # conversion factor

# product_type UUID map for UK company — locked at generation time
PRODUCT_TYPE_MAP = {
    'Retail DTC':       'pt-uk-retail-dtc-0000000000000001',
    'Wholesale Retail': 'pt-uk-wholesale-retail-000000001',
    'Wholesale Bulk':   'pt-uk-wholesale-bulk-0000000001',
    'Sample':           'pt-uk-sample-000000000000000001',
    'Merged':           'pt-uk-merged-000000000000000001',
}

# Google Sheets (shared with "Anyone with the link")
SHEETS = {
    "roast":     "1Ii3L6fKzESsPh8c3CXMpOdhNkrscssKoscykXCR6mSQ",
    "sales":     "1GdLVUBX39fBFdsfS4O3zWe-Ouu7lgkmRlXIYAqdGZRM",
    "orders":    "1jTln_YNUGmJLR9yIS9MuSOJup1tzzuPjSjBIAYl93SU",
    "inventory": "11tUddh2iUPcVn23NFO1Yu62-QWyvSSx5KSHa47AbNUg",
    "config":    "16AYkINGozr11sufcZsuJIdHZ6UdMmICQg6W4mRQrzvU",
    "filters":   "1evWpwaBByKCNAt_8Ku5Xb7osPZ5E0R63vSAH7m424-U",
}

# Tab name → (sheet_key, column_names_override)
# column_names_override is used when the header row is garbled (e.g. Contact)
TABS = {
    # Roast sheet
    "Roast Log":                   ("roast", None),
    "Roast Recipes":               ("roast", None),
    # Sales sheet
    "Sales Area":                  ("sales", None),
    "Sales Notes":                 ("sales", None),
    "Sales Tasks":                 ("sales", None),
    "Sales Tracking":              ("sales", None),
    "Sales Goals":                 ("sales", None),
    "Sales Team":                  ("sales", None),
    "Team Member Role":            ("sales", None),
    "Contact Role":                ("sales", None),
    # Orders/Products sheet
    "Customers":                   ("orders", None),
    "Contact":                     ("orders", ["Contact ID", "Contact", "Company", "Role", "Email", "Phone", "Notes"]),
    "Products":                    ("orders", None),
    "Products Price Log":          ("orders", None),
    "Orders":                      ("orders", None),
    "Order Details":               ("orders", None),
    "Team":                        ("orders", None),
    # Inventory sheet
    "Shipment Received":           ("inventory", None),
    "Coffee Inventory":            ("inventory", None),
    "Coffee Inventory Purchased":  ("inventory", None),
    "Consumable Inventory":        ("inventory", None),
    "Consumable Inventory Purchased": ("inventory", None),
    "Supplier":                    ("inventory", None),
    "Supplier Category":           ("inventory", None),
    # Config sheet
    "Customer Category":           ("config", None),
    "Charge Weight Options":       ("config", None),
    "Size":                        ("config", None),
    "Standard Parameters":         ("config", None),
    # Filters sheet
    "Product Filter":              ("filters", None),
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def log(msg):
    print(msg, file=sys.stderr)


def fetch_csv(tab_name):
    """Fetch a Google Sheet tab as a list of dicts via gviz CSV export."""
    sheet_key, col_override = TABS[tab_name]
    sheet_id = SHEETS[sheet_key]
    import urllib.parse
    url = (
        f"https://docs.google.com/spreadsheets/d/{sheet_id}"
        f"/gviz/tq?tqx=out:csv&sheet={urllib.parse.quote(tab_name)}"
    )
    log(f"  Fetching {tab_name} ...")
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    resp = urlopen(req)
    text = resp.read().decode("utf-8-sig")
    reader = csv.reader(io.StringIO(text))

    if col_override:
        # Skip garbled header, use our own column names
        next(reader)
        rows = [dict(zip(col_override, row)) for row in reader if any(c.strip() for c in row)]
    else:
        rows = list(csv.DictReader(io.StringIO(text)))

    log(f"    -> {len(rows)} rows")
    return rows


def new_uuid():
    return str(uuid.uuid4())


def parse_date(val):
    if not val or not val.strip():
        return None
    val = val.strip()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y",
                "%d/%m/%Y", "%d/%m/%y",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S",
                "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %I:%M:%S %p",
                "%d/%m/%Y %H:%M:%S"):
        try:
            return datetime.strptime(val, fmt).date()
        except ValueError:
            continue
    return None


def parse_datetime(val):
    if not val or not val.strip():
        return None
    val = val.strip()
    for fmt in ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S",
                "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %I:%M:%S %p",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S",
                "%m/%d/%Y %I:%M %p",
                "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
                "%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%d/%m/%Y"):
        try:
            return datetime.strptime(val, fmt)
        except ValueError:
            continue
    return None


def sql_text(val):
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().replace("'", "''")
    return f"'{val}'"


def sql_num(val):
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().replace(",", "").replace("%", "").replace("$", "").replace("£", "").replace("€", "")
    try:
        float(val)
        return val
    except ValueError:
        return "NULL"


def sql_bool(val):
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return "NULL"
    val = str(val).strip().lower()
    if val in ("true", "yes", "1", "y"):
        return "TRUE"
    if val in ("false", "no", "0", "n"):
        return "FALSE"
    return "NULL"


def sql_date(val):
    d = parse_date(val) if isinstance(val, str) else val
    if d is None:
        return "NULL"
    return f"'{d.isoformat()}'"


def sql_timestamp(val, tz_offset="+00:00"):
    """UK timezone — use +00:00 (GMT/UTC) as default."""
    dt = parse_datetime(val) if isinstance(val, str) else val
    if dt is None:
        return "NULL"
    return f"'{dt.strftime('%Y-%m-%d %H:%M:%S')}{tz_offset}'"


def g(row, key, default=""):
    """Get a value from a row dict, handling missing/None and whitespace keys."""
    # Try exact key first
    val = row.get(key, None)
    if val is not None:
        return val if val is not None else default
    # Try stripped key (handles "Order Id " with trailing space)
    for k, v in row.items():
        if k.strip() == key.strip():
            return v if v is not None else default
    return default


def kg_to_lbs(val_str):
    """Convert a kg value string to lbs, return as string or NULL."""
    n = sql_num(val_str)
    if n == "NULL":
        return "NULL"
    return str(round(float(n) * KG_TO_LBS, 6))


# ── Table Processors ────────────────────────────────────────────────────────

def process_company_setup():
    """Create company, facility, team, and seed params."""
    global COMPANY_ID, FACILITY_ID, ADMIN_TEAM_ID
    COMPANY_ID = "752af3ed-4"                              # locked — Social Hour Coffee Roasters UK
    FACILITY_ID = "b9b37e83-1986-46c0-bc69-fce89120155e"  # locked — Anglesey Roastery
    ADMIN_TEAM_ID = "sUd46re4"                             # Andy Kimmelshue from Team tab

    stmts = []

    # Company
    stmts.append(
        f"INSERT INTO public.companies (company_id, company_name, created_by)\n"
        f"VALUES ({sql_text(COMPANY_ID)}, 'Social Hour Coffee Roasters UK', {sql_text(ADMIN_TEAM_ID)})\n"
        f"ON CONFLICT (company_id) DO NOTHING;"
    )

    # Facility
    stmts.append(
        f"INSERT INTO public.facilities (facility_id, company_id, facility_name, time_zone, country_code, created_by)\n"
        f"VALUES ({sql_text(FACILITY_ID)}, {sql_text(COMPANY_ID)}, 'Anglesey Roastery', 'Europe/London', 'GB', {sql_text(ADMIN_TEAM_ID)})\n"
        f"ON CONFLICT (facility_id) DO NOTHING;"
    )

    # product_type rows — required before products can be inserted (FK constraint)
    for ptype_text, ptype_id in PRODUCT_TYPE_MAP.items():
        stmts.append(
            f"INSERT INTO public.product_type (product_type_id, product_type, company_id, created_by)\n"
            f"VALUES ({sql_text(ptype_id)}, {sql_text(ptype_text)}, {sql_text(COMPANY_ID)}, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (product_type_id) DO NOTHING;"
        )

    return stmts


def process_team(rows, sales_team_rows):
    """Insert team members. Andy Kimmelshue = company_admin."""
    global ADMIN_TEAM_ID
    stmts = []

    # Build a lookup of Sales Team for role mapping
    sales_role_map = {}
    for r in sales_team_rows:
        tid = g(r, "Team Member ID").strip()
        role = g(r, "Role").strip()
        if tid and role:
            sales_role_map[tid] = role

    for r in rows:
        tid = g(r, "Team Member ID").strip()
        name = g(r, "Name").strip()
        email = g(r, "Email").strip()
        if not tid:
            continue

        # Andy Kimmelshue is the company_admin
        if "kimmelshue" in name.lower() or "andy" in name.lower():
            ADMIN_TEAM_ID = tid
            role = "company_admin"
        else:
            role = "manager"  # default other team members to manager

        stmts.append(
            f"INSERT INTO public.team (team_member_id, name, email, company_id, facility_id, role, onboarding_completed, created_by)\n"
            f"VALUES ({sql_text(tid)}, {sql_text(name)}, {sql_text(email)}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, "
            f"{sql_text(role)}, FALSE, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (team_member_id) DO NOTHING;"
        )

    # Also insert Sales Team members that aren't in the Team tab
    team_ids = {g(r, "Team Member ID").strip() for r in rows}
    for r in sales_team_rows:
        tid = g(r, "Team Member ID").strip()
        if not tid or tid in team_ids:
            continue
        name = g(r, "Name").strip()
        email = g(r, "Email").strip()

        if "hagler" in name.lower() and "tiffany" in name.lower():
            role = "sales_person"
        elif "kimmelshue" in name.lower() or "andy" in name.lower():
            # Andy's sales team entry — different ID, same person. Still company_admin.
            role = "company_admin"
        else:
            role = "manager"

        stmts.append(
            f"INSERT INTO public.team (team_member_id, name, email, company_id, facility_id, role, onboarding_completed, created_by)\n"
            f"VALUES ({sql_text(tid)}, {sql_text(name)}, {sql_text(email)}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, "
            f"{sql_text(role)}, FALSE, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (team_member_id) DO NOTHING;"
        )

    return stmts


def process_seed_params():
    """Seed company_parameters from standard_parameters for this facility,
    then add currency and display_weight_unit overrides for UK."""
    stmts = [
        # 1. Seed all standard params
        f"INSERT INTO public.company_parameters (company_id, facility_id, parameter_id, value, value_number, display_name, created_by)\n"
        f"SELECT {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, sp.parameters_id, sp.text_value, sp.amount, sp.parameter, {sql_text(ADMIN_TEAM_ID)}\n"
        f"FROM public.standard_parameters sp\n"
        f"WHERE NOT EXISTS (\n"
        f"  SELECT 1 FROM public.company_parameters cp\n"
        f"  WHERE cp.company_id = {sql_text(COMPANY_ID)} AND cp.facility_id = {sql_text(FACILITY_ID)} AND cp.parameter_id = sp.parameters_id\n"
        f");",
    ]

    # 2. Add currency standard param if it doesn't exist yet
    currency_param_id = "currency_001"
    stmts.append(
        f"INSERT INTO public.standard_parameters (parameters_id, parameter, text_value, data_type)\n"
        f"VALUES ('{currency_param_id}', 'Currency', 'USD', 'text')\n"
        f"ON CONFLICT (parameters_id) DO NOTHING;"
    )

    # 3. Add display_weight_unit standard param if it doesn't exist yet
    weight_unit_param_id = "weight_unit_001"
    stmts.append(
        f"INSERT INTO public.standard_parameters (parameters_id, parameter, text_value, data_type)\n"
        f"VALUES ('{weight_unit_param_id}', 'Display Weight Unit', 'lbs', 'text')\n"
        f"ON CONFLICT (parameters_id) DO NOTHING;"
    )

    # 4. Set GBP currency for this UK facility
    stmts.append(
        f"INSERT INTO public.company_parameters (company_id, facility_id, parameter_id, value, display_name, created_by)\n"
        f"VALUES ({sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, '{currency_param_id}', 'GBP', 'Currency', {sql_text(ADMIN_TEAM_ID)})\n"
        f"ON CONFLICT DO NOTHING;"
    )

    # 5. Set kg display weight unit for this UK facility
    stmts.append(
        f"INSERT INTO public.company_parameters (company_id, facility_id, parameter_id, value, display_name, created_by)\n"
        f"VALUES ({sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, '{weight_unit_param_id}', 'kg', 'Display Weight Unit', {sql_text(ADMIN_TEAM_ID)})\n"
        f"ON CONFLICT DO NOTHING;"
    )

    return stmts


def process_recent_coffee_order():
    """Provision the Recent Coffee Order singleton."""
    return [
        f"INSERT INTO public.recent_coffee_order (recent_coffee_order_id, company_id, facility_id, total_pallets, lbs_ordered, recommended_pallets, bags_left, created_by)\n"
        f"VALUES ({sql_text(new_uuid())}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, 0, 0, 0, 0, {sql_text(ADMIN_TEAM_ID)})\n"
        f"ON CONFLICT DO NOTHING;"
    ]


def process_supplier_category(rows):
    stmts = []
    for r in rows:
        scid = g(r, "Supplier Category ID").strip()
        sc = g(r, "Supplier Category").strip()
        if not scid:
            continue
        stmts.append(
            f"INSERT INTO public.supplier_category (supplier_category_id, supplier_category, company_id, created_by)\n"
            f"VALUES ({sql_text(scid)}, {sql_text(sc)}, {sql_text(COMPANY_ID)}, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (supplier_category_id) DO NOTHING;"
        )
    return stmts


def process_supplier(rows):
    stmts = []
    for r in rows:
        sid = g(r, "Supplier ID").strip()
        if not sid:
            continue
        stmts.append(
            f"INSERT INTO public.supplier (supplier_id, supplier, supplier_category, company_id, created_by)\n"
            f"VALUES ({sql_text(sid)}, {sql_text(g(r, 'Supplier'))}, {sql_text(g(r, 'Supplier Category'))}, {sql_text(COMPANY_ID)}, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (supplier_id) DO NOTHING;"
        )
    return stmts


def process_customer_category(rows):
    """customer_category is just a text enum on customers — no separate table in most schemas.
    But if there's a customer_category table, insert there."""
    # The existing schema doesn't have a separate customer_category table with IDs.
    # These are just text values used in customers.customer_category.
    # Skip — the values will be inserted directly on customers.
    return []


def process_contact_role(rows):
    stmts = []
    for r in rows:
        crid = g(r, "Contact Role ID").strip()
        cr = g(r, "Contact Role").strip()
        if not crid:
            continue
        stmts.append(
            f"INSERT INTO public.contact_role (contact_role_id, contact_role, company_id, created_by)\n"
            f"VALUES ({sql_text(crid)}, {sql_text(cr)}, {sql_text(COMPANY_ID)}, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (contact_role_id) DO NOTHING;"
        )
    return stmts


def process_size(rows):
    """Size table — convert kg weights to lbs."""
    stmts = []
    for r in rows:
        sid = g(r, "Size ID").strip()
        sname = g(r, "Size Name").strip()
        weight_kg = g(r, "Weight").strip()
        if not sid:
            continue

        weight_lbs = kg_to_lbs(weight_kg)

        stmts.append(
            f"INSERT INTO public.size (size_id, size_name, weight, company_id, created_by)\n"
            f"VALUES ({sql_text(sid)}, {sql_text(sname)}, {weight_lbs}, {sql_text(COMPANY_ID)}, {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (size_id) DO NOTHING;"
        )
    return stmts


def process_charge_weight_options(rows):
    """Charge weight options — convert kg to lbs."""
    stmts = []
    for r in rows:
        cw_kg = g(r, "Charge Weight Options").strip()
        if not cw_kg:
            continue
        cw_lbs = kg_to_lbs(cw_kg)
        cw_id = new_uuid()
        stmts.append(
            f"INSERT INTO public.charge_weight_options (id, charge_weight, company_id, facility_id)\n"
            f"VALUES ({sql_text(cw_id)}, {cw_lbs}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT DO NOTHING;"
        )
    return stmts


def process_sales_area(rows):
    stmts = []
    for r in rows:
        said = g(r, "Sales Area ID").strip()
        sa = g(r, "Sales Area").strip()
        if not said:
            continue
        stmts.append(
            f"INSERT INTO public.sales_area (id, area_name, company_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(said)}, {sql_text(sa)}, {sql_text(COMPANY_ID)}, now(), now())\n"
            f"ON CONFLICT (id) DO NOTHING;"
        )
    return stmts


def process_coffee_inventory(rows):
    """Coffee inventory — origins."""
    stmts = []
    for r in rows:
        oid = g(r, "Origin ID").strip()
        origin = g(r, "Origin").strip()
        supplier = g(r, "Supplier").strip()
        if not oid:
            continue

        last_inv = g(r, "Last Inventory").strip()
        inv_count = g(r, "Inventory Count - Bags").strip()

        stmts.append(
            f"INSERT INTO public.coffee_inventory "
            f"(origin_id, origin, supplier_id, last_inventory, inventory_count_bags, "
            f"company_id, facility_id, created_by, is_active)\n"
            f"VALUES ({sql_text(oid)}, {sql_text(origin)}, {sql_text(supplier)}, "
            f"{sql_date(last_inv)}, {sql_num(inv_count) if inv_count else '0'}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, {sql_text(ADMIN_TEAM_ID)}, TRUE)\n"
            f"ON CONFLICT (origin_id) DO NOTHING;"
        )
    return stmts


def process_consumable_inventory(rows):
    stmts = []
    for r in rows:
        ciid = g(r, "Consumable Inventory ID").strip()
        item = g(r, "Consumable Inventory Item").strip()
        if not ciid:
            continue

        inv_date = g(r, "Last Inventory Date").strip()
        inv_count = g(r, "Inventory Count").strip()

        stmts.append(
            f"INSERT INTO public.consumable_inventory "
            f"(consumable_inventory_id, consumable_inventory_item, last_inventory_date, "
            f"inventory_count, company_id, facility_id, created_by, is_active)\n"
            f"VALUES ({sql_text(ciid)}, {sql_text(item)}, {sql_date(inv_date)}, "
            f"{sql_num(inv_count)}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, {sql_text(ADMIN_TEAM_ID)}, TRUE)\n"
            f"ON CONFLICT (consumable_inventory_id) DO NOTHING;"
        )

        # Also insert into history if we have date + count
        if inv_date and inv_count and inv_count.strip():
            stmts.append(
                f"INSERT INTO public.consumable_inventory_history "
                f"(history_id, consumable_id, inventory_date, inventory_count, notes, "
                f"facility_id, company_id, created_at, updated_at, created_by)\n"
                f"SELECT gen_random_uuid()::text, {sql_text(ciid)}, {sql_date(inv_date)}, "
                f"{sql_num(inv_count)}, 'Initial migration count', "
                f"{sql_text(FACILITY_ID)}, {sql_text(COMPANY_ID)}, now(), now(), {sql_text(ADMIN_TEAM_ID)}\n"
                f"WHERE NOT EXISTS (\n"
                f"  SELECT 1 FROM public.consumable_inventory_history\n"
                f"  WHERE consumable_id = {sql_text(ciid)} AND inventory_date = {sql_date(inv_date)}\n"
                f");"
            )

    return stmts


def process_customers(rows):
    stmts = []
    for r in rows:
        cid = g(r, "Customer ID").strip()
        if not cid:
            continue

        # Sheet "Notes" maps to DB "tags" column
        stmts.append(
            f"INSERT INTO public.customers "
            f"(customer_id, customer_category, name_company, "
            f"deal_open_closed, sales_area, sales_person, email, phone, street, city, "
            f"state, zip, tags, customer_since, flag, "
            f"created_at, created_by, updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(cid)}, {sql_text(g(r, 'Customer Category'))}, {sql_text(g(r, 'Name/Company'))}, "
            f"{sql_bool(g(r, 'Deal Open/Closed'))}, {sql_text(g(r, 'Sales Area'))}, {sql_text(g(r, 'Sales Person'))}, "
            f"{sql_text(g(r, 'Email'))}, {sql_text(g(r, 'Phone'))}, {sql_text(g(r, 'Street'))}, {sql_text(g(r, 'City'))}, "
            f"{sql_text(g(r, 'State'))}, {sql_text(g(r, 'Zip'))}, {sql_text(g(r, 'Notes'))}, "
            f"{sql_date(g(r, 'Customer Since'))}, {sql_bool(g(r, 'Flag'))}, "
            f"now(), {sql_text(ADMIN_TEAM_ID)}, now(), NULL, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (customer_id) DO NOTHING;"
        )
    return stmts


def process_contacts(rows):
    """Contact table — columns: Contact ID, Contact, Company, Role, Email, Phone, Notes."""
    stmts = []
    for r in rows:
        cid = g(r, "Contact ID").strip()
        if not cid:
            continue

        stmts.append(
            f"INSERT INTO public.contacts "
            f"(contact_id, contact, role, email, phone, notes, "
            f"customer_id, company_id, facility_id, is_primary, is_active)\n"
            f"VALUES ({sql_text(cid)}, {sql_text(g(r, 'Contact'))}, {sql_text(g(r, 'Role'))}, "
            f"{sql_text(g(r, 'Email'))}, {sql_text(g(r, 'Phone'))}, {sql_text(g(r, 'Notes'))}, "
            f"{sql_text(g(r, 'Company'))}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, TRUE, TRUE)\n"
            f"ON CONFLICT (contact_id) DO NOTHING;"
        )
    return stmts


def process_roast_recipes(rows):
    """Recipes + decompose into recipe_components."""
    recipe_stmts = []
    component_stmts = []

    for r in rows:
        rid = g(r, "Recipe ID").strip()
        if not rid:
            continue

        recipe_name = g(r, "Recipe Name")
        image = g(r, "Image")

        # Decompose origins
        origin_pairs = []
        for i in range(1, 6):
            origin_key = f"Origin {i}" if i > 1 else "Origin 1"
            pct_key = "Percentage" if i == 1 else f"Percentage {i}"
            origin_val = g(r, origin_key).strip()
            pct_val = g(r, pct_key).strip()
            if origin_val:
                origin_pairs.append((origin_val, pct_val))

        num_origins = len(origin_pairs)
        roast_type = "'Pre-Blend'" if num_origins > 1 else "'Single Origin/Post-Blend'"

        recipe_stmts.append(
            f"INSERT INTO public.roast_recipes "
            f"(recipe_id, recipe_name, image, roast_type, "
            f"company_id, facility_id, created_at, updated_at, created_by)\n"
            f"VALUES ({sql_text(rid)}, {sql_text(recipe_name)}, {sql_text(image)}, {roast_type}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now(), {sql_text(ADMIN_TEAM_ID)})\n"
            f"ON CONFLICT (recipe_id) DO NOTHING;"
        )

        for origin_val, pct_val in origin_pairs:
            comp_id = new_uuid()
            # Parse percentage: "70.00%" -> 0.70
            pct_num = "NULL"
            if pct_val:
                try:
                    pct_num = str(float(pct_val.replace("%", "")) / 100)
                except ValueError:
                    pct_num = "NULL"

            component_stmts.append(
                f"INSERT INTO public.recipe_components "
                f"(component_id, recipe_id, item_id, percentage, coffee_item, "
                f"created_at, updated_at, created_by, company_id, facility_id)\n"
                f"VALUES ({sql_text(comp_id)}, {sql_text(rid)}, {sql_text(origin_val)}, {pct_num}, "
                f"{sql_text(origin_val)}, now(), now(), {sql_text(ADMIN_TEAM_ID)}, "
                f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
                f"ON CONFLICT (component_id) DO NOTHING;"
            )

    return recipe_stmts, component_stmts


def process_roast_log(rows, charge_weight_map):
    """Roast log — charge_weight is now a UUID FK to charge_weight_options.
    We need to map the kg value to the charge_weight_options row we created."""
    stmts = []
    for r in rows:
        rlid = g(r, "Roast Log ID").strip()
        if not rlid:
            continue

        roast_date = g(r, "Roast Date")
        origin = g(r, "Origin")
        recipe_id = g(r, "Recipe ID")
        cw_kg = g(r, "Charge Weight").strip()
        rw_kg = g(r, "Roasted Weight").strip()
        charged = g(r, "Charged?")
        chaff = g(r, "Chaff Cleaned?")

        # Convert weights kg -> lbs
        cw_lbs = kg_to_lbs(cw_kg)
        rw_lbs = kg_to_lbs(rw_kg)

        # Map charge_weight to the UUID
        cw_uuid = charge_weight_map.get(cw_kg, None)

        stmts.append(
            f"INSERT INTO public.roast_log "
            f'(roast_log_id, roast_date, origin_id, recipe_id, '
            f'charge_weight, charge_weight_lbs, roasted_weight, '
            f'"charged?", "chaff_cleaned?", '
            f"created_at, created_by, updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(rlid)}, {sql_timestamp(roast_date)}, {sql_text(origin)}, "
            f"{sql_text(recipe_id)}, {sql_text(cw_uuid) if cw_uuid else 'NULL'}, "
            f"{cw_lbs}, {rw_lbs}, "
            f"{sql_bool(charged)}, {sql_bool(chaff)}, "
            f"now(), {sql_text(ADMIN_TEAM_ID)}, now(), NULL, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (roast_log_id) DO NOTHING;"
        )
    return stmts


def derive_group_name(product_name, product_type):
    """Derive a product group name by stripping channel suffix and size labels.
    UK products use sizes like 227g, 1KG, 500g, Case of N, etc.
    """
    import re
    if product_type in ('Merged', 'Sample'):
        return None
    name = product_name or ''
    # Strip channel suffix (- DTC, - WS)
    name = re.sub(r'\s+-\s+(DTC|WS)\s*$', '', name, flags=re.IGNORECASE).strip()
    # Strip trailing size labels (metric and imperial, case of N)
    name = re.sub(
        r'\s+(\d+(?:\.\d+)?\s*(?:g|kg|lbs?|oz)|Case\s+of\s+\d+|\d+(?:\.\d+)?\s*(?:G|KG|LBS?|OZ))\s*$',
        '', name, flags=re.IGNORECASE
    ).strip()
    return name if name else None


def process_products(rows):
    """Products — also extract consumable BOM into product_consumables.
    Derives product groups and includes group_id in INSERT (required by constraint).
    """
    import uuid as _uuid

    product_stmts = []
    bom_stmts = []
    group_stmts = []

    # Pass 1: build group_name → group_id mapping
    group_map = {}  # group_name -> group_id
    products_data = []
    for r in rows:
        pid = g(r, "Product Id").strip()
        if not pid:
            continue
        pname = g(r, "Product Name")
        ptype = g(r, "Product Type")
        gname = derive_group_name(pname, ptype)
        if gname and gname not in group_map:
            group_map[gname] = str(_uuid.uuid4())
        products_data.append((r, pid, pname, ptype, gname))

    # Emit product_groups INSERTs
    for gname, gid in sorted(group_map.items()):
        group_stmts.append(
            f"INSERT INTO public.product_groups "
            f"(group_id, group_name, company_id, facility_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(gid)}, {sql_text(gname)}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now())\n"
            f"ON CONFLICT (group_id) DO NOTHING;"
        )

    # Pass 2: emit product INSERTs with group_id
    for r, pid, pname, ptype, gname in products_data:
        gid = group_map.get(gname) if gname else None
        is_active = "FALSE" if sql_bool(g(r, "Archived?")) == "TRUE" else "TRUE"

        # Resolve product_type text → UUID (required by FK constraint)
        ptype_id = PRODUCT_TYPE_MAP.get(ptype, ptype)

        product_stmts.append(
            f"INSERT INTO public.products "
            f"(product_id, product_name, recipe_id, product_type, size, image, "
            f"group_id, is_active, created_at, created_by, updated_at, updated_by, "
            f"company_id, facility_id)\n"
            f"VALUES ({sql_text(pid)}, {sql_text(pname)}, "
            f"{sql_text(g(r, 'Recipe Id'))}, {sql_text(ptype_id)}, "
            f"{sql_text(g(r, 'Size'))}, {sql_text(g(r, 'Image'))}, "
            f"{sql_text(gid)}, "
            f"{is_active}, now(), {sql_text(ADMIN_TEAM_ID)}, now(), NULL, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (product_id) DO NOTHING;"
        )

        # Unflatten consumable BOM: Consumable Inventory ID 1..4
        seen_consumables = set()
        for i in range(1, 5):
            cid = g(r, f"Consumable Inventory ID {i}").strip()
            if not cid or cid in seen_consumables:
                continue
            seen_consumables.add(cid)

            # Count how many times this consumable appears (for quantity)
            qty = sum(1 for j in range(1, 5)
                      if g(r, f"Consumable Inventory ID {j}").strip() == cid)

            bom_id = new_uuid()
            bom_stmts.append(
                f"INSERT INTO public.product_consumables "
                f"(product_consumable_id, product_id, consumable_id, quantity, "
                f"company_id, facility_id, created_at, updated_at)\n"
                f"VALUES ({sql_text(bom_id)}, {sql_text(pid)}, {sql_text(cid)}, {qty}, "
                f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now())\n"
                f"ON CONFLICT (product_consumable_id) DO NOTHING;"
            )

    return group_stmts, product_stmts, bom_stmts


def process_products_price_log(rows):
    """Price log — strip £ symbol, store numeric."""
    stmts = []
    for r in rows:
        plid = g(r, "Price Log ID").strip()
        if not plid:
            continue

        price = g(r, "Price").strip()
        date_updated = g(r, "Date Updated")
        end_date = g(r, "End Date")

        stmts.append(
            f"INSERT INTO public.products_price_log "
            f"(price_log_id, product_id, price, date_updated, end_date, "
            f"company_id, facility_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(plid)}, {sql_text(g(r, 'Product Id'))}, "
            f"{sql_num(price)}, {sql_date(date_updated)}, {sql_date(end_date)}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now())\n"
            f"ON CONFLICT (price_log_id) DO NOTHING;"
        )
    return stmts


def process_orders(rows):
    stmts = []
    for r in rows:
        oid = g(r, "Order Id").strip()
        if not oid:
            continue

        stmts.append(
            f"INSERT INTO public.orders "
            f"(order_id, customer_id, order_date, order_status, order_notes, "
            f'previous_order, next_order, "update column", '
            f"created_at, created_by, updated_at, updated_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(oid)}, {sql_text(g(r, 'Customer Id'))}, "
            f"{sql_date(g(r, 'Order Date'))}, {sql_text(g(r, 'Order Status'))}, "
            f"{sql_text(g(r, 'Order Notes'))}, "
            f"{sql_text(g(r, 'Previous Order'))}, {sql_text(g(r, 'Next Order'))}, "
            f"{sql_text(g(r, 'update column'))}, "
            f"now(), {sql_text(ADMIN_TEAM_ID)}, now(), NULL, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (order_id) DO NOTHING;"
        )
    return stmts


def process_order_details(rows):
    stmts = []
    for r in rows:
        odid = g(r, "OrderDetail Id").strip()
        if not odid:
            continue
        qty = g(r, "Quantity").strip()
        try:
            if float(qty) <= 0:
                continue  # skip zero/negative quantity rows
        except (ValueError, TypeError):
            pass

        stmts.append(
            f"INSERT INTO public.order_details "
            f"(order_detail_id, order_id, product_id, coffee_prep, quantity, "
            f"item_status, previous_order_details, next_order_details, "
            f"company_id, facility_id, created_at, created_by, updated_at)\n"
            f"VALUES ({sql_text(odid)}, {sql_text(g(r, 'Order Id'))}, "
            f"{sql_text(g(r, 'Product Id'))}, {sql_text(g(r, 'Coffee Prep'))}, "
            f"{sql_num(g(r, 'Quantity'))}, {sql_text(g(r, 'Item Status'))}, "
            f"{sql_text(g(r, 'Previous Order Details'))}, {sql_text(g(r, 'Next Order Details'))}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), {sql_text(ADMIN_TEAM_ID)}, now())\n"
            f"ON CONFLICT (order_detail_id) DO NOTHING;"
        )
    return stmts


def process_shipment_received(rows):
    stmts = []
    for r in rows:
        sid = g(r, "Shipment ID").strip()
        if not sid:
            continue
        stmts.append(
            f"INSERT INTO public.shipment_received "
            f"(shipment_id, supplier_id, shipping_cost, date_received, "
            f"created_at, updated_at, created_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(sid)}, {sql_text(g(r, 'Supplier Id'))}, "
            f"{sql_num(g(r, 'Shipping Cost'))}, {sql_date(g(r, 'Date Received'))}, "
            f"now(), now(), {sql_text(ADMIN_TEAM_ID)}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (shipment_id) DO NOTHING;"
        )
    return stmts


def process_coffee_inventory_purchased(rows):
    stmts = []
    for r in rows:
        opid = g(r, "Origin Purchase ID").strip()
        if not opid:
            continue
        stmts.append(
            f"INSERT INTO public.coffee_inventory_purchased "
            f"(origin_purchase_id, shipment_id, origin, cost_lb, amount, "
            f"created_at, updated_at, created_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(opid)}, {sql_text(g(r, 'Shipment ID'))}, "
            f"{sql_text(g(r, 'Origin'))}, {sql_num(g(r, 'Cost/LB'))}, "
            f"{sql_num(g(r, 'Amount'))}, "
            f"now(), now(), {sql_text(ADMIN_TEAM_ID)}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (origin_purchase_id) DO NOTHING;"
        )
    return stmts


def process_consumable_inventory_purchased(rows):
    stmts = []
    for r in rows:
        cpid = g(r, "Consumable Purchase ID").strip()
        if not cpid:
            continue
        stmts.append(
            f"INSERT INTO public.consumable_inventory_purchased "
            f"(consumable_purchase_id, shipment_id, consumable_inventory_item, cost_unit, amount, "
            f"created_at, updated_at, created_by, company_id, facility_id)\n"
            f"VALUES ({sql_text(cpid)}, {sql_text(g(r, 'Shipment ID'))}, "
            f"{sql_text(g(r, 'Consumable Inventory Item'))}, {sql_num(g(r, 'Cost/Unit'))}, "
            f"{sql_num(g(r, 'Amount'))}, "
            f"now(), now(), {sql_text(ADMIN_TEAM_ID)}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT (consumable_purchase_id) DO NOTHING;"
        )
    return stmts


def process_sales_goals(rows):
    stmts = []
    for r in rows:
        sgid = g(r, "Sales Goal ID").strip()
        if not sgid:
            continue
        stmts.append(
            f"INSERT INTO public.sales_goals "
            f"(sales_goal_id, sales_person, first_action_daily_goal, follow_up_action_daily_goal, "
            f"personal_action_weekly_goal, signed_accounts_weekly_goal, "
            f"company_id, facility_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(sgid)}, {sql_text(g(r, 'Sales Person'))}, "
            f"{sql_num(g(r, 'First Action Daily Goal'))}, {sql_num(g(r, 'Follow up Action Daily Goal'))}, "
            f"{sql_num(g(r, 'Personal Action Weekly Goal'))}, {sql_num(g(r, 'Signed Accounts Weekly Goal'))}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now())\n"
            f"ON CONFLICT (sales_goal_id) DO NOTHING;"
        )
    return stmts


def process_sales_tracking(rows):
    stmts = []
    for r in rows:
        stid = g(r, "Sales Tracking ID").strip()
        if not stid:
            continue
        stmts.append(
            f"INSERT INTO public.sales_tracking "
            f"(sales_tracking_id, sales_person, period, "
            f"company_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(stid)}, {sql_text(g(r, 'Sales Person'))}, "
            f"{sql_text(g(r, 'Period'))}, "
            f"{sql_text(COMPANY_ID)}, now(), now())\n"
            f"ON CONFLICT (sales_tracking_id) DO NOTHING;"
        )
    return stmts


def process_sales_tasks(rows):
    stmts = []
    for r in rows:
        stid = g(r, "Sales Task Id").strip()
        if not stid:
            continue
        stmts.append(
            f"INSERT INTO public.sales_tasks "
            f"(sales_task_id, sales_person, customer_id, contact, sales_activity_type, "
            f"task, date_due, status, "
            f"company_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(stid)}, {sql_text(g(r, 'Sales Person'))}, "
            f"{sql_text(g(r, 'Customer Id'))}, {sql_text(g(r, 'Contact'))}, "
            f"{sql_text(g(r, 'Sales Activity Type'))}, {sql_text(g(r, 'Task'))}, "
            f"{sql_date(g(r, 'Date Due'))}, {sql_bool(g(r, 'Status'))}, "
            f"{sql_text(COMPANY_ID)}, now(), now())\n"
            f"ON CONFLICT (sales_task_id) DO NOTHING;"
        )
    return stmts


def process_sales_notes(rows):
    stmts = []
    for r in rows:
        snid = g(r, "SalesNote Id").strip()
        if not snid:
            continue
        stmts.append(
            f"INSERT INTO public.sales_notes "
            f"(salesnote_id, customer_id, contact, sales_activity_type, "
            f"sales_person, sales_note, date, "
            f"company_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(snid)}, {sql_text(g(r, 'Customer Id'))}, "
            f"{sql_text(g(r, 'Contact'))}, {sql_text(g(r, 'Sales Activity Type'))}, "
            f"{sql_text(g(r, 'Sales Person'))}, {sql_text(g(r, 'Sales Note'))}, "
            f"{sql_date(g(r, 'Date'))}, "
            f"{sql_text(COMPANY_ID)}, now(), now())\n"
            f"ON CONFLICT (salesnote_id) DO NOTHING;"
        )
    return stmts


def process_product_filter(rows):
    stmts = []
    for r in rows:
        pfid = g(r, "Products Filter ID").strip()
        if not pfid:
            continue
        stmts.append(
            f"INSERT INTO public.product_filter "
            f"(products_filter_id, product_id, recipe_id, size, order_status, "
            f"company_id, facility_id, created_at, updated_at)\n"
            f"VALUES ({sql_text(pfid)}, {sql_text(g(r, 'Product'))}, "
            f"{sql_text(g(r, 'Recipe'))}, {sql_text(g(r, 'Size'))}, "
            f"{sql_text(g(r, 'Order Status'))}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now())\n"
            f"ON CONFLICT (products_filter_id) DO NOTHING;"
        )
    return stmts


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    log("=" * 60)
    log("Social Hour UK -> Supabase Migration")
    log("=" * 60)

    # ── 0. Setup IDs ────────────────────────────────────────────────────
    all_sql = []
    stats = {}

    def emit(table, stmts):
        stats[table] = len(stmts)
        if stmts:
            all_sql.append(f"\n-- ── {table} ({len(stmts)} rows) " + "─" * 40)
            all_sql.extend(stmts)

    # ── 1. Create company + facility ────────────────────────────────────
    log("\n[1] Setting up company and facility ...")
    emit("_company_setup", process_company_setup())

    # ── 2. Fetch all CSVs ───────────────────────────────────────────────
    log("\n[2] Fetching CSVs from Google Sheets ...")
    csv_data = {}
    for tab_name in TABS:
        try:
            csv_data[tab_name] = fetch_csv(tab_name)
        except Exception as e:
            log(f"  ERROR fetching {tab_name}: {e}")
            csv_data[tab_name] = []

    # ── 3. Team members ─────────────────────────────────────────────────
    log("\n[3] Processing team members ...")
    emit("team", process_team(csv_data["Team"], csv_data["Sales Team"]))

    # ── 4. Seed company_parameters ──────────────────────────────────────
    log("\n[4] Seeding company_parameters ...")
    emit("company_parameters", process_seed_params())

    # ── 5. Recent coffee order singleton ────────────────────────────────
    log("\n[5] Provisioning recent_coffee_order ...")
    emit("recent_coffee_order", process_recent_coffee_order())

    # ── 6. Reference / config tables ────────────────────────────────────
    log("\n[6] Processing reference tables ...")
    emit("supplier_category", process_supplier_category(csv_data["Supplier Category"]))
    emit("supplier", process_supplier(csv_data["Supplier"]))
    emit("contact_role", process_contact_role(csv_data["Contact Role"]))
    emit("sales_area", process_sales_area(csv_data["Sales Area"]))
    emit("size", process_size(csv_data["Size"]))

    # Charge weight options — need to track the mapping for roast_log
    charge_weight_map = {}  # kg_value -> uuid
    cw_rows = csv_data["Charge Weight Options"]
    cw_stmts = []
    for r in cw_rows:
        cw_kg = g(r, "Charge Weight Options").strip()
        if not cw_kg:
            continue
        cw_lbs = kg_to_lbs(cw_kg)
        cw_id = new_uuid()
        charge_weight_map[cw_kg] = cw_id
        cw_stmts.append(
            f"INSERT INTO public.charge_weight_options (id, charge_weight, company_id, facility_id)\n"
            f"VALUES ({sql_text(cw_id)}, {cw_lbs}, {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)})\n"
            f"ON CONFLICT DO NOTHING;"
        )
    emit("charge_weight_options", cw_stmts)

    # ── 7. Inventory ────────────────────────────────────────────────────
    log("\n[7] Processing inventory ...")
    emit("coffee_inventory", process_coffee_inventory(csv_data["Coffee Inventory"]))
    emit("consumable_inventory", process_consumable_inventory(csv_data["Consumable Inventory"]))

    # ── 8. Customers + Contacts ─────────────────────────────────────────
    log("\n[8] Processing customers + contacts ...")
    emit("customers", process_customers(csv_data["Customers"]))
    emit("contacts", process_contacts(csv_data["Contact"]))

    # ── 9. Recipes ──────────────────────────────────────────────────────
    log("\n[9] Processing recipes ...")
    recipe_stmts, component_stmts = process_roast_recipes(csv_data["Roast Recipes"])
    emit("roast_recipes", recipe_stmts)
    emit("recipe_components", component_stmts)

    # ── 10. Roast log ───────────────────────────────────────────────────
    log("\n[10] Processing roast log ...")
    emit("roast_log", process_roast_log(csv_data["Roast Log"], charge_weight_map))

    # ── 11. Products + BOM ──────────────────────────────────────────────
    log("\n[11] Processing products + consumable BOM ...")
    group_stmts, product_stmts, bom_stmts = process_products(csv_data["Products"])
    emit("product_groups", group_stmts)
    emit("products", product_stmts)
    emit("product_consumables", bom_stmts)

    # ── 12. Price log ───────────────────────────────────────────────────
    log("\n[12] Processing price log ...")
    emit("products_price_log", process_products_price_log(csv_data["Products Price Log"]))

    # ── 13. Shipments + Purchases ───────────────────────────────────────
    log("\n[13] Processing shipments (may be empty) ...")
    emit("shipment_received", process_shipment_received(csv_data["Shipment Received"]))
    emit("coffee_inventory_purchased", process_coffee_inventory_purchased(csv_data["Coffee Inventory Purchased"]))
    emit("consumable_inventory_purchased", process_consumable_inventory_purchased(csv_data["Consumable Inventory Purchased"]))

    # ── 14. Orders ──────────────────────────────────────────────────────
    log("\n[14] Processing orders ...")
    emit("orders", process_orders(csv_data["Orders"]))
    emit("order_details", process_order_details(csv_data["Order Details"]))

    # ── 15. Sales tables ────────────────────────────────────────────────
    log("\n[15] Processing sales tables ...")
    emit("sales_goals", process_sales_goals(csv_data["Sales Goals"]))
    emit("sales_tracking", process_sales_tracking(csv_data["Sales Tracking"]))
    emit("sales_tasks", process_sales_tasks(csv_data["Sales Tasks"]))
    emit("sales_notes", process_sales_notes(csv_data["Sales Notes"]))
    emit("product_filter", process_product_filter(csv_data["Product Filter"]))

    # ── 16. Output SQL ──────────────────────────────────────────────────
    log("\n[16] Generating SQL ...\n")

    print("-- =============================================================")
    print("-- Social Hour Coffee Roasters UK -> Supabase Migration")
    print(f"-- Generated: {datetime.now().isoformat()}")
    print(f"-- Company:   {COMPANY_ID}")
    print(f"-- Facility:  {FACILITY_ID}")
    print("-- =============================================================")
    print()
    print("BEGIN;")
    print()
    print("-- Disable triggers during bulk insert to avoid cost chain cascades")
    print("SET session_replication_role = replica;")

    for line in all_sql:
        print(line)

    print()
    print("-- Re-enable triggers")
    print("SET session_replication_role = DEFAULT;")

    # Backfill snapshot columns
    print()
    print("-- Backfill snapshot columns")
    print(f"""UPDATE public.roast_log rl
SET
  recipe_name_snapshot = rr.recipe_name,
  coffee_name_snapshot = ci.origin
FROM public.roast_recipes rr,
     public.coffee_inventory ci
WHERE rl.recipe_id = rr.recipe_id
  AND ci.origin_id = rl.origin_id
  AND ci.facility_id = rl.facility_id
  AND rl.company_id = '{COMPANY_ID}'
  AND (rl.recipe_name_snapshot IS NULL OR rl.coffee_name_snapshot IS NULL);""")
    print()
    print(f"""UPDATE public.order_details od
SET product_name_snapshot = p.product_name
FROM public.products p
WHERE od.product_id = p.product_id
  AND od.company_id = '{COMPANY_ID}'
  AND od.product_name_snapshot IS NULL;""")

    # After re-enabling triggers, touch products to fire COGS calc
    print()
    print("-- Touch products to trigger COGS calculation")
    print(f"""UPDATE public.products
SET updated_at = now()
WHERE company_id = '{COMPANY_ID}';""")

    print()
    print("COMMIT;")

    # Summary
    log("=" * 60)
    log("Summary:")
    total = 0
    for table, count in stats.items():
        log(f"  {table:40s}  {count:4d} rows")
        total += count
    log(f"  {'TOTAL':40s}  {total:4d} rows")
    log("=" * 60)
    log(f"\nCompany ID:  {COMPANY_ID}")
    log(f"Facility ID: {FACILITY_ID}")
    log(f"Admin Team:  {ADMIN_TEAM_ID}")
    log(f"\nSQL written to stdout. Review, then execute:")
    log(f"  PGPASSWORD='...' psql \"$DATABASE_URL\" < scripts/migration_uk.sql")


if __name__ == "__main__":
    main()
