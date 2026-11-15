#!/usr/bin/env python3
"""Build the bundled campsite dataset for the app.

Pulls campsites from open sources, normalizes them to one schema, and writes
CampSitesUSA/Resources/sites.json.

Sources:
  - OpenStreetMap via Overpass (no key)      -> always on
  - NPS Data API      (env NPS_API_KEY)      -> skipped if key missing
  - RIDB/Recreation.gov (env RIDB_API_KEY)   -> skipped if key missing

Usage:
  python3 scripts/pipeline/build_sites.py --states UT AZ
  NPS_API_KEY=... RIDB_API_KEY=... python3 scripts/pipeline/build_sites.py --states UT

Only the Python standard library is used, so there is nothing to install.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "CampSitesUSA" / "Resources" / "sites.json"
UA = "CampSitesUSA-data-pipeline/0.1"
OVERPASS_MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]


def http_json(url: str, *, data: bytes | None = None, headers: dict | None = None, retries: int = 3):
    h = {"User-Agent": UA, "Accept": "application/json", **(headers or {})}
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=h)
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - network flakiness, retry
            if attempt == retries - 1:
                raise
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s after: {e}", file=sys.stderr)
            time.sleep(wait)


# ---------------------------------------------------------------- OSM
OSM_AMENITY_TAGS = {
    "toilets": "toilets",
    "drinking_water": "water",
    "shower": "showers",
    "power_supply": "electric",
    "sanitary_dump_station": "dump",
    "fireplace": "fire_ring",
    "picnic_table": "picnic_table",
    "internet_access": "wifi",
}


def osm_sites(state: str) -> list[dict]:
    q = f"""
    [out:json][timeout:170];
    area["ISO3166-2"="US-{state}"][admin_level=4]->.s;
    (
      nwr["tourism"="camp_site"](area.s);
      nwr["tourism"="caravan_site"](area.s);
    );
    out center tags;
    """
    body = urllib.parse.urlencode({"data": q}).encode()
    data, last = None, None
    for mirror in OVERPASS_MIRRORS:
        try:
            data = http_json(mirror, data=body, retries=2)
            break
        except Exception as e:  # noqa: BLE001 - try next mirror
            last = e
            print(f"  {mirror} failed: {e}", file=sys.stderr)
    if data is None:
        raise RuntimeError(f"all Overpass mirrors failed: {last}")
    out = []
    for el in data.get("elements", []):
        t = el.get("tags", {})
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if lat is None or lon is None:
            continue
        fee = t.get("fee")
        free = True if fee == "no" else False if fee in ("yes",) or (fee and fee[0].isdigit()) else None
        basic = t.get("camp_site") in ("basic", "dispersed") or t.get("backcountry") == "yes"
        kind = "rv_park" if t.get("tourism") == "caravan_site" else ("dispersed" if basic else "campground")
        amenities = sorted({v for k, v in OSM_AMENITY_TAGS.items() if t.get(k) not in (None, "no")})
        if t.get("tents") == "yes":
            amenities.append("tents")
        if t.get("caravans") == "yes" or t.get("motorhome") == "yes":
            amenities.append("rv")
        out.append({
            "id": f"osm:{el['type'][0]}{el['id']}",
            "name": t.get("name") or ("Dispersed site" if kind == "dispersed" else "Unnamed campsite"),
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "state": state,
            "source": "osm",
            "kind": kind,
            "free": free,
            "fee": fee if fee not in ("yes", "no") else None,
            "reservable": t.get("reservation") in ("required", "yes", "recommended"),
            "agency": t.get("operator"),
            "url": t.get("website") or t.get("contact:website"),
            "phone": t.get("phone") or t.get("contact:phone"),
            "description": t.get("description"),
            "amenities": sorted(set(amenities)),
            "maxVehicleLength": None,
            "openingHours": t.get("opening_hours"),
        })
    return out


# ---------------------------------------------------------------- NPS
def nps_sites(state: str, key: str) -> list[dict]:
    url = f"https://developer.nps.gov/api/v1/campgrounds?stateCode={state}&limit=500"
    data = http_json(url, headers={"X-Api-Key": key})
    out = []
    for c in data.get("data", []):
        try:
            lat, lon = float(c["latitude"]), float(c["longitude"])
        except (KeyError, ValueError, TypeError):
            continue
        fees = c.get("fees") or []
        cost = [float(f["cost"]) for f in fees if str(f.get("cost", "")).replace(".", "", 1).isdigit()]
        am = c.get("amenities") or {}
        amenities = []
        if any("Flush" in s or "Vault" in s or "Portable" in s for s in am.get("toilets", [])):
            amenities.append("toilets")
        if any("Yes" in s for s in am.get("potableWater", [])):
            amenities.append("water")
        if any("Yes" in s for s in am.get("showers", [])):
            amenities.append("showers")
        if any("Yes" in s for s in am.get("dumpStation", [])) or am.get("dumpStation") == "Yes":
            amenities.append("dump")
        acc = c.get("accessibility") or {}
        rv_len = acc.get("rvMaxLength")
        out.append({
            "id": f"nps:{c['id']}",
            "name": c.get("name"),
            "lat": round(lat, 6), "lon": round(lon, 6), "state": state,
            "source": "nps", "kind": "campground",
            "free": (max(cost) == 0) if cost else None,
            "fee": f"${min(cost):.0f}+" if cost and max(cost) > 0 else None,
            "reservable": bool(c.get("reservationUrl")),
            "agency": f"NPS · {c.get('parkCode', '').upper()}",
            "url": c.get("reservationUrl") or c.get("url"),
            "phone": None,
            "description": c.get("description"),
            "amenities": sorted(set(amenities)),
            "maxVehicleLength": float(rv_len) if str(rv_len or "").replace(".", "", 1).isdigit() and float(rv_len) > 0 else None,
            "openingHours": None,
        })
    return out


# ---------------------------------------------------------------- RIDB
def ridb_sites(state: str, key: str) -> list[dict]:
    out, offset = [], 0
    while True:
        url = f"https://ridb.recreation.gov/api/v1/facilities?state={state}&limit=50&offset={offset}&full=true"
        data = http_json(url, headers={"apikey": key})
        recs = data.get("RECDATA", [])
        for f in recs:
            if "camp" not in (f.get("FacilityTypeDescription") or "").lower():
                continue
            lat, lon = f.get("FacilityLatitude"), f.get("FacilityLongitude")
            if not lat or not lon:
                continue
            orgs = f.get("ORGANIZATION") or []
            fid = f["FacilityID"]
            out.append({
                "id": f"ridb:{fid}",
                "name": (f.get("FacilityName") or "").title(),
                "lat": round(lat, 6), "lon": round(lon, 6), "state": state,
                "source": "ridb", "kind": "campground",
                "free": None,
                "fee": None,
                "reservable": bool(f.get("Reservable")),
                "agency": orgs[0].get("OrgAbbrevName") if orgs else None,
                "url": f"https://www.recreation.gov/camping/campgrounds/{fid}",
                "phone": f.get("FacilityPhone") or None,
                "description": f.get("FacilityDescription"),
                "amenities": [],
                "maxVehicleLength": None,
                "openingHours": None,
            })
        total = data.get("METADATA", {}).get("RESULTS", {}).get("TOTAL_COUNT", 0)
        offset += 50
        if offset >= total or not recs:
            break
    return out


# ---------------------------------------------------------------- merge
def dist_m(a: dict, b: dict) -> float:
    k = math.pi / 180
    x = (b["lon"] - a["lon"]) * k * math.cos((a["lat"] + b["lat"]) * k / 2)
    y = (b["lat"] - a["lat"]) * k
    return 6371000 * math.hypot(x, y)


def dedupe(sites: list[dict]) -> list[dict]:
    """Drop OSM points within 150 m of an official (NPS/RIDB) site, after
    copying the useful OSM fields (amenities, free flag) onto the official one."""
    official = [s for s in sites if s["source"] != "osm"]
    kept = list(official)
    for s in (x for x in sites if x["source"] == "osm"):
        match = next((o for o in official if abs(o["lat"] - s["lat"]) < 0.002 and dist_m(o, s) < 150), None)
        if match:
            match["amenities"] = sorted(set(match["amenities"]) | set(s["amenities"]))
            if match["free"] is None:
                match["free"] = s["free"]
        else:
            kept.append(s)
    return kept


def load_dotenv(path: Path) -> None:
    """Minimal .env reader (KEY=value lines). Real environment variables win."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--states", nargs="+", default=["UT"], help="2-letter state codes")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    load_dotenv(ROOT / ".env")
    nps_key, ridb_key = os.environ.get("NPS_API_KEY"), os.environ.get("RIDB_API_KEY")
    all_sites: list[dict] = []
    for st in (s.upper() for s in args.states):
        print(f"[{st}] OSM…", file=sys.stderr)
        batch = osm_sites(st)
        if nps_key:
            print(f"[{st}] NPS…", file=sys.stderr)
            batch += nps_sites(st, nps_key)
        if ridb_key:
            print(f"[{st}] RIDB…", file=sys.stderr)
            batch += ridb_sites(st, ridb_key)
        batch = dedupe(batch)
        print(f"[{st}] {len(batch)} sites", file=sys.stderr)
        all_sites += batch
    if not nps_key:
        print("NPS_API_KEY not set: skipped NPS (get one at https://www.nps.gov/subjects/developer/get-started.htm)", file=sys.stderr)
    if not ridb_key:
        print("RIDB_API_KEY not set: skipped Recreation.gov (get one at https://ridb.recreation.gov)", file=sys.stderr)

    payload = {
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "attribution": "© OpenStreetMap contributors (ODbL); NPS & Recreation.gov data (public domain)",
        "sites": sorted(all_sites, key=lambda s: s["id"]),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    print(f"wrote {len(all_sites)} sites -> {args.out} ({args.out.stat().st_size/1024:.0f} KB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
