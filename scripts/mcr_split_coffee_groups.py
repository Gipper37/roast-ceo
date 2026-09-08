#!/usr/bin/env python3
"""
Split MCR's broad Kona / Maui groups (and international decaf/peaberry) into
finer coffee groups. Generates SQL to stdout.

Creates new coffee_inventory origins (groups), repoints coffee_source +
coffee_inventory_purchased (lots), repoints the recipe_components of the
recipes built from Artisan blends, and resets the old Kona/Maui stock anchors.
"""
import re, json, sys
from pathlib import Path

COMPANY_ID  = "9ShiyDAXhV"
FACILITY_ID = "5cc581b9-2803-42c2-98de-0ba16ae42f8e"
DL = Path("/Users/wanderingaloha/my-supabase-project/MCR/strata migration/download.json")

# Existing broad origins
OLD = {
    "maui":     "orig_142ffc976e750f22",
    "kona":     "orig_2bb4bb4cfe71072a",
    "png":      "orig_93f7f73f959de942",
    "timor":    "orig_48164153d732217b",
    "mexico":   "orig_0d75323d13d7e2fe",
    "brazil":   "orig_c655bcaf99a986b1",
    "colombia": "orig_d393e3392710921a",
}

# New groups: id → (name, bag_size)
NEW_GROUPS = {
    "orig_mcr_kona_prime":      ("Kona Prime",       "100"),
    "orig_mcr_kona_peaberry":   ("Kona Peaberry",    "100"),
    "orig_mcr_kona_organic":    ("Kona Organic",     "100"),
    "orig_mcr_kona_h3":         ("Kona H3",          "100"),
    "orig_mcr_kona_decaf":      ("Kona Decaf",       "100"),
    "orig_mcr_kona_castaway":   ("Kona Castaway",    "100"),
    "orig_mcr_maui_yellow":     ("Maui Yellow",      "100"),
    "orig_mcr_maui_h3":         ("Maui H3",          "100"),
    "orig_mcr_maui_red":        ("Maui Red",         "100"),
    "orig_mcr_maui_moka":       ("Maui Moka",        "100"),
    "orig_mcr_maui_peaberry":   ("Maui Peaberry",    "100"),
    "orig_mcr_maui_decaf":      ("Maui Decaf",       "100"),
    "orig_mcr_decaf":           ("Decaf",            "152"),
    "orig_mcr_pacific_peaberry":("Pacific Peaberry", "152"),
}

# coffee_source.coffee_name → new origin_id (exact match)
SOURCE_TO_GROUP = {
    # Kona
    "Hawaii No.3 (Kona)":   "orig_mcr_kona_h3",
    "Kona #3":              "orig_mcr_kona_h3",
    "Kona Castaway Estate": "orig_mcr_kona_castaway",
    "Kona Castaway Reserve":"orig_mcr_kona_castaway",
    "Kona Decaf":           "orig_mcr_kona_decaf",
    "Kona Organic":         "orig_mcr_kona_organic",
    "Kona Peaberry":        "orig_mcr_kona_peaberry",
    "Kona Prime":           "orig_mcr_kona_prime",
    "Kona Prime 16/17":     "orig_mcr_kona_prime",
    "Kona Prime 18/19":     "orig_mcr_kona_prime",
    "Kona Prime Peaberry":  "orig_mcr_kona_peaberry",
    # Maui
    "Maui Dec Yellow 14":               "orig_mcr_maui_decaf",
    "Maui H3":                          "orig_mcr_maui_h3",
    "Maui Moka 11":                     "orig_mcr_maui_moka",
    "Maui Moka 14":                     "orig_mcr_maui_moka",
    "Maui Red 14":                      "orig_mcr_maui_red",
    "Maui Red Catuai Wash":             "orig_mcr_maui_red",
    "Maui Red H3":                      "orig_mcr_maui_h3",
    "Maui Red Natural 14 (NO LONGER USE)":"orig_mcr_maui_red",
    "Maui Red Natural 16":              "orig_mcr_maui_red",
    "Maui Red Peaberry":                "orig_mcr_maui_peaberry",
    "Maui Yellow 14 Nautral (NO LONGER USE)":"orig_mcr_maui_yellow",
    "Maui Yellow 16":                   "orig_mcr_maui_yellow",
    "Maui Yellow H3 Natural":           "orig_mcr_maui_h3",
    "Maui Yellow Peaberry":             "orig_mcr_maui_peaberry",
    # "Maui Red / Yellow Natural/Wash" stays under Maui (no entry)
    # International decaf
    "Decaf Brazil (FLAVOR)":        "orig_mcr_decaf",
    "Decaf Colombia (DECAF BLENDS)":"orig_mcr_decaf",
    "Decaf Mexico Esmeralda":       "orig_mcr_decaf",
    # International peaberry → Pacific Peaberry
    "Papa New Guinea Peaberry": "orig_mcr_pacific_peaberry",
    "PNG Peaberry":             "orig_mcr_pacific_peaberry",
    "Organic Timor peaberry":   "orig_mcr_pacific_peaberry",
    "Organic Timor Peaberry":   "orig_mcr_pacific_peaberry",
}

