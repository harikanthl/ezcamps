#!/usr/bin/env python3
"""
Assign a US state to coordinate-only campsite records.

Several open datasets (OSM, USFS) publish latitude/longitude but no state
field. This script does an offline point-in-polygon join against the Census
TIGERweb state boundaries and adds/fills a `state` column in the normalized
CSVs. It also repairs obviously swapped or sign-flipped coordinates when a
candidate lands inside a state.

Input:
  data/us_state_boundaries.geojson   US Census TIGERweb, public domain

Updated files:
  data/osm_camp_sites.csv            adds `state`
  data/osm_dump_stations.csv         adds `state`
  data/osm_rest_areas.csv            adds `state`
  data/usfs_recreation_sites.csv     adds `state`
  data/nps_campgrounds.csv           adds `state`
  data/blm_camping.csv               fills blank `state`
  data/recreation_gov_camping.csv    fills blank `state`

Usage:
  python3 scripts/derive_states.py
  python3 scripts/derive_states.py --refresh-boundaries

This uses only the Python standard library. The boundary file is simplified to
about 50 m, which is good enough for state assignment but not for parcel-level
work.
"""

from __future__ import annotations

import csv
import json
import math
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
BOUNDARY_FILE = DATA / "us_state_boundaries.geojson"
BOUNDARY_URL = (
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/"
    "State_County/MapServer/0/query"
    "?where=1%3D1&outFields=STUSAB%2CNAME%2CGEOID&returnGeometry=true"
    "&outSR=4326&f=geojson&maxAllowableOffset=0.0005&geometryPrecision=5"
)

STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
    "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
    "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
    "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
    "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
    "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
    "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
    "PR": "Puerto Rico", "VI": "Virgin Islands", "GU": "Guam",
    "AS": "American Samoa", "MP": "Northern Mariana Islands",
}

# filename, latitude column, longitude column, insert state after this column
FILES = [
    ("osm_camp_sites.csv", "latitude", "longitude", "operator"),
    ("osm_dump_stations.csv", "latitude", "longitude", "operator"),
    ("osm_rest_areas.csv", "latitude", "longitude", "operator"),
    ("usfs_recreation_sites.csv", "latitude", "longitude", "forestname"),
    ("nps_campgrounds.csv", "latitude", "longitude", "park_code"),
    # Existing state columns: fill blanks only.
    ("blm_camping.csv", "latitude", "longitude", None),
    ("recreation_gov_camping.csv", "latitude", "longitude", None),
]


def download_boundaries() -> None:
    print(f"downloading {BOUNDARY_URL}")
    req = urllib.request.Request(
        BOUNDARY_URL,
        headers={"User-Agent": "CampSitesUSA-catalog/0.1 (offline state join)"},
    )
    with urllib.request.urlopen(req, timeout=180) as response:
        data = json.load(response)
    data["attribution"] = "US Census Bureau, TIGERweb State/County (public domain)"
    data["retrieved"] = "2026-11-15"
    data["note"] = (
        "Simplified with maxAllowableOffset=0.0005 degrees (~50 m) "
        "for point-in-state assignment."
    )
    BOUNDARY_FILE.write_text(json.dumps(data, separators=(",", ":")))
    print(f"  wrote {BOUNDARY_FILE} ({BOUNDARY_FILE.stat().st_size / 1e6:.1f} MB)")


def bounds(ring: list[list[float]]) -> tuple[float, float, float, float]:
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def point_in_ring(x: float, y: float, ring: list[list[float]]) -> bool:
    """Ray casting. The ring must be closed (GeoJSON guarantees this)."""
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / (yj - yi) + xi
        ):
            inside = not inside
        j = i
    return inside


class Polygon:
    __slots__ = ("rings", "boxes", "dateline")

    def __init__(self, rings: list[list[list[float]]]):
        self.dateline = any(bounds(r)[2] - bounds(r)[0] > 180 for r in rings)
        if self.dateline:
            # Unwrap negative longitudes so a ring crossing 180 E/W is contiguous.
            rings = [
                [[x + 360 if x < 0 else x, y] for x, y in ring]
                for ring in rings
            ]
        self.rings = rings
        self.boxes = [bounds(r) for r in rings]

    def contains(self, lon: float, lat: float) -> bool:
        x = lon + 360 if self.dateline and lon < 0 else lon
        minx, miny, maxx, maxy = self.boxes[0]
        if not (minx <= x <= maxx and miny <= lat <= maxy):
            return False
        if not point_in_ring(x, lat, self.rings[0]):
            return False
        for ring, box in zip(self.rings[1:], self.boxes[1:]):
            if box[0] <= x <= box[2] and box[1] <= lat <= box[3]:
                if point_in_ring(x, lat, ring):
                    return False
        return True


