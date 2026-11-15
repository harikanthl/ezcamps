#!/usr/bin/env python3
"""Render docs/PARKS.md from the NPS and USFS tables."""

from __future__ import annotations

import csv
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "docs" / "PARKS.md"


def main() -> None:
    parks = list(csv.DictReader((DATA / "nps_parks.csv").open()))
    by_state: dict[str, list[dict]] = defaultdict(list)
    for p in parks:
        state = (p["states"] or "??").split(",")[0]
        by_state[state].append(p)

    designations = Counter(p["designation"] for p in parks)
    fees = sum(1 for p in parks if p["has_entrance_fee"] == "yes")

    lines = [
        "# Parks Catalog — National Park System",
        "",
        f"_Generated 2026-11-15 from the NPS Data API snapshot (`data/nps_parks.csv`). "
        f"{len(parks)} units across {len(by_state)} states/territories._",
        "",
        "## At a glance",
        "",
        f"- **{len(parks)}** National Park System units",
        f"- **{fees}** charge an entrance fee",
        f"- **{len(designations)}** designation types",
        "",
        "| Designation | Units |",
        "|---|---:|",
    ]
    for name, count in designations.most_common():
        lines.append(f"| {name} | {count} |")

    lines += [
        "",
        "## Units by state",
        "",
        "Multi-state units are listed under their first state; the `States` column shows all.",
        "",
        "| State | Unit | Designation | Entrance fee | Activities (sample) |",
        "|---|---|---|---|---|",
    ]
    for state in sorted(by_state):
        for p in sorted(by_state[state], key=lambda x: x["name"]):
            acts = "; ".join(p["activities"].split(";")[:4])
            fee = f"${p['entrance_fee_cost']}" if p["has_entrance_fee"] == "yes" else "Free"
            states = p["states"].replace(",", ", ")
            name = f"[{p['name']}]({p['url']})"
            lines.append(f"| {states} | {name} | {p['designation']} | {fee} | {acts} |")

    usfs_path = DATA / "usfs_recreation_sites.csv"
    if usfs_path.exists():
        forests = sorted({r["forestname"] for r in csv.DictReader(usfs_path.open()) if r["forestname"]})
        lines += [
            "",
            "## National Forests and Grasslands in the USFS recreation data",
            "",
            f"**{len(forests)}** units appear in the Recreation Opportunities layer:",
            "",
        ]
        for f in forests:
            lines.append(f"- {f}")

    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT} ({len(parks)} parks, {len(designations)} designations)")


if __name__ == "__main__":
    main()
