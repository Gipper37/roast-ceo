#!/usr/bin/env python3
"""
Build the MCR composed-title backfill PROPOSAL (review TSV + idempotent UPDATE SQL).

GOAL: every active coffee_source for company 9ShiyDAXhV should have its display
title fully COMPOSABLE from structured columns, with no MEANINGFUL token lost.

Composed title format (omit empty parts, in order):
    [country] [region] [grade_label] [process] [+ "Decaf" when is_decaf]
Varietals are DELIBERATELY EXCLUDED from the title (Gesha/Robusta live in
varietals[] as DATA only). A missing varietal is NOT a gap.

READ-ONLY: this script only WRITES the two artifact files. No DB writes.
"""

import csv

COMPANY_ID = "9ShiyDAXhV"
SRC_TSV = "/tmp/mcr_sources_full.tsv"
OUT_TSV = "/Users/wanderingaloha/my-supabase-project/scripts/mcr_composed_title_review.tsv"
OUT_SQL = "/Users/wanderingaloha/my-supabase-project/scripts/mcr_composed_title_backfill.sql"

# Per-source curated decisions, keyed by coffee_source_id.
# Each value: dict with keys country, region, grade_label, process, is_decaf,
# certs (list), varietals (list), is_peaberry (bool or None=keep), gap (str or "").
#
# gap is populated ONLY when the composed title still drops a MEANINGFUL token
# from the original name (ignoring varietals + pure casing/spelling fixes).
P = {}

def s(country="", region="", grade_label="", process="", is_decaf=False,
      certs=None, varietals=None, is_peaberry=False, gap=""):
    return dict(country=country, region=region, grade_label=grade_label,
                process=process, is_decaf=is_decaf,
                certs=certs or [], varietals=varietals or [],
                is_peaberry=is_peaberry, gap=gap)

# ---- BRAZIL ----
P["csrc_e6cac7ee284067a7"] = s("Brazil", "Mogiana")                       # Brazil Mogiana
P["csrc_5de796c028876030"] = s("Brazil", "Mogiana", grade_label="15/16")  # Brazil Mogiana 15/16
P["csrc_d7988f5e334bbb0f"] = s("Brazil", "Mogiana", grade_label="15/17")  # Brazil Mogiana 15/17
P["csrc_81f73985aac71db7"] = s("Brazil", "Mogiana", grade_label="17/18")  # Brazil Mogiana 17/18
P["csrc_7d11bddf8db2e72d"] = s("Brazil", "Sul de Minas")                  # Brazil Sul De Minas

# ---- COLOMBIA ----
P["csrc_0a84d7ad205487c5"] = s("Colombia", grade_label="Excelso")
P["csrc_e59e36a550ac6cfe"] = s("Colombia", "Huila", grade_label="Supremo")   # "Hulia"->Huila (spelling)
P["csrc_a62b479c16f3a46f"] = s("Colombia", "Medellin", grade_label="Excelso")# "Medelin"->Medellin
P["csrc_1619c377f98171c9"] = s("Colombia", grade_label="Supremo")
P["csrc_241e8bed4968e9f0"] = s("Colombia", varietals=["Gesha"])              # Gesha is data-only, not in title

# ---- COSTA RICA ----
P["csrc_c66f57af57b8205f"] = s("Costa Rica", "Tarrazu")

# ---- DECAF (origin) ----
# "Decaf Brazil (FLAVOR)" -> the (FLAVOR) parenthetical is a category tag, not a coffee attribute.
P["csrc_23753f1ab6d3f9c9"] = s("Brazil", is_decaf=True)
# "Decaf Colombia (DECAF BLENDS)" -> parenthetical is a category tag.
P["csrc_058f4808fbf5f03e"] = s("Colombia", is_decaf=True)
# "Decaf Mexico Esmeralda" -> Esmeralda is the estate/lot name; keep as region.
P["csrc_167feec140bf4ccc"] = s("Mexico", "Esmeralda", is_decaf=True)

# ---- EL SALVADOR ----
P["csrc_214aa09f8d6df8d9"] = s("El Salvador")
P["15c8cf88-62f9-4dbf-8d3a-eae6854e1c14"] = s("El Salvador", "Everest")  # Everest = farm/lot -> region

# ---- GUATEMALA ----
P["csrc_254a56c3c710f2c2"] = s("Guatemala", grade_label="SHB")  # Strictly Hard Bean grade

