#!/usr/bin/env python3
"""
Import MCR coffee + consumable invoices into Supabase.
Generates SQL to stdout, progress/warnings to stderr.

Usage:
    python3 scripts/import_mcr_invoices.py > scripts/mcr_invoices.sql 2> scripts/mcr_invoices.log
    # Review SQL, then:
    PGPASSWORD='SDH-h3FNHXSrxj-' psql "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres" < scripts/mcr_invoices.sql
"""

import os, re, sys, uuid, pdfplumber
from datetime import datetime, date
from pathlib import Path

# ── Constants ─────────────────────────────────────────────────────────────────
COMPANY_ID  = "9ShiyDAXhV"
FACILITY_ID = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"
COFFEE_DIR     = Path("/Users/wanderingaloha/my-supabase-project/MCR/strata migration/Coffee Invoices/Royal Invoices")
CONSUMABLE_DIR = Path("/Users/wanderingaloha/my-supabase-project/MCR/strata migration/Consumable Invoices")
SKIP_FILES = {
    "6145929[24].pdf",  # exact duplicate of 6145929
    "6117212.pdf",      # tariff surcharge for prior Guatemala invoice — not a new shipment
    "6127437.pdf",      # finance charge for late payment — not a coffee purchase
    "6127439.pdf",      # finance charge for late payment — not a coffee purchase
}

# ── Bag sizes available in DB (lbs) ───────────────────────────────────────────
BAG_SIZES_LBS = [40, 47, 50, 66, 94, 100, 110, 132, 134, 152, 154, 656, 658, 664]

# ── Origin keyword → origin_id ────────────────────────────────────────────────
ORIGIN_MAP = [
    ("colombia",    "orig_d393e3392710921a"),
    ("honduras",    "orig_d669c72ce18c7651"),
    ("brazil",      "orig_c655bcaf99a986b1"),
    ("peru",        "orig_5e487c2d0035d0d4"),
    ("guatemala",   "orig_b3890561c1c3ba25"),
    ("nicaragua",   "orig_bd7157c2ff0a76b3"),
    ("mexico",      "orig_0d75323d13d7e2fe"),
    ("costa rica",  "orig_d5456517bf131c45"),
    ("el salvador", "orig_28d3a9afb33fb94a"),
    ("sumatra",     "orig_17c8424053723e32"),
    ("timor",       "orig_48164153d732217b"),
    ("papua",       "orig_93f7f73f959de942"),
    ("png",         "orig_93f7f73f959de942"),
    ("new guinea",  "orig_93f7f73f959de942"),
    ("yemen",       "orig_0798b3ed3a9e31a1"),
    ("kona",        "orig_2bb4bb4cfe71072a"),
    ("ka'u",        "orig_afb785641116ec03"),
    ("kau",         "orig_afb785641116ec03"),
    ("maui",        "orig_142ffc976e750f22"),
    ("sulawesi",    "orig_17c8424053723e32"),  # Indonesia, closest = Sumatra
    ("toraja",      "orig_17c8424053723e32"),  # Sulawesi sub-region → Sumatra
]

# ── Coffee source fuzzy map (first match wins) ────────────────────────────────
COFFEE_SOURCE_MAP = [
    ("colombia excelso ep",       "csrc_0a84d7ad205487c5"),
    ("colombia excelso",          "csrc_0a84d7ad205487c5"),
    ("colombia supremo",          "csrc_1619c377f98171c9"),
    ("colombia medellin",         "csrc_a62b479c16f3a46f"),
    ("colombia medellin excelso", "csrc_a62b479c16f3a46f"),
    ("colombia huila",            "csrc_e59e36a550ac6cfe"),
    ("colombia gesha",            "csrc_241e8bed4968e9f0"),
    ("organic colombia",          "csrc_51dc895c7e973ba2"),
    ("decaf colombia",            "csrc_058f4808fbf5f03e"),
    ("honduras copan",            "csrc_548695e94eeac96e"),
    ("honduras comsa",            "csrc_2c416abfbff80f03"),
    ("honduras calan",            "csrc_f48911ac42eb8b84"),
    ("honduras siguatepeque",     "csrc_fec67ce029c1abd0"),
    ("organic honduras copan",    "csrc_90760e479a2af138"),
    ("organic honduras",          "csrc_e58386e99c4408e6"),
    ("brazil mogiana",            "csrc_e6cac7ee284067a7"),
    ("brazil sul de minas",       "csrc_7d11bddf8db2e72d"),
    ("brazil natural",            "csrc_81f73985aac71db7"),
    ("organic peru selva",        "csrc_c8a7362b8bc1d2fc"),
    ("organic peru",              "csrc_1483d3f39c6ded9f"),
    ("peru vida",                 "csrc_c3692df4e5b76f59"),
    ("peru ft",                   "csrc_9e22c4ecd79db3bb"),
    ("guatemala shb",             "csrc_254a56c3c710f2c2"),
    ("guatemala",                 "csrc_254a56c3c710f2c2"),
    ("nicaragua robusta",         "csrc_0c03c745fe7bc804"),
    ("nicaragua olomega",         "csrc_7c9c7f0eca21d029"),
    ("nicaragua segovia",         "csrc_c3d0eb4019e21b9b"),
    ("organic nicaragua",         "csrc_10b5149aecee5e0d"),
    ("decaf mexico",              "csrc_167feec140bf4ccc"),
    ("organic mexico",            "csrc_211af3db661e89ed"),
    ("mexico veracruz",           "csrc_c8bfd38d18d2a86b"),
    ("sumatra takengon",          "csrc_b39931a7edd8a6e3"),
    ("organic timor",             "csrc_b505ba346aadb72d"),
    ("organic png simbu",         "csrc_c9f7cf5ed2d057ae"),
    ("organic png",               "csrc_209100c254f6e64d"),
    ("png peaberry",              "csrc_b0855e2e4d4a11c5"),
    ("papua new guinea peaberry", "csrc_d2bed255e650be0e"),
    ("costa rica tarrazu",        "csrc_c66f57af57b8205f"),
    ("costa rica",                "csrc_c66f57af57b8205f"),
    ("el salvador",               "csrc_214aa09f8d6df8d9"),
    ("yemen",                     "csrc_f9c78ea8c2cdba62"),
    ("kona peaberry",             "csrc_5b2aa7260e08ff80"),
    ("kona prime peaberry",       "csrc_e8146f2795c12d52"),
    ("kona prime",                "csrc_e9680b0b3ec3c1b2"),
    ("kona organic",              "csrc_cd00fb0683a9171d"),
    ("kona decaf",                "csrc_3ee355aeaa090e0d"),
    ("kona castaway reserve",     "csrc_3983ca85110c4fa5"),
    ("kona castaway",             "csrc_54f520e29c3c78d2"),
    ("ka'u honey",                "csrc_c46a36549e65eff7"),
    ("ka'u",                      "csrc_419905aff309b85a"),
    ("maui red peaberry",         "csrc_8cac746b77fa5e30"),
    ("maui yellow peaberry",      "csrc_bfd0fd07d8f36e9e"),
    ("maui red natural",          "csrc_4e30e28a5edaac06"),
    ("maui red h3",               "csrc_e9a889b35f8b992e"),
    ("maui red catuai",           "csrc_0f87e935cf02c610"),
    ("maui red",                  "csrc_0d41704569f55641"),
    ("maui yellow h3",            "csrc_d793c3dba1f9c7d9"),
    ("maui yellow",               "csrc_d11df67fcd1d3bd9"),
    ("maui moka",                 "csrc_44109ca9903ae026"),
    ("maui h3",                   "csrc_a6837a97a66e2a7e"),
]

