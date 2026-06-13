#!/usr/bin/env python3
"""
MCR QuickBooks order import — planner / dry-run.

Reads the QB "Sales by Item Detail" CSV + the approved match data + read-only
PROD snapshots (MCR/analysis/migration_plan/snapshot/*.tsv) and computes the full
plan: products/groups/sizes to create, products to link, customers, orders +
order_details — and reconciles dollars against the QB report. DRY-RUN = no writes.

Usage:  python3 scripts/mcr_qb_import.py            # dry-run report
"""
import csv, json, os, re, collections, difflib

BASE = "/Users/wanderingaloha/my-supabase-project/MCR/analysis/migration_plan"
SNAP = f"{BASE}/snapshot"
QB_CSV = "/Users/wanderingaloha/my-supabase-project/MCR/strata migration/Custom Report - 06.2025 - 06.2026.csv"
CO = "9ShiyDAXhV"; FAC = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"

# ---- load snapshots ----------------------------------------------------------
def tsv(p):
    return [l.rstrip("\n").split("\t") for l in open(p, encoding="utf-8") if l.strip()]

prods = tsv(f"{SNAP}/products.tsv")          # id,group_id,group_name,size_id,size_name,channel_id,channel_name,price,recipe_id,is_active
groups = {r[1].strip().lower(): r[0] for r in tsv(f"{SNAP}/groups.tsv")}        # name->id
sizes = {r[1].strip().lower(): (r[0], r[2]) for r in tsv(f"{SNAP}/sizes.tsv")}  # name->(id,weight)
channels = {r[1].strip().lower(): r[0] for r in tsv(f"{SNAP}/channels.tsv")}    # name->id
recipes = {r[1].strip().lower(): r[0] for r in tsv(f"{SNAP}/recipes.tsv")}      # name->id
dcons = {r[0]: (r[1], r[2]) for r in tsv(f"{SNAP}/dist_consumables.tsv")}       # id->(name,cost)
WHOLESALE = channels.get("wholesale")
existing_by_key = {}                          # (group_id,size_id,channel_id) -> product_id
existing_ids = set()
for r in prods:
    existing_ids.add(r[0])
    existing_by_key[(r[1], r[3], r[5])] = r[0]
prod_by_id = {r[0]: r for r in prods}

matches = {m["qb_item"]: m for m in json.load(open(f"{BASE}/matches_final.json"))}
qb_items = {it["item"]: it for it in json.load(open(f"{BASE}/qb_items.json"))}
recipe_a = {a["group"]: a for a in json.load(open(f"{BASE}/recipe_assignments.json"))}
nc_cls = {c["qb_item"]: c for c in json.load(open(f"{BASE}/noncoffee_classified.json"))}

CASE_WEIGHT = {  # case/pallet size token -> lbs
    "12-count 2lb case": 24.0, "10x2lb case": 20.0, "80-count 2oz case (labeled)": 10.0,
    "80-count 2oz case (no label)": 10.0, "10-count 8oz case": 5.0,
    "40-count 2oz case (labeled, green bags)": 5.0, "2oz case 40": 5.0,
}
SIZE_ALIAS = {"5lb": "5lbs", "2lb": "2lbs", "1lb": "1lb", "8oz": "8oz", "2oz": "2oz", "7oz": "7oz"}

def gid(name):
    if not name: return None
    n = name.strip().lower()
    if n in groups: return groups[n]
    m = difflib.get_close_matches(n, list(groups), n=1, cutoff=0.92)
    return groups[m[0]] if m else None

def rid(name):
    if not name: return None
    n = name.strip().lower()
    if n in recipes: return recipes[n]
    m = difflib.get_close_matches(n, list(recipes), n=1, cutoff=0.8)
    return recipes[m[0]] if m else None

# ---- resolve each QB item to a target product --------------------------------
# returns dict with: kind(product_type), action(link|create), product_id(if link),
#   pkey, group(name,id,is_new), size(name,id,is_new,weight), channel_id, recipe_id,
#   source_consumable_id, unit_cost, unresolved(reason)
# Manual overrides for matcher misses (item -> forced group/size, Coffee)
OVERRIDES = {
    "8r Anu Anu Cold Brew (8 oz Anu Anu Cold Brew Ground for Toddy)":
        {"group": "AnuAnu Cold Brew (French Roast)", "size": "8oz"},
}

