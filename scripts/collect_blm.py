#!/usr/bin/env python3
"""
Collect BLM national recreation camping points (RIDB-derived).

Service: https://gis.blm.gov/natl/rest/services/recreation/BLM_Natl_Recreation_Sites_Facilities/MapServer
Layer 2 = BLM Natl RIDB Recreation Camping (539 points as of 2026-11)
Fields include stay limit, fees, reservation URL, directions and activities.

Usage: python3 scripts/collect_blm.py
"""

from __future__ import annotations

import csv
import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

LAYER = 2
SERVICE = (
    "https://gis.blm.gov/natl/rest/services/recreation/"
    f"BLM_Natl_Recreation_Sites_Facilities/MapServer/{LAYER}/query"
)
OUT_DIR = Path(__file__).resolve().parent.parent / "data"
FIELDS = [
    "RecAreaID", "RecAreaName", "State", "RecAreaLatitude", "RecAreaLongitude",
    "StayLimit", "RecAreaFeeDescription", "Keywords", "ActivityNames",
    "RecAreaReservationURL", "BLMRecURL", "RecAreaMapURL", "RecAreaPhone",
    "RecAreaEmail", "RecAreaDescription", "RecAreaDirections", "LastUpdatedDate",
]


def strip_html(value: str | None) -> str:
    if not value:
        return ""
    text = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def get(params: dict) -> dict:
    req = urllib.request.Request(
        f"{SERVICE}?{urllib.parse.urlencode(params)}",
        headers={"User-Agent": "CampSitesUSA-research/0.1"},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as exc:  # noqa: BLE001
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    count = get({"where": "1=1", "returnCountOnly": "true", "f": "json"})["count"]
    print(f"total={count}")
    rows: list[dict] = []
    offset = 0
    while offset < count:
        batch = get({
            "where": "1=1",
            "outFields": ",".join(FIELDS),
            "returnGeometry": "false",
            "orderByFields": "OBJECTID",
            "resultOffset": offset,
            "resultRecordCount": 500,
            "f": "json",
        })
        feats = batch.get("features", [])
        if not feats:
            break
        for f in feats:
            a = f["attributes"]
            rows.append({
                "source": "blm",
                "source_id": a.get("RecAreaID"),
                "name": a.get("RecAreaName"),
                "state": a.get("State"),
                "latitude": a.get("RecAreaLatitude"),
                "longitude": a.get("RecAreaLongitude"),
                "stay_limit": html.unescape(strip_html(a.get("StayLimit"))),
                "fee_description": strip_html(a.get("RecAreaFeeDescription")),
                "activities": a.get("ActivityNames") or "",
                "keywords": a.get("Keywords") or "",
                "reservation_url": a.get("RecAreaReservationURL") or "",
                "blm_url": a.get("BLMRecURL") or "",
                "map_url": a.get("RecAreaMapURL") or "",
                "phone": a.get("RecAreaPhone") or "",
                "email": a.get("RecAreaEmail") or "",
                "description": strip_html(a.get("RecAreaDescription")),
                "directions": strip_html(a.get("RecAreaDirections")),
                "last_updated": a.get("LastUpdatedDate"),
            })
        offset += len(feats)
        print(f"  {offset}/{count}")
        time.sleep(0.2)

    out = OUT_DIR / "blm_camping.csv"
    with out.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} rows -> {out}")


if __name__ == "__main__":
    main()
