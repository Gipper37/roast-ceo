#!/usr/bin/env python3
"""
Import MCR Artisan blends → roast_recipes + recipe_components, and link
high-confidence product groups to their recipe (products.recipe_id).

Generates SQL to stdout, log to stderr.
"""
import json, sys, re, uuid
from pathlib import Path

COMPANY_ID  = "9ShiyDAXhV"
FACILITY_ID = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"
DL = Path("/Users/wanderingaloha/my-supabase-project/MCR/strata migration/download.json")

def log(m): print(m, file=sys.stderr)

# ── Artisan coffee name → MCR origin_id (keyword, first match wins) ──────────
ORIGIN_KW = [
    ("mahi pono", "orig_142ffc976e750f22"),   # Maui farm
    ("maui",      "orig_142ffc976e750f22"),
    ("brazil",    "orig_c655bcaf99a986b1"),
    ("colombia",  "orig_d393e3392710921a"),
    ("costa rica","orig_d5456517bf131c45"),
    ("el salvador","orig_28d3a9afb33fb94a"),
    ("guatemala", "orig_b3890561c1c3ba25"),
    ("honduras",  "orig_d669c72ce18c7651"),
    ("nicaragua", "orig_bd7157c2ff0a76b3"),
    ("mexico",    "orig_0d75323d13d7e2fe"),
    ("sumatra",   "orig_17c8424053723e32"),
    ("yemen",     "orig_0798b3ed3a9e31a1"),
    ("kau",       "orig_afb785641116ec03"),
    ("kona",      "orig_2bb4bb4cfe71072a"),
    ("papa new guinea", "orig_93f7f73f959de942"),
    ("png",       "orig_93f7f73f959de942"),
    ("peru",      "orig_5e487c2d0035d0d4"),
]
def origin_for(name):
    n = name.lower()
    for kw, oid in ORIGIN_KW:
        if kw in n: return oid
    return None

# ── Blend label → product group_id (confident matches) ──────────────────────
# Multiple Artisan blends can target the same group (e.g. roast-level variants
# of one product); we create ONE recipe per group and link the group's products.
BLEND_TO_GROUP = {
    "Lokelani Blend":          "e312f6b7-a862-42d8-8854-13a43e4854a4",
    "Flavor":                  "5827f392-d083-4eef-8235-1dbcdf384d55",
    "Hoala Blend":             "a65a9aec-ba8e-4da2-844a-ef89e05d85d3",
    "French Roast":            "76d414bf-6501-4f93-8a29-fde19368efa9",
    "Espresso":                "2697c180-0451-4f16-8401-7292984cb331",
    "Club Imua":               "1c285e1f-1eeb-4898-8833-09f51a306721",
    "Puk Sup Blend":           "34a49d90-5dc5-4589-87cb-b7d735be29fb",
    "Nokaoi":                  "4d12031e-c742-43e8-8f57-7f0c447068b1",
    "House Blend":             "f012f063-84cf-461e-8f77-52ef60678da9",
    "Fresh Trade":             "af7381f1-4448-4c65-8bf1-31fbd41ab6b3",
    "SW Sup DK":               "576988f0-f1f9-4638-8bde-4815c6df97e0",
    "SW Sup LT":               "0dbf5ce3-436b-4a8f-803d-34a8431a6e15",
    "Maui Red Bag":            "80869405-03a5-4811-8032-923bef52bf28",
    "Maui Moka":               "12f19a24-91f0-4015-844a-46a638620cf3",
    "Maui Pea LT":             "97655176-be7e-4a63-8684-ddac9206fdd0",
    "Maui Pea DK":             "9e3a2ff9-dfe2-4c7a-891e-238b0e8a13f7",
    "Red Rooster":             "aec48ce1-0f16-4875-84a1-27a941833644",
    "Espresso Decaf":          "a402cdf6-e405-4888-8355-356652733a18",
    "Flavor Decaf":            "fce3c213-4312-4d9d-8e3b-b53b31d68272",
    "French Decaf":            "2ceb206d-b50b-4c2b-87b1-8f83e5e7c590",
    "MCR HI Blend Decaf":      "6e182c63-9bea-41ed-879b-9fc148ede8fb",
    "Pacific Pea Blend":       "324918dd-2603-4e3c-868b-869c25bac0f4",
    "Pacific Blend":           "00c8c2ad-e62b-4e43-8031-282301bd2ac3",
    "NicBeans Kona":           "4f311a31-dd51-4317-8eb7-79f8492c22ad",
    "Kona Decaf":              "e2336191-b1eb-4b5a-8b8a-37910ee861ae",
    "Kona BL Med":             "1c90dc79-7d17-4bda-8dbe-1ba445b76ccf",
    "Kona BL DK":              "bf224475-f792-48d0-800c-c9e886a23025",
    "Kona BL LT":              "8a9a0c25-5086-47ea-86c7-56a93e7e0fdc",
    "Kona Castaway (Reserve)": "96c791ca-5314-4659-8438-67fa3c171aff",
    "Kona Est DK":             "97caa757-dda0-4079-8bee-dd00fb8fc8f6",
    "Kona Est LT":             "3130167e-e7eb-44e0-8929-5ec41376a2b6",
    "Kona Pea Med":            "59486988-61ae-4412-88ea-501f3f7b0539",
    "Kau":                     "0046e157-d821-4fb7-8491-0ea826b96451",
    "Mama's Espresso":         "bb4c8c13-c400-4d88-8144-b9fb3c93bff2",
    "Nobu Espresso":           "8fe36eff-4341-4ba5-8d24-8dd83204b776",
    "Org Kona Bl Med":         "3b6bd1ac-8446-4871-8245-85e3b224db59",
    "ORG Kona BL DK":          "1a681c64-dc73-4e5e-8892-e75c9c9edf7b",
    # medium-confidence (still linked, flagged in log)
    "Euro Dark":               "6906006d-de70-4de6-8c5d-7c4c762ddb6a",  # European
    "Sumatra DK":              "a73416f6-70b0-4d93-87d3-8a6369ee5af4",  # Sumatra
    "Colombian Dark":          "d1a00e39-890f-4fa3-8d8a-f16e0b8d9d0e",  # Colombian Supremo Dark
    "MCR HI Blend":            "e05fa45b-71a6-4eed-8b88-0fde812f2f91",  # Kraken Maui Blend
    "Yellow Cat":              "8b97b37d-39e3-41ee-876d-dfd08d1210f2",  # Maui Cat
}
MEDIUM = {"Euro Dark","Sumatra DK","Colombian Dark","MCR HI Blend","Yellow Cat"}

