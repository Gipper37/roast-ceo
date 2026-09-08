#!/usr/bin/env python3
"""
MCR composed-title v3 — DRY RUN (no DB writes).

Composes a fully-automatic title for every active coffee_source row of company
9ShiyDAXhV, archives the known dup extras, and emits a reviewable TSV plus an
idempotent backfill SQL file. NOTHING is executed here.

COMPOSED-TITLE RULE v3 (no name_override):
  Title = [country] [region] [farm] [grade_label] [Decaf?] [Peaberry?] [certs...]
  certs LAST; omit empty parts. 'Peaberry' suppressed if grade_label already
  carries it. FALLBACK when region+farm+grade_label are ALL empty: insert the
  next-deeper datum (varietals -> process -> flavor_notes) in the descriptive
  slot (after country, before markers).

Hawaiian: country = 'USA - <island>' (USA - Kona / USA - Ka'u / USA - Maui).
  Distinguishing detail (Red/Yellow/Prime/#screen) -> region or grade_label;
  Honey/Natural/Washed -> process. No doubled island, no invented farm.

Robusta is folded into varietals[]. is_decaf bool column added; title shows
'Decaf' for the 6 decaf sources. certs (Organic, ...) stay in the title.
"""
import csv, os, subprocess, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
COMPANY = "9ShiyDAXhV"
PSQL = "/opt/homebrew/Cellar/postgresql@17/17.8/bin/psql"
PSQL_URL = "postgresql://postgres@db.pwpslalerytymorcodlv.supabase.co:5432/postgres"
PGPASS = "SDH-h3FNHXSrxj-"