# ── Consumable SKU maps (per-supplier) ────────────────────────────────────────

MONIN_SKU = {
    "M-AS045A":  "cons_6fcd68bddd0cc8ba",  # SF Vanilla
    "M-AS009A":  "cons_e5cff3ce8154a1c8",  # SF Caramel
    "M-AS023A":  "cons_51149e49cc6f260c",  # SF Hazelnut
    "M-AS013A":  "cons_e4e215eb5786b96f",  # SF Coconut
    "M-AR008A":  "cons_443bb82c7f671064",  # Blueberry
    "M-AR009A":  "cons_12e35025493dedf2",  # Caramel
    "M-AR013A":  "cons_f0e92246b3b5840e",  # Coconut
    "M-AR018A":  "cons_25ecc8e8c7fc8d0d",  # Ginger
    "M-AR039A":  "cons_b69d2e24130c4ce3",  # Pistachio
    "M-AR040A":  "cons_e33d8d7c290403b7",  # Raspberry
    "M-AR045A":  "cons_0a22ec5e1241b32e",  # Vanilla
    "M-AR048A":  "cons_60f47a89c1b6258d",  # Macnut
    "M-AR051A":  "cons_5b19ae609649d61c",  # Toffee Nut
    "M-AR056A":  "cons_2317692b977ca244",  # Rose
    "M-AR061A":  "cons_9f5a966e75ff92f8",  # Lavender
    "M-AR084A":  "cons_e2390001e3d85d5f",  # Honey
    "M-AR145A":  "cons_9cc08a390c6f9fd4",  # Toasted Marshmallow
    "M-AR147A":  "cons_f078adbc6749b29a",  # Elderflower
    "M-AR210A":  "cons_a51949a0726f7fb3",  # Salted Caramel
    "M-AR255A":  "cons_fe8373862bb86f36",  # Watermelon
    "M-AR361A":  "cons_e3956e2ad5de2ae3",  # Ube
    "M-AR400A":  "cons_23eca31cf45d78eb",  # Toasted Coconut
    "M-FR019F":  "cons_0e7dc2aa59104a52",  # Grapefruit
    "M-FR030F":  "cons_ce5cb1dc9d4df487",  # Lychee
    "M-FR069F":  "cons_a2ada01695e53236",  # Blood Orange
    "M-FR095F":  "cons_0a3d2c190e9fda5d",  # Cucumber
    "M-FR177F":  "cons_21e852a124c38f5b",  # Hibiscus
    "M-FR224F":  "cons_5645c1654fd679cb",  # Vanilla Creme
    "M-VJ235FP": "cons_571643ea8b27e444",  # Basil Concentrate
    "M-GC009FP": "cons_71828c5e1ab159ad",  # Dark Chocolate
}

TRICORBRAUN_ITEM = {
    "290856": "cons_379958b3eca1295c",  # 6-10oz Gusseted Silver
    "311773": "cons_b9584abbc90990ad",  # 6-10oz Gusseted Black
    "289805": "cons_1622bc2b3cb01690",  # 12-16oz Gusseted Green
    "293069": "cons_cff90efbf7e21c78",  # 12-16oz Gusseted Silver
    "289810": "cons_fdff739f2c479bac",  # 12-16oz Gusseted Brt Red
    "289141": "cons_311ef21161b37e66",  # 12-16oz Gusseted Black
    "271413": "cons_baa07dfc75ab7866",  # 12-16oz NK BBB
    "271367": "cons_2c8ddd27ee8042c2",  # 8oz NK BBB
    "289822": "cons_c8d028dd6380dada",  # 5lb Wide Gusseted Silver
    "289826": "cons_5c7ff51d2ba97f1f",  # 5lb Wide Gusseted Black
    "289820": "cons_dd19c01e76386e28",  # 5lb Wide Gusseted Gold
    "319642": "cons_0c73ab79754db53c",  # 2lb Clear/Clear Valve/Zip (Costco)
}

PACK_PLUS_ITEM = {
    "FGE-2Z01":  "cons_302777d9004715b7",  # 2oz Gusseted Gold, no valve
    "FGS-8Z07-V": "cons_29bf15b3de6be336", # 8oz Green valve (closest: 6-10oz Green)
    "FGS-8Z06-V": "cons_fdff739f2c479bac", # 8oz Red valve (closest: 12-16oz Brt Red)
}

