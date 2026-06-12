#!/usr/bin/env python3
"""
MCR re-import — DRY RUN (read-only, prints a review report; changes nothing).

Two parts:
  1. STRUCTURE SOURCES — parse each coffee_source.coffee_name into the same
     structured fields SHUSA uses (country_of_origin / region / grade_quality /
     grade_classification / grade_screen / grade_prep / is_peaberry / grade_label
     / process / certifications). Flag sources that collapse to one identity.
  2. CONSOLIDATE LOTS — invoices (entry_method='shipment') are the canonical
     lots (real Royal#, cost, receipt date). Match the April baseline lots to
     them by Royal#; the April on-hand becomes a count anchor; baseline rows are
     dropped. Lots fully consumed before April → counted 0.

Run: python3 scripts/mcr_reimport_dryrun.py
"""
import re
import psycopg2
import psycopg2.extras

COMPANY_ID = "9ShiyDAXhV"
DSN = "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
import os
os.environ.setdefault("PGPASSWORD", "SDH-h3FNHXSrxj-")

# ── Vocab (from SHUSA + standard coffee grading) ────────────────────────────
COUNTRY_MAP = {
    "brazil": "Brazil", "colombia": "Colombia", "colombian": "Colombia",
    "costa rica": "Costa Rica", "el salvador": "El Salvador",
    "guatemala": "Guatemala", "honduras": "Honduras", "mexico": "Mexico",
    "nicaragua": "Nicaragua", "nicaragu": "Nicaragua", "peru": "Peru",
    "sumatra": "Indonesia", "sulawesi": "Indonesia", "timor": "Timor-Leste",
    "yemen": "Yemen", "papa new guinea": "Papua New Guinea", "png": "Papua New Guinea",
    "papua new guinea": "Papua New Guinea",
    # Hawaii — SHUSA convention: country = "USA – <island>"
    "kona": "USA – Kona", "maui": "USA – Maui", "ka'u": "USA – Ka'u",
    "kau": "USA – Ka'u", "hawaii": "USA – Kona", "mahi pono": "USA – Maui",
}
HAWAII = {"USA – Kona", "USA – Maui", "USA – Ka'u"}
KONA_GRADES = ["Extra Fancy", "Fancy", "Prime", "No.3", "No. 3", "#3"]
MAUI_TYPES = ["Red Catuai", "Red", "Yellow", "Moka", "Mokka", "H3"]
KONA_FARMS = ["Castaway"]
QUALITY = ["SHG", "SHB", "SS", "HG", "Extra Fancy", "Fancy", "Excelso", "Supremo",
           "Supreme", "Prime", "Grade 1", "Estate", "Reserve"]
CLASSIFICATION = ["FC", "GC", "EP"]
PROCESS = ["Pulped Natural", "Semi Washed", "Wet Hulled", "Natural", "Washed",
           "Wash", "Honey", "Catuai Wash"]
CERTS = [("organic", "USDA Organic"), ("ft-flo", "Fair Trade"), ("ft-usa", "Fair Trade"),
         ("ft ", "Fair Trade"), ("flo", "Fair Trade")]
SCREEN_RE = re.compile(r'(\d{1,2}\s*/\s*\d{1,2}|\d{1,2}\s*\+|#\s*\d{1,2}(?:\s*,\s*\d{1,2})*|No\.?\s*\d+)', re.I)
ANNOT_RE = re.compile(r'\((?:NO LONGER USE|New Coffee|not peaberry|FLAVOR|DECAF BLENDS)\)', re.I)

def norm(s): return re.sub(r'\s+', ' ', (s or '').strip())

def parse_source(name: str) -> dict:
    raw = norm(name)
    work = ANNOT_RE.sub('', raw)
    work = re.sub(r'\b(?:natutal|nautral)\b', 'Natural', work, flags=re.I)  # common typos
    low = work.lower()
    out = {"country_of_origin": None, "region": None, "farm": None, "varietals": [],
           "grade_quality": "", "grade_classification": "", "grade_screen": "", "grade_prep": "",
           "is_peaberry": False, "process": "", "certifications": [], "_notes": []}

    # certifications
    for key, val in CERTS:
        if key in low and val not in out["certifications"]:
            out["certifications"].append(val)
    work = re.sub(r'\bOrganic\b', '', work, flags=re.I)
    work = re.sub(r'\bFT[- ]?(FLO|USA)?\b', '', work, flags=re.I)

    # peaberry
    if 'peaberry' in low:
        out["is_peaberry"] = True
        work = re.sub(r'\bpeaberry\b', '', work, flags=re.I)

    # decaf
    if 'decaf' in low or low.startswith('dec '):
        out["process"] = "Decaf"
        work = re.sub(r'\bdecaf?\b', '', work, flags=re.I)

    # country (longest-match first)
    for k in sorted(COUNTRY_MAP, key=len, reverse=True):
        if re.search(r'\b' + re.escape(k) + r'\b', work, flags=re.I):
            out["country_of_origin"] = COUNTRY_MAP[k]
            work = re.sub(r'\b' + re.escape(k) + r'\b', '', work, flags=re.I, count=1)
            break
    is_hawaii = out["country_of_origin"] in HAWAII

    if is_hawaii:
        for t in MAUI_TYPES:   # Maui type = the differentiator → varietals
            if re.search(r'\b' + re.escape(t) + r'\b', work, flags=re.I):
                out["varietals"].append("Mokka" if t.lower() in ("moka", "mokka") else t)
                work = re.sub(r'\b' + re.escape(t) + r'\b', '', work, flags=re.I)
        for f in KONA_FARMS:
            if re.search(r'\b' + re.escape(f) + r'\b', work, flags=re.I):
                out["farm"] = f
                work = re.sub(r'\b' + re.escape(f) + r'\b', '', work, flags=re.I)
        for g in KONA_GRADES:
            if re.search(re.escape(g), work, flags=re.I):
                out["grade_quality"] = "No.3" if g.lower() in ("no.3", "no. 3", "#3") else g
                work = re.sub(re.escape(g), '', work, flags=re.I); break

    # screen (NN/NN is always a screen size — incl. Kona 16/17, 18/19)
    m = SCREEN_RE.search(work)
    if m:
        out["grade_screen"] = re.sub(r'\s+', '', m.group(1))
        work = work[:m.start()] + work[m.end():]

    # quality / classification / process (token scan)
    for q in QUALITY:
        if re.search(r'\b' + re.escape(q) + r'\b', work, flags=re.I):
            out["grade_quality"] = q
            work = re.sub(r'\b' + re.escape(q) + r'\b', '', work, flags=re.I); break
    for c in CLASSIFICATION:
        if re.search(r'\b' + re.escape(c) + r'\b', work):
            out["grade_classification"] = c
            work = re.sub(r'\b' + re.escape(c) + r'\b', '', work); break
    for p in PROCESS:
        if re.search(r'\b' + re.escape(p) + r'\b', work, flags=re.I):
            if not out["process"]: out["process"] = p
            work = re.sub(r'\b' + re.escape(p) + r'\b', '', work, flags=re.I); break

    # whatever's left (cleaned) is the region/farm if no region yet
    leftover = norm(re.sub(r'[/,#()]+', ' ', work))
    if leftover and not out["region"]:
        out["region"] = leftover
    elif leftover and out["region"]:
        out["_notes"].append(f"leftover '{leftover}'")

    # grade_label = quality + classification + screen + prep (+ Peaberry)
    parts = [out["grade_quality"], out["grade_classification"], out["grade_screen"], out["grade_prep"]]
    label = " ".join(p for p in parts if p)
    if out["is_peaberry"]:
        label = (label + " Peaberry").strip()
    out["grade_label"] = label.strip()
    return out