class StateFeature:
    __slots__ = ("code", "name", "polygons", "box", "dateline")

    def __init__(self, code: str, name: str, polygons: list[Polygon]):
        self.code = code
        self.name = name
        self.polygons = polygons
        self.dateline = any(p.dateline for p in polygons)
        if not self.dateline:
            xs = [b[0] for p in polygons for b in p.boxes]
            ys = [b[1] for p in polygons for b in p.boxes]
            X = [b[2] for p in polygons for b in p.boxes]
            Y = [b[3] for p in polygons for b in p.boxes]
            self.box = (min(xs), min(ys), max(X), max(Y))
        else:
            self.box = None

    def contains(self, lon: float, lat: float) -> bool:
        if self.box is not None:
            minx, miny, maxx, maxy = self.box
            if not (minx <= lon <= maxx and miny <= lat <= maxy):
                return False
        return any(p.contains(lon, lat) for p in self.polygons)


def load_features() -> list[StateFeature]:
    data = json.loads(BOUNDARY_FILE.read_text())
    features = []
    for feature in data.get("features", []):
        code = feature["properties"]["STUSAB"]
        geometry = feature["geometry"]
        if geometry["type"] == "Polygon":
            raw_polygons = [geometry["coordinates"]]
        elif geometry["type"] == "MultiPolygon":
            raw_polygons = geometry["coordinates"]
        else:
            continue
        polygons = [Polygon(rings) for rings in raw_polygons]
        features.append(StateFeature(code, STATE_NAMES.get(code, feature["properties"]["NAME"]), polygons))
    return features


def locate(features: list[StateFeature], lat: float, lon: float) -> tuple[str, str] | None:
    for feature in features:
        if feature.contains(lon, lat):
            return feature.code, feature.name
    return None


def is_valid(lat: float, lon: float) -> bool:
    return -90 <= lat <= 90 and -180 <= lon <= 180


def parse_point(lat_raw: str, lon_raw: str) -> tuple[float, float] | None:
    try:
        lat = float(lat_raw)
        lon = float(lon_raw)
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lon)):
        return None
    return lat, lon


def candidate_points(lat: float, lon: float) -> list[tuple[float, float]]:
    """Plausible repairs for bad source coordinates, most likely first."""
    a, b = abs(lat), abs(lon)
    candidates = [
        (lon, lat),          # swapped
        (a, -b),             # latitude sign flipped
        (b, -a),             # both swapped and a sign flipped
        (a, b),              # longitude sign flipped (Guam/MP)
        (b, a),
        (-a, -b),
        (-b, -a),
        (-a, b),
        (-b, a),
    ]
    seen = set()
    out = []
    for candidate in candidates:
        if candidate not in seen and is_valid(*candidate):
            seen.add(candidate)
            out.append(candidate)
    return out


def update_file(
    path: Path,
    lat_col: str,
    lon_col: str,
    insert_after: str | None,
    features: list[StateFeature],
) -> dict[str, int]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)

    had_state = "state" in fieldnames
    if not had_state:
        index = fieldnames.index(insert_after) + 1 if insert_after in fieldnames else len(fieldnames)
        fieldnames.insert(index, "state")

    stats = {
        "rows": len(rows),
        "already": 0,
        "filled": 0,
        "repaired_coords": 0,
        "still_missing": 0,
        "outside_us": 0,
    }

    for row in rows:
        current = (row.get("state") or "").strip()
        if current:
            stats["already"] += 1
            if had_state:
                continue

        parsed = parse_point(row.get(lat_col, ""), row.get(lon_col, ""))
        if parsed is None:
            stats["still_missing"] += 1
            continue

        lat, lon = parsed
        original_valid = is_valid(lat, lon)
        located = locate(features, lat, lon) if original_valid else None
        if located is None:
            # Out-of-range coordinates may be swapped or sign-flipped. For
            # in-range points, only try flipping a sign: a valid point in the
            # ocean or another country must stay unassigned.
            candidates = (
                [(lat, -lon), (-lat, lon)] if original_valid else candidate_points(lat, lon)
            )
            for candidate in candidates:
                located = locate(features, *candidate)
                if located:
                    row[lat_col] = f"{candidate[0]:.6f}"
                    row[lon_col] = f"{candidate[1]:.6f}"
                    stats["repaired_coords"] += 1
                    break

        if located is None:
            stats["outside_us"] += 1
            stats["still_missing"] += 1
            row["state"] = ""
            continue

        row["state"] = located[1]
        stats["filled"] += 1

    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(
        f"{path.name:34s} rows={stats['rows']:>6}  "
        f"already={stats['already']:>6}  filled={stats['filled']:>6}  "
        f"fixed_coords={stats['repaired_coords']:>3}  "
        f"missing={stats['still_missing']:>3}  outside_us={stats['outside_us']:>3}"
    )
    return stats


def main() -> None:
    if "--refresh-boundaries" in sys.argv or not BOUNDARY_FILE.exists():
        download_boundaries()
    features = load_features()
    print(f"loaded {len(features)} state/territory polygons from {BOUNDARY_FILE.name}")

    for filename, lat_col, lon_col, insert_after in FILES:
        path = DATA / filename
        if not path.exists():
            print(f"skip {filename}: not collected")
            continue
        update_file(path, lat_col, lon_col, insert_after, features)


if __name__ == "__main__":
    main()
