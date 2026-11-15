#!/usr/bin/env python3
"""
Normalize the US OpenStreetMap campsite extract into a flat CSV.

Input : data/osm_camp_sites_raw.json  (Overpass `out center tags`)
Output: data/osm_camp_sites.csv

License: ODbL 1.0. Attribution to OpenStreetMap contributors required;
derived databases are share-alike. Keep this file isolated from proprietary
data if you redistribute derived databases.
"""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def yesno(value: str | None) -> str:
    if value is None:
        return ""
    v = str(value).strip().lower()
    if v in {"yes", "true", "1"}:
        return "yes"
    if v in {"no", "false", "0"}:
        return "no"
    return v


def main() -> None:
    raw = json.loads((DATA / "osm_camp_sites_raw.json").read_text())
    els = raw.get("elements", [])
    print(f"elements={len(els)}")

    rows = []
    for e in els:
        t = e.get("tags", {})
        lat = e.get("lat") or (e.get("center") or {}).get("lat")
        lon = e.get("lon") or (e.get("center") or {}).get("lon")
        if lat is None or lon is None:
            continue
        osm_type = e.get("type", "")
        osm_id = e.get("id")
        fee_raw = t.get("fee", "")
        fv = fee_raw.strip().lower()
        if fv in {"no", "free", "0"}:
            fee = "free"
        elif fv in {"yes", "true", "1"}:
            fee = "fee"
        elif fv == "donation":
            fee = "donation"
        elif fv:
            fee = "fee"
        elif t.get("charge"):
            fee = "fee"
        else:
            fee = "unknown"
        rows.append({
            "source": "osm",
            "osm_type": osm_type,
            "osm_id": osm_id,
            "name": t.get("name", ""),
            "camp_site": t.get("camp_site", ""),
            "tourism": t.get("tourism", "camp_site"),
            "fee": fee,
            "fee_raw": fee_raw,
            "charge": t.get("charge", ""),
            "access": t.get("access", ""),
            "capacity": t.get("capacity", ""),
            "max_stay": t.get("maxstay", ""),
            "opening_hours": t.get("opening_hours", ""),
            "seasonal": t.get("seasonal", ""),
            "operator": t.get("operator", ""),
            "latitude": lat,
            "longitude": lon,
            "toilets": yesno(t.get("toilets")),
            "drinking_water": yesno(t.get("drinking_water")),
            "shower": yesno(t.get("shower")),
            "power_supply": yesno(t.get("power_supply")),
            "dump_station": yesno(t.get("sanitary_dump_station")),
            "picnic_table": yesno(t.get("picnic_table")),
            "fire_pit": yesno(t.get("fire_pit") or t.get("fireplace")),
            "wheelchair": t.get("wheelchair", ""),
            "pets": t.get("dog", ""),
            "website": t.get("website", "") or t.get("contact:website", ""),
            "phone": t.get("phone", "") or t.get("contact:phone", ""),
            "description": (t.get("description", "") or "")[:1000],
            "osm_url": f"https://www.openstreetmap.org/{osm_type}/{osm_id}",
        })

    out = DATA / "osm_camp_sites.csv"
    with out.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print(f"wrote {len(rows)} -> {out}")
    print("by type:", Counter(r["osm_type"] for r in rows))
    print("fee:", Counter(r["fee"] or "unknown" for r in rows).most_common())
    print("camp_site:", Counter(r["camp_site"] or "untagged" for r in rows).most_common(10))
    print("with name:", sum(1 for r in rows if r["name"]), "with water:", sum(1 for r in rows if r["drinking_water"] == "yes"))


if __name__ == "__main__":
    main()
