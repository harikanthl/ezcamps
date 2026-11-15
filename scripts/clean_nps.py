#!/usr/bin/env python3
"""
Normalize the NPS API payloads into CSV for the catalog/database.

Input : data/nps_parks_raw.json, data/nps_campgrounds_raw.json
Output: data/nps_parks.csv, data/nps_campgrounds.csv

The raw files are fetched with the public NPS Data API (developer.nps.gov).
DEMO_KEY is rate-limited; get a free key for production refreshes.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def boolish(value) -> str:
    if value is None:
        return "unknown"
    if isinstance(value, list):
        return "yes" if value else "unknown"
    if isinstance(value, str):
        text = value.strip().lower()
        if not text:
            return "unknown"
        if text in {"yes", "true", "1"}:
            return "yes"
        if text in {"no", "false", "0"}:
            return "no"
        return "unknown"
    return "yes" if value else "no"


def activities(items) -> str:
    return ";".join(a.get("name", "") for a in (items or []))


def topics(items) -> str:
    return ";".join(t.get("name", "") for t in (items or []))


def fees(items) -> tuple[str, str, str]:
    if not items:
        return "", "", ""
    return (
        items[0].get("cost", ""),
        items[0].get("description", ""),
        items[0].get("title", ""),
    )


def main() -> None:
    parks = json.loads((DATA / "nps_parks_raw.json").read_text())["data"]
    camps = json.loads((DATA / "nps_campgrounds_raw.json").read_text())["data"]

    park_rows = []
    for p in parks:
        cost, fee_desc, fee_title = fees(p.get("entranceFees"))
        park_rows.append({
            "source": "nps",
            "park_code": p.get("parkCode"),
            "name": p.get("fullName"),
            "designation": p.get("designation"),
            "states": p.get("states"),
            "latitude": p.get("latitude"),
            "longitude": p.get("longitude"),
            "url": p.get("url"),
            "description": (p.get("description") or "").strip(),
            "directions": (p.get("directionsInfo") or "").strip(),
            "weather": (p.get("weatherInfo") or "").strip(),
            "activities": activities(p.get("activities")),
            "topics": topics(p.get("topics")),
            "entrance_fee_cost": cost,
            "entrance_fee_title": fee_title,
            "entrance_fee_description": fee_desc,
            "has_entrance_fee": "yes" if cost not in ("", "0", "0.00") else "no",
        })

    camp_rows = []
    for c in camps:
        campsites = c.get("campsites") or {}
        amenities = c.get("amenities") or {}
        access = c.get("accessibility") or {}
        camp_rows.append({
            "source": "nps",
            "id": c.get("id"),
            "park_code": c.get("parkCode"),
            "name": c.get("name"),
            "latitude": c.get("latitude"),
            "longitude": c.get("longitude"),
            "url": c.get("url"),
            "description": (c.get("description") or "").strip(),
            "total_sites": campsites.get("totalSites"),
            "tent_only_sites": campsites.get("tentOnly"),
            "rv_only_sites": campsites.get("rvOnly"),
            "group_sites": campsites.get("group"),
            "horse_sites": campsites.get("horse"),
            "electrical_hookups": campsites.get("electricalHookups"),
            "walk_boat_sites": campsites.get("walkBoatTo"),
            "other_sites": campsites.get("other"),
            "reservable_sites": c.get("numberOfSitesReservable"),
            "first_come_first_serve_sites": c.get("numberOfSitesFirstComeFirstServe"),
            "reservation_url": c.get("reservationUrl"),
            "reservation_info": (c.get("reservationInfo") or "").strip(),
            "toilets": boolish(amenities.get("toilets")),
            "potable_water": boolish(amenities.get("potableWater")),
            "showers": boolish(amenities.get("showers")),
            "dump_station": boolish(amenities.get("dumpStation")),
            "camp_store": boolish(amenities.get("campStore")),
            "firewood_for_sale": boolish(amenities.get("firewoodForSale")),
            "ice_for_sale": boolish(amenities.get("iceAvailableForSale")),
            "laundry": boolish(amenities.get("laundry")),
            "cell_reception": amenities.get("cellPhoneReception") or "",
            "wheelchair_access": access.get("wheelchairAccess") or "",
            "rv_allowed": access.get("rvAllowed") or "",
            "rv_max_length_ft": access.get("rvMaxLength") or "",
            "trailer_allowed": access.get("trailerAllowed") or "",
            "trailer_max_length_ft": access.get("trailerMaxLength") or "",
            "access_roads": ";".join(access.get("accessRoads") or []),
            "regulations": (c.get("regulationsOverview") or "").strip(),
        })

    for name, rows in (("nps_parks.csv", park_rows), ("nps_campgrounds.csv", camp_rows)):
        with (DATA / name).open("w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {len(rows)} rows -> data/{name}")


if __name__ == "__main__":
    main()