ALLEN_ITEM = {
    "AF4490":  "cons_6caeba6fb8742db0",  # Hawaiian Hazelnut
    "AF10514": "cons_e62cfa0ba153f448",  # Chocolate Macadamia
    "AF4151":  "cons_ac35ed6867a710bb",  # Vanilla Macnut
    "AF4110":  "cons_c3fc6f48924b6385",  # French Vanilla
    "AF1709":  "cons_aabce6e7995b84c3",  # Macadamia Nut
    "AF1360":  "cons_6a70eb13ccc887d8",  # Hawaiian Coconut
    "AF1109":  "cons_531d0c39cc29f78c",  # Chocolate Raspberry
    "LA-59721": "cons_9ec693b1dbc2d162", # Lavender (S&S Flavors also uses this code)
}

MERAKI_ITEM = {
    "0AP005109": "cons_82b9675665c96f1f",  # Mediterranean Rooibos
    "0AP005115": "cons_cb195021fa33f45d",  # Earl Grey Decaf
    "0AP005103": "cons_8b7bf895c2fd8fde",  # Jasmine Green
    "0AP005114": "cons_1c8de1e3547ab0ea",  # Moroccan Mint
    "0AP005110": "cons_172b32b093e830fa",  # Ginger Citrus
    "0AP005102": "cons_5e535fefe33deab8",  # Spiced Chai
    "0AP005101": "cons_ddad54794013a012",  # English Breakfast
    "0AP005105": "cons_40a8edc107169414",  # Tropical Green
    "0AP005108": "cons_0032318a30c810ad",  # Chamomile Citrus
    "0AP005401": "cons_fd853d7bef824709",  # Raspberry Hibiscus → Hibiscus Tea
    "0AP005403": "cons_6fdca57805d5b3a4",  # Mango Black → Mango Black 50/1oz
    "0AP005402": "cons_37f5c0361e0d483e",  # Traditional Black
}

VERITIV_ITEM = {
    "10688821": "cons_d5c0afc50a71e0cf",  # 10x10x10
    "10221820": None,                       # AK/HI surcharge — skip
}

# ── Helpers ───────────────────────────────────────────────────────────────────
def log(msg): print(msg, file=sys.stderr)
def new_uuid(): return str(uuid.uuid4())

def sql_text(v):
    if v is None or (isinstance(v, str) and not v.strip()): return "NULL"
    return "'" + str(v).strip().replace("'", "''") + "'"

def sql_num(v):
    if v is None: return "NULL"
    try: return str(float(str(v).replace(",","").replace("$","").strip()))
    except: return "NULL"

def sql_date(d):
    if d is None: return "NULL"
    if isinstance(d, (date, datetime)): return f"'{d.strftime('%Y-%m-%d')}'"
    return f"'{d}'"

def parse_date(s):
    if not s: return None
    s = str(s).strip()
    for fmt in ("%m-%d-%Y","%m/%d/%Y","%Y-%m-%d","%m-%d-%y","%m/%d/%y",
                "%m/%d/%y","%B %d, %Y","%b %d, %Y","%d-%b-%Y","%m/%d/%Y %H:%M:%S",
                "%m/%d/%y %H:%M:%S"):
        try: return datetime.strptime(s, fmt).date()
        except: pass
    # Handle "02/24/2026" style already covered above; try compact date
    m = re.search(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})', s)
    if m:
        yr = int(m.group(3)); yr = yr+2000 if yr < 100 else yr
        try: return date(yr, int(m.group(1)), int(m.group(2)))
        except: pass
    return None

def kg_to_lbs(kg): return kg * 2.20462

def closest_bag_size(lbs):
    return str(min(BAG_SIZES_LBS, key=lambda x: abs(x - lbs)))

def match_origin(desc):
    d = desc.lower()
    for kw, oid in ORIGIN_MAP:
        if kw in d: return oid, kw
    return None, None

def match_coffee_source(desc):
    d = desc.lower()
    for kw, sid in COFFEE_SOURCE_MAP:
        if kw in d: return sid, kw
    return None, None

def pdf_text(path):
    with pdfplumber.open(path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)

# ── SQL builders ──────────────────────────────────────────────────────────────
def sql_supplier(sid, name, category):
    return (f"INSERT INTO public.supplier (supplier_id, supplier, supplier_category, company_id, created_at, updated_at, created_by)\n"
            f"VALUES ({sql_text(sid)},{sql_text(name)},{sql_text(category)},{sql_text(COMPANY_ID)},now(),now(),{sql_text(COMPANY_ID)})\n"
            f"ON CONFLICT (supplier_id) DO NOTHING;")

def sql_shipment(shipment_id, supplier_id, order_date, po_number, shipping_cost=None):
    return (f"INSERT INTO public.shipment_received\n"
            f"  (shipment_id, supplier_id, order_date, date_received, po_number, shipping_cost, status,\n"
            f"   company_id, facility_id, created_at, updated_at, created_by)\n"
            f"VALUES\n"
            f"  ({sql_text(shipment_id)},{sql_text(supplier_id)},{sql_date(order_date)},{sql_date(order_date)},\n"
            f"   {sql_text(po_number)},{sql_num(shipping_cost)},'received',\n"
            f"   {sql_text(COMPANY_ID)},{sql_text(FACILITY_ID)},now(),now(),{sql_text(COMPANY_ID)})\n"
            f"ON CONFLICT (shipment_id) DO NOTHING;")