def psql(sql):
    out = subprocess.run(
        [PSQL, PSQL_URL, "-At", "-F", "\t", "-c", sql],
        env={**os.environ, "PGPASSWORD": PGPASS},
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("psql error:\n" + out.stderr)
    return [line.split("\t") for line in out.stdout.splitlines() if line]


# ── dup groups: archive these source_ids (keep the row with a purchase) ──────
# The 4 explicitly-named groups in the task, PLUS 4 additional same-coffee
# re-import duplicates (all from the 2026-06-12 batch, all 0 purchases) that
# collapse to an identical title on the same origin_id and would otherwise
# violate the uq_coffee_source(company_id,origin_id,coffee_name) guard. These
# fall under the same stated dedup rule: keep the purchase/cleaner-named row.
ARCHIVE_IDS = {
    # Kona #3 (3 rows) -> keep csrc_b95b8329674802f0 (1 purchase)
    "4574235f-7e3a-4bf1-8560-0ce2619e748d": "Hawaii Kona No.3",
    "csrc_e912e88bdc7bb317": "Kona #3",
    # Maui Mokka 11 (2 rows) -> keep csrc_44109ca9903ae026 (1 purchase)
    "f47482ad-0c29-41e8-a85d-132cf6a61271": "Maui Mokka 11",
    # Maui Mokka 14 (2 rows) -> keep csrc_487d98cba93b6956 (1 purchase)
    "b41d7af7-e06d-4ca5-87c8-6b3cc480ac40": "Maui mokka 14",
    # Ka'u #18 Honey (2 rows) -> keep csrc_b12267adaddfb9fb (1 purchase)
    "4cb216bb-e7e2-4d87-bd69-9674ad39d908": "Kau 18 Honey",
    # ── additional re-import dups (2026-06-12 batch, 0 purchases) ──
    # Kona Organic (2 rows) -> keep csrc_cd00fb0683a9171d (1 purchase)
    "d439446a-6523-4365-b18b-3fc98fb48a57": "Organic Kona",
    # Maui H3 (2 rows, both 0 purch) -> keep csrc_a6837a97a66e2a7e (cleaner name, no invented farm)
    "107396af-3b99-4c29-bf49-ecd6e8f05678": "Mahi Pono h3",
    # Ka'u #18 plain (dup of #18 Honey/#18 Natural concept) -> archive, no purchase
    "aae70ef1-a9ce-4152-a760-aabeedfd8dba": "Kau 18",
    # Ka'u #19 plain (dup of #19 Natural) -> archive, no purchase
    "2d7716a7-bbc3-4dff-880c-df2679640626": "Kau 19",
}

# ── the 6 decaf sources ──────────────────────────────────────────────────────
DECAF_IDS = {
    "csrc_23753f1ab6d3f9c9",  # Decaf Brazil (FLAVOR)
    "csrc_058f4808fbf5f03e",  # Decaf Colombia (DECAF BLENDS)
    "csrc_167feec140bf4ccc",  # Decaf Mexico Esmeralda
    "csrc_3ee355aeaa090e0d",  # Kona Decaf
    "csrc_05fece7c03fc47c7",  # Maui Dec Yellow 14
    "798a628f-d9d0-42ea-ba65-77629775a8d3",  # Mexico Decaf
}

# Per-source authored field set. Country/region/grade_label/process/varietals/
# certs are derived from the trapped descriptor. Each entry: the structured
# values that, after composition, yield the v3 title. Hand-curated for accuracy
# because the source names carry typos + free text and every distinguishing
# token must survive into a unique title within its origin_id group.
#
# fields: country, region, farm, grade_label, process, varietals(list),
#         certs(list), is_peaberry(bool), is_decaf(bool), flavor(list)
PLAN = {
    # ── Brazil (orig_c655bcaf99a986b1) ──
    "csrc_e6cac7ee284067a7": dict(country="Brazil", region="Mogiana", grade_label="SS FC"),
    "csrc_5de796c028876030": dict(country="Brazil", region="Mogiana", grade_label="SS FC 15/16"),
    "csrc_d7988f5e334bbb0f": dict(country="Brazil", region="Mogiana", grade_label="SS FC 15/17"),
    "csrc_81f73985aac71db7": dict(country="Brazil", region="Mogiana", grade_label="SS FC 17/18"),
    "csrc_7d11bddf8db2e72d": dict(country="Brazil", region="Sul de Minas", grade_label="SS FC"),
    # ── Colombia (orig_d393e3392710921a) ──
    "csrc_0a84d7ad205487c5": dict(country="Colombia", grade_label="Excelso EP"),
    "csrc_e59e36a550ac6cfe": dict(country="Colombia", region="Huila", grade_label="Supremo"),
    "csrc_a62b479c16f3a46f": dict(country="Colombia", region="Medellín", grade_label="Excelso"),
    "csrc_1619c377f98171c9": dict(country="Colombia", grade_label="Supremo"),
    "csrc_241e8bed4968e9f0": dict(country="Colombia", varietals=["Gesha"]),  # fallback -> Colombia Gesha
    "csrc_51dc895c7e973ba2": dict(country="Colombia", grade_label="Excelso EP", certs=["Organic"]),
    # ── Costa Rica (orig_d5456517bf131c45) ──
    "csrc_c66f57af57b8205f": dict(country="Costa Rica", region="Tarrazú", grade_label="SHB"),
    # ── Decaf blends (orig_mcr_decaf) ──
    "csrc_23753f1ab6d3f9c9": dict(country="Brazil", is_decaf=True),       # Brazil Decaf
    "csrc_058f4808fbf5f03e": dict(country="Colombia", is_decaf=True),     # Colombia Decaf
    "csrc_167feec140bf4ccc": dict(country="Mexico", region="Esmeralda", is_decaf=True),
    "798a628f-d9d0-42ea-ba65-77629775a8d3": dict(country="Mexico", is_decaf=True),  # Mexico Decaf
    # ── El Salvador (orig_28d3a9afb33fb94a) ──
    "csrc_214aa09f8d6df8d9": dict(country="El Salvador", grade_label="SHG"),
    "15c8cf88-62f9-4dbf-8d3a-eae6854e1c14": dict(country="El Salvador", region="Everest"),
    # ── Guatemala (orig_b3890561c1c3ba25) ──
    "csrc_254a56c3c710f2c2": dict(country="Guatemala", grade_label="SHB"),
    # ── Hawaii Kona #3 (orig_mcr_kona_h3) — keep b95 ──
    "csrc_b95b8329674802f0": dict(country="USA - Kona", grade_label="#3"),
    # ── Honduras (orig_d669c72ce18c7651) ──
    "csrc_f48911ac42eb8b84": dict(country="Honduras", region="Calán", grade_label="SHG"),
    "csrc_2c416abfbff80f03": dict(country="Honduras", region="COMSA", grade_label="SHG"),
    "csrc_548695e94eeac96e": dict(country="Honduras", region="Copán", grade_label="SHG"),
    "csrc_fec67ce029c1abd0": dict(country="Honduras", region="Siguatepeque", grade_label="SHG"),
    "csrc_e58386e99c4408e6": dict(country="Honduras", region="COMSA", grade_label="SHG", certs=["Organic"]),
    "csrc_90760e479a2af138": dict(country="Honduras", region="Copán", grade_label="SHG", certs=["Organic"]),
    # ── Ka'u (orig_afb785641116ec03) — keep b12 for #18 Honey ──
    "csrc_419905aff309b85a": dict(country="USA - Ka'u", grade_label="#16/17/18/19"),
    "csrc_b12267adaddfb9fb": dict(country="USA - Ka'u", grade_label="#18", process="Honey"),
    "csrc_a110e005da5a37f0": dict(country="USA - Ka'u", grade_label="#19", process="Natural"),
    "csrc_c46a36549e65eff7": dict(country="USA - Ka'u", process="Honey"),
    "csrc_22b6cff651892be0": dict(country="USA - Ka'u", grade_label="#18", process="Natural"),
    # ── Kona castaway (orig_mcr_kona_castaway) ──
    "csrc_54f520e29c3c78d2": dict(country="USA - Kona", region="Castaway Estate"),
    "csrc_3983ca85110c4fa5": dict(country="USA - Kona", region="Castaway Reserve"),
    # ── Kona decaf (orig_mcr_kona_decaf) ──
    "csrc_3ee355aeaa090e0d": dict(country="USA - Kona", is_decaf=True),
    # ── Kona organic (orig_mcr_kona_organic) ──
    "csrc_cd00fb0683a9171d": dict(country="USA - Kona", certs=["Organic"]),
    # ── Kona peaberry (orig_mcr_kona_peaberry) ──
    "csrc_5b2aa7260e08ff80": dict(country="USA - Kona", is_peaberry=True),
    "csrc_e8146f2795c12d52": dict(country="USA - Kona", grade_label="Prime", is_peaberry=True),
    # ── Kona prime (orig_mcr_kona_prime) ──
    "csrc_e2a2740c094d113c": dict(country="USA - Kona", grade_label="Prime 16/17"),
    "csrc_4952616625ead19a": dict(country="USA - Kona", grade_label="Prime 18/19"),
    # ── Maui H3 (orig_mcr_maui_h3) ──
    "csrc_a6837a97a66e2a7e": dict(country="USA - Maui", grade_label="H3"),
    "csrc_e9a889b35f8b992e": dict(country="USA - Maui", region="Red", grade_label="H3"),
    "csrc_d793c3dba1f9c7d9": dict(country="USA - Maui", region="Yellow", grade_label="H3", process="Natural"),
    # ── Maui Moka (orig_mcr_maui_moka) — keep 44109/487 ──
    "csrc_44109ca9903ae026": dict(country="USA - Maui", grade_label="11", varietals=["Mokka"]),
    "csrc_487d98cba93b6956": dict(country="USA - Maui", grade_label="14", varietals=["Mokka"]),
    # ── Maui mixed (orig_142ffc976e750f22) — keep 0d41 ──
    "csrc_0d41704569f55641": dict(country="USA - Maui", region="Red / Yellow", process="Natural / Washed"),
    # ── Maui red (orig_mcr_maui_red) ──
    "csrc_ae0824323728699f": dict(country="USA - Maui", region="Red", grade_label="14"),
    "csrc_0f87e935cf02c610": dict(country="USA - Maui", region="Red", process="Washed", varietals=["Catuai"]),
    "csrc_4e30e28a5edaac06": dict(country="USA - Maui", region="Red", grade_label="16", process="Natural"),
    # ── Maui peaberry (orig_mcr_maui_peaberry) ──
    "csrc_8cac746b77fa5e30": dict(country="USA - Maui", region="Red", is_peaberry=True),
    "csrc_bfd0fd07d8f36e9e": dict(country="USA - Maui", region="Yellow", is_peaberry=True),
    # ── Maui yellow (orig_mcr_maui_yellow) ──
    "a1b7c502-64c5-4d6e-98a4-9d8745e40e1a": dict(country="USA - Maui", region="Yellow"),
    "csrc_d11df67fcd1d3bd9": dict(country="USA - Maui", region="Yellow", grade_label="16"),
    # ── Maui decaf (orig_mcr_maui_decaf) ──
    "csrc_05fece7c03fc47c7": dict(country="USA - Maui", region="Yellow", grade_label="14", is_decaf=True),
    # ── Mexico (orig_0d75323d13d7e2fe) ──
    "csrc_c8bfd38d18d2a86b": dict(country="Mexico", region="Veracruz", grade_label="HG"),
    "csrc_211af3db661e89ed": dict(country="Mexico", grade_label="HG", certs=["Organic"]),
    # ── Nicaragua (orig_bd7157c2ff0a76b3) ──
    "csrc_7c9c7f0eca21d029": dict(country="Nicaragua", region="Olomega", grade_label="SHG"),
    "csrc_0c03c745fe7bc804": dict(country="Nicaragua", varietals=["Robusta"]),  # fallback -> Nicaragua Robusta
    "53b6f685-6a2f-4dcd-b9ad-732aac9fcb12": dict(country="Nicaragua", region="Olomega"),
    "csrc_10b5149aecee5e0d": dict(country="Nicaragua", grade_label="SHG", certs=["Organic"]),
    # ── Papua New Guinea (orig_93f7f73f959de942) ──
    "csrc_209100c254f6e64d": dict(country="Papua New Guinea", certs=["Organic"]),
    "csrc_c9f7cf5ed2d057ae": dict(country="Papua New Guinea", region="Simbu", certs=["Organic"]),
    "csrc_27019e3a8b1d2c6a": dict(country="Papua New Guinea"),  # fallback empty -> plain country
    # ── Pacific peaberry (orig_mcr_pacific_peaberry) ──
    "csrc_d2bed255e650be0e": dict(country="Papua New Guinea", is_peaberry=True),
    "csrc_936ef021d0846852": dict(country="Timor", is_peaberry=True, certs=["Organic"]),
    # ── Peru (orig_5e487c2d0035d0d4) ──
    "csrc_1483d3f39c6ded9f": dict(country="Peru", certs=["Organic"]),
    "csrc_c8a7362b8bc1d2fc": dict(country="Peru", region="Selva Andina", certs=["Organic"]),
    "csrc_9e22c4ecd79db3bb": dict(country="Peru", region="Café de Mujer APROCCURMA", certs=["Organic", "Fair Trade"]),
    "csrc_c3692df4e5b76f59": dict(country="Peru", region="Vida Alta"),
    # ── Sumatra/Indonesia (orig_17c8424053723e32) ──
    "csrc_ce35b4d21f498f12": dict(country="Indonesia", region="Sumatra"),
    "csrc_b39931a7edd8a6e3": dict(country="Indonesia", region="Sumatra Takengon & Sulawesi"),
    # ── Yemen (orig_0798b3ed3a9e31a1) ──
    "csrc_f9c78ea8c2cdba62": dict(country="Yemen", varietals=["Mokka"]),  # fallback -> Yemen Mokka
}


def compose_title(p):
    """Apply v3 composition rule to a plan dict."""
    country = p.get("country", "") or ""
    region = p.get("region", "") or ""
    farm = p.get("farm", "") or ""
    grade = p.get("grade_label", "") or ""
    process = p.get("process", "") or ""
    varietals = p.get("varietals", []) or []
    certs = p.get("certs", []) or []
    flavor = p.get("flavor", []) or []
    is_decaf = bool(p.get("is_decaf", False))
    is_pea = bool(p.get("is_peaberry", False))

    parts = []
    if country:
        parts.append(country)

    core = [x for x in (region, farm, grade) if x]
    if core:
        parts.extend(core)
        # Process is a distinguishing detail (Hawaiian Honey/Natural/Washed,
        # etc.). It is NOT in the v2 ordered slots, but when the descriptive
        # core is present it still differentiates same-grade lots, so it rides
        # in the distinguishing slot right after grade_label (before the
        # Decaf/Peaberry/certs markers). It also stays in the process column.
        if process:
            parts.append(process)
    else:
        # fallback chain: varietals -> process -> flavor_notes
        if varietals:
            parts.append(" ".join(varietals))
        elif process:
            parts.append(process)
        elif flavor:
            parts.append(", ".join(flavor))

    if is_decaf:
        parts.append("Decaf")

    grade_has_pea = "peaberry" in grade.lower()
    if is_pea and not grade_has_pea:
        parts.append("Peaberry")

    for c in certs:
        parts.append(c)

    return " ".join(x for x in parts if x).strip()


def sql_str(v):
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"


def sql_arr(items):
    if not items:
        return "'{}'"
    inner = ",".join('"' + str(i).replace('"', '\\"') + '"' for i in items)
    return "'{" + inner + "}'"


def main():
    srcs = psql(f"""SELECT cs.coffee_source_id, cs.coffee_name, COALESCE(cs.origin_id,''),
        (SELECT count(*) FROM coffee_inventory_purchased p WHERE p.coffee_source_id=cs.coffee_source_id)
        FROM coffee_source cs WHERE cs.company_id='{COMPANY}' AND cs.is_active
        ORDER BY cs.coffee_name;""")

    # Existing INACTIVE rows matter: uq_coffee_source(company_id,origin_id,
    # coffee_name) is NOT filtered by is_active, so an archived row holding a
    # name we want to assign to an active row blocks the UPDATE. Capture them.
    inactive = psql(f"""SELECT cs.coffee_source_id, COALESCE(cs.origin_id,''), cs.coffee_name
        FROM coffee_source cs WHERE cs.company_id='{COMPANY}' AND NOT cs.is_active
        ORDER BY cs.origin_id, cs.coffee_name;""")

    live_ids = {r[0] for r in srcs}
    plan_ids = set(PLAN) | set(ARCHIVE_IDS)
    missing = live_ids - plan_ids
    extra = plan_ids - live_ids
    if missing:
        sys.exit("PLAN missing active source ids: " + ", ".join(sorted(missing)))
    if extra:
        sys.exit("PLAN has ids not active/live: " + ", ".join(sorted(extra)))

    origin_by_id = {r[0]: r[2] for r in srcs}
    name_by_id = {r[0]: r[1] for r in srcs}

    rows = []          # surviving
    archived = []      # (sid, original_name)
    for sid, name, origin, _purch in srcs:
        if sid in ARCHIVE_IDS:
            archived.append((sid, name))
            continue
        p = dict(PLAN[sid])
        p["is_decaf"] = bool(p.get("is_decaf")) or (sid in DECAF_IDS)
        title = compose_title(p)
        rows.append(dict(sid=sid, name=name, origin=origin, plan=p, title=title))

    # ── uniqueness check among survivors, per origin_id ──
    by_origin = defaultdict(list)
    for r in rows:
        by_origin[r["origin"]].append(r["title"])
    dup_titles = []
    for origin, titles in by_origin.items():
        seen = {}
        for t in titles:
            seen[t] = seen.get(t, 0) + 1
        for t, c in seen.items():
            if c > 1:
                dup_titles.append((origin, t, c))

    # ── collisions vs already-INACTIVE rows on the same (origin_id, name).
    # The unique index spans inactive rows, so a surviving title equal to an
    # archived row's name blocks the UPDATE. Free the slot by renaming the
    # archived blocker to '<name> (archived <shortid>)' BEFORE the active
    # UPDATEs. Idempotent: if already suffixed, skip.
    survivor_keys = {(r["origin"], r["title"]) for r in rows}
    inactive_renames = []  # (sid, origin, old_name, new_name)
    for sid, origin, name in inactive:
        if (origin, name) in survivor_keys:
            new_name = f"{name} (archived {sid[:8]})"
            inactive_renames.append((sid, origin, name, new_name))

    # ── write review TSV ──
    review = os.path.join(HERE, "mcr_composed_title_review_v3.tsv")
    with open(review, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["coffee_source_id", "original_name", "action", "country",
                    "region", "grade_label", "process", "is_decaf", "certs",
                    "varietals", "final_title"])
        for sid, oname in archived:
            w.writerow([sid, oname, "archive", "", "", "", "", "", "", "", ""])
        for r in rows:
            p = r["plan"]
            w.writerow([
                r["sid"], r["name"], "keep",
                p.get("country", ""), p.get("region", ""), p.get("grade_label", ""),
                p.get("process", ""), "Y" if p.get("is_decaf") else "",
                "|".join(p.get("certs", []) or []),
                "|".join(p.get("varietals", []) or []),
                r["title"],
            ])

    # ── write idempotent backfill SQL (NOT executed) ──
    sqlf = os.path.join(HERE, "mcr_composed_title_backfill_v3.sql")
    with open(sqlf, "w") as f:
        f.write("-- MCR composed-title v3 backfill — generated, idempotent, NOT executed.\n")
        f.write("-- Review before applying. company_id='%s', active sources only.\n" % COMPANY)
        f.write("BEGIN;\n\n")
        f.write("-- 0. is_decaf column (idempotent)\n")
        f.write("ALTER TABLE coffee_source ADD COLUMN IF NOT EXISTS is_decaf boolean NOT NULL DEFAULT false;\n\n")

        f.write("-- 1. Archive dup extras FIRST so titles don't collide on uq_coffee_source.\n")
        for sid, oname in archived:
            f.write("UPDATE coffee_source SET is_active=false "
                    f"WHERE coffee_source_id={sql_str(sid)} AND company_id='{COMPANY}';"
                    f"  -- {oname}\n")
        f.write("\n")

        f.write("-- 1b. Free name slots held by already-INACTIVE rows that equal a surviving\n")
        f.write("--     title on the same origin_id (uq_coffee_source spans inactive rows).\n")
        if not inactive_renames:
            f.write("--     (none)\n")
        for sid, origin, old_name, new_name in inactive_renames:
            f.write(f"UPDATE coffee_source SET coffee_name={sql_str(new_name)} "
                    f"WHERE coffee_source_id={sql_str(sid)} AND company_id='{COMPANY}' "
                    f"AND NOT is_active AND coffee_name={sql_str(old_name)};"
                    f"  -- frees '{old_name}'\n")
        f.write("\n")

        f.write("-- 2. Per-surviving-source backfill (structured fields + composed coffee_name).\n")
        for r in rows:
            p = r["plan"]
            sets = [
                f"country_of_origin={sql_str(p.get('country',''))}",
                f"region={sql_str(p.get('region',''))}",
                f"grade_label={sql_str(p.get('grade_label',''))}",
                f"process={sql_str(p.get('process',''))}",
                f"is_decaf={'true' if p.get('is_decaf') else 'false'}",
                f"is_peaberry={'true' if p.get('is_peaberry') else 'false'}",
                f"varietals={sql_arr(p.get('varietals', []))}",
                f"certifications={sql_arr(p.get('certs', []))}",
                f"coffee_name={sql_str(r['title'])}",
            ]
            f.write(f"UPDATE coffee_source SET {', '.join(sets)} "
                    f"WHERE coffee_source_id={sql_str(r['sid'])} AND company_id='{COMPANY}';\n")
        f.write("\n")

        f.write("-- 3. Guard: (origin_id, coffee_name) must be UNIQUE before COMMIT.\n")
        f.write("--    Two checks: (a) among SURVIVING ACTIVE rows (the deliverable);\n")
        f.write("--    (b) across ALL rows (matches uq_coffee_source, which spans inactive).\n")
        f.write("DO $$\nDECLARE active_dups int; all_dups int;\nBEGIN\n")
        f.write("  SELECT count(*) INTO active_dups FROM (\n")
        f.write("    SELECT origin_id, coffee_name FROM coffee_source\n")
        f.write(f"    WHERE company_id='{COMPANY}' AND is_active\n")
        f.write("    GROUP BY origin_id, coffee_name HAVING count(*) > 1\n")
        f.write("  ) d;\n")
        f.write("  IF active_dups > 0 THEN\n")
        f.write("    RAISE EXCEPTION 'composed-title v3: % duplicate (origin_id, coffee_name) among active survivors — aborting', active_dups;\n")
        f.write("  END IF;\n")
        f.write("  SELECT count(*) INTO all_dups FROM (\n")
        f.write("    SELECT origin_id, coffee_name FROM coffee_source\n")
        f.write(f"    WHERE company_id='{COMPANY}'\n")
        f.write("    GROUP BY origin_id, coffee_name HAVING count(*) > 1\n")
        f.write("  ) d;\n")
        f.write("  IF all_dups > 0 THEN\n")
        f.write("    RAISE EXCEPTION 'composed-title v3: % duplicate (origin_id, coffee_name) across all rows (uq_coffee_source) — aborting', all_dups;\n")
        f.write("  END IF;\nEND $$;\n\n")
        f.write("COMMIT;\n")

    # ── summary ──
    print(f"surviving: {len(rows)}")
    print(f"archived: {len(archived)} -> {[a[1] for a in archived]}")
    print(f"inactive blockers renamed: {[(r[2], r[1]) for r in inactive_renames]}")
    print(f"dup titles among survivors (per origin): {dup_titles}")
    # also global title collisions for awareness
    all_titles = defaultdict(int)
    for r in rows:
        all_titles[r["title"]] += 1
    global_dups = {t: c for t, c in all_titles.items() if c > 1}
    print(f"global title collisions (cross-origin, informational): {global_dups}")
    print(f"\nreview -> {review}\nsql    -> {sqlf}")

    return len(rows), [a[1] for a in archived], dup_titles


if __name__ == "__main__":
    main()
