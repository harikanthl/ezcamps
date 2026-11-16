#!/usr/bin/env python3
"""
Build CampSitesUSA/Resources/safety_index.json: for every campsite, its county and nearby national
parks, plus county crime context from the FBI Crime Data Explorer.

Crime context is the county sheriff's office: the agency that polices unincorporated land, which is
where most campsites are. Rates are offenses per 100,000 people over the last full calendar year,
next to the state and US rates from the same FBI response. It's context for the area, never a
claim about a specific campsite, and the app says so.

Inputs
  CampSitesUSA/Resources/sites.json                    app campsites
  data/nps_campgrounds.csv, data/nps_parks.csv         park codes and centres
  --counties  cb_YYYY_us_county_500k.kml               Census cartographic county boundaries (KML)
  FBI_API_KEY                                          api.data.gov key (env or .env); DEMO_KEY for a tiny trial

Usage
  python3 -I scripts/pipeline/safety_index.py --counties /path/to/cb_2024_us_county_500k.kml
  python3 -I scripts/pipeline/safety_index.py --counties ... --states UT --year 2025   # trial run
  python3 -I scripts/pipeline/safety_index.py --counties ... --no-crime                # counties + parks only

FBI responses are cached under data/cache/cde/ so a run that hits the rate limit resumes where it stopped.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITES = ROOT / "CampSitesUSA" / "Resources" / "sites.json"
OUT = ROOT / "CampSitesUSA" / "Resources" / "safety_index.json"
CACHE = ROOT / "data" / "cache" / "cde"
CDE = "https://api.usa.gov/crime/fbi/cde"
PARK_RADIUS_MI = 20
PARK_KINDS = re.compile(r"National (Park|Monument|Recreation Area|Seashore|Lakeshore|Preserve|River|Forest)", re.I)


# MARK: Counties (Census KML)

def load_counties(path: Path) -> list[dict]:
    """[{geoid, name, state, rings: [(outer, holes)], bbox}] from a Census cartographic KML."""
    ns = {"k": "http://www.opengis.net/kml/2.2"}
    out = []
    for _, el in ET.iterparse(path, events=("end",)):
        if not el.tag.endswith("Placemark"):
            continue
        data = {d.get("name"): (d.text or "") for d in el.iter() if d.tag.endswith("SimpleData")}
        polys = []
        for poly in (p for p in el.iter() if p.tag.endswith("Polygon")):
            rings = {"outer": None, "holes": []}
            for b in poly:
                coords = next((c.text for c in b.iter() if c.tag.endswith("coordinates")), "") or ""
                pts = [tuple(map(float, xy.split(",")[:2])) for xy in coords.split()]
                if b.tag.endswith("outerBoundaryIs"):
                    rings["outer"] = pts
                elif b.tag.endswith("innerBoundaryIs"):
                    rings["holes"].append(pts)
            if rings["outer"]:
                polys.append(rings)
        if polys and data.get("GEOID"):
            xs = [x for p in polys for x, _ in p["outer"]]
            ys = [y for p in polys for _, y in p["outer"]]
            out.append({
                "geoid": data["GEOID"],
                "name": data.get("NAMELSAD") or data.get("NAME", ""),
                "short": data.get("NAME", ""),
                "state": data.get("STUSPS", ""),
                "polys": polys,
                "bbox": (min(xs), min(ys), max(xs), max(ys)),
            })
        el.clear()
    _ = ns
    return out


def inside(pt: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    x, y = pt
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def county_of(lon: float, lat: float, grid: dict, counties: list[dict]) -> dict | None:
    for idx in grid.get((math.floor(lon), math.floor(lat)), ()):
        c = counties[idx]
        x0, y0, x1, y1 = c["bbox"]
        if not (x0 <= lon <= x1 and y0 <= lat <= y1):
            continue
        for p in c["polys"]:
            if inside((lon, lat), p["outer"]) and not any(inside((lon, lat), h) for h in p["holes"]):
                return c
    return None


def build_grid(counties: list[dict]) -> dict:
    grid: dict = {}
    for i, c in enumerate(counties):
        x0, y0, x1, y1 = c["bbox"]
        for gx in range(math.floor(x0), math.floor(x1) + 1):
            for gy in range(math.floor(y0), math.floor(y1) + 1):
                grid.setdefault((gx, gy), []).append(i)
    return grid


# MARK: Parks

def miles(a: tuple[float, float], b: tuple[float, float]) -> float:
    k = math.pi / 180
    x = (b[1] - a[1]) * k * math.cos((a[0] + b[0]) * k / 2)
    y = (b[0] - a[0]) * k
    return 3958.8 * math.hypot(x, y)


def load_parks() -> tuple[dict[str, str], list[tuple[str, float, float]]]:
    camp_park = {}
    with (ROOT / "data" / "nps_campgrounds.csv").open(newline="") as f:
        for r in csv.DictReader(f):
            if r.get("id") and re.fullmatch(r"[a-z]{4}", r.get("park_code") or ""):
                camp_park["nps:" + r["id"]] = r["park_code"]
    centres = []
    with (ROOT / "data" / "nps_parks.csv").open(newline="") as f:
        for r in csv.DictReader(f):
            try:
                lat, lon = float(r["latitude"]), float(r["longitude"])
            except (TypeError, ValueError):
                continue
            if PARK_KINDS.search(r.get("designation") or r.get("name") or ""):
                centres.append((r["park_code"], lat, lon))
    return camp_park, centres


# MARK: FBI Crime Data Explorer

def api_key() -> str:
    key = os.environ.get("FBI_API_KEY")
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("FBI_API_KEY="):
                key = line.split("=", 1)[1].strip()
    return key or "DEMO_KEY"


def cde(path: str, key: str) -> dict:
    """GET with an on-disk cache and polite retries (the key is never written to the cache or logs)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / (re.sub(r"[^A-Za-z0-9._-]+", "_", path) + ".json")
    if cached.exists():
        return json.loads(cached.read_text())
    sep = "&" if "?" in path else "?"
    req = urllib.request.Request(f"{CDE}/{path}{sep}API_KEY={urllib.parse.quote(key)}", headers={"User-Agent": "ezcamp-pipeline"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = json.load(r)
                remaining = int(r.headers.get("X-RateLimit-Remaining") or 100)
            cached.write_text(json.dumps(body))
            if remaining < 3:
                print("  rate limit nearly used up; waiting 10 minutes", file=sys.stderr)
                time.sleep(600)
            return body
        except urllib.error.HTTPError as e:
            if e.code == 429:
                print(f"  429 on {path.split('?')[0]}; waiting 15 minutes", file=sys.stderr)
                time.sleep(900)
            elif e.code in (500, 502, 503, 504):
                time.sleep(5 * (attempt + 1))
            else:
                raise RuntimeError(f"{e.code} for {path.split('?')[0]}") from None
        except (urllib.error.URLError, TimeoutError):
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"gave up on {path.split('?')[0]}")


def sheriff_for(county: dict, agencies: dict) -> dict | None:
    """The county's sheriff (or county police) office from the CDE agency list for its state."""
    wanted = county["short"].upper()
    candidates = []
    for listed, rows in agencies.items():
        names = {n.strip().upper() for n in listed.split(",")}
        if wanted not in names:
            continue
        for a in rows:
            if a.get("agency_type_name") != "County":
                continue
            n = (a.get("agency_name") or "").lower()
            score = 2 if "sheriff" in n else 1 if "county police" in n else 0
            if score:
                candidates.append((score, len(names) == 1, a))
    if not candidates:
        return None
    candidates.sort(key=lambda t: (t[0], t[1]), reverse=True)
    return candidates[0][2]


def annual(resp: dict, label_suffix: str, who: str) -> tuple[float | None, int]:
    """Sum of 12 monthly values for one series, and how many months had data."""
    series = (resp.get("offenses") or {}).get(label_suffix, {}).get(who) or {}
    vals = [v for v in series.values() if isinstance(v, (int, float))]
    return (sum(vals) if vals else None), len(vals)


def crime_for(agency: dict, state_name: str, year: int, key: str) -> dict | None:
    ori = agency["ori"]
    out: dict = {"agency": agency["agency_name"], "ori": ori}
    for code, field in (("V", "violent"), ("P", "property")):
        r = cde(f"summarized/agency/{ori}/{code}?from=01-{year}&to=12-{year}", key)
        name = agency["agency_name"]
        actual, months = annual(r, "actuals", f"{name} Offenses")
        pops = (r.get("populations") or {}).get("population", {}).get(name) or {}
        pop = max([p for p in pops.values() if isinstance(p, (int, float))] or [0])
        state_rate, _ = annual(r, "rates", f"{state_name} Offenses")
        us_rate, _ = annual(r, "rates", "United States Offenses")
        out[field] = round(actual / pop * 100_000, 1) if actual is not None and pop > 0 and months >= 10 else None
        out[f"{field}Count"] = actual
        out[f"state_{field}"] = round(state_rate, 1) if state_rate is not None else None
        out[f"us_{field}"] = round(us_rate, 1) if us_rate is not None else None
        out["population"] = pop
        out["months"] = min(out.get("months", 12), months)
    if out.get("violent") is None and out.get("property") is None:
        return None
    return out


# MARK: Main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--counties", required=True, type=Path, help="Census cartographic county KML")
    ap.add_argument("--year", type=int, default=date.today().year - 1, help="calendar year of crime data")
    ap.add_argument("--states", help="only fetch crime for these states, e.g. UT,WY (trial runs)")
    ap.add_argument("--no-crime", action="store_true")
    args = ap.parse_args()

    sites = json.loads(SITES.read_text())["sites"]
    counties = load_counties(args.counties)
    grid = build_grid(counties)
    print(f"{len(counties)} counties, {len(sites)} sites", file=sys.stderr)

    camp_park, centres = load_parks()
    site_county: dict[str, dict] = {}
    index_sites: dict[str, object] = {}
    for s in sites:
        c = county_of(s["lon"], s["lat"], grid, counties)
        parks = []
        if s["id"] in camp_park:
            parks.append(camp_park[s["id"]])
        for code, lat, lon in centres:
            if code not in parks and miles((s["lat"], s["lon"]), (lat, lon)) <= PARK_RADIUS_MI:
                parks.append(code)
        if c:
            site_county[s["id"]] = c
        entry = [c["geoid"] if c else None, parks[:3]] if parks else (c["geoid"] if c else None)
        if entry is not None:
            index_sites[s["id"]] = entry
    print(f"county found for {len(site_county)} sites; park codes for "
          f"{sum(1 for v in index_sites.values() if isinstance(v, list))}", file=sys.stderr)

    used = {c["geoid"]: c for c in site_county.values()}
    out_counties: dict[str, dict] = {
        g: {"name": c["name"], "state": c["state"]} for g, c in used.items()
    }

    crime_year = None
    if not args.no_crime:
        key = api_key()
        only = set(args.states.split(",")) if args.states else None
        states = sorted({c["state"] for c in used.values() if not only or c["state"] in only})
        print(f"crime: {len(states)} states, year {args.year}, key {'DEMO_KEY' if key == 'DEMO_KEY' else 'set'}", file=sys.stderr)
        found = 0
        for st in states:
            try:
                raw = cde(f"agency/byStateAbbr/{st}", key)
            except RuntimeError as e:
                print(f"  {st}: no agency list ({e})", file=sys.stderr)
                continue
            # Expect {county: [agency, ...]}; territories and errors come back in other shapes.
            agencies = {k: [a for a in v if isinstance(a, dict)] for k, v in raw.items() if isinstance(v, list)} if isinstance(raw, dict) else {}
            if not agencies:
                print(f"  {st}: no agencies listed, skipped", file=sys.stderr)
                continue
            state_name = next((a.get("state_name") for rows in agencies.values() for a in rows if a.get("state_name")), st)
            for g, c in sorted(used.items()):
                if c["state"] != st:
                    continue
                sheriff = sheriff_for(c, agencies)
                if not sheriff:
                    continue
                try:
                    info = crime_for(sheriff, state_name, args.year, key)
                except RuntimeError as e:
                    print(f"  {c['name']}, {st}: {e}", file=sys.stderr)
                    continue
                if info:
                    out_counties[g]["crime"] = info
                    found += 1
            print(f"  {st}: done ({found} counties with crime data so far)", file=sys.stderr)
        crime_year = args.year

    OUT.write_text(json.dumps({
        "generated": date.today().isoformat(),
        "crimeYear": crime_year,
        "sources": {
            "counties": "US Census Bureau cartographic boundary files",
            "crime": "FBI Crime Data Explorer (UCR), county sheriff's office, offenses per 100,000 people",
            "parks": "National Park Service",
        },
        "counties": out_counties,
        "sites": index_sites,
    }, separators=(",", ":")))
    print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.1f} MB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