def sql_coffee_purchase(purchase_id, shipment_id, origin_id, bags, cost_lb, bag_size_id, lot_id, source_id):
    return (f"INSERT INTO public.coffee_inventory_purchased\n"
            f"  (origin_purchase_id, shipment_id, origin, bags_ordered, cost_lb,\n"
            f"   bag_size, lot_id, coffee_source_id, entry_method,\n"
            f"   company_id, facility_id, created_at, updated_at, created_by)\n"
            f"VALUES\n"
            f"  ({sql_text(purchase_id)},{sql_text(shipment_id)},{sql_text(origin_id)},\n"
            f"   {sql_num(bags)},{sql_num(cost_lb)},\n"
            f"   {sql_text(bag_size_id)},{sql_text(lot_id)},{sql_text(source_id)},\n"
            f"   'shipment',\n"
            f"   {sql_text(COMPANY_ID)},{sql_text(FACILITY_ID)},now(),now(),{sql_text(COMPANY_ID)})\n"
            f"ON CONFLICT (origin_purchase_id) DO NOTHING;")

def sql_cons_purchase(purchase_id, shipment_id, cons_id, qty, cost_unit):
    return (f"INSERT INTO public.consumable_inventory_purchased\n"
            f"  (consumable_purchase_id, shipment_id, consumable_inventory_item, amount, cost_unit,\n"
            f"   company_id, facility_id, created_at, updated_at, created_by)\n"
            f"VALUES\n"
            f"  ({sql_text(purchase_id)},{sql_text(shipment_id)},{sql_text(cons_id)},\n"
            f"   {sql_num(qty)},{sql_num(cost_unit)},\n"
            f"   {sql_text(COMPANY_ID)},{sql_text(FACILITY_ID)},now(),now(),{sql_text(COMPANY_ID)})\n"
            f"ON CONFLICT (consumable_purchase_id) DO NOTHING;")

# ── Invoice parsers ───────────────────────────────────────────────────────────

def parse_royal(path):
    """
    Royal Coffee invoice.
    Item line format: N Description QTY RATE AMOUNT
    Sub-lines: REF #: X, Price: X/lb, Net Weight: X lb
    Bag size: from description "XX.X kg Bags"
    """
    result = {"invoice_number": None, "invoice_date": None, "line_items": []}
    text = pdf_text(path)
    lines = text.split("\n")

    m = re.search(r'#\s*(\d{7,})', text)
    if m: result["invoice_number"] = m.group(1)

    for pat in [r'Invoice Date\s*[:\-]?\s*(\d{2}[-/]\d{2}[-/]\d{4})',
                r'Invoice Date\s*[:\-]?\s*(\d{2}[-/]\d{2}[-/]\d{2})']:
        m = re.search(pat, text, re.IGNORECASE)
        if m: result["invoice_date"] = parse_date(m.group(1)); break

    for i, line in enumerate(lines):
        line = line.strip()
        # Numbered item line ending with: qty rate amount (three numbers)
        m = re.match(r'^(\d+)\s+(.+?)\s+([\d]+\.[\d]+)\s+([\d,\.]+)\s+([\d,\.]+)$', line)
        if not m: continue

        desc     = m.group(2).strip()
        qty_bags = int(float(m.group(3)))
        ref_no = price_lb = net_wt = bag_size_id = None

        for j in range(i+1, min(i+10, len(lines))):
            sub = lines[j].strip()
            rm = re.search(r'REF\s*#\s*[:\-]?\s*([\w\-]+)', sub, re.IGNORECASE)
            if rm and not ref_no: ref_no = rm.group(1).strip()
            pm = re.search(r'Price:\s*\$?([\d\.]+)/lb', sub, re.IGNORECASE)
            if pm and not price_lb: price_lb = float(pm.group(1))
            nm = re.search(r'Net Weight:\s*([\d,\.]+)\s*lb', sub, re.IGNORECASE)
            if nm and not net_wt: net_wt = float(nm.group(1).replace(",",""))
            if re.match(r'^\d+\s+\S', sub) and j > i+1: break

        if not price_lb or not net_wt: continue

        bm = re.search(r'([\d\.]+)\s*kg\s*Bags?', desc, re.IGNORECASE)
        if bm:
            bag_size_id = closest_bag_size(kg_to_lbs(float(bm.group(1))))

        result["line_items"].append({
            "description": desc, "ref_no": ref_no, "qty_bags": qty_bags,
            "net_weight_lbs": net_wt, "cost_lb": price_lb,
            "bag_size_id": bag_size_id, "total": round(net_wt * price_lb, 2),
        })
    return result


def parse_monin(path):
    """Monin: SKU Description UOM Qty Qty UnitPrice Total"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Monin",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice Number:\s*([\w\-]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date:\s*([\d/\-]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    for line in text.split("\n"):
        m = re.match(r'^(M-[A-Z0-9]+)\s+(.+?)\s+(\d+)\s+\d+\s+([\d\.]+)\s+([\d\.]+)', line.strip())
        if m:
            sku = m.group(1); qty = int(m.group(3))
            unit_price = float(m.group(4)); total = float(m.group(5))
            cons_id = MONIN_SKU.get(sku)
            result["line_items"].append({
                "description": f"{sku} {m.group(2).strip()}", "cons_id": cons_id,
                "qty": qty, "unit_price": unit_price, "total": total,
            })
    return result


def parse_tricorbraun(path):
    """TricorBraun: Line# Item# Description Qty Unit UnitPrice PerUnit Amount"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "TricorBraun",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Number\s+(INVF\d+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Date\s+(\d{1,2}/\d{1,2}/\d{4})', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    for line in text.split("\n"):
        line = line.strip()
        # "1 290856 6-10oz Gusseted Silver w/Valve 2,000.00 Ea 0.326000 per Each 652.00"
        m = re.match(r'^(\d+)\s+(\d{5,6})\s+(.+?)\s+([\d,]+\.[\d]+)\s+Ea\s+([\d\.]+)\s+per\s+Each\s+([\d,\.]+)', line)
        if m:
            item_no = m.group(2); desc = m.group(3).strip()
            qty = float(m.group(4).replace(",","")); unit_price = float(m.group(5))
            total = float(m.group(6).replace(",",""))
            cons_id = TRICORBRAUN_ITEM.get(item_no)
            result["line_items"].append({
                "description": f"{item_no} {desc}", "cons_id": cons_id,
                "qty": int(qty), "unit_price": unit_price, "total": total,
            })
    return result


