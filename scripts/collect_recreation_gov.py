#!/usr/bin/env python3
"""
Collect camping-related listings from Recreation.gov's public search endpoint.

The endpoint is the same one the recreation.gov website uses. It is NOT a
documented/supported API (RIDB is the supported one), so treat this as a
snapshot: be polite, cache the output, and do not hammer availability
endpoints. Listing data is public information about federal recreation sites.

Output:
  data/recreation_gov_camping.jsonl   one normalized record per line
  data/recreation_gov_camping.csv     flat subset for spreadsheets/SQLite

Usage: python3 scripts/collect_recreation_gov.py
"""

from __future__ import annotations

import csv
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://www.recreation.gov/api/search"
QUERY = "camping"
PAGE_SIZE = 500
OUT_DIR = Path(__file__).resolve().parent.parent / "data"
UA = "CampSitesUSA-research/0.1 (catalog build; contact: local)"


def fetch_page(start: int) -> dict:
    params = urllib.parse.urlencode({"q": QUERY, "size": PAGE_SIZE, "start": start})
    req = urllib.request.Request(f"{BASE}?{params}", headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as exc:  # noqa: BLE001
            if attempt == 3:
                raise
            print(f"  retry {attempt + 1} at start={start}: {exc}")
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def names(values) -> str:
    if not values:
        return ""
    out: list[str] = []
    seen: set[str] = set()
    for v in values:
        name = (v.get("activity_name", "") if isinstance(v, dict) else str(v)).strip()
        key = name.lower()
        if name and key not in seen:
            seen.add(key)
            out.append(name)
    return ";".join(out)


def normalize(r: dict) -> dict:
    addr = (r.get("addresses") or [{}])[0]
    price = r.get("price_range") or {}
    links = r.get("links") or []
    official = r.get("official_site_url") or next(
        (l.get("url") for l in links if l.get("link_type") == "Official"), ""
    )
    return {
        "source": "recreation.gov",
        "source_id": r.get("entity_id") or r.get("id"),
        "entity_type": r.get("entity_type"),
        "name": r.get("name"),
        "parent_name": r.get("parent_name"),
        "parent_type": r.get("parent_type"),
        "agency": r.get("org_name"),
        "agency_id": r.get("org_id"),
        "state": r.get("state_code"),
        "city": r.get("city") or addr.get("city"),
        "postal_code": addr.get("postal_code"),
        "latitude": r.get("latitude"),
        "longitude": r.get("longitude"),
        "description": (r.get("description") or "").strip(),
        "official_url": official,
        "image_url": r.get("preview_image_url"),
        "reservable": r.get("reservable"),
        "has_lottery": r.get("has_lottery"),
        "price_min": price.get("amount_min"),
        "price_max": price.get("amount_max"),
        "price_unit": price.get("per_unit"),
        "campsites_count": r.get("campsites_count"),
        "accessible_campsites_count": r.get("accessible_campsites_count"),
        "max_vehicle_length_ft": r.get("campsite_max_vehicle_length"),
        "equipment_allowed": names(r.get("campsite_equipment_name")),
        "site_types": names(r.get("campsite_type_of_use")),
        "reserve_types": names(r.get("campsite_reserve_type")),
        "activities": names(r.get("activities")),
        "average_rating": r.get("average_rating"),
        "rating_count": r.get("number_of_ratings"),
        "cell_coverage_score": r.get("aggregate_cell_coverage"),
        "time_zone": r.get("time_zone"),
        "notices": " | ".join(
            n.get("notice_text") or n.get("title") or "" for n in (r.get("notices") or [])
        ).strip(" |"),
    }


CSV_FIELDS = [
    "source_id", "entity_type", "name", "parent_name", "agency", "state", "city",
    "latitude", "longitude", "reservable", "price_min", "price_max", "price_unit",
    "campsites_count", "accessible_campsites_count", "max_vehicle_length_ft",
    "equipment_allowed", "site_types", "reserve_types", "activities",
    "average_rating", "rating_count", "cell_coverage_score", "official_url",
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    first = fetch_page(0)
    total = int(first["total"])
    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    print(f"total={total} pages={pages}")

    records: dict[str, dict] = {}
    batch = first
    for page in range(pages):
        if page:
            batch = fetch_page(page * PAGE_SIZE)
            time.sleep(0.35)
        for raw in batch.get("results", []):
            rec = normalize(raw)
            if rec["source_id"]:
                records[str(rec["source_id"])] = rec
        print(f"  page {page + 1}/{pages} -> {len(records)} unique")

    rows = sorted(records.values(), key=lambda r: (r["state"] or "", r["name"] or ""))
    with (OUT_DIR / "recreation_gov_camping.jsonl").open("w") as fh:
        for rec in rows:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    with (OUT_DIR / "recreation_gov_camping.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_FIELDS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} records")


if __name__ == "__main__":
    main()