def resolve(item):
    m = matches[item]; d = m["decision"]
    if d == "match_existing":
        pid = m.get("matched_product_id")
        if pid in existing_ids:
            return {"action": "link", "kind": "Coffee", "product_id": pid, "pkey": pid}
        # stale/missing product_id -> re-resolve via group+size+channel (override-aware)
        ov = OVERRIDES.get(item, {})
        g = ov.get("group") or m.get("matched_group") or m.get("new_group") or ""
        sztok = (ov.get("size") or m.get("size") or "").strip()
        g_id = gid(g); s_name = SIZE_ALIAS.get(sztok, sztok)
        s_id, s_wt = sizes.get(s_name.lower(), (None, None))
        ch = WHOLESALE
        if g_id and s_id and (g_id, s_id, ch) in existing_by_key:
            return {"action": "link", "kind": "Coffee",
                    "product_id": existing_by_key[(g_id, s_id, ch)], "pkey": existing_by_key[(g_id, s_id, ch)]}
        if g_id:  # group exists, size missing -> create product under existing group
            return {"action": "create", "kind": "Coffee",
                    "group": {"name": g, "id": g_id, "is_new": False},
                    "size": {"name": s_name, "id": s_id, "is_new": s_id is None, "weight": s_wt},
                    "channel_id": ch, "recipe_id": None, "source_consumable_id": None, "unit_cost": None,
                    "pkey": ("C", g_id, (s_id or s_name.lower()), ch)}
        return {"action": "link", "kind": "Coffee", "product_id": pid, "pkey": item,
                "unresolved": f"match_existing but no product/group resolved (pid={pid}, group={g!r})"}
    if d == "non_coffee_resale":
        c = nc_cls.get(item, {})
        kind = c.get("kind", "Consumable")
        scid = c.get("source_consumable_id")
        cost = dcons.get(scid, (None, None))[1] if scid else None
        gname = (re.sub(r"\s*\(.*\)\s*$", "", item).strip() or item)[:60]
        return {"action": "create", "kind": kind,
                "group": {"name": gname, "id": None, "is_new": True},
                "size": {"name": None, "id": None, "is_new": False, "weight": None},
                "channel_id": None, "recipe_id": None,
                "source_consumable_id": scid, "unit_cost": cost,
                "pkey": ("NC", gname, kind)}
    # new_product (coffee)
    g = m.get("new_group") or m.get("matched_group") or ""
    g_is_new = bool(m.get("group_is_new"))
    g_id = None if g_is_new else gid(g)
    if not g_is_new and g_id is None:
        g_is_new = True  # name didn't resolve -> treat as new
    # size
    sztok = (m.get("size") or "").strip()
    s_name = SIZE_ALIAS.get(sztok, sztok)
    s_id = s_wt = None; s_new = False
    if s_name.lower() in sizes:
        s_id, s_wt = sizes[s_name.lower()]
    elif sztok in CASE_WEIGHT:
        s_new = True; s_wt = CASE_WEIGHT[sztok]; s_name = sztok
    elif s_name.lower() in {k for k in sizes}:
        s_id, s_wt = sizes[s_name.lower()]
    else:
        s_new = True; s_name = sztok or "(unspecified)"
    # recipe
    rec = None
    if g in recipe_a and not recipe_a[g].get("needs_new_recipe"):
        rec = rid(recipe_a[g].get("recipe_name"))
    ch = WHOLESALE
    # existing product?
    if g_id and s_id and (g_id, s_id, ch) in existing_by_key:
        return {"action": "link", "kind": "Coffee", "product_id": existing_by_key[(g_id, s_id, ch)],
                "pkey": existing_by_key[(g_id, s_id, ch)]}
    return {"action": "create", "kind": "Coffee",
            "group": {"name": g, "id": g_id, "is_new": g_is_new},
            "size": {"name": s_name, "id": s_id, "is_new": s_new, "weight": s_wt},
            "channel_id": ch, "recipe_id": rec,
            "source_consumable_id": None, "unit_cost": None,
            "pkey": ("C", (g_id or g.lower()), (s_id or s_name.lower()), ch)}

item_res = {it: resolve(it) for it in matches}

