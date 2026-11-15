#!/usr/bin/env python3
"""
Collect USFS Recreation Opportunities (EDW) as a nationwide CSV.

Service: https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RecreationOpportunities_01/MapServer/0
License: USDA Forest Service data, public domain / CC BY 4.0 per data.gov listing.
Updated nightly by the Forest Service.

Usage: python3 scripts/collect_usfs.py
"""

from __future__ import annotations

import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

SERVICE = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RecreationOpportunities_01/MapServer/0/query"
OUT_DIR = Path(__file__).resolve().parent.parent / "data"
PARTIAL = OUT_DIR / "usfs_recreation_sites.partial.jsonl"
FIELDS = [
    "recareaid", "recareaname", "markeractivity", "markeractivitygroup", "forestname",
    "latitude", "longitude", "open_season_start", "open_season_end", "openstatus",
    "feedescription", "reservation_info", "restrictions", "accessibility",
    "operational_hours", "recareaurl", "recareadescription",
]


def get(params: dict) -> dict:
    url = f"{SERVICE}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "CampSitesUSA-research/0.1"})
    for attempt in range(7):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except Exception as exc:  # noqa: BLE001
            if attempt == 6:
                raise
            print(f"  retry {attempt + 1}: {exc}")
            time.sleep(min(30, 3 * (attempt + 1)))
    raise RuntimeError("unreachable")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    count = get({"where": "1=1", "returnCountOnly": "true", "f": "json"})["count"]
    print(f"total={count}")

    # Resume support: the EDW service resets long connections, so persist each
    # page and pick up where we left off.
    rows: list[dict] = []
    if PARTIAL.exists():
        for line in PARTIAL.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    offset = len(rows)
    page = 500
    print(f"resuming at {offset}")
    while offset < count:
        batch = get({
            "where": "1=1",
            "outFields": ",".join(FIELDS),
            "returnGeometry": "false",
            "orderByFields": "objectid",
            "resultOffset": offset,
            "resultRecordCount": page,
            "f": "json",
        })
        feats = batch.get("features", [])
        if not feats:
            break
        with PARTIAL.open("a") as fh:
            for f in feats:
                fh.write(json.dumps(f["attributes"]) + "\n")
        rows.extend(f["attributes"] for f in feats)
        offset += len(feats)
        print(f"  {offset}/{count}")
        time.sleep(1.0)

    with (OUT_DIR / "usfs_recreation_sites.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} rows")


if __name__ == "__main__":
    main()
