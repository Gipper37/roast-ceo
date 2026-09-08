#!/usr/bin/env python3
"""
MCR coffee_source backfill — DRY RUN (no DB writes).

Reads live coffee_source / coffee_inventory / supplier (SELECT only) + the
GREEN COFFEE sheet, parses the descriptor trapped in coffee_name into the
structured columns, attaches farm/supplier, corrects bag sizes to invoice
truth, and archives dead rows. Emits:

  scripts/mcr_coffee_backfill_review.tsv   reviewable mapping (one row/source)
  scripts/mcr_coffee_backfill.sql          UPDATE/INSERT SQL, NOT executed

Apply only after review + explicit approval. Requires the
20260621000001_coffee_source_supplier migration applied first (supplier_id col).
"""
import csv, re, subprocess, sys, os
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHEET = os.path.join(ROOT, "MCR/strata migration/April 2026 - Inventory Spreadsheet.xlsx")
COMPANY = "9ShiyDAXhV"
PSQL_URL = "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
PGPASS = "SDH-h3FNHXSrxj-"
ROYAL_SUPPLIER_ID = "mcr-supplier-royal-coffee"

# ── invoice-true group bag size (lbs); Hawaiian left untouched (variable) ──
INVOICE_BAG = {
    "Brazil": 132, "Colombia": 154, "Sumatra": 132, "Timor": 132,
    "Costa Rica": 152, "Guatemala": 152, "Honduras": 152, "Mexico": 152,
    "Nicaragua": 152, "Peru": 152, "El Salvador": 152,
    "Decaf": 132, "Pacific Peaberry": 132, "Papua New Guinea": 152,
}
AMBIGUOUS_BAG = {  # origin -> note shown in review; group value left as-is
    "Papua New Guinea": "invoice shows Siane Chimbu Ecotact=132; purchases=152 — confirm",
    "Peru": "invoices=152 (Vida Alta) but purchase records=154 — confirm",
}