# ---- aggregate product plan --------------------------------------------------
to_create = {}   # pkey -> spec
new_groups = {}; new_sizes = {}
link_ok = link_bad = 0
for it, r in item_res.items():
    if r["action"] == "link":
        if r.get("unresolved"): link_bad += 1
        else: link_ok += 1
    else:
        to_create.setdefault(r["pkey"], r)
        if r["kind"] == "Coffee":
            if r["group"]["is_new"]: new_groups.setdefault(r["group"]["name"].lower(), r["group"]["name"])
            if r["size"]["is_new"]: new_sizes.setdefault(r["size"]["name"], r["size"]["weight"])
        else:
            new_groups.setdefault(("nc", r["group"]["name"].lower()), r["group"]["name"])

create_by_kind = collections.Counter(s["kind"] for s in to_create.values())
nc_linked = sum(1 for s in to_create.values() if s["kind"] != "Coffee" and s.get("source_consumable_id"))
nc_total = sum(1 for s in to_create.values() if s["kind"] != "Coffee")

# ---- parse QB CSV: customers + orders ---------------------------------------
rows = list(csv.reader(open(QB_CSV, newline="", encoding="utf-8-sig")))
H = rows[0]; idx = {n: H.index(n) for n in ["Type","Date","Num","Memo","Name","Item","Qty","Sales Price","Amount"]}
def g_(r, n): j = idx[n]; return r[j].strip() if j < len(r) else ""
def num(s):
    try: return float(s.replace(",", ""))
    except: return None

customers = collections.OrderedDict()
orders = collections.defaultdict(lambda: {"cust": None, "date": None, "lines": [], "total": 0.0})
DISCOUNT_ITEMS = re.compile(r"^(sales )?discount\b", re.I)
line_total = 0.0; det = 0; unresolved_lines = 0; unresolved_amt = 0.0
disc_lines = 0
for r in rows[1:]:
    typ = g_(r, "Type")
    if typ not in ("Invoice", "Credit Memo"): continue
    nm = g_(r, "Name"); it = g_(r, "Item"); num_ = g_(r, "Num"); date = g_(r, "Date")
    q = num(g_(r, "Qty")); a = num(g_(r, "Amount")) or 0.0
    if nm: customers.setdefault(nm, 0); customers[nm] += 1
    key = (typ, num_)
    o = orders[key]; o["cust"] = nm; o["date"] = date; o["total"] += a
    line_total += a; det += 1
    # resolve product for this line
    r = item_res.get(it)
    if r and not r.get("unresolved"):
        if r["kind"] == "Discount":
            disc_lines += 1
    else:
        unresolved_lines += 1; unresolved_amt += a
    o["lines"].append((it, q, a))

# ---- REPORT ------------------------------------------------------------------
P = print
P("=" * 78); P("MCR QUICKBOOKS IMPORT — DRY RUN (no DB writes)"); P("=" * 78)
P(f"\nPRODUCTS ({len(item_res)} QB items):")
P(f"  LINK to existing product : {link_ok}" + (f"   ⚠ {link_bad} unresolved matched_product_id" if link_bad else ""))
P(f"  CREATE new products      : {len(to_create)} distinct (from {sum(1 for r in item_res.values() if r['action']=='create')} items, deduped)")
for k, v in create_by_kind.most_common():
    P(f"      - {k:11}: {v}")
P(f"  NEW product_groups       : {len(new_groups)}  (coffee + non-coffee)")
P(f"  NEW sizes (case/pallet)  : {len(new_sizes)} -> " + ", ".join(f"{n}={w}lb" for n, w in new_sizes.items()))
P(f"  Non-coffee cost-linked   : {nc_linked}/{nc_total} to distribution consumables (rest manual cost)")

P(f"\nCUSTOMERS:")
P(f"  NEW customers (name-only): {len(customers)}   (MCR currently has 0)")

P(f"\nORDERS:")
P(f"  orders (1 per invoice)   : {len(orders)}")
P(f"  order_details (lines)    : {det}")
P(f"  lines resolving to Discount/adjustment products: {disc_lines}")

P(f"\n$ RECONCILIATION:")
qb_total = sum(it['amount'] for it in qb_items.values())
P(f"  sum of QB line Amounts   : ${line_total:,.2f}")
P(f"  (qb_items.json total)    : ${qb_total:,.2f}")
P(f"  unresolved lines         : {unresolved_lines}  (${unresolved_amt:,.2f})")
if unresolved_lines:
    seen = collections.Counter()
    for r in rows[1:]:
        if g_(r,"Type") not in ("Invoice","Credit Memo"): continue
        it = g_(r,"Item")
        if it not in item_res and not DISCOUNT_ITEMS.search(it): seen[it] += 1
    P("  unresolved items (top):")
    for it, n in seen.most_common(10): P(f"      {it[:55]:55} x{n}")

