#!/usr/bin/env python3
"""
One-shot: fetch roast_log timestamps from Google Sheets, emit UPDATE SQL.

The original migrate_sheets.py stripped time components from roast_date
by calling .date() on parsed datetimes. This script fetches the source
CSV and generates UPDATE statements to restore the correct timestamps.

Usage:
    python3 scripts/extract_roast_timestamps.py > /tmp/roast_timestamps.sql
"""

import csv
import io
import sys
from datetime import datetime
from urllib.request import urlopen, Request

# ── Config ────────────────────────────────────────────────────────────────

TZ_OFFSET = "-10:00"  # Pacific/Honolulu (HST)

SHEET2_BASE = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vQ3l7JyaWWgPH8iGC_pV9Su73juwyu9766OZIysGBQUUVGvC_U5JPc8"
    "ZgmUwUq37SAqE0T0dwA8uS6z/pub"
)
ROAST_LOG_GID = 933493873


# ── Helpers ───────────────────────────────────────────────────────────────

def log(msg):
    print(msg, file=sys.stderr)


def parse_datetime(val):
    """Parse various date/datetime formats, preserving time. Returns datetime or None."""
    if not val or not val.strip():
        return None
    val = val.strip()
    for fmt in (
        "%m/%d/%Y %I:%M:%S %p",   # 1/19/2026 8:30:00 AM
        "%m/%d/%Y %H:%M:%S",      # 1/19/2026 08:30:00
        "%Y-%m-%dT%H:%M:%S",      # 2026-01-19T08:30:00
        "%Y-%m-%d %H:%M:%S",      # 2026-01-19 08:30:00
        "%m/%d/%Y %I:%M %p",      # 1/19/2026 8:30 AM
        "%m/%d/%Y",                # 1/19/2026  (no time → midnight)
        "%Y-%m-%d",                # 2026-01-19 (no time → midnight)
        "%m/%d/%y",                # 1/19/26    (no time → midnight)
    ):
        try:
            return datetime.strptime(val, fmt)
        except ValueError:
            continue
    return None


def sql_timestamp(dt):
    """Format a datetime as a timestamptz SQL literal."""
    if dt is None:
        return "NULL"
    return f"'{dt.strftime('%Y-%m-%d %H:%M:%S')}{TZ_OFFSET}'"


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    url = f"{SHEET2_BASE}?gid={ROAST_LOG_GID}&single=true&output=csv"
    log(f"Fetching roast_log CSV from Google Sheets ...")
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    resp = urlopen(req)
    text = resp.read().decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    rows = list(reader)
    log(f"  -> {len(rows)} total rows in sheet")

    updates = []
    has_time_count = 0
    no_time_count = 0
    skipped = 0

    for r in rows:
        roast_log_id = r.get("Roast Log ID", "").strip()
        roast_date_raw = r.get("Roast Date", "").strip()

        if not roast_log_id or not roast_date_raw:
            skipped += 1
            continue

        dt = parse_datetime(roast_date_raw)
        if dt is None:
            log(f"  WARNING: could not parse date '{roast_date_raw}' for {roast_log_id}")
            skipped += 1
            continue

        # Track whether this row actually had a time component
        if dt.hour != 0 or dt.minute != 0 or dt.second != 0:
            has_time_count += 1
        else:
            no_time_count += 1

        ts = sql_timestamp(dt)
        escaped_id = roast_log_id.replace("'", "''")
        updates.append(
            f"UPDATE public.roast_log SET roast_date = {ts} "
            f"WHERE roast_log_id = '{escaped_id}';"
        )

    # Output SQL
    print("-- Roast date timestamp backfill")
    print(f"-- Generated: {datetime.now().isoformat()}")
    print(f"-- Source: Google Sheets roast_log (gid={ROAST_LOG_GID})")
    print(f"-- Rows with time: {has_time_count}, date-only: {no_time_count}, skipped: {skipped}")
    print()
    for stmt in updates:
        print(stmt)

    log(f"\nDone. {len(updates)} UPDATE statements generated.")
    log(f"  With time component: {has_time_count}")
    log(f"  Date-only (midnight): {no_time_count}")
    log(f"  Skipped: {skipped}")


if __name__ == "__main__":
    main()