# Artisan coffee name (recipe ingredient) → (old_origin_key, new_origin_id)
# Only entries that actually MOVE are listed.
ING_TO_NEW = {
    "Mahi Pono h3":             ("maui", "orig_mcr_maui_h3"),
    "Maui Mokka 11":            ("maui", "orig_mcr_maui_moka"),
    "Maui mokka 14":            ("maui", "orig_mcr_maui_moka"),
    "Maui Yellow Peaberry":     ("maui", "orig_mcr_maui_peaberry"),
    "Maui Red 14":              ("maui", "orig_mcr_maui_red"),
    "Maui Yellow":              ("maui", "orig_mcr_maui_yellow"),
    "Mexico Decaf":             ("mexico", "orig_mcr_decaf"),
    "Kona Decaf":               ("kona", "orig_mcr_kona_decaf"),
    "Papa New Guinea Peaberry": ("png", "orig_mcr_pacific_peaberry"),
    "Hawaii Kona No.3":         ("kona", "orig_mcr_kona_h3"),
    "Kona Prime 18/19":         ("kona", "orig_mcr_kona_prime"),
    "kona Peaberry":            ("kona", "orig_mcr_kona_peaberry"),
    "Organic Kona":             ("kona", "orig_mcr_kona_organic"),
    # "Maui Red/Yellow Prime" → stays Maui; "Organic Papa New Guinea" → stays PNG
}

def sql_text(v): return "'" + str(v).replace("'", "''") + "'" if v is not None else "NULL"

def recipe_id_for(label):
    return "rcp-mcr-" + re.sub(r'[^a-z0-9]+','-', label.lower()).strip('-')[:40]

def main():
    out = []
    out.append("BEGIN;")
    out.append("SET LOCAL app.skip_audit = 'true';")

    # 1. Create new origins
    out.append("\n-- ── 1. New coffee groups (origins) ──")
    for oid, (name, bag) in NEW_GROUPS.items():
        out.append(
            f"INSERT INTO public.coffee_inventory (origin_id, origin, bag_size, "
            f"inventory_count_bags, in_stock, company_id, facility_id, is_active, created_at, updated_at, created_by) "
            f"VALUES ({sql_text(oid)}, {sql_text(name)}, {sql_text(bag)}, 0, 0, "
            f"{sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, true, now(), now(), {sql_text(COMPANY_ID)}) "
            f"ON CONFLICT (origin_id) DO NOTHING;"
        )

    # 2. Repoint coffee_sources
    out.append("\n-- ── 2. Repoint coffee_sources to new groups ──")
    for name, newid in SOURCE_TO_GROUP.items():
        out.append(
            f"UPDATE public.coffee_source SET origin_id = {sql_text(newid)} "
            f"WHERE company_id = {sql_text(COMPANY_ID)} AND coffee_name = {sql_text(name)};"
        )

    # 3. Repoint purchases (lots) to follow their source's new origin
    out.append("\n-- ── 3. Repoint coffee_inventory_purchased (lots) by source ──")
    out.append(
        f"UPDATE public.coffee_inventory_purchased cip "
        f"SET origin = cs.origin_id "
        f"FROM public.coffee_source cs "
        f"WHERE cip.coffee_source_id = cs.coffee_source_id "
        f"AND cip.company_id = {sql_text(COMPANY_ID)};"
    )

    # 4. Repoint recipe_components for the recipes built from Artisan blends
    out.append("\n-- ── 4. Repoint recipe_components to new groups ──")
    d = json.load(open(DL))
    coffees = {c['_id']: c.get('label','') for c in d.get('Coffee', [])}
    blends = [b for b in d.get('Blend', []) if not b.get('deleted') and b.get('label') and b.get('ingredients')]
    repoint_count = 0
    for b in blends:
        if b['label'].strip() == "HOALA":  # dup, skipped at import
            continue
        rid = recipe_id_for(b['label'])
        for ing in b['ingredients']:
            cn = coffees.get(ing.get('coffee'), '')
            if cn in ING_TO_NEW:
                old_key, newid = ING_TO_NEW[cn]
                old_origin = OLD[old_key]
                pct = round(float(ing.get('ratio') or 0), 4)
                out.append(
                    f"UPDATE public.recipe_components SET coffee_item = {sql_text(newid)} "
                    f"WHERE recipe_id = {sql_text(rid)} AND coffee_item = {sql_text(old_origin)} "
                    f"AND ROUND(percentage::numeric, 4) = {pct};"
                )
                repoint_count += 1

    # 5. Reset old Kona/Maui stock to 0 via a history count entry (direct
    #    edits to inventory_count_bags are guarded). Sources moved out, so a
    #    0 count clears the stale anchor; user recounts per new group.
    out.append("\n-- ── 5. Reset old Kona/Maui stock via history count = 0 ──")
    for key in ("kona", "maui"):
        out.append(
            f"INSERT INTO public.coffee_inventory_history "
            f"(history_id, origin_id, inventory_date, bag_count, notes, company_id, facility_id, created_by) "
            f"VALUES (gen_random_uuid()::text, {sql_text(OLD[key])}, CURRENT_DATE, 0, "
            f"'Reset after group split', {sql_text(COMPANY_ID)}, {sql_text(FACILITY_ID)}, {sql_text(COMPANY_ID)});"
        )

    out.append("\nCOMMIT;")
    print("\n".join(out))
    print(f"\n-- recipe component repoints: {repoint_count}", file=sys.stderr)

if __name__ == "__main__":
    main()