P(f"\nSAMPLE new coffee products to create (first 6):")
n=0
for pk, s in to_create.items():
    if s["kind"]=="Coffee":
        rec = s["recipe_id"] or "(recipe null)"
        P(f"  {s['group']['name'][:30]:30} | {s['size']['name']:10} | recipe={rec[:24]}")
        n+=1
        if n>=6: break
P("\nDRY RUN complete — nothing written.")

# ---- SQL EMITTER (real import) ----------------------------------------------
def emit_sql():
    import uuid as U, hashlib, datetime
    NS = U.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8"); MARK = "mcr-qb-import"
    PREP = {"whole_bean": "Whole Bean", "ground": "Drip Ground"}
    PT = {"Coffee":"ptype_coffee","Consumable":"ptype_consumable","Equipment":"ptype_equipment","Service":"ptype_service","Discount":"ptype_discount"}
    def S(x): return "NULL" if x in (None,"") else "'"+str(x).replace("'","''")+"'"
    def Nn(x): return "NULL" if x in (None,"") else str(x)
    def guuid(nm): return str(U.uuid5(NS,"mcrimp:grp:"+nm.strip().lower()))
    def sizeid(nm): return "size_mcrimp_"+hashlib.md5(nm.encode()).hexdigest()[:12]
    def pidf(pk): return "mcrimp-prod-"+hashlib.md5(repr(pk).encode()).hexdigest()[:16]
    def custid(nm): return "mcrimp-cust-"+hashlib.md5(nm.encode()).hexdigest()[:14]
    def oidf(t,n): return "mcrimp-ord-"+hashlib.md5((("CM|" if t=="Credit Memo" else "INV|")+(n or "NA")).encode()).hexdigest()[:16]  # hash => collision-proof (e.g. '101647' vs '101647*')
    def pdate(d):
        for f in ("%m/%d/%Y","%m/%d/%y"):
            try: return datetime.datetime.strptime(d,f).date().isoformat()
            except: pass
        return None
    # group_id -> representative recipe_id (so new sizes of an existing blend inherit its recipe)
    def batch(table, cols, rows, conflict, chunk=400):
        s = []; cl = ",".join(cols)
        for k in range(0, len(rows), chunk):
            s.append(f"INSERT INTO {table} ({cl}) VALUES " + ",".join(rows[k:k+chunk]) + f" ON CONFLICT ({conflict}) DO NOTHING;")
        return s

    grp_recipe = {}
    for r in prods:
        if r[8] and r[1] not in grp_recipe: grp_recipe[r[1]] = r[8]
    out = [f"-- MCR QB import (generated). Reversible: created_by='{MARK}' / id prefix 'mcrimp-'. Batched multi-row INSERTs."]

    # 1. SIZES
    size_id_map = {name: sizeid(name) for name in new_sizes}
    srows = [f"({S(sizeid(n))},{S(n)},{Nn(w)},{S(CO)},true,{S(MARK)})" for n, w in new_sizes.items()]
    out.append("\n-- 1. SIZES"); out += batch("size", ["size_id","size_name","weight","company_id","is_active","created_by"], srows, "size_id")

    # 2. GROUPS (product_groups has no created_by; reversible via uuid5)
    groups_emit = {}
    for pk, s in to_create.items():
        if s["kind"] == "Coffee" and s["group"]["is_new"]: groups_emit[s["group"]["name"].lower()] = s["group"]["name"]
        elif s["kind"] != "Coffee": groups_emit[("nc", s["group"]["name"].lower())] = s["group"]["name"]
    grows = [f"({S(guuid(g))},{S(g)},{S(CO)},{S(FAC)},false,{S(MARK)})" for g in groups_emit.values()]
    out.append("\n-- 2. GROUPS"); out += batch("product_groups", ["group_id","group_name","company_id","facility_id","is_visible","created_by"], grows, "group_id")

    # 3. PRODUCTS
    item_pid = {it: r["product_id"] for it, r in item_res.items() if r["action"]=="link" and not r.get("unresolved")}
    pkey_pid = {}; pk_price = {}
    for it, r in item_res.items():
        if r["action"]=="create" and r["pkey"] not in pk_price:
            ps = qb_items.get(it,{}).get("price_samples") or []
            try: pk_price[r["pkey"]] = float(ps[0]) if ps else None
            except: pk_price[r["pkey"]] = None
    prows = []
    for pk, s in to_create.items():
        pid = pidf(pk); pkey_pid[pk] = pid
        if s["kind"] == "Coffee":
            gid_v = s["group"]["id"] if not s["group"]["is_new"] else guuid(s["group"]["name"])
            size_v = s["size"]["id"] or size_id_map.get(s["size"]["name"])
            chan_v = s["channel_id"]; pt = PT["Coffee"]; uc = None; sc = None
            rec_v = s.get("recipe_id") or (grp_recipe.get(gid_v) if not s["group"]["is_new"] else None)
        else:
            gid_v = guuid(s["group"]["name"]); size_v = None; chan_v = None; rec_v = None
            pt = PT[s["kind"]]; uc = s.get("unit_cost"); sc = s.get("source_consumable_id")
        prows.append(f"({S(pid)},{S(gid_v)},{S(size_v)},{S(chan_v)},{S(pt)},{S(rec_v)},{Nn(pk_price.get(pk))},{Nn(uc)},{S(sc)},{S(CO)},{S(FAC)},true,{S(MARK)})")
    out.append("\n-- 3. PRODUCTS")
    out += batch("products", ["product_id","group_id","size","channel","product_type","recipe_id","price","unit_cost","source_consumable_id","company_id","facility_id","is_active","created_by"], prows, "product_id", chunk=200)
    for it, r in item_res.items():
        if r["action"] == "create": item_pid[it] = pkey_pid[r["pkey"]]

    # 4. CUSTOMERS
    cust_map = {}; crows = []
    for nm in customers:
        cid = custid(nm); cust_map[nm] = cid
        crows.append(f"({S(cid)},{S(nm)},{S(CO)},{S(FAC)},true,{S(MARK)})")
    out.append("\n-- 4. CUSTOMERS"); out += batch("customers", ["customer_id","name_company","company_id","facility_id","is_active","created_by"], crows, "customer_id")

    # 5. ORDERS + ORDER_DETAILS
    orows = []; odrows = []; od_updates = []
    for (typ, num), o in orders.items():
        oid = oidf(typ, num); cid = cust_map.get(o["cust"]); odate = pdate(o["date"])
        onote = f"QB {typ} #{num}"
        orows.append(f"({S(oid)},{S(cid)},{S(odate)},'Delivered',{S(onote)},{S(CO)},{S(FAC)},{S(MARK)})")
        for i, (it, q, a) in enumerate(o["lines"]):
            pid = item_pid.get(it)
            if not pid: continue
            try: qf = float(q) if q not in (None, "") else 0
            except: qf = 0
            qty = abs(qf) if qf != 0 else 1
            odid = "mcrimp-od-" + hashlib.md5((oid + str(i)).encode()).hexdigest()[:16]
            prep = PREP.get(matches.get(it, {}).get("coffee_prep"))
            odrows.append(f"({S(odid)},{S(oid)},{S(pid)},{Nn(qty)},{S(prep)},'Delivered',{S(CO)},{S(FAC)},{S(odate)},{S(cid)},{S(MARK)})")
            od_updates.append((odid, round(a, 4)))
    out.append("\n-- 5a. ORDERS"); out += batch("orders", ["order_id","customer_id","order_date","order_status","order_notes","company_id","facility_id","created_by"], orows, "order_id", chunk=500)
    # item_status='Delivered' (these are historical delivered orders) — else lines default to 'Open' and clog the Pack Queue
    out.append("\n-- 5b. ORDER_DETAILS"); out += batch("order_details", ["order_detail_id","order_id","product_id","quantity","coffee_prep","item_status","company_id","facility_id","order_date","customer_id","created_by"], odrows, "order_detail_id", chunk=400)

    # 6. historical line prices (QB amounts, signed)
    out.append("\n-- 6. historical line prices (QB amounts, signed)")
    for k in range(0, len(od_updates), 500):
        vals = ",".join(f"({S(i)},{Nn(tp)})" for i, tp in od_updates[k:k+500])
        out.append(f"UPDATE order_details od SET total_price=v.tp FROM (VALUES {vals}) AS v(id,tp) WHERE od.order_detail_id=v.id;")

    open(f"{BASE}/mcr_import.sql", "w").write("\n".join(out) + "\n")
    P(f"\nwrote {BASE}/mcr_import.sql  ({len(out)} statements, {len(odrows)} order lines)")

import sys
if "--emit-sql" in sys.argv:
    emit_sql()
