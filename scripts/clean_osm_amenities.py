#!/usr/bin/env python3
"""
Normalize OSM dump stations and rest areas.

Inputs : data/osm_dump_stations_raw.json, data/osm_rest_areas_raw.json
Outputs: data/osm_dump_stations.csv, data/osm_rest_areas.csv

License: ODbL 1.0 — attribute OpenStreetMap contributors.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def yes(value) -> str:
    if value is None:
        return ""
    v = str(value).strip().lower()
    if v in {"yes", "true", "1"}:
        return "yes"
    if v in {"no", "false", "0"}:
        return "no"
    return v


def coords(e: dict):
    return e.get("lat") or (e.get("center") or {}).get("lat"), e.get("lon") or (e.get("center") or {}).get("lon")


def write(name: str, rows: list[dict]) -> None:
    if not rows:
        print(f"skip {name}: no rows")
        return
    with (DATA / name).open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} -> data/{name}")


def main() -> None:
    dump = json.loads((DATA / "osm_dump_stations_raw.json").read_text()).get("elements", [])
    rows = []
    for e in dump:
        t = e.get("tags", {})
        lat, lon = coords(e)
        if lat is None:
            continue
        rows.append({
            "source": "osm",
            "osm_type": e.get("type"),
            "osm_id": e.get("id"),
            "name": t.get("name", ""),
            "fee": yes(t.get("fee")),
            "charge": t.get("charge", ""),
            "access": t.get("access", ""),
            "opening_hours": t.get("opening_hours", ""),
            "operator": t.get("operator", ""),
            "drinking_water": yes(t.get("drinking_water")),
            "toilets": yes(t.get("toilets")),
            "website": t.get("website", "") or t.get("contact:website", ""),
            "phone": t.get("phone", "") or t.get("contact:phone", ""),
            "description": (t.get("description", "") or "")[:500],
            "latitude": lat,
            "longitude": lon,
            "osm_url": f"https://www.openstreetmap.org/{e.get('type')}/{e.get('id')}",
        })
    write("osm_dump_stations.csv", rows)

    rest = json.loads((DATA / "osm_rest_areas_raw.json").read_text()).get("elements", [])
    rows = []
    for e in rest:
        t = e.get("tags", {})
        lat, lon = coords(e)
        if lat is None:
            continue
        rows.append({
            "source": "osm",
            "osm_type": e.get("type"),
            "osm_id": e.get("id"),
            "name": t.get("name", ""),
            "highway": t.get("highway", ""),
            "direction": t.get("direction", ""),
            "toilets": yes(t.get("toilets")),
            "drinking_water": yes(t.get("drinking_water")),
            "fee": yes(t.get("fee")),
            "opening_hours": t.get("opening_hours", ""),
            "operator": t.get("operator", ""),
            "truck_parking": yes(t.get("hgv") or t.get("truck_parking")),
            "caravan": yes(t.get("caravan")),
            "motorhome": yes(t.get("motorhome")),
            "max_stay": t.get("maxstay", ""),
            "latitude": lat,
            "longitude": lon,
            "osm_url": f"https://www.openstreetmap.org/{e.get('type')}/{e.get('id')}",
        })
    write("osm_rest_areas.csv", rows)


if __name__ == "__main__":
    main()
