#!/usr/bin/env python3
"""Generate roast_log INSERTs for the MCR artisan usage import.
Reads the artisan.plus export (StockChange 'Roast' records), dedups by
external_roast_id against STRATA, maps each blend.label -> STRATA recipe ->
consolidated origin (mirroring existing roasts), and emits SQL. Specials:
MAHI PONO -> Maui H3, MAUI KULA SKY -> Maui Red. Usage-only (no lots/counts)."""
import json, re

JSON_PATH   = "MCR/strata migration/artisan data.json"
EXT_PATH    = "/tmp/strata_ext.txt"
RECIPE_PATH = "/tmp/recipe_map.tsv"
OUT_PATH    = "/tmp/import_roasts.sql"
CO  = "9ShiyDAXhV"
FAC = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"
MAUI_H3, MAUI_RED = "orig_mcr_maui_h3", "orig_mcr_maui_red"

def norm(s): return re.sub(r'[^a-z0-9]', '', (s or '').lower())
def q(s): return "'" + str(s).replace("'", "''") + "'"

ext = {l.strip() for l in open(EXT_PATH) if l.strip()}
recipes = {}  # norm_name -> (recipe_id, origin, display)
for line in open(RECIPE_PATH):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3 and p[1] and p[2]:
        recipes[norm(p[0])] = (p[1], p[2], p[0])

def resolve(label):
    n = norm(label)
    if "mahipono" in n: return (None, MAUI_H3, label)
    if "kulasky" in n:  return (None, MAUI_RED, label)
    if n in recipes:    return recipes[n]
    # near-match (e.g. "HOALA" -> "hoala blend")
    cands = [(rid, o, d) for rn, (rid, o, d) in recipes.items()
             if n and (n in rn or rn in n) and abs(len(n) - len(rn)) <= 6]
    return cands[0] if len(cands) == 1 else (None, None, label)

data = json.load(open(JSON_PATH))
roasts = [s for s in data.get("StockChange", [])
          if s.get("__t") == "Roast" and s.get("roast_id") not in ext]

rows, unmapped, by_origin = [], [], {}
for s in roasts:
    label = (s.get("blend") or {}).get("label") or s.get("label") or ""
    rid, origin, disp = resolve(label)
    if not origin:
        unmapped.append((s.get("roast_id"), label)); continue
    amt = round(float(s.get("amount") or 0), 4)
    dt  = s.get("date")
    by_origin[origin] = by_origin.get(origin, 0) + amt
    rid_sql = q(rid) if rid else "NULL"
    rows.append(
        "INSERT INTO roast_log (roast_log_id, external_roast_id, roast_date, roast_date_utc, "
        "origin_id, recipe_id, charge_weight_lbs, charge_weight, \"charged?\", is_buffer, "
        "planned_lots, company_id, facility_id, recipe_name_snapshot) VALUES "
        f"(gen_random_uuid()::text, {q(s['roast_id'])}, {q(dt)}::timestamptz, {q(dt)}::timestamptz, "
        f"{q(origin)}, {rid_sql}, {amt}, {amt}, true, false, '[]'::jsonb, {q(CO)}, {q(FAC)}, {q(disp)});"
    )

with open(OUT_PATH, "w") as f:
    f.write("\n".join(rows) + "\n")

print(f"missing roasts: {len(roasts)}  emitted: {len(rows)}  unmapped: {len(unmapped)}")
print(f"total green lbs: {round(sum(by_origin.values()),1)}")
print("by origin:")
for o, lbs in sorted(by_origin.items(), key=lambda x: -x[1]):
    print(f"  {o}: {round(lbs,1)}")
if unmapped:
    print("UNMAPPED (need attention):")
    for rid, lab in unmapped: print(f"  {rid}  label={lab!r}")