def parse_pack_plus(path):
    """Pack Plus: SKU Description Ordered Shipped B/O UnitPrice UnitDisc Total"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Pack Plus",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'INVOICE\s+(\d+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date:\s*([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))
    m = re.search(r'Shipping(?:\s+Freight\s+Charge)?.*?\$([\d,\.]+)', text)
    if m:
        try: result["shipping_cost"] = float(m.group(1).replace(",",""))
        except: pass

    for line in text.split("\n"):
        line = line.strip()
        m = re.match(r'^(FG[ES]-\S+)\s+(.+?)\s+([\d,]+)\s+([\d,]+)\s+\d+\s+\$([\d\.]+)\s+\$[\d\.]+\s+\$([\d,\.]+)', line)
        if m:
            sku = m.group(1); desc = m.group(2).strip()
            qty = int(m.group(3).replace(",",""))
            unit_price = float(m.group(5)); total = float(m.group(6).replace(",",""))
            cons_id = PACK_PLUS_ITEM.get(sku)
            result["line_items"].append({
                "description": f"{sku} {desc}", "cons_id": cons_id,
                "qty": qty, "unit_price": unit_price, "total": total,
            })
    return result


def parse_allen_flavors(path):
    """Allen Flavors: Qty UofM CustItem ItemNo Description PackSize Qty UnitPrice ExtPrice"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Allen Flavors",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice No:\s*([\w]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Date:\s*([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    for line in text.split("\n"):
        line = line.strip()
        # "1 Jerryc AF4490-43.95 HAWAIIAN HAZELNUT TYPE (1 × 43.95 LBS) 43.95 $610.91 $610.91"
        m = re.match(r'^\d+\s+\w+\s+(AF[\d]+|LA-[\d]+)[-\.][\d\.]+\s+(.+?)\s+[\d\.]+\s+\$([\d\.]+)\s+\$([\d,\.]+)', line)
        if m:
            code = m.group(1); desc = m.group(2).strip()
            unit_price = float(m.group(3)); total = float(m.group(4).replace(",",""))
            qty = 1  # Allen sells by weight (lbs), qty=1 unit/pack
            cons_id = ALLEN_ITEM.get(code)
            result["line_items"].append({
                "description": f"{code} {desc}", "cons_id": cons_id,
                "qty": qty, "unit_price": total, "total": total,  # unit_price = total (one pack)
            })
    return result


def parse_ss_flavors(path):
    """S&S Flavors: single-line lavender flavor"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "S&S Flavors",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice Number\s+([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date\s+([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))
    m = re.search(r'Freight Charges:\s*\$([\d,\.]+)', text)
    if m:
        try: result["shipping_cost"] = float(m.group(1).replace(",",""))
        except: pass

    m = re.search(r'(LA-[\d]+).*?([\d\.]+)\s+\$([\d\.]+)\s+\$([\d,\.]+)', text)
    if m:
        code = m.group(1); qty = float(m.group(2))
        unit_price = float(m.group(3)); total = float(m.group(4).replace(",",""))
        cons_id = ALLEN_ITEM.get(code)
        result["line_items"].append({
            "description": f"{code} Lavender Flavor", "cons_id": cons_id,
            "qty": qty, "unit_price": unit_price, "total": total,
        })
    return result


def parse_meraki(path):
    """Meraki: QTY ORD QTY SHIP B.O. ITEM_NO DESCRIPTION UNIT_PRICE EXTENDED"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Meraki Tea",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Number:\s*([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Date:\s*([\w]+ [\d]+, [\d]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    for line in text.split("\n"):
        line = line.strip()
        m = re.match(r'^(\d+)\s+\d+\s+(0AP\d+)\s+(.+?)\s+\$([\d\.]+)\s+\$([\d,\.]+)', line)
        if m:
            qty = int(m.group(1)); sku = m.group(2); desc = m.group(3).strip()
            unit_price = float(m.group(4)); total = float(m.group(5).replace(",",""))
            cons_id = MERAKI_ITEM.get(sku)
            result["line_items"].append({
                "description": f"{sku} {desc}", "cons_id": cons_id,
                "qty": qty, "unit_price": unit_price, "total": total,
            })
    return result


def parse_advanced_labels(path):
    """Advanced Labels: custom label invoice"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Advanced Labels",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice No\s+([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date\s+([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # "50513 8oz Dawn Patrol Labels\n2,000 2,000 5/29/2026 $285.71 Per M $571.42"
    m = re.search(r'([\d]+)\s+(.+?Labels?)\s*\n.*?([\d,]+)\s+[\d,]+\s+[\d/]+\s+\$([\d\.]+)\s+Per\s+M\s+\$([\d,\.]+)', text)
    if m:
        prod_no = m.group(1); desc = m.group(2).strip()
        qty = int(m.group(3).replace(",","")); unit_price = float(m.group(4))
        total = float(m.group(5).replace(",",""))
        cons_id = "cons_24287fb8f8c20b86" if "dawn patrol" in desc.lower() else None
        result["line_items"].append({
            "description": f"{prod_no} {desc}", "cons_id": cons_id,
            "qty": qty, "unit_price": unit_price / 1000, "total": total,
        })
    return result


def parse_presto_labels(path):
    """Presto Labels: strip labels"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Presto Labels",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice No:\s*([\w]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date:\s*([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # "6000 6000 MCR Organic Strip 2.5" x 0.375" Rectangle 382-AZJET $0.08080 EA $484.80"
    for line in text.split("\n"):
        line = line.strip()
        m = re.match(r'^(\d+)\s+\d+\s+(.+?)\s+[\w\-]+\s+\$([\d\.]+)\s+EA\s+\$([\d,\.]+)', line)
        if m:
            qty = int(m.group(1)); desc = m.group(2).strip()
            unit_price = float(m.group(3)); total = float(m.group(4).replace(",",""))
            # Match to strip labels
            cons_id = None
            if "organic" in desc.lower(): cons_id = "cons_2e236490e95cd0d2"
            elif "whole bean" in desc.lower(): cons_id = "cons_ff225a255e624462"
            result["line_items"].append({
                "description": desc, "cons_id": cons_id,
                "qty": qty, "unit_price": unit_price, "total": total,
            })
    return result


def parse_online_label(path):
    """Online Labels: label rolls"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Online Label",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice\s+([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date\s+([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))
    m = re.search(r'Shipping:\s*\$([\d,\.]+)', text)
    if m:
        try: result["shipping_cost"] = float(m.group(1).replace(",",""))
        except: pass

    # "RL930DT RC 1.5" x 1.5" Standard White 4 14.675 $58.70"
    for line in text.split("\n"):
        line = line.strip()
        m = re.match(r'^(RL[\w]+)\s+(.+?)\s+(\d+)\s+[\d\.]+\s+\$([\d,\.]+)', line)
        if m:
            sku = m.group(1); desc = m.group(2).strip()
            qty = int(m.group(3)); total = float(m.group(4).replace(",",""))
            if "1.5" in desc and "1.5" in desc:
                cons_id = "cons_57f78a7f44dc6a24"  # 1.5 x 1.5 label
            elif "4" in sku and "6" in desc:
                cons_id = "cons_dbc6cf6d6146f383"  # 4x6 label
            else:
                cons_id = None
            result["line_items"].append({
                "description": f"{sku} {desc}", "cons_id": cons_id,
                "qty": qty, "unit_price": total / qty if qty else 0, "total": total,
            })
    return result


def parse_urnex(path):
    """Urnex: Cafiza or Rinza cleaner"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Urnex",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice Number:\s*([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date\s+([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # Cafiza: "12-ESP12-20 CASE 3 3 0 77.60000 232.80"
    m = re.search(r'12-ESP12-20\s+CASE\s+(\d+)\s+\d+\s+\d+\s+([\d\.]+)\s+([\d\.]+)', text)
    if m:
        qty = int(m.group(1)); unit_price = float(m.group(2)); total = float(m.group(3))
        result["line_items"].append({
            "description": "Cafiza 12-ESP12-20 Case", "cons_id": "cons_d61b7fa75eab37bb",
            "qty": qty, "unit_price": unit_price, "total": total,
        })
        return result

    # Rinza: "6 6 EA 39265.0000/CLEANER,MILK RINZA 1 LITER 29.75 178.50"
    m = re.search(r'(\d+)\s+\d+\s+EA.*?RINZA.*?([\d\.]+)\s+([\d\.]+)', text)
    if m:
        qty = int(m.group(1)); unit_price = float(m.group(2)); total = float(m.group(3))
        result["line_items"].append({
            "description": "Milk Rinza Cleaner 1L", "cons_id": "cons_084991a8dca4a9a8",
            "qty": qty, "unit_price": unit_price, "total": total,
        })
    return result


def parse_bhakti(path):
    """Bhakti Chai"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Bhakti Chai",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice no\.:\s*([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice date:\s*([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # "1. 801098 801098 - Original Quarts - Carton (UOM = 150 $26.96 $4,044.00"
    m = re.search(r'801098.*?(\d+)\s+\$([\d\.]+)\s+\$([\d,\.]+)', text, re.DOTALL)
    if m:
        qty = int(m.group(1)); unit_price = float(m.group(2)); total = float(m.group(3).replace(",",""))
        result["line_items"].append({
            "description": "801098 Bhakti Original Quarts", "cons_id": "cons_9262bb5502b31d5d",
            "qty": qty, "unit_price": unit_price, "total": total,
        })
    return result


def parse_bedford(path):
    """Bedford Industries: tin ties"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Bedford Industries",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'#INV([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    # Date at top: "12/31/2025"
    m = re.search(r'(\d{2}/\d{2}/\d{4})\s*\n.*?Phone', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # "2794750100 18 TH $42.35 $762.30"
    m = re.search(r'(\d{10})\s+(\d+)\s+TH\s+\$([\d\.]+)\s+\$([\d,\.]+)', text)
    if m:
        qty = int(m.group(2)) * 1000  # TH = thousands
        unit_price = float(m.group(3)) / 1000; total = float(m.group(4).replace(",",""))
        result["line_items"].append({
            "description": "4.75 x .315 Tin Tie", "cons_id": "cons_7c945f5e8259af15",
            "qty": qty, "unit_price": unit_price, "total": total,
        })
    return result


def parse_veritiv(path):
    """Veritiv: boxes/packaging"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Veritiv",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'(079-[\d]+)\s+(\d{2}/\d{2}/\d{4})', text)
    if m: result["invoice_number"] = m.group(1); result["invoice_date"] = parse_date(m.group(2))

    # From filename, determine box type
    fname = path.stem.lower()
    if "10x10x10" in fname:
        cons_id = "cons_d5c0afc50a71e0cf"; box_desc = "10x10x10 Box"
    elif "18x12x12" in fname:
        cons_id = "cons_c66aad5a08c93789"; box_desc = "18x12x12 Box"
    elif "18x12x8" in fname:
        cons_id = "cons_cf5a66085373e9e6"; box_desc = "18x12x8 Box"
    elif "20x9" in fname or "support" in fname:
        cons_id = "cons_5206095933c7906a"; box_desc = "Display Support Pads"
    else:
        cons_id = None; box_desc = "Box"

    # Format A: M (thousands) — "... 50 50 EA 980.0000 M 49.00 Y" (price may have comma)
    m = re.search(r'\d{8}\s+\S+.+?\s+(\d+)\s+\d+\s+EA\s+([\d,\.]+)\s+M\s+([\d,\.]+)', text)
    if m:
        qty = int(m.group(1))
        unit_price = float(m.group(2).replace(",","")) / 1000
        total = float(m.group(3).replace(",",""))
        result["line_items"].append({"description": box_desc, "cons_id": cons_id,
                                     "qty": qty, "unit_price": unit_price, "total": total})
        return result
    # Format B: EA (each) — "... 270 270 EA 2.4500 EA 661.50 Y"
    m = re.search(r'\d{8}\s+\S+.+?\s+(\d+)\s+\d+\s+EA\s+([\d\.]+)\s+EA\s+([\d\.]+)', text)
    if m:
        qty = int(m.group(1)); unit_price = float(m.group(2)); total = float(m.group(3))
        result["line_items"].append({"description": box_desc, "cons_id": cons_id,
                                     "qty": qty, "unit_price": unit_price, "total": total})
        return result
    # Fallback: Total Amount Due
    m2 = re.search(r'Total Amount Due\s+([\d,\.]+)', text)
    if m2:
        total = float(m2.group(1).replace(",",""))
        result["line_items"].append({
            "description": box_desc, "cons_id": cons_id,
            "qty": 1, "unit_price": total, "total": total,
            })
    return result


def parse_guittard(path):
    """Guittard: image-based PDF, create shipment only"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Guittard",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'SO(\d+)', path.stem)
    if m: result["invoice_number"] = m.group(1)

    # Can't extract line items from image PDF
    m = re.search(r'\$\s*([\d,]+\.[\d]+)', text)
    if m:
        log(f"    ℹ Guittard: image PDF, total ~${m.group(1)} — shipment only, no line items")
    return result


def parse_rimfire(path):
    """Rimfire Imports: produce boxes"""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": "Rimfire Imports",
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    m = re.search(r'Invoice\s*\n\s*([\d]+)', text)
    if m: result["invoice_number"] = m.group(1)
    m = re.search(r'Invoice Date:\s*([\d/]+)', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    # "1 BOXS2001-4 SHIPPER - VEGIE V1.7 PLAIN 20CT/bndl 1.00 CS 1.00 CS 95.00 95.00"
    m = re.search(r'BOXS\S+\s+(.+?)\s+1\.00\s+CS.*?([\d\.]+)\s+([\d\.]+)', text, re.DOTALL)
    if m:
        desc = m.group(1).strip(); total = float(m.group(3))
        result["line_items"].append({
            "description": f"Produce Box: {desc}", "cons_id": None,  # No MCR match
            "qty": 1, "unit_price": total, "total": total,
        })
    return result


def parse_generic(path):
    """Generic parser: extract invoice# and date, no line items."""
    result = {"invoice_number": None, "invoice_date": None, "supplier_name": path.stem,
              "shipping_cost": None, "line_items": []}
    text = pdf_text(path)

    for pat in [r'Invoice\s*(?:No|#|Number)[:\s]+([\w\-]+)',
                r'INV\s*[#:\s]*([\w\-]+)',
                r'Invoice\s+([\w\d\-]+)\s*\n']:
        m = re.search(pat, text, re.IGNORECASE)
        if m: result["invoice_number"] = m.group(1).strip(); break

    m = re.search(r'(\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4})', text)
    if m: result["invoice_date"] = parse_date(m.group(1))

    return result


def get_consumable_parser(path):
    """Return the appropriate parser based on filename."""
    stem = path.stem.lower()
    if "monin"       in stem: return parse_monin
    if "tricorbraun" in stem: return parse_tricorbraun
    if "pack plus"   in stem: return parse_pack_plus
    if "allen"       in stem: return parse_allen_flavors
    if "s&s"         in stem or "scisorek" in stem: return parse_ss_flavors
    if "meraki"      in stem: return parse_meraki
    if "advanced labels" in stem: return parse_advanced_labels
    if "presto"      in stem: return parse_presto_labels
    if "online label" in stem: return parse_online_label
    if "urnex"       in stem: return parse_urnex
    if "bunn"        in stem: return parse_urnex   # also sells Rinza Cleaner
    if "bhakti"      in stem: return parse_bhakti
    if "bedford"     in stem: return parse_bedford
    if "veritiv"     in stem: return parse_veritiv
    if "guittard"    in stem: return parse_guittard
    if "rimfire"     in stem: return parse_rimfire
    return parse_generic


# ── Supplier IDs ──────────────────────────────────────────────────────────────
ROYAL_ID = "mcr-supplier-royal-coffee"

def supplier_id_for(name):
    slug = re.sub(r'[^a-z0-9]', '-', name.lower())[:35].strip('-')
    return f"mcr-sup-{slug}"

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    log("=" * 70)
    log(f"MCR Invoice Import  |  Company={COMPANY_ID}  Facility={FACILITY_ID}")
    log("=" * 70)

    all_sql = []; warnings = []
    def emit(label, stmts):
        if stmts:
            all_sql.append(f"\n-- ── {label} " + "─"*max(0,60-len(label)))
            all_sql.extend(stmts)

    # ── 1. Suppliers ─────────────────────────────────────────────────────────
    log("\n[1] Suppliers")
    sup_stmts = [sql_supplier(ROYAL_ID, "Royal Coffee", "GG1a6L")]
    log(f"  Royal Coffee")

    # Consumable suppliers from filenames
    seen_sups = {}
    for pdf in sorted(CONSUMABLE_DIR.glob("*.pdf")):
        stem = pdf.stem
        # Strip trailing invoice numbers / model codes to get clean supplier name
        sup = re.sub(r'\s*[-–]\s*(INV|Invoice|SO|Sales Quote|Dawn Patrol|Rinza Cleaner|Oval Labels|'
                     r'Strip Labels|Produce Boxes|Cafiza Cleaner|Tin Ties|Flavor|Matcha|'
                     r'Small Boxes|Large Boxes|Medium Boxes|Support Pads|8oz Red Bag|'
                     r'2oz.*|8oz.*|[\d].*)$', '', stem, flags=re.IGNORECASE).strip()
        if sup not in seen_sups:
            sid = supplier_id_for(sup)
            seen_sups[sup] = sid
            sup_stmts.append(sql_supplier(sid, sup, "PlmoC2"))
            log(f"  {sup}")
    emit("SUPPLIERS", sup_stmts)

    # ── 2. Coffee invoices ────────────────────────────────────────────────────
    log("\n[2] Coffee invoices (Royal Coffee)")
    ok = warn = 0

    for pdf in sorted(COFFEE_DIR.glob("*.pdf")):
        if pdf.name in SKIP_FILES:
            log(f"  SKIP (dup): {pdf.name}"); continue

        log(f"\n  {pdf.name}")
        inv = parse_royal(pdf)

        inv["invoice_number"] = inv["invoice_number"] or pdf.stem
        if not inv["invoice_date"]:
            log(f"    ⚠ No date"); warnings.append(f"⚠ {pdf.name}: no date")

        ship_id = f"mcr-ship-royal-{inv['invoice_number']}"
        emit(f"COFFEE SHIP {inv['invoice_number']}", [sql_shipment(ship_id, ROYAL_ID, inv["invoice_date"], inv["invoice_number"])])

        if not inv["line_items"]:
            log(f"    ⚠ No line items"); warnings.append(f"⚠ {pdf.name}: no line items"); warn += 1; continue

        pur_stmts = []
        for item in inv["line_items"]:
            origin_id, origin_kw = match_origin(item["description"])
            source_id, source_kw = match_coffee_source(item["description"])
            if not origin_id:
                warnings.append(f"⚠ {pdf.name}: no origin for '{item['description'][:50]}'")
            pid = f"mcr-cip-{inv['invoice_number']}-{new_uuid()[:8]}"
            pur_stmts.append(sql_coffee_purchase(pid, ship_id, origin_id, item["qty_bags"],
                                                  item["cost_lb"], item.get("bag_size_id"), item.get("ref_no"), source_id))
            log(f"    ✓ {item['description'][:55]} → {origin_kw or 'NONE'} | "
                f"bags={item['qty_bags']} $/lb={item['cost_lb']} "
                f"bag_size={item.get('bag_size_id','?')} lot={item.get('ref_no','?')} "
                f"src={'✓' if source_id else '–'}")
        emit(f"COFFEE PURCH {inv['invoice_number']}", pur_stmts)
        ok += 1

    log(f"\n  Coffee: {ok} ok, {warn} with issues")

    # ── 3. Consumable invoices ────────────────────────────────────────────────
    log("\n[3] Consumable invoices")
    ok = warn = 0

    for pdf in sorted(CONSUMABLE_DIR.glob("*.pdf")):
        log(f"\n  {pdf.name}")
        parser = get_consumable_parser(pdf)
        inv = parser(pdf)

        inv["invoice_number"] = inv.get("invoice_number") or pdf.stem
        if not inv.get("invoice_date"):
            log(f"    ℹ No date found")

        # Map supplier name to ID
        stem = pdf.stem
        sup_name = re.sub(r'\s*[-–]\s*(INV|Invoice|SO|Sales Quote|Dawn Patrol|Rinza Cleaner|Oval Labels|'
                          r'Strip Labels|Produce Boxes|Cafiza Cleaner|Tin Ties|Flavor|Matcha|'
                          r'Small Boxes|Large Boxes|Medium Boxes|Support Pads|8oz Red Bag|'
                          r'2oz.*|8oz.*|[\d].*)$', '', stem, flags=re.IGNORECASE).strip()
        sup_id = seen_sups.get(sup_name, supplier_id_for(sup_name))

        ship_id = f"mcr-ship-{re.sub(r'[^a-z0-9]','-',pdf.stem.lower())[:45]}"
        emit(f"CONS SHIP {pdf.stem[:45]}", [sql_shipment(ship_id, sup_id, inv.get("invoice_date"),
                                                          inv["invoice_number"], inv.get("shipping_cost"))])

        items = inv.get("line_items", [])
        if not items:
            log(f"    ℹ No line items (image PDF or no match)"); warn += 1; continue

        pur_stmts = []
        for item in items:
            cons_id = item.get("cons_id")
            if not cons_id:
                log(f"    ℹ No match: '{item['description'][:50]}' — skipped")
                continue
            qty = item.get("qty", 1) or 1
            unit_price = item.get("unit_price") or (item.get("total",0) / qty)
            pid = f"mcr-consp-{new_uuid()[:12]}"
            pur_stmts.append(sql_cons_purchase(pid, ship_id, cons_id, qty, unit_price))
            log(f"    ✓ '{item['description'][:45]}' → {cons_id} qty={qty} unit=${unit_price:.4f}")

        if pur_stmts:
            emit(f"CONS PURCH {pdf.stem[:45]}", pur_stmts)
            ok += 1
        else:
            warn += 1

    log(f"\n  Consumables: {ok} ok, {warn} with issues")

    # ── Output ────────────────────────────────────────────────────────────────
    print("-- " + "="*70)
    print(f"-- MCR Invoice Import  |  {datetime.now().isoformat()}")
    print(f"-- Company={COMPANY_ID}  Facility={FACILITY_ID}")
    print("-- " + "="*70)
    print()
    print("BEGIN;")
    print("SET LOCAL app.skip_audit = 'true';")
    for s in all_sql: print(s)
    print("\nCOMMIT;")

    log("\n" + "="*70)
    log(f"Warnings ({len(warnings)}):")
    for w in warnings: log(f"  {w}")
    log("="*70)
    log(f"\nSQL → stdout. Run:")
    log(f"  PGPASSWORD='SDH-h3FNHXSrxj-' psql \"postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres\" < scripts/mcr_invoices.sql")

if __name__ == "__main__":
    main()
