#!/usr/bin/env python3
"""
Generate the corrected MCR composed-title backfill (v2).

Source of truth: the already-verified proposal in
scripts/mcr_composed_title_review.tsv (80 active sources, was GO).

Corrections applied (per user spec 2026-06-23):
  1. Hawaiian country = 'USA - <island>' (USA - Maui / USA - Kona / USA - Ka'u).
     Region/grade hold the distinguishing detail (Red, Yellow, Prime, #screen).
     Process holds Honey/Natural/Washed. No doubled island, no invented farm.
  2. name_override (new nullable text col): composed title EXCLUDES botanical
     varietals; when excluding the varietal leaves the title non-unique/generic,
     set name_override to the correct full display name preserving the varietal.
  3. final_title = COALESCE(name_override, composed_title); coffee_name := final_title.
     Varietal stays in varietals[] regardless.

Composed title format: country + region + grade_label + process + (Decaf if is_decaf).
"""

import csv

# Each row: (id, original_name, country, region, grade_label, process, is_decaf, varietals(list), name_override or None)
# country/region/grade_label/process are the CORRECTED values.
# Composed title is derived; final_title = override or composed.
ROWS = [
    # --- Brazil ---
    ("csrc_e6cac7ee284067a7", "Brazil Mogiana",        "Brazil", "Mogiana", "",      "", False, [], None),
    ("csrc_5de796c028876030", "Brazil Mogiana 15/16",  "Brazil", "Mogiana", "15/16", "", False, [], None),
    ("csrc_d7988f5e334bbb0f", "Brazil Mogiana 15/17",  "Brazil", "Mogiana", "15/17", "", False, [], None),
    ("csrc_81f73985aac71db7", "Brazil Mogiana 17/18",  "Brazil", "Mogiana", "17/18", "", False, [], None),
    ("csrc_7d11bddf8db2e72d", "Brazil Sul De Minas",   "Brazil", "Sul de Minas", "", "", False, [], None),
    ("csrc_23753f1ab6d3f9c9", "Decaf Brazil (FLAVOR)", "Brazil", "", "", "", True,  [], None),

    # --- Colombia ---
    ("csrc_0a84d7ad205487c5", "Colombia Excelso",          "Colombia", "",          "Excelso", "", False, [], None),
    ("csrc_e59e36a550ac6cfe", "Colombia Hulia Supremo",    "Colombia", "Huila",     "Supremo", "", False, [], None),
    ("csrc_a62b479c16f3a46f", "Colombia Medelin Excelso",  "Colombia", "Medellin",  "Excelso", "", False, [], None),
    ("csrc_1619c377f98171c9", "Colombia Supremo",          "Colombia", "",          "Supremo", "", False, [], None),
    # Gesha: botanical varietal is SOLE distinguisher -> composed collapses to "Colombia". Override.
    ("csrc_241e8bed4968e9f0", "Colombian Gesha",           "Colombia", "",          "",        "", False, ["Gesha"], "Colombia Gesha"),
    ("csrc_058f4808fbf5f03e", "Decaf Colombia (DECAF BLENDS)", "Colombia", "",      "",        "", True,  [], None),
    ("csrc_51dc895c7e973ba2", "Organic Colombia",          "Colombia", "",          "",        "", False, [], None),

    # --- Costa Rica ---
    ("csrc_c66f57af57b8205f", "Costa Rica Tarrazu", "Costa Rica", "Tarrazu", "", "", False, [], None),

    # --- Mexico ---
    ("csrc_167feec140bf4ccc", "Decaf Mexico Esmeralda", "Mexico", "Esmeralda", "", "", True,  [], None),
    ("798a628f-d9d0-42ea-ba65-77629775a8d3", "Mexico Decaf", "Mexico", "",     "", "", True,  [], None),
    ("csrc_c8bfd38d18d2a86b", "Mexico Veracruz",        "Mexico", "Veracruz",  "", "", False, [], None),
    ("csrc_211af3db661e89ed", "Organic Mexico",         "Mexico", "",          "", "", False, [], None),

    # --- El Salvador ---
    ("csrc_214aa09f8d6df8d9", "El Salvador",         "El Salvador", "",        "", "", False, [], None),
    ("15c8cf88-62f9-4dbf-8d3a-eae6854e1c14", "El Salvador Everest", "El Salvador", "Everest", "", "", False, [], None),

    # --- Guatemala ---
    ("csrc_254a56c3c710f2c2", "Guatemala SHB", "Guatemala", "", "SHB", "", False, [], None),

    # --- Honduras ---
    ("csrc_f48911ac42eb8b84", "Honduras Calan",         "Honduras", "Calan",        "", "", False, [], None),
    ("csrc_2c416abfbff80f03", "Honduras Comsa",         "Honduras", "Comsa",        "", "", False, [], None),
    ("csrc_548695e94eeac96e", "Honduras Copan",         "Honduras", "Copan",        "", "", False, [], None),
    ("csrc_fec67ce029c1abd0", "Honduras Siguatepeque",  "Honduras", "Siguatepeque", "", "", False, [], None),
    ("csrc_e58386e99c4408e6", "Organic Honduras Comsa", "Honduras", "Comsa",        "", "", False, [], None),
    ("csrc_90760e479a2af138", "Organic Honduras Copan", "Honduras", "Copan",        "", "", False, [], None),

    # --- USA / Hawaii: Kona (country = 'USA - Kona') ---
    ("4574235f-7e3a-4bf1-8560-0ce2619e748d", "Hawaii Kona No.3",     "USA - Kona", "", "#3", "", False, [], None),
    ("csrc_b95b8329674802f0", "Hawaii No.3 (Kona)",                  "USA - Kona", "", "#3", "", False, [], None),
    ("csrc_e912e88bdc7bb317", "Kona #3",                             "USA - Kona", "", "#3", "", False, [], None),
    ("csrc_54f520e29c3c78d2", "Kona Castaway Estate",   "USA - Kona", "Castaway",  "Estate",  "", False, [], None),
    ("csrc_3983ca85110c4fa5", "Kona Castaway Reserve",  "USA - Kona", "Castaway",  "Reserve", "", False, [], None),
    ("csrc_3ee355aeaa090e0d", "Kona Decaf",             "USA - Kona", "",          "",        "", True,  [], None),
    ("csrc_cd00fb0683a9171d", "Kona Organic",           "USA - Kona", "",          "",        "", False, [], None),
    ("d439446a-6523-4365-b18b-3fc98fb48a57", "Organic Kona", "USA - Kona", "",     "",        "", False, [], None),
    ("csrc_5b2aa7260e08ff80", "Kona Peaberry",          "USA - Kona", "",          "Peaberry","", False, [], None),
    ("csrc_e2a2740c094d113c", "Kona Prime 16/17",       "USA - Kona", "Prime",     "16/17",   "", False, [], None),
    ("csrc_4952616625ead19a", "Kona Prime 18/19",       "USA - Kona", "Prime",     "18/19",   "", False, [], None),
    ("csrc_e8146f2795c12d52", "Kona Prime Peaberry",    "USA - Kona", "Prime",     "Peaberry","", False, [], None),

    # --- USA / Hawaii: Ka'u (country = "USA - Ka'u") ---
    ("csrc_419905aff309b85a", "Ka'u #16,17,18,19",          "USA - Ka'u", "", "#16-19", "",       False, [], None),
    ("csrc_b12267adaddfb9fb", "Ka'u #18 Semi Washed (Honey)","USA - Ka'u","", "#18",    "Honey",  False, [], None),
    ("csrc_a110e005da5a37f0", "Ka'u #19 Natural",           "USA - Ka'u", "", "#19",    "Natural",False, [], None),
    ("csrc_c46a36549e65eff7", "Ka'u Honey",                 "USA - Ka'u", "", "",        "Honey",  False, [], None),
    ("csrc_22b6cff651892be0", "Ka'u Natutal # 18",          "USA - Ka'u", "", "#18",     "Natural",False, [], None),
    ("aae70ef1-a9ce-4152-a760-aabeedfd8dba", "Kau 18",      "USA - Ka'u", "", "#18",     "",       False, [], None),
    ("4cb216bb-e7e2-4d87-bd69-9674ad39d908", "Kau 18 Honey","USA - Ka'u", "", "#18",     "Honey",  False, [], None),
    ("2d7716a7-bbc3-4dff-880c-df2679640626", "Kau 19",      "USA - Ka'u", "", "#19",     "",       False, [], None),

    # --- USA / Hawaii: Maui (country = 'USA - Maui') ---
    # Mahi Pono is a real farm literally in the original name -> region; H3 grade.
    ("107396af-3b99-4c29-bf49-ecd6e8f05678", "Mahi Pono h3", "USA - Maui", "Mahi Pono", "H3", "", False, [], None),
    ("csrc_a6837a97a66e2a7e", "Maui H3",                "USA - Maui", "", "H3",        "",       False, [], None),
    ("csrc_05fece7c03fc47c7", "Maui Dec Yellow 14",     "USA - Maui", "Yellow", "14",  "",       True,  [], None),
    # Mokka: botanical varietal. Keep screen number as distinguisher; preserve Mokka via override.
    ("csrc_44109ca9903ae026", "Maui Moka 11",  "USA - Maui", "", "11", "", False, ["Mokka"], "USA - Maui Mokka 11"),
    ("csrc_487d98cba93b6956", "Maui Moka 14",  "USA - Maui", "", "14", "", False, ["Mokka"], "USA - Maui Mokka 14"),
    ("f47482ad-0c29-41e8-a85d-132cf6a61271", "Maui Mokka 11", "USA - Maui", "", "11", "", False, ["Mokka"], "USA - Maui Mokka 11"),
    ("b41d7af7-e06d-4ca5-87c8-6b3cc480ac40", "Maui mokka 14", "USA - Maui", "", "14", "", False, ["Mokka"], "USA - Maui Mokka 14"),
    ("csrc_0d41704569f55641", "Maui Red / Yellow Natural/Wash", "USA - Maui", "Red/Yellow", "", "Natural/Washed", False, [], None),
    ("csrc_ae0824323728699f", "Maui Red 14",            "USA - Maui", "Red", "14",      "",       False, [], None),
    # Catuai is a varietal; Red + Washed remain as distinguishers -> no override needed.
    ("csrc_0f87e935cf02c610", "Maui Red Catuai Wash",   "USA - Maui", "Red", "",        "Washed", False, ["Catuai"], None),
    ("csrc_e9a889b35f8b992e", "Maui Red H3",            "USA - Maui", "Red", "H3",       "",      False, [], None),
    ("csrc_4e30e28a5edaac06", "Maui Red Natural 16",    "USA - Maui", "Red", "16",       "Natural",False, [], None),
    ("csrc_8cac746b77fa5e30", "Maui Red Peaberry",      "USA - Maui", "Red", "Peaberry", "",      False, [], None),
    ("a1b7c502-64c5-4d6e-98a4-9d8745e40e1a", "Maui Yellow", "USA - Maui", "Yellow", "",  "",      False, [], None),
    ("csrc_d11df67fcd1d3bd9", "Maui Yellow 16",         "USA - Maui", "Yellow", "16",     "",      False, [], None),
    ("csrc_d793c3dba1f9c7d9", "Maui Yellow H3 Natural", "USA - Maui", "Yellow", "H3",     "Natural",False, [], None),
    ("csrc_bfd0fd07d8f36e9e", "Maui Yellow Peaberry",   "USA - Maui", "Yellow", "Peaberry","",     False, [], None),

    # --- Nicaragua ---
    ("csrc_7c9c7f0eca21d029", "Nicaragu Olomega Supreme", "Nicaragua", "Olomega", "Supremo", "", False, [], None),
    # Robusta is a species/varietal; SOLE distinguisher -> composed collapses to "Nicaragua". Override.
    ("csrc_0c03c745fe7bc804", "Nicaragu Robusta",         "Nicaragua", "",        "",        "", False, ["Robusta"], "Nicaragua Robusta"),
    ("53b6f685-6a2f-4dcd-b9ad-732aac9fcb12", "Nicaragua Olomega", "Nicaragua", "Olomega", "", "", False, [], None),
    ("csrc_10b5149aecee5e0d", "Organic Nicaragua",        "Nicaragua", "",        "",        "", False, [], None),

    # --- Papua New Guinea ---
    ("csrc_209100c254f6e64d", "Organic Papua New Guinea",      "Papua New Guinea", "",      "",        "", False, [], None),
    ("csrc_c9f7cf5ed2d057ae", "Organic PNG Simbu",             "Papua New Guinea", "Simbu", "",        "", False, [], None),
    ("csrc_27019e3a8b1d2c6a", "Papa New Guinea (not peaberry)","Papua New Guinea", "",      "",        "", False, [], None),
    ("csrc_d2bed255e650be0e", "Papa New Guinea Peaberry",      "Papua New Guinea", "",      "Peaberry","", False, [], None),

    # --- Peru ---
    ("csrc_1483d3f39c6ded9f", "Organic Peru",             "Peru", "",                       "", "", False, [], None),
    ("csrc_c8a7362b8bc1d2fc", "Organic Peru Selva Andina","Peru", "Selva Andina",           "", "", False, [], None),
    ("csrc_9e22c4ecd79db3bb", "PERU FT-FLO/USA ORGANIC CAFE DE MUJER APROCCURMA", "Peru", "APROCCURMA Cafe de Mujer", "", "", False, [], None),
    ("csrc_c3692df4e5b76f59", "Peru Vida Alta",           "Peru", "Vida Alta",              "", "", False, [], None),

    # --- Sumatra ---
    ("csrc_ce35b4d21f498f12", "Sumatra",                     "Sumatra", "",                    "", "", False, [], None),
    ("csrc_b39931a7edd8a6e3", "Sumatra Takengon & Sulawesi", "Sumatra", "Takengon & Sulawesi", "", "", False, [], None),

    # --- Timor ---
    ("csrc_936ef021d0846852", "Organic Timor Peaberry", "Timor", "", "Peaberry", "", False, [], None),

    # --- Yemen ---
    # Mocca/Mokka is the botanical varietal AND the only token besides country.
    # Composed would collapse to "Yemen". Override to preserve Mokka.
    ("csrc_f9c78ea8c2cdba62", "Yemen Mocca", "Yemen", "", "", "", False, ["Mokka"], "Yemen Mokka"),
]