# ---- HAWAII: KONA ----
# Un-mangle: country=USA, region=Kona, drop doubled island, no invented farms.
P["4574235f-7e3a-4bf1-8560-0ce2619e748d"] = s("USA", "Kona", grade_label="#3")  # Hawaii Kona No.3
P["csrc_b95b8329674802f0"] = s("USA", "Kona", grade_label="#3")                  # Hawaii No.3 (Kona)
P["csrc_e912e88bdc7bb317"] = s("USA", "Kona", grade_label="#3")                  # Kona #3
P["csrc_54f520e29c3c78d2"] = s("USA", "Kona", grade_label="Castaway Estate")     # Kona Castaway Estate
P["csrc_3983ca85110c4fa5"] = s("USA", "Kona", grade_label="Castaway Reserve")    # Kona Castaway Reserve
P["csrc_3ee355aeaa090e0d"] = s("USA", "Kona", is_decaf=True)                     # Kona Decaf
P["csrc_cd00fb0683a9171d"] = s("USA", "Kona", certs=["Organic"])                 # Kona Organic
P["csrc_5b2aa7260e08ff80"] = s("USA", "Kona", grade_label="Peaberry", is_peaberry=True)  # Kona Peaberry
P["csrc_e2a2740c094d113c"] = s("USA", "Kona", grade_label="Prime 16/17")         # Kona Prime 16/17
P["csrc_4952616625ead19a"] = s("USA", "Kona", grade_label="Prime 18/19")         # Kona Prime 18/19
P["csrc_e8146f2795c12d52"] = s("USA", "Kona", grade_label="Prime Peaberry", is_peaberry=True)  # Kona Prime Peaberry
P["d439446a-6523-4365-b18b-3fc98fb48a57"] = s("USA", "Kona", certs=["Organic"])  # Organic Kona

# ---- HAWAII: KA'U ----
P["csrc_419905aff309b85a"] = s("USA", "Ka'u", grade_label="#16-19")              # Ka'u #16,17,18,19
P["csrc_b12267adaddfb9fb"] = s("USA", "Ka'u", grade_label="#18", process="Honey")  # Ka'u #18 Semi Washed (Honey)
P["csrc_a110e005da5a37f0"] = s("USA", "Ka'u", grade_label="#19", process="Natural") # Ka'u #19 Natural
P["csrc_c46a36549e65eff7"] = s("USA", "Ka'u", process="Honey")                   # Ka'u Honey
P["csrc_22b6cff651892be0"] = s("USA", "Ka'u", grade_label="#18", process="Natural") # Ka'u Natutal # 18 (typo Natutal->Natural)
P["aae70ef1-a9ce-4152-a760-aabeedfd8dba"] = s("USA", "Ka'u", grade_label="#18")  # Kau 18
P["4cb216bb-e7e2-4d87-bd69-9674ad39d908"] = s("USA", "Ka'u", grade_label="#18", process="Honey")  # Kau 18 Honey
P["2d7716a7-bbc3-4dff-880c-df2679640626"] = s("USA", "Ka'u", grade_label="#19")  # Kau 19

# ---- HAWAII: MAUI ----
# Maui color (Red/Yellow) = the cherry/lot color, kept as a grade-style descriptor.
# "H3" = Maui grade/lot designation (kept). "Moka/Mokka" = Mokka varietal style -> kept as varietal data,
#   but it is part of the human name, so retain it in grade_label too (it's a lot/cultivar name on Maui, not the
#   excluded Gesha/Robusta sense). Treat Mokka as a meaningful lot token -> include in grade_label.
P["csrc_05fece7c03fc47c7"] = s("USA", "Maui", grade_label="Yellow 14", is_decaf=True)  # Maui Dec Yellow 14 (Dec=Decaf)
P["csrc_a6837a97a66e2a7e"] = s("USA", "Maui", grade_label="H3")                   # Maui H3
P["csrc_44109ca9903ae026"] = s("USA", "Maui", grade_label="Mokka 11", varietals=["Mokka"])  # Maui Moka 11
P["csrc_487d98cba93b6956"] = s("USA", "Maui", grade_label="Mokka 14", varietals=["Mokka"])  # Maui Moka 14
P["f47482ad-0c29-41e8-a85d-132cf6a61271"] = s("USA", "Maui", grade_label="Mokka 11", varietals=["Mokka"])  # Maui Mokka 11
P["b41d7af7-e06d-4ca5-87c8-6b3cc480ac40"] = s("USA", "Maui", grade_label="Mokka 14", varietals=["Mokka"])  # Maui mokka 14
# "Maui Red / Yellow Natural/Wash" = combined/mixed lot. Keep both colors + both processes in grade_label.
P["csrc_0d41704569f55641"] = s("USA", "Maui", grade_label="Red/Yellow Natural/Washed")  # mixed lot
P["csrc_ae0824323728699f"] = s("USA", "Maui", grade_label="Red 14")              # Maui Red 14
P["csrc_0f87e935cf02c610"] = s("USA", "Maui", grade_label="Red", process="Washed", varietals=["Catuai"])  # Maui Red Catuai Wash
P["csrc_e9a889b35f8b992e"] = s("USA", "Maui", grade_label="Red H3")              # Maui Red H3
P["csrc_4e30e28a5edaac06"] = s("USA", "Maui", grade_label="Red 16", process="Natural")  # Maui Red Natural 16
P["csrc_8cac746b77fa5e30"] = s("USA", "Maui", grade_label="Red Peaberry", is_peaberry=True)  # Maui Red Peaberry
P["a1b7c502-64c5-4d6e-98a4-9d8745e40e1a"] = s("USA", "Maui", grade_label="Yellow")  # Maui Yellow
P["csrc_d11df67fcd1d3bd9"] = s("USA", "Maui", grade_label="Yellow 16")           # Maui Yellow 16
P["csrc_d793c3dba1f9c7d9"] = s("USA", "Maui", grade_label="Yellow H3", process="Natural")  # Maui Yellow H3 Natural
P["csrc_bfd0fd07d8f36e9e"] = s("USA", "Maui", grade_label="Yellow Peaberry", is_peaberry=True)  # Maui Yellow Peaberry
# "Mahi Pono h3" -> Mahi Pono is a Maui farm. Keep farm in region per "no invented farm UNLESS truly in name" (it IS in the name).
P["107396af-3b99-4c29-bf49-ecd6e8f05678"] = s("USA", "Maui", grade_label="Mahi Pono H3")  # Mahi Pono h3