# Blends intentionally NOT auto-linked to a group (recipe still created)
NO_LINK = {"MB LT","MB DK","MB Med (2oz)","Organic DK","Organic Med","Organic LT",
           "Organic Espresso","Organic French","Mama's Maui Moka","Mama's Maui Red",
           "SW Pea LT","HOALA"}  # HOALA dup of Hoala Blend

def sql_text(v):
    if v is None or (isinstance(v,str) and not v.strip()): return "NULL"
    return "'"+str(v).replace("'","''")+"'"

def main():
    d = json.load(open(DL))
    blends = [b for b in d.get('Blend',[]) if not b.get('deleted') and b.get('label') and b.get('ingredients')]
    coffees = {c['_id']: c.get('label', c.get('hr_id','?')) for c in d.get('Coffee',[])}

    out = []
    recipe_count = comp_count = link_count = 0
    unmapped_origins = []
    group_recipe = {}  # group_id -> recipe_id (so we link products)

    for b in blends:
        label = b['label'].strip()
        if label == "HOALA":  # duplicate of "Hoala Blend"
            log(f"skip dup recipe: {label}"); continue
        ings = b['ingredients']
        rid = "rcp-mcr-" + re.sub(r'[^a-z0-9]+','-', label.lower()).strip('-')[:40]
        roast_type = 'Pre-Blend' if len(ings) > 1 else 'Single Origin'

        out.append(
            f"INSERT INTO public.roast_recipes (recipe_id, recipe_name, roast_type, "
            f"company_id, facility_id, created_at, updated_at, created_by, is_active)\n"
            f"VALUES ({sql_text(rid)}, {sql_text(label)}, {sql_text(roast_type)}, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now(), {sql_text(COMPANY_ID)}, true)\n"
            f"ON CONFLICT (recipe_id) DO NOTHING;"
        )
        recipe_count += 1

        for ing in ings:
            cname = coffees.get(ing.get('coffee'), ing.get('coffee'))
            oid = origin_for(cname)
            pct = round(float(ing.get('ratio') or 0), 4)
            if not oid:
                unmapped_origins.append(f"{label}: {cname}")
                continue
            cmp_id = "rcc-" + uuid.uuid5(uuid.NAMESPACE_DNS, rid+cname).hex[:16]
            out.append(
                f"INSERT INTO public.recipe_components (component_id, recipe_id, percentage, "
                f"coffee_item, company_id, facility_id, created_at, updated_at, created_by)\n"
                f"VALUES ({sql_text(cmp_id)}, {sql_text(rid)}, {pct}, {sql_text(oid)}, "
                f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, now(), now(), {sql_text(COMPANY_ID)})\n"
                f"ON CONFLICT (component_id) DO NOTHING;"
            )
            comp_count += 1

        gid = BLEND_TO_GROUP.get(label)
        if gid:
            group_recipe[gid] = rid
            tag = " [MEDIUM]" if label in MEDIUM else ""
            log(f"recipe {label} -> group {gid}{tag}")
        elif label not in NO_LINK:
            log(f"recipe {label} (no group link)")

    # Link products to recipes for matched groups
    out.append("\n-- ── Link products to recipes (matched groups) ──")
    for gid, rid in group_recipe.items():
        out.append(
            f"UPDATE public.products SET recipe_id = {sql_text(rid)} "
            f"WHERE company_id = {sql_text(COMPANY_ID)} AND group_id = {sql_text(gid)} "
            f"AND is_active = true;"
        )
        link_count += 1

    print("-- MCR Artisan blends → roast_recipes + recipe_components + product links")
    print("BEGIN;")
    print("SET LOCAL app.skip_audit = 'true';")
    for s in out: print(s)
    print("COMMIT;")

    log("="*60)
    log(f"recipes: {recipe_count}  components: {comp_count}  group links: {link_count}")
    if unmapped_origins:
        log("UNMAPPED ORIGINS:")
        for u in unmapped_origins: log("  "+u)

if __name__ == "__main__":
    main()