def compose(country, region, grade, process, is_decaf):
    parts = [country, region, grade, process]
    title = " ".join(p for p in parts if p)
    if is_decaf:
        title = (title + " Decaf").strip() if title else "Decaf"
    return title


def main():
    tsv_path = "/Users/wanderingaloha/my-supabase-project/scripts/mcr_composed_title_review_v2.tsv"
    sql_path = "/Users/wanderingaloha/my-supabase-project/scripts/mcr_composed_title_backfill_v2.sql"

    out_rows = []
    for (cid, orig, country, region, grade, process, is_decaf, varietals, override) in ROWS:
        composed = compose(country, region, grade, process, is_decaf)
        final = override if override else composed
        out_rows.append({
            "coffee_source_id": cid,
            "original_name": orig,
            "country": country,
            "region": region,
            "grade_label": grade,
            "process": process,
            "is_decaf": "t" if is_decaf else "f",
            "varietals": ",".join(varietals),
            "name_override": override or "",
            "composed_title": composed,
            "final_title": final,
        })

    # Write TSV
    cols = ["coffee_source_id", "original_name", "country", "region", "grade_label",
            "process", "is_decaf", "varietals", "name_override", "composed_title", "final_title"]
    with open(tsv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter="\t")
        w.writeheader()
        for r in out_rows:
            w.writerow(r)

    # Write SQL
    def q(s):
        return "'" + s.replace("'", "''") + "'"

    def qnull(s):
        return q(s) if s else "NULL"

    def arr(lst):
        if not lst:
            return "'{}'::text[]"
        inner = ",".join(q(x) for x in lst)
        return "ARRAY[" + inner + "]::text[]"

    lines = []
    lines.append("-- MCR composed-title backfill (v2, corrected)")
    lines.append("-- company_id='9ShiyDAXhV', active sources only. Idempotent.")
    lines.append("-- Corrections: (1) USA - <island> country; (2) name_override for varietal-sole cases;")
    lines.append("-- (3) coffee_name := COALESCE(name_override, composed_title). Varietal kept in varietals[].")
    lines.append("BEGIN;")
    lines.append("")
    lines.append("ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;")
    lines.append("ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS name_override text;")
    lines.append("")
    for r in out_rows:
        cid = r["coffee_source_id"]
        country = r["country"]
        region = r["region"]
        grade = r["grade_label"]
        process = r["process"]
        is_decaf = "true" if r["is_decaf"] == "t" else "false"
        varietals = [v for v in r["varietals"].split(",") if v]
        override = r["name_override"]
        final = r["final_title"]
        lines.append(f"-- {r['original_name']}  ->  {final}")
        lines.append("UPDATE coffee_source SET")
        lines.append(f"  country_of_origin = {qnull(country)},")
        lines.append(f"  region            = {qnull(region)},")
        lines.append(f"  grade_label       = {qnull(grade)},")
        lines.append(f"  process           = {qnull(process)},")
        lines.append(f"  is_decaf          = {is_decaf},")
        lines.append(f"  varietals         = {arr(varietals)},")
        lines.append(f"  name_override     = {qnull(override)},")
        lines.append(f"  coffee_name       = {q(final)}")
        lines.append(f"WHERE coffee_source_id = {q(cid)} AND company_id = '9ShiyDAXhV';")
        lines.append("")
    lines.append("COMMIT;")

    with open(sql_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    # Uniqueness / dropped-token report
    from collections import Counter
    finals = Counter(r["final_title"] for r in out_rows)
    dups = {k: v for k, v in finals.items() if v > 1}

    overrides = [(r["original_name"], r["name_override"]) for r in out_rows if r["name_override"]]

    print(f"COUNT={len(out_rows)}")
    print("OVERRIDES:")
    for o, ov in overrides:
        print(f"  {o} -> {ov}")
    print("DUP_FINAL_TITLES:")
    for k, v in sorted(dups.items()):
        ids = [r["coffee_source_id"] for r in out_rows if r["final_title"] == k]
        print(f"  ({v}x) {k}  :: {', '.join(ids)}")
    print(f"TSV={tsv_path}")
    print(f"SQL={sql_path}")


if __name__ == "__main__":
    main()