def psql(sql):
    out = subprocess.run(
        ["/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql", PSQL_URL,
         "-At", "-F", "\t", "-c", sql],
        env={**os.environ, "PGPASSWORD": PGPASS},
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("psql error:\n" + out.stderr)
    rows = [line.split("\t") for line in out.stdout.splitlines() if line]
    return rows

def norm(s):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", (s or "").lower())).strip()

# ── country (exact app keys for grade dropdowns) ───────────────────────────
BIG_ISLAND = "USA – Hawaii (Big Island)"  # en-dash, must match COUNTRIES_OF_ORIGIN
HAWAII = (BIG_ISLAND, "USA – Maui", "USA – Kauai", "USA – Molokai", "USA – Oahu")
def country_of(name, group):
    n = norm(name); g = norm(group); t = n + " " + g
    # Hawaii: Big Island districts (Kona/Ka'u/Puna/Hamakua) collapse to one
    # origin that drives the grade dropdown; the district goes in `region`.
    # Other islands are their own origins. Order matters (kauai contains "kau").
    if "kona" in t: return BIG_ISLAND
    if "kauai" in t: return "USA – Kauai"
    if "ka u" in t or re.search(r"\bkau\b", t): return BIG_ISLAND   # Ka'u
    if "puna" in t or "hamakua" in t: return BIG_ISLAND
    if "molokai" in t: return "USA – Molokai"
    if "oahu" in t: return "USA – Oahu"
    if any(k in t for k in ["maui", "mahi pono", "mokka", "moka"]): return "USA – Maui"
    if "hawaii" in t: return BIG_ISLAND
    table = [
        ("brazil", "Brazil"), ("colombia", "Colombia"), ("costa rica", "Costa Rica"),
        ("el salvador", "El Salvador"), ("guatemala", "Guatemala"), ("honduras", "Honduras"),
        ("nicaragu", "Nicaragua"), ("mexico", "Mexico"), ("peru", "Peru"),
        ("sumatra", "Indonesia"), ("timor", "Timor-Leste"),
        ("papa new guinea", "Papua New Guinea"), ("png", "Papua New Guinea"),
        ("yemen", "Yemen"),
    ]
    for key, val in table:
        if key in n or key in g:
            return val
    return ""

def is_hawaiian(name, group):
    return country_of(name, group) in HAWAII

# ── certifications / peaberry / process / varietals ────────────────────────
def certs_of(name):
    n = norm(name); out = []
    if "organic" in n: out.append("Organic")
    if re.search(r"\bft\b|ft flo|fair trade|flo", n): out.append("Fair Trade")
    if "rainforest" in n: out.append("Rainforest Alliance")
    return out

def peaberry_of(name):
    return bool(re.search(r"peaberry|\bpb\b", norm(name)))

def process_of(name):
    n = norm(name)
    if "semi wash" in n: return "Semi-Washed"
    if "honey" in n: return "Honey"
    if "natural" in n or "natutal" in n or "nautral" in n: return "Natural"
    if "wash" in n: return "Washed"
    return ""

def varietals_of(name):
    n = norm(name); out = []
    if "gesha" in n or "geisha" in n: out.append("Gesha")
    if "catuai" in n: out.append("Catuai")
    if "mokka" in n or re.search(r"\bmoka\b", n): out.append("Mokka")
    if "robusta" in n: out.append("Robusta")
    return out

# ── grade parsing per country -> (quality, classification, screen, prep) ────
SCREEN_RE = re.compile(r"\b(\d{2}/\d{2})\b")
def kona_grade(name):
    """Map a Big Island source name to a valid Hawaii grade dropdown value (incl H3)."""
    low = norm(name)
    raw = name.lower()  # raw keeps '#' that norm() strips, so '#3' is detectable
    if re.search(r"no\.?\s*3|#\s*3|\bh3\b", raw): return "H3"
    if "extra fancy" in low: return "Extra Fancy"
    if re.search(r"number 1|no\.?\s*1|#\s*1", low): return "Number 1"
    if "fancy" in low: return "Fancy"
    if "select" in low: return "Select"
    if "prime" in low: return "Prime"  # screen (16/17 etc) dropped — Kona uses #-grades
    return ""  # Castaway/Estate/Reserve/Organic/Decaf/Peaberry -> no grade

def parse_grade(name, country):
    n = name
    q = c = s = p = ""
    low = norm(n)
    if country == BIG_ISLAND:
        return kona_grade(name), "", "", ""
    if country in ("USA – Maui", "USA – Kauai", "USA – Molokai", "USA – Oahu"):
        # Other Hawaiian islands are freeform; only grade-like token is H3
        return ("H3" if re.search(r"no\.?\s*3|#\s*3|\bh3\b", low) else ""), "", "", ""
    sm = SCREEN_RE.search(n)
    if sm: s = sm.group(1)
    if country == "Brazil":
        if re.search(r"\bss\b", low): q = "SS"
        elif re.search(r"\bhs\b", low): q = "HS"
        elif re.search(r"\bry\b", low): q = "RY"
        elif re.search(r"\bs fc\b|\bs gc\b", low): q = "S"
        if re.search(r"\bfc\b", low): c = "FC"
        elif re.search(r"\bgc\b", low): c = "GC"
    elif country == "Colombia":
        if "supremo" in low: q = "Supremo"
        elif "excelso" in low: q = "Excelso"
        elif "ugq" in low: q = "UGQ"
        if re.search(r"\bep\b", low): p = "EP"
        s = ""  # Colombia has no screen dimension
    else:
        # single-value grades land in grade_quality (matches GradeInput)
        m = re.search(r"\b(SHB|SHG|GHB|MHB|HB|SH|HG|CS|MG|EPW|PW|LGA)\b", n)
        if m: q = m.group(1)
        elif "supreme" in low or "supremo" in low: q = "Supremo"  # invalid except Colombia -> validator flags
    return q, c, s, p

def compose_grade(q, c, s, p, pea):
    return " ".join(x for x in [q, c, s, p, "Peaberry" if pea else ""] if x)

# ── valid grade options per country (mirrors lib/coffee-options.ts) ─────────
COMPOSER_VALID = {
    "Brazil":   {"quality": {"SS","S","HS","RY"}, "classification": {"FC","GC"},
                 "screen": {"13/14","14/16","15/16","16/18","17/18","18+"}, "prep": set()},
    "Colombia": {"quality": {"Supremo","Excelso","UGQ"}, "classification": set(),
                 "screen": set(), "prep": {"EP"}},
}
SINGLE_VALID = {
    "Costa Rica": {"SHB","GHB","HB","MHB","LGA"},
    "Guatemala":  {"SHB","HB","SH","EPW","PW"},
    "Honduras":   {"SHG","HG","CS"},
    "El Salvador":{"SHG","HG","CS"},
    "Nicaragua":  {"SHG","HG","MG"},
    "Mexico":     {"SHG","HG","Prime Washed","Good Washed"},
    "Peru":       {"ESHP","SHP","HP","MCM"},
    "Indonesia":  {"Grade 1","Grade 2","Grade 3","Grade 4a","Grade 4b","Grade 5","Grade 6"},
    "USA – Hawaii (Big Island)": {"Extra Fancy","Fancy","Number 1","Select","Prime","H3"},
}
# Countries with NO grade system in the app -> freeform text input (any value ok).
# USA – Maui/Kauai/Molokai/Oahu, Timor-Leste, Papua New Guinea, Yemen.

# ── invoice-derived grade defaults (Royal Coffee invoices). Fill ONLY when the
#    name yields nothing; every value is a valid dropdown option. Peru excluded
#    (invoices say "SHB", which is NOT a valid Peru option) and Decaf excluded.
ENRICH = {
    "Brazil":      {"quality": "SS", "classification": "FC"},  # all Royal Brazil = SS FC
    "Colombia":    {"quality": "Excelso", "prep": "EP"},       # predominant Colombia Excelso EP
    "Costa Rica":  {"quality": "SHB"},
    "Guatemala":   {"quality": "SHB"},
    "Honduras":    {"quality": "SHG"},
    "El Salvador": {"quality": "SHG"},
    "Nicaragua":   {"quality": "SHG"},
    "Mexico":      {"quality": "HG"},     # invoices: Altura/Veracruz HG
    "Indonesia":   {"quality": "Grade 1"},
}

def enrich_grade(group, country, q, c, s, p):
    """Fill grade fields the name omitted, from invoice defaults. Returns
    (q, c, s, p, enriched_bool)."""
    if group == "Decaf" or country not in ENRICH:
        return q, c, s, p, False
    d = ENRICH[country]; changed = False
    if "quality" in d and not q: q = d["quality"]; changed = True
    if "classification" in d and not c: c = d["classification"]; changed = True
    if "prep" in d and not p: p = d["prep"]; changed = True
    return q, c, s, p, changed

def validate_grade(country, q, c, s, p):
    """Blank + flag any parsed grade value that isn't a real dropdown option
    for the country. Freeform countries (Hawaii/Timor/PNG/Yemen) pass through."""
    flags = []
    if country in COMPOSER_VALID:
        v = COMPOSER_VALID[country]
        out = {}
        for key, val in (("quality", q), ("classification", c), ("screen", s), ("prep", p)):
            if val and val not in v[key]:
                flags.append(f"grade?:{key}='{val}' invalid for {country}")
                out[key] = ""
            else:
                out[key] = val
        return out["quality"], out["classification"], out["screen"], out["prep"], flags
    if country in SINGLE_VALID:
        if q and q not in SINGLE_VALID[country]:
            flags.append(f"grade?:'{q}' invalid for {country}")
            q = ""
        # single-value countries shouldn't carry the composer sub-fields
        if c or s or p:
            flags.append("grade?:stray composer parts dropped")
            c = s = p = ""
        return q, c, s, p, flags
    return q, c, s, p, flags  # freeform — leave as-is

# ── region: residual after stripping country/grade/process/cert/etc ────────
REGION_FIX = {
    "medelin": "Medellín", "medellin": "Medellín", "hulia": "Huila", "huila": "Huila",
    "tarrazu": "Tarrazú", "copan": "Copán", "olomega": "Olomega", "segovia": "Segovia",
    "alta mogiana": "Alta Mogiana", "mogiana": "Mogiana", "sul de minas": "Sul de Minas",
    "veracruz": "Veracruz", "esmeralda": "Esmeralda", "everest": "Everest",
    "siguatepeque": "Siguatepeque", "calan": "Calán", "comsa": "COMSA",
    "takengon": "Takengon", "simbu": "Simbu", "selva andina": "Selva Andina",
    "vida alta": "Vida Alta",
}
STRIP_WORDS = {
    "organic","decaf","peaberry","pb","ft","flo","usa","cafe","de","mujer","aproccurma",
    "ss","fc","gc","s","hs","ry","ep","supremo","excelso","ugq","supreme","shb","shg",
    "ghb","mhb","hb","sh","hg","cs","mg","epw","pw","lga","prime","estate","reserve",
    "castaway","no","natural","washed","wash","honey","semi","new","not","coffee","blends",
    "flavor","gesha","geisha","catuai","mokka","moka","robusta","selva","andina",
}
def region_of(name, country):
    # Hawaiian: region = the island/district. Other-island origins already name
    # the island in the country slot; the Big Island origin needs the district.
    if country in HAWAII:
        if country == "USA – Maui": return "Maui"
        if country == "USA – Kauai": return "Kauai"
        if country == "USA – Molokai": return "Molokai"
        if country == "USA – Oahu": return "Oahu"
        nm = norm(name)  # Big Island -> district
        if "kona" in nm: return "Kona"
        if "ka u" in nm or re.search(r"\bkau\b", nm): return "Ka'u"
        if "puna" in nm: return "Puna"
        if "hamakua" in nm: return "Hamakua"
        return ""
    # Known region/coop/farm descriptors (handles typos + multi-word) first.
    nn = norm(name)
    for k, v in REGION_FIX.items():
        if k in nn:
            return v
    base = name
    base = re.sub(r"\(.*?\)", " ", base)          # drop parentheticals
    base = SCREEN_RE.sub(" ", base)
    base = re.sub(r"#\s*[\d,]+", " ", base)        # lot markers like #18, #16,17
    base = re.sub(r"\bno\.?\s*\d+\b", " ", base, flags=re.I)
    base = re.sub(r"\b\d+\b", " ", base)
    # remove country words
    for w in (country or "").replace("(", " ").replace(")", " ").split():
        base = re.sub(rf"\b{re.escape(w)}\b", " ", base, flags=re.I)
    for alias in ["colombian","brazilian","nicaragu a","nicaragu","papa new guinea","png","hawaii","kona","maui","ka u","kau","timor","sumatra","sulawesi","mexico","mexican"]:
        base = re.sub(rf"\b{re.escape(alias)}\b", " ", base, flags=re.I)
    toks = [t for t in norm(base).split() if t and t not in STRIP_WORDS]
    if not toks: return ""
    phrase = " ".join(toks)
    for k, v in REGION_FIX.items():
        if k in phrase:
            return v
    return phrase.title()

# ── GREEN COFFEE sheet: normalized item -> (farm, bag_lbs) ─────────────────
def load_sheet():
    import openpyxl
    wb = openpyxl.load_workbook(SHEET, data_only=True)
    ws = wb["GREEN COFFEE"]
    by_name = defaultdict(lambda: {"farms": [], "bags": []})
    for r in ws.iter_rows(min_row=4, values_only=True):
        item = (r[0] or "").strip() if r[0] else ""
        supplier = (r[3] or "").strip() if len(r) > 3 and r[3] else ""
        bag = r[5] if len(r) > 5 else None
        if not item or item.upper() in ("HAWAIIAN","MAUI","DECAF","INTERNATIONAL") or "total" in item.lower():
            continue
        key = norm(item)
        if supplier: by_name[key]["farms"].append(supplier)
        try:
            if bag is not None: by_name[key]["bags"].append(int(round(float(bag))))
        except (TypeError, ValueError):
            pass
    return by_name

# ── farm/supplier normalization for Hawaiian ───────────────────────────────
def norm_farm(raw):
    n = norm(raw)
    if "kau coffee mill" in n: return "Kau Coffee Mill"
    if "mahi pono" in n: return "Mahi Pono Farms"
    if "maui grown" in n: return "Maui Grown Coffee"
    if "mele mahina" in n: return "Mele Mahina Farms"
    if "generations" in n: return "Generations Kona"
    if "aloha hills" in n: return "Aloha Hills"
    if "aloha farms" in n: return "Aloha Farms"
    if "kona coffee company" in n: return "Kona Coffee Company"
    return raw.strip()

def supplier_id_for(farm):
    return "mcr-sup-" + re.sub(r"[^a-z0-9]+", "-", farm.lower()).strip("-")

def sql_str(v):
    if v is None or v == "": return "NULL"
    return "'" + str(v).replace("'", "''") + "'"

def sql_arr(items):
    if not items: return "'{}'"
    inner = ",".join('"' + i.replace('"', '\\"') + '"' for i in items)
    return "'{" + inner + "}'"

def main():
    sheet = load_sheet()
    srcs = psql(f"""SELECT cs.coffee_source_id, cs.coffee_name, COALESCE(ci.origin,''),
        COALESCE(cs.bag_size,''), cs.is_active
        FROM coffee_source cs LEFT JOIN coffee_inventory ci ON ci.origin_id=cs.origin_id
        WHERE cs.company_id='{COMPANY}' ORDER BY ci.origin, cs.coffee_name;""")
    inv = psql(f"""SELECT origin, COALESCE(bag_size,'') FROM coffee_inventory
        WHERE company_id='{COMPANY}' ORDER BY origin;""")
    existing_sup = {r[1] for r in psql(f"SELECT supplier_id, supplier FROM supplier WHERE company_id='{COMPANY}';")}

    new_suppliers = {}   # farm name -> supplier_id
    rows = []
    for sid, name, group, cur_bag, is_active in srcs:
        country = country_of(name, group)
        haw = country in HAWAII
        pea = peaberry_of(name)
        proc = process_of(name)
        cert = certs_of(name)
        vars_ = varietals_of(name)
        q, c, s, p = parse_grade(name, country)
        q, c, s, p, gflags = validate_grade(country, q, c, s, p)
        q, c, s, p, enriched = enrich_grade(group, country, q, c, s, p)
        if enriched: gflags = gflags + ["grade enriched from invoice"]
        glabel = compose_grade(q, c, s, p, pea)
        region = region_of(name, country)

        # farm / supplier
        m = sheet.get(norm(name)) or {}
        farms = m.get("farms", [])
        if haw:
            farm = norm_farm(farms[0]) if farms else ""
            supplier = farm
        else:
            farm = ""
            supplier = "Royal Coffee"
        sup_id = ""
        if supplier == "Royal Coffee":
            sup_id = ROYAL_SUPPLIER_ID
        elif supplier:
            sup_id = supplier_id_for(supplier)
            if supplier not in existing_sup:
                new_suppliers[supplier] = sup_id

        # bag size: international -> invoice truth; Hawaiian untouched (variable).
        # Ambiguous origins (Peru, PNG) are left as-is and only flagged, except
        # an obvious Hawaiian-default "100" leak on an international source.
        proposed_bag = cur_bag
        flags = list(gflags)
        if not haw:
            low = norm(name)
            if group in AMBIGUOUS_BAG:
                flags.append("bag?:" + AMBIGUOUS_BAG[group])
                if cur_bag == "100":
                    proposed_bag = "132" if pea else cur_bag
                    flags.append("had Hawaiian-default 100 — set 132 (peaberry GrainPro)")
            else:
                inv_bag = INVOICE_BAG.get(group)
                if inv_bag:
                    proposed_bag = str(inv_bag)
                    if group == "El Salvador" and "everest" in low: proposed_bag = "154"
                    if group == "Honduras" and "comsa" in low: proposed_bag = "154"

        # dead rows
        new_active = is_active
        if "no longer use" in norm(name):
            new_active = "f"; flags.append("ARCHIVE (no longer use)")
        if any(t in norm(name) for t in ["natutal","nautral"]) or "(new coffee)" in name.lower():
            flags.append("typo/dup — review for merge")
        if not country: flags.append("country?")
        if not haw and not farms and group not in ("Decaf",): pass  # intl farm intentionally blank

        rows.append(dict(
            sid=sid, name=name, group=group, country=country, region=region,
            process=proc, q=q, c=c, s=s, p=p, glabel=glabel, pea=pea,
            certs=cert, vars=vars_, farm=farm, supplier=supplier, sup_id=sup_id,
            cur_bag=cur_bag, bag=proposed_bag,
            cur_active=is_active, active=new_active, flags="; ".join(flags),
        ))

    # ── write review TSV ──
    review = os.path.join(HERE, "mcr_coffee_backfill_review.tsv")
    with open(review, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["coffee_name","group","country","region","process","grade_label",
                    "peaberry","certs","varietals","farm","supplier","bag_size","is_active","flags"])
        for r in rows:
            w.writerow([r["name"], r["group"], r["country"], r["region"], r["process"],
                        r["glabel"], "Y" if r["pea"] else "", "|".join(r["certs"]),
                        "|".join(r["vars"]),
                        r["farm"], r["supplier"],
                        (r["cur_bag"]+"→"+r["bag"]) if r["cur_bag"]!=r["bag"] else r["bag"],
                        (r["cur_active"]+"→"+r["active"]) if r["cur_active"]!=r["active"] else r["active"],
                        r["flags"]])

    # ── write SQL (NOT executed) ──
    sqlf = os.path.join(HERE, "mcr_coffee_backfill.sql")
    with open(sqlf, "w") as f:
        f.write("-- MCR coffee_source backfill — generated, NOT executed. Review before applying.\n")
        f.write("-- Requires 20260621000001_coffee_source_supplier (supplier_id col) applied first.\nBEGIN;\n\n")
        f.write("-- 1. New Hawaiian farm suppliers\n")
        for farm, sid in sorted(new_suppliers.items()):
            f.write(f"INSERT INTO supplier (supplier_id, supplier, supplier_category, company_id, is_active) "
                    f"VALUES ({sql_str(sid)}, {sql_str(farm)}, 'Green Coffee', '{COMPANY}', true) "
                    f"ON CONFLICT (supplier_id) DO NOTHING;\n")
        f.write("\n-- 2. coffee_source backfill\n")
        for r in rows:
            sets = [
                f"country_of_origin={sql_str(r['country'])}",
                f"region={sql_str(r['region'])}",
                f"process={sql_str(r['process'])}",
                f"farm={sql_str(r['farm'])}",
                f"grade_quality={sql_str(r['q'])}",
                f"grade_classification={sql_str(r['c'])}",
                f"grade_screen={sql_str(r['s'])}",
                f"grade_prep={sql_str(r['p'])}",
                f"grade_label={sql_str(r['glabel'])}",
                f"is_peaberry={'true' if r['pea'] else 'false'}",
                f"certifications={sql_arr(r['certs'])}",
                f"varietals={sql_arr(r['vars'])}",
                f"supplier_id={sql_str(r['sup_id'])}",
                f"bag_size={sql_str(r['bag'])}",
            ]
            if r["active"] != r["cur_active"]:
                sets.append(f"is_active={'true' if r['active']=='t' else 'false'}")
            f.write(f"UPDATE coffee_source SET {', '.join(sets)} WHERE coffee_source_id={sql_str(r['sid'])};\n")
        f.write("\n-- 3. coffee_inventory group bag-size corrections (invoice truth)\n")
        invmap = {o: b for o, b in inv}
        for origin, target in INVOICE_BAG.items():
            cur = invmap.get(origin)
            if cur is not None and cur != str(target) and origin not in AMBIGUOUS_BAG:
                f.write(f"UPDATE coffee_inventory SET bag_size='{target}' WHERE company_id='{COMPANY}' AND origin={sql_str(origin)};  -- was {cur}\n")
        f.write("\nCOMMIT;\n")

    # ── summary ──
    n = len(rows)
    print(f"sources: {n}")
    print(f"country filled: {sum(1 for r in rows if r['country'])}/{n}")
    print(f"region filled: {sum(1 for r in rows if r['region'])}/{n}")
    print(f"process filled: {sum(1 for r in rows if r['process'])}/{n}")
    print(f"grade filled: {sum(1 for r in rows if r['glabel'])}/{n}")
    print(f"farm filled: {sum(1 for r in rows if r['farm'])}/{n}")
    print(f"bag changes: {sum(1 for r in rows if r['cur_bag']!=r['bag'])}")
    print(f"archived: {sum(1 for r in rows if r['active']!=r['cur_active'])}")
    print(f"flagged: {sum(1 for r in rows if r['flags'])}")
    print(f"new suppliers ({len(new_suppliers)}): {', '.join(sorted(new_suppliers))}")
    print(f"group bag corrections: {[(o,invmap.get(o),INVOICE_BAG[o]) for o in INVOICE_BAG if invmap.get(o) and invmap.get(o)!=str(INVOICE_BAG[o]) and o not in AMBIGUOUS_BAG]}")
    print(f"\nreview -> {review}\nsql    -> {sqlf}")

if __name__ == "__main__":
    main()