def identity(p):
    """Structured identity for dedupe."""
    return (p["country_of_origin"], (p["region"] or '').lower(), (p["farm"] or '').lower(),
            tuple(sorted(v.lower() for v in p["varietals"])),
            p["grade_label"].lower(), p["process"].lower(), p["is_peaberry"],
            tuple(sorted(p["certifications"])))

def royal(lot_id):
    m = re.search(r'(\d{4,6})', lot_id or '')
    return m.group(1) if m else None

def main():
    conn = psycopg2.connect(DSN)
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
      SELECT cs.coffee_source_id, cs.coffee_name, ci.origin AS grp, cs.origin_id
      FROM coffee_source cs LEFT JOIN coffee_inventory ci ON ci.origin_id=cs.origin_id
      WHERE cs.company_id=%s AND cs.is_active ORDER BY ci.origin, cs.coffee_name
    """, (COMPANY_ID,))
    sources = cur.fetchall()

    print("=" * 78)
    print("PART 1 — SOURCE STRUCTURING (proposed)")
    print("=" * 78)
    parsed = {}
    ident_map = {}
    for s in sources:
        p = parse_source(s["coffee_name"])
        parsed[s["coffee_source_id"]] = (s, p)
        ident_map.setdefault(identity(p), []).append(s["coffee_name"])
        title = " · ".join(x for x in [p["country_of_origin"], p["farm"], p["region"],
                                       ", ".join(p["varietals"]), p["grade_label"],
                                       p["process"], ", ".join(p["certifications"])] if x)
        flag = "  ⚠ " + "; ".join(p["_notes"]) if p["_notes"] else ""
        print(f"\n  {s['coffee_name']}")
        print(f"    → {title or '(unparsed)'}{flag}")

    print("\n" + "=" * 78)
    print("PROPOSED MERGES (sources that collapse to one identity)")
    print("=" * 78)
    merges = {k: v for k, v in ident_map.items() if len(v) > 1}
    if not merges:
        print("  none")
    for k, names in merges.items():
        print(f"  • {' = '.join(names)}")

    print("\n" + "=" * 78)
    print("PART 2 — LOT CONSOLIDATION (match baseline↔invoice by Royal#)")
    print("=" * 78)
    cur.execute("""
      SELECT cip.entry_method, cip.lot_id, cip.amount, cip.remaining_lbs, cip.cost_lb,
             sr.date_received, ci.origin AS grp
      FROM coffee_inventory_purchased cip
      LEFT JOIN coffee_inventory ci ON ci.origin_id=cip.origin AND ci.facility_id=cip.facility_id
      LEFT JOIN shipment_received sr ON sr.shipment_id=cip.shipment_id
      WHERE cip.company_id=%s ORDER BY ci.origin, cip.entry_method
    """, (COMPANY_ID,))
    lots = cur.fetchall()
    base = {}; ship = {}
    for l in lots:
        r = royal(l["lot_id"])
        (base if l["entry_method"] == 'baseline' else ship).setdefault(r, []).append(l)
    matched = sum(1 for r in base if r in ship)
    print(f"  baseline lots: {sum(len(v) for v in base.values())}  |  "
          f"invoice lots: {sum(len(v) for v in ship.values())}")
    print(f"  baseline Royal#s matched to an invoice: {matched}/{len(base)}")
    print("\n  Unmatched baseline lots (no invoice — would need a synthetic lot):")
    for r, v in base.items():
        if r not in ship:
            for l in v: print(f"    • #{r}  {l['grp']}  {l['amount']} lb  ${l['cost_lb']}")
    conn.close()

if __name__ == "__main__":
    main()
