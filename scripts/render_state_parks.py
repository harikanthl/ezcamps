#!/usr/bin/env python3
"""Render data/state_park_systems.csv into docs/STATE-PARKS.md."""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "state_park_systems.csv"
OUT = ROOT / "docs" / "STATE-PARKS.md"


def main() -> None:
    rows = list(csv.DictReader(DATA.open()))
    platforms = Counter(
        r["reservation_platform_detected"] or "No fingerprint"
        for r in rows
        if r["http_status"] == "200"
    )
    verified = sum(1 for r in rows if r["http_status"] == "200")

    lines = [
        "# State Park Systems — 50-State Directory",
        "",
        "_Generated from `data/state_park_systems.csv` on 2026-11-15. Re-run `scripts/collect_state_parks.py` then `scripts/render_state_parks.py` to refresh._",
        "",
        f"**{len(rows)} states** · **{verified} returned HTTP 200** from this build environment. "
        "Most of the rest return 403 to scripted clients but are valid official sites. "
        "Always treat the official URL as the source of truth.",
        "",
        "## Reservation platform summary",
        "",
        "| Platform | States detected |",
        "|---|---:|",
    ]
    for name, count in platforms.most_common():
        lines.append(f"| {name} | {count} |")

    lines += [
        "",
        "> Detection is a best-effort scan of each homepage for platform fingerprints. "
        "`No fingerprint` means the fetched page did not expose a platform string — not that no reservation system exists. "
        "Blocked pages are excluded from this summary. Several states run separate systems for cabins, permits or lotteries.",
        "",
        "## Directory",
        "",
        "| State | Agency | Official site | Site status | Reservation platform detected | Notes |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        status = r["http_status"]
        status_label = "200 OK" if status == "200" else status.replace("ERR:", "blocked/slow: ")
        platform = r["reservation_platform_detected"] or "—"
        notes = r["notes"] or ""
        lines.append(
            f"| **{r['state']}** | {r['agency']} | <{r['official_url']}> | {status_label} | {platform} | {notes} |"
        )

    lines += [
        "",
        "## What to collect per state",
        "",
        "For each state park system, the useful fields are:",
        "",
        "- Park and campground names, coordinates, season and fees",
        "- Site types: tent, RV, cabin, yurt, group, equestrian",
        "- Hookups, showers, dump station, potable water, cell signal",
        "- Pet rules, quiet hours, generator hours, fire rules",
        "- Out-of-state surcharges and discount passes",
        "- Reservation window, cancellation policy and lottery parks",
        "- Dispersed/WMA camping rules (often a different agency)",
        "",
        "## Highest-value states to adapt first",
        "",
        "Ranked by inventory, camping culture and Recreation.gov/ReserveAmerica coverage:",
        "",
        "1. California — 980 Recreation.gov listings; own ReserveCalifornia system",
        "2. Oregon — 689 listings; ReserveAmerica",
        "3. Utah — 674 listings; ReserveAmerica",
        "4. Colorado — 486 listings; mixed platforms",
        "5. Idaho — 458 listings; large dispersed-camping culture",
        "6. Montana — 373 listings; ReserveAmerica",
        "7. Arizona — 319 listings; snowbird/LTVA market",
        "8. Washington — 304 listings; GoingToCamp",
        "9. Texas — large state park system; ReserveAmerica",
        "10. Florida — large snowbird/coastal market; ReserveAmerica",
        "",
    ]
    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
