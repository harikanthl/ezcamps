#!/usr/bin/env python3
"""
Collect NPS API layers: alerts, things to do, visitor centers, webcams.

Requires an NPS API key. Set it in the environment; do not hard-code it:

    export NPS_API_KEY=...
    python3 scripts/collect_nps.py

`DEMO_KEY` works for a smoke test but is rate-limited.

Outputs:
  data/nps_alerts.csv
  data/nps_things_to_do.csv
  data/nps_visitor_centers.csv
  data/nps_webcams.csv
"""

from __future__ import annotations

import csv
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://developer.nps.gov/api/v1"
DATA = Path(__file__).resolve().parent.parent / "data"
KEY = os.environ.get("NPS_API_KEY", "DEMO_KEY")
PAGE = 500


def fetch(path: str, params: dict) -> dict:
    # Key in a header, not the query string, so it never shows up in URLs, logs or tracebacks.
    url = f"{BASE}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "CampSitesUSA-research/0.1", "X-Api-Key": KEY})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as exc:  # noqa: BLE001
            if attempt == 4:
                raise
            print(f"  retry {attempt + 1} {path}: {exc}")
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def fetch_all(path: str) -> list[dict]:
    first = fetch(path, {"limit": PAGE, "start": 0})
    total = int(first.get("total", 0))
    rows = list(first.get("data", []))
    print(f"{path}: total={total}")
    start = len(rows)
    while start < total:
        batch = fetch(path, {"limit": PAGE, "start": start}).get("data", [])
        if not batch:
            break
        rows.extend(batch)
        start += len(batch)
        print(f"  {start}/{total}")
        time.sleep(0.25)
    return rows


def clean(value) -> str:
    if value is None:
        return ""
    text = re.sub(r"<[^>]+>", " ", str(value))
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def names(values) -> str:
    return ";".join(v.get("name", "") for v in (values or []) if isinstance(v, dict))


def park_codes(values) -> str:
    return ";".join(v.get("parkCode", "") for v in (values or []) if isinstance(v, dict))


def write_csv(name: str, rows: list[dict]) -> None:
    if not rows:
        print(f"skip {name}: no rows")
        return
    with (DATA / name).open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} -> data/{name}")


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)

    alerts = fetch_all("alerts")
    write_csv("nps_alerts.csv", [{
        "source": "nps",
        "id": a.get("id"),
        "park_code": a.get("parkCode"),
        "category": a.get("category"),
        "title": a.get("title"),
        "description": clean(a.get("description")),
        "url": a.get("url"),
        "last_indexed": a.get("lastIndexedDate"),
    } for a in alerts])

    todos = fetch_all("thingstodo")
    write_csv("nps_things_to_do.csv", [{
        "source": "nps",
        "id": t.get("id"),
        "park_codes": park_codes(t.get("relatedParks")),
        "title": t.get("title"),
        "activities": names(t.get("activities")),
        "topics": names(t.get("topics")),
        "duration": t.get("duration") or t.get("durationDescription"),
        "season": t.get("season") or t.get("seasonDescription"),
        "time_of_day": t.get("timeOfDay") or t.get("timeOfDayDescription"),
        "fees_apply": t.get("doFeesApply"),
        "fee_description": clean(t.get("feeDescription")),
        "reservation_required": t.get("isReservationRequired"),
        "pets_permitted": t.get("arePetsPermitted"),
        "accessibility": clean(t.get("accessibilityInformation")),
        "latitude": t.get("latitude"),
        "longitude": t.get("longitude"),
        "short_description": clean(t.get("shortDescription")),
        "url": t.get("url"),
    } for t in todos])

    centers = fetch_all("visitorcenters")
    write_csv("nps_visitor_centers.csv", [{
        "source": "nps",
        "id": v.get("id"),
        "park_code": v.get("parkCode"),
        "name": v.get("name"),
        "latitude": v.get("latitude"),
        "longitude": v.get("longitude"),
        "description": clean(v.get("description")),
        "directions": clean(v.get("directionsInfo")),
        "url": v.get("url"),
        "passport_stamp": v.get("isPassportStampLocation"),
    } for v in centers])

    cams = fetch_all("webcams")
    write_csv("nps_webcams.csv", [{
        "source": "nps",
        "id": c.get("id"),
        "park_code": c.get("parkCode"),
        "title": c.get("title"),
        "status": c.get("status"),
        "latitude": c.get("latitude"),
        "longitude": c.get("longitude"),
        "description": clean(c.get("description")),
        "url": c.get("url"),
    } for c in cams])


if __name__ == "__main__":
    main()
