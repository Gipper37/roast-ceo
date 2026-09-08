"""
Tag the reconstructed past-subscribers in Shopify.

Segments come from subscriber_history.csv. Tags are additive (Tags Command =
MERGE) so nothing already on the customer is disturbed.

  past-subscriber        all 475, the umbrella
  subscriber-winback     301, no order in over a year
  subscriber-recent      174, ordered within the last year
  sub-active / sub-slipping / sub-lapsed    finer recency, for sequencing sends
  cadence-monthly / cadence-6wk / cadence-bimonthly / cadence-quarterly
                         what frequency to actually offer them

Writes matrixify_subscriber_tags.csv
"""
import csv, collections
from pathlib import Path

BASE = Path("/Users/wanderingaloha/my-supabase-project/MCR")

# ---- Shopify customers, for real IDs and marketing consent
cust = {}
for r in csv.DictReader(open(BASE / "Customers_2026-08-12_165304.csv", encoding="utf-8-sig")):
    e = (r.get("Email") or "").strip().lower()
    i = (r.get("ID") or "").strip()
    if e and i and e not in cust:
        cust[e] = {"id": i, "mkt": (r.get("Email Marketing: Status") or "").strip(),
                   "tags": (r.get("Tags") or "")}

def cadence(days):
    d = int(days)
    if d <= 35:  return "cadence-monthly"
    if d <= 52:  return "cadence-6wk"
    if d <= 75:  return "cadence-bimonthly"
    return "cadence-quarterly"

rows, missing, optout = [], [], []
counts = collections.Counter()
for r in csv.DictReader(open(BASE / "subscriber_history.csv", encoding="utf-8")):
    if r["subscription_like"] != "Y": continue
    e = r["email"]
    c = cust.get(e)
    if not c:
        missing.append(e); continue

    d = int(r["days_since_last"])
    tags = ["past-subscriber"]
    if d >= 365:
        tags += ["subscriber-winback", "sub-gone"]
    else:
        tags.append("subscriber-recent")
        tags.append("sub-active" if d < 90 else "sub-slipping" if d < 180 else "sub-lapsed")
    tags.append(cadence(r["median_gap_days"]))
    for t in tags: counts[t] += 1

    if c["mkt"] == "not_subscribed": optout.append((e, r["lifetime_value"]))

    rows.append({"ID": c["id"], "Email": e, "Command": "UPDATE",
                 "Tags": ", ".join(tags), "Tags Command": "MERGE"})

with open(BASE / "matrixify_subscriber_tags.csv", "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=["ID", "Email", "Command", "Tags", "Tags Command"])
    w.writeheader(); w.writerows(rows)

print(f"rows to import : {len(rows)}")
print(f"not found in the Shopify export : {len(missing)}")
for e in missing[:8]: print("    ", e)
print("\ntag counts:")
for t in ("past-subscriber", "subscriber-winback", "subscriber-recent",
          "sub-active", "sub-slipping", "sub-lapsed", "sub-gone",
          "cadence-monthly", "cadence-6wk", "cadence-bimonthly", "cadence-quarterly"):
    if counts[t]: print(f"   {counts[t]:>4}  {t}")
print(f"\nnot_subscribed, must stay out of any marketing send: {len(optout)}")
for e, v in sorted(optout, key=lambda x: -float(x[1]))[:10]:
    print(f"   ${float(v):>9,.0f}  {e}")