# ---- MEXICO ----
P["798a628f-d9d0-42ea-ba65-77629775a8d3"] = s("Mexico", is_decaf=True)  # Mexico Decaf
P["csrc_c8bfd38d18d2a86b"] = s("Mexico", "Veracruz")                    # Mexico Veracruz

# ---- NICARAGUA ----
P["csrc_7c9c7f0eca21d029"] = s("Nicaragua", "Olomega", grade_label="Supremo")  # Nicaragu Olomega Supreme (Supreme->Supremo grade)
P["csrc_0c03c745fe7bc804"] = s("Nicaragua", varietals=["Robusta"])             # Nicaragu Robusta -> Robusta is data-only
P["53b6f685-6a2f-4dcd-b9ad-732aac9fcb12"] = s("Nicaragua", "Olomega")          # Nicaragua Olomega

# ---- ORGANIC (cert) origins ----
P["csrc_51dc895c7e973ba2"] = s("Colombia", certs=["Organic"])
P["csrc_e58386e99c4408e6"] = s("Honduras", "Comsa", certs=["Organic"])
P["csrc_90760e479a2af138"] = s("Honduras", "Copan", certs=["Organic"])
P["csrc_211af3db661e89ed"] = s("Mexico", certs=["Organic"])
P["csrc_10b5149aecee5e0d"] = s("Nicaragua", certs=["Organic"])
P["csrc_209100c254f6e64d"] = s("Papua New Guinea", certs=["Organic"])
P["csrc_1483d3f39c6ded9f"] = s("Peru", certs=["Organic"])
P["csrc_c8a7362b8bc1d2fc"] = s("Peru", "Selva Andina", certs=["Organic"])
P["csrc_c9f7cf5ed2d057ae"] = s("Papua New Guinea", "Simbu", certs=["Organic"])  # PNG Simbu
P["csrc_936ef021d0846852"] = s("Timor", grade_label="Peaberry", certs=["Organic"], is_peaberry=True)  # Organic Timor Peaberry

# ---- HONDURAS ----
P["csrc_f48911ac42eb8b84"] = s("Honduras", "Calan")
P["csrc_2c416abfbff80f03"] = s("Honduras", "Comsa")
P["csrc_548695e94eeac96e"] = s("Honduras", "Copan")
P["csrc_fec67ce029c1abd0"] = s("Honduras", "Siguatepeque")

# ---- PAPUA NEW GUINEA ----
# "Papa New Guinea (not peaberry)" -> the "(not peaberry)" is a disambiguator vs the peaberry lot.
#   It carries no positive attribute (it's the absence of peaberry); composes to plain PNG. Note, not gap.
P["csrc_27019e3a8b1d2c6a"] = s("Papua New Guinea")  # Papa New Guinea (not peaberry)
P["csrc_d2bed255e650be0e"] = s("Papua New Guinea", grade_label="Peaberry", is_peaberry=True)  # Papa New Guinea Peaberry

# ---- PERU ----
# Big messy one: "PERU FT-FLO/USA ORGANIC CAFE DE MUJER APROCCURMA"
#   country=Peru; certs=Organic + Fair Trade (FT-FLO); region/lot = APROCCURMA co-op, Cafe de Mujer (women's) program.
#   Keep co-op + program as region so the human name reconstructs.
P["csrc_9e22c4ecd79db3bb"] = s(
    "Peru", region="APROCCURMA Cafe de Mujer",
    certs=["Organic", "Fair Trade"],
    gap="")  # FT-FLO captured as Fair Trade cert; co-op + women's program preserved in region. No meaningful token lost.
