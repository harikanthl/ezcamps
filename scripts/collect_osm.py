#!/usr/bin/env python3
"""
Collect US OpenStreetMap camping layers via Overpass.

Outputs:
  data/osm_camp_sites_raw.json     23,843 tourism=camp_site nodes
  data/osm_dump_stations_raw.json  1,697 dump stations (nodes + ways)
  data/osm_rest_areas_raw.json     2,477 rest areas (nodes + ways)

The campsite pull is nodes-only. Ways/relations are counted but not pulled in
one request because a combined query is too large for the public endpoint.
Split by state if you need polygon campsites.

Usage: python3 scripts/collect_osm.py
"""

from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

ENDPOINT = "https://overpass-api.de/api/interpreter"
DATA = Path(__file__).resolve().parent.parent / "data"
UA = "CampSitesUSA-research/0.1 (catalog build)"

QUERIES = {
    "osm_camp_sites_raw.json": (
        '[out:json][timeout:800];'
        'area["ISO3166-1"="US"][admin_level=2]->.a;'
        'node["tourism"="camp_site"](area.a);'
        'out body;'
    ),
    "osm_dump_stations_raw.json": (
        '[out:json][timeout:240];'
        'area["ISO3166-1"="US"][admin_level=2]->.a;'
        '(node["amenity"="sanitary_dump_station"](area.a);'
        'way["amenity"="sanitary_dump_station"](area.a););'
        'out center tags;'
    ),
    "osm_rest_areas_raw.json": (
        '[out:json][timeout:240];'
        'area["ISO3166-1"="US"][admin_level=2]->.a;'
        '(node["highway"="rest_area"](area.a);'
        'way["highway"="rest_area"](area.a););'
        'out center tags;'
    ),
}


def fetch(query: str) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={"User-Agent": UA, "Accept": "application/json"},
    )
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                return json.load(r)
        except Exception as exc:  # noqa: BLE001
            wait = min(60, 5 * (attempt + 1))
            print(f"  retry {attempt + 1} in {wait}s: {exc}")
            time.sleep(wait)
    raise RuntimeError("Overpass failed after retries")


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    for i, (filename, query) in enumerate(QUERIES.items()):
        if i:
            time.sleep(8)  # be polite; concurrent requests get 429
        print(f"fetching {filename} ...")
        payload = fetch(query)
        elements = payload.get("elements", [])
        (DATA / filename).write_text(json.dumps(payload))
        print(f"  {len(elements)} elements -> data/{filename}")


if __name__ == "__main__":
    main()
