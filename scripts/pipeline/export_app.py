#!/usr/bin/env python3
"""
Export the canonical `campsites` table from data/campsites.db into the app bundle
(CampSitesUSA/Resources/sites.json), in the shape the Swift `Site` model decodes.

Usage:
  python3 scripts/build_db.py                 # rebuild the database first
  python3 -I scripts/pipeline/export_app.py   # all states
  python3 -I scripts/pipeline/export_app.py --states UT AZ
Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "data" / "campsites.db"
OUT = ROOT / "CampSitesUSA" / "Resources" / "sites.json"
ACTIVITIES_OUT = ROOT / "CampSitesUSA" / "Resources" / "activities.json"
STATES_OUT = ROOT / "CampSitesUSA" / "Resources" / "state_bounds.json"
BOUNDARIES = ROOT / "data" / "boundaries" / "us_states.json"
STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
    "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
    "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "PR": "Puerto Rico", "RI": "Rhode Island", "SC": "South Carolina",
    "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
    "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
}


def export_state_bounds() -> int:
    """Bounding boxes for offline tile packs (western-hemisphere rings only, so Alaska's
    Aleutians past the antimeridian don't stretch its box around the globe)."""
    states = json.loads(BOUNDARIES.read_text())["states"]
    out = []
    for code, rings in sorted(states.items()):
        pts = [p for r in rings for p in r if p[0] < 0]
        out.append({"code": code, "name": STATE_NAMES.get(code, code),
                    "minLat": round(min(p[1] for p in pts), 4), "maxLat": round(max(p[1] for p in pts), 4),
                    "minLon": round(min(p[0] for p in pts), 4), "maxLon": round(max(p[0] for p in pts), 4)})
    STATES_OUT.write_text(json.dumps(out, separators=(",", ":")))
    return len(out)
DESCRIPTION_CHARS = 320  # the sheet shows a short blurb; full text stays in the database

ATTRIBUTION = ("© OpenStreetMap contributors (ODbL); USDA Forest Service (CC BY 4.0); "
               "National Park Service, Recreation.gov and BLM data (public domain)")


def short(text: str | None) -> str | None:
    if not text or len(text) <= DESCRIPTION_CHARS:
        return text
    cut = text[:DESCRIPTION_CHARS].rsplit(" ", 1)[0]
    return cut.rstrip(",.;:") + "…"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--states", nargs="*", help="2-letter state codes (default: all)")
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    sql = "SELECT * FROM campsites"
    params: list[str] = []
    if args.states:
        sql += f" WHERE state IN ({','.join('?' for _ in args.states)})"
        params = [s.upper() for s in args.states]
    sites = []
    for r in conn.execute(sql + " ORDER BY id", params):
        sites.append({
            "id": r["id"], "name": r["name"], "lat": r["lat"], "lon": r["lon"],
            "state": r["state"], "source": r["source"], "kind": r["kind"],
            "free": None if r["free"] is None else bool(r["free"]), "fee": r["fee"],
            "reservable": bool(r["reservable"]), "agency": r["agency"], "url": r["url"],
            "phone": r["phone"], "description": short(r["description"]),
            "amenities": json.loads(r["amenities"]), "maxVehicleLength": r["max_rig_ft"],
            "openingHours": r["opening_hours"], "stayLimit": r["stay_limit"],
            "cell": r["cell"],
        })
    activities = []
    for r in conn.execute("SELECT * FROM activities ORDER BY id"):
        activities.append({k: v for k, v in {
            "id": r["id"], "name": r["name"], "type": r["type"], "difficulty": r["difficulty"],
            "basis": r["difficulty_basis"], "lat": round(r["lat"], 5), "lon": round(r["lon"], 5),
            "miles": r["miles"], "duration": r["duration"], "uses": r["uses"], "place": r["place"],
            "url": r["url"], "description": short(r["description"]), "source": r["source"],
        }.items() if v is not None})
    conn.close()
    ACTIVITIES_OUT.write_text(json.dumps({"generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                                          "activities": activities}, separators=(",", ":"), ensure_ascii=False))
    print(f"wrote {len(activities)} activities -> {ACTIVITIES_OUT} ({ACTIVITIES_OUT.stat().st_size / 1048576:.1f} MB)")
    # Drop nulls to keep the bundle small; Swift decodes missing optionals as nil.
    sites = [{k: v for k, v in s.items() if v is not None} for s in sites]
    payload = {
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "attribution": ATTRIBUTION,
        "sites": sites,
    }
    args.out.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    print(f"wrote {len(sites)} sites -> {args.out} ({args.out.stat().st_size / 1048576:.1f} MB)")
    print(f"wrote {export_state_bounds()} state bounds -> {STATES_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