P["csrc_c3692df4e5b76f59"] = s("Peru", "Vida Alta")  # Peru Vida Alta

# ---- SUMATRA ----
P["csrc_ce35b4d21f498f12"] = s("Sumatra")
# "Sumatra Takengon & Sulawesi" = blend of two origins (Sumatra Takengon + Sulawesi). region holds both.
P["csrc_b39931a7edd8a6e3"] = s("Sumatra", "Takengon & Sulawesi")

# ---- YEMEN ----
# "Yemen Mocca" -> Mocca = the classic Yemeni Mokha/Mocca varietal-style; keep as varietal data,
#   but it's a defining human token -> include in grade_label so the title reconstructs.
P["csrc_f9c78ea8c2cdba62"] = s("Yemen", grade_label="Mocca", varietals=["Mokka"])  # Yemen Mocca


def compose(country, region, grade_label, process, is_decaf):
    parts = [p for p in (country, region, grade_label, process) if p]
    title = " ".join(parts)
    if is_decaf:
        title = (title + " Decaf").strip() if title else "Decaf"
    return title


def main():
    rows = []
    with open(SRC_TSV) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("\t")
            # cols: id, name, country, region, grade_label, process, certs, varietals, peaberry, gq, gc, gs, gp, farm
            if len(cols) < 9:
                continue
            rows.append(cols)

    missing = [r[0] for r in rows if r[0] not in P]
    if missing:
        raise SystemExit("UNMAPPED ids: " + ", ".join(missing))

    review = []
    sql_updates = []
    gaps = []

    for r in rows:
        sid = r[0]
        orig = r[1]
        prop = P[sid]
        title = compose(prop["country"], prop["region"], prop["grade_label"],
                        prop["process"], prop["is_decaf"])
        certs_s = ",".join(prop["certs"])
        var_s = ",".join(prop["varietals"])
        review.append([
            sid, orig, prop["country"], prop["region"], prop["grade_label"],
            prop["process"], "t" if prop["is_decaf"] else "f",
            certs_s, var_s, title, prop["gap"],
        ])
        if prop["gap"]:
            gaps.append((sid, orig, title, prop["gap"]))

        # --- idempotent UPDATE ---
        def lit(v):
            return "'" + v.replace("'", "''") + "'" if v else "NULL"
        def arr(vals):
            if not vals:
                return "'{}'::text[]"
            inner = ",".join(v.replace("\\", "\\\\").replace('"', '\\"') for v in vals)
            esc = inner.replace("'", "''")
            return "'{" + esc + "}'::text[]"
        sql_updates.append(
            "UPDATE coffee_source SET\n"
            f"    country_of_origin = {lit(prop['country'])},\n"
            f"    region            = {lit(prop['region'])},\n"
            f"    grade_label       = {lit(prop['grade_label'])},\n"
            f"    process           = {lit(prop['process'])},\n"
            f"    is_decaf          = {'true' if prop['is_decaf'] else 'false'},\n"
            f"    is_peaberry       = {'true' if prop['is_peaberry'] else 'false'},\n"
            f"    certifications    = {arr(prop['certs'])},\n"
            f"    varietals         = {arr(prop['varietals'])},\n"
            "    updated_at        = now()\n"
            f"WHERE coffee_source_id = {lit(sid)}\n"
            f"  AND company_id = '{COMPANY_ID}' AND is_active;  -- {orig}  =>  {title}"
        )

    # write TSV
    with open(OUT_TSV, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["coffee_source_id", "original_name", "country", "region",
                    "grade_label", "process", "is_decaf", "certs", "varietals",
                    "composed_title", "gap"])
        w.writerows(review)

    # write SQL
    with open(OUT_SQL, "w") as f:
        f.write("-- MCR composed-title backfill PROPOSAL (idempotent, additive/guarded)\n")
        f.write(f"-- company_id = '{COMPANY_ID}', ACTIVE sources only.\n")
        f.write("-- Composed title = [country] [region] [grade_label] [process] [+ Decaf]; varietals excluded.\n")
        f.write("-- REVIEW ONLY -- do not run without explicit approval.\n\n")
        f.write("BEGIN;\n\n")
        f.write("-- New structured flag for decaf (additive, safe to re-run).\n")
        f.write("ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;\n\n")
        f.write("\n\n".join(sql_updates))
        f.write("\n\nCOMMIT;\n")

    print(f"sources processed: {len(rows)}")
    print(f"sources with gap : {len(gaps)}")
    for g in gaps:
        print("  GAP:", g[0], "|", g[1], "=>", g[2], "||", g[3])
    print(f"TSV: {OUT_TSV}")
    print(f"SQL: {OUT_SQL}")


if __name__ == "__main__":
    main()
