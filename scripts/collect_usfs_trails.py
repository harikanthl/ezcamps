#!/usr/bin/env python3
"""
Collect National Forest System trails (USFS EDW, CC BY 4.0) and aggregate the
segments into one row per trail.

Source: https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0
  ~86k segments. Each has trail_class (1-5), typical_trail_grade, gis_miles and
  managed uses (hiker, bicycle, pack/saddle, motorcycle, ATV, 4WD).

Note: USFS trail class is a *development* scale, not difficulty.
  TC1 = minimally developed (primitive, rough)   TC5 = fully developed (often paved)
scripts/pipeline/activities.py turns class + grade + length into a difficulty.

Resumable: raw segment pages are appended to data/usfs_trails.partial.jsonl
(git-ignored) and the run continues after the last objectid it saw.

Usage: python3 -I scripts/collect_usfs_trails.py
Writes data/usfs_trails.csv. Stdlib only.
"""

from __future__ import annotations

import csv
import json
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARTIAL = ROOT / "data" / "usfs_trails.partial.jsonl"
OUT = ROOT / "data" / "usfs_trails.csv"
SERVICE = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_TrailNFSPublish_01/MapServer/0/query"
FIELDS = ["objectid", "trail_cn", "trail_no", "trail_name", "trail_type", "trail_class",
          "typical_trail_grade", "gis_miles", "bmp", "admin_org", "trail_surface",
          "national_trail_designation", "hiker_pedestrian_managed", "bicycle_managed",
          "pack_saddle_managed", "motorcycle_managed", "atv_managed", "fourwd_managed"]
USES = {"hiker_pedestrian_managed": "hike", "bicycle_managed": "bike", "pack_saddle_managed": "horse",
        "motorcycle_managed": "motorcycle", "atv_managed": "atv", "fourwd_managed": "4wd"}
PAGE = 2000


def fetch(after: int) -> dict:
    params = {
        "where": f"objectid > {after}", "outFields": ",".join(FIELDS), "returnGeometry": "true",
        "outSR": "4326", "maxAllowableOffset": "0.002", "geometryPrecision": "5",
        "orderByFields": "objectid", "resultRecordCount": str(PAGE), "f": "json",
    }
    url = SERVICE + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ezcamps-data-pipeline"})
            with urllib.request.urlopen(req, timeout=180) as r:
                data = json.load(r)
            if "error" in data:
                raise RuntimeError(data["error"])
            return data
        except Exception as e:  # noqa: BLE001 - flaky government server; back off and retry
            wait = 5 * (attempt + 1)
            print(f"  page after {after} failed ({e}); retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"giving up after objectid {after}")


def collect() -> None:
    last = 0
    if PARTIAL.exists():
        for line in PARTIAL.open():
            last = max(last, json.loads(line)["a"]["objectid"])
        print(f"resuming after objectid {last}", file=sys.stderr)
    with PARTIAL.open("a") as out:
        while True:
            data = fetch(last)
            feats = data.get("features", [])
            if not feats:
                break
            for f in feats:
                paths = (f.get("geometry") or {}).get("paths") or []
                start = paths[0][0] if paths and paths[0] else None
                end = paths[-1][-1] if paths and paths[-1] else None
                out.write(json.dumps({"a": f["attributes"], "s": start, "e": end}) + "\n")
                last = max(last, f["attributes"]["objectid"])
            out.flush()
            print(f"  {last} …", file=sys.stderr)
            if not data.get("exceededTransferLimit") and len(feats) < PAGE:
                break


def aggregate() -> int:
    trails: dict[str, dict] = {}
    segs: dict[str, list] = defaultdict(list)
    for line in PARTIAL.open():
        rec = json.loads(line)
        a = rec["a"]
        if a.get("trail_type") != "TERRA" or not a.get("trail_cn"):
            continue
        segs[a["trail_cn"]].append(rec)
    for cn, rs in segs.items():
        rs.sort(key=lambda r: r["a"].get("bmp") or 0)
        first = rs[0]
        classes = [int(r["a"]["trail_class"]) for r in rs if str(r["a"].get("trail_class") or "").isdigit()]
        miles = sum(r["a"].get("gis_miles") or 0 for r in rs)
        weighted_grade: dict[str, float] = defaultdict(float)
        for r in rs:
            g = (r["a"].get("typical_trail_grade") or "").replace("TG0", "").strip()
            if g and g != "N/A":
                weighted_grade[g.split(" - ")[-1].lstrip("+")] += r["a"].get("gis_miles") or 0
        uses = sorted({u for r in rs for k, u in USES.items()
                       if r["a"].get(k) not in (None, "", "N/A")})
        if not first["s"]:
            continue
        trails[cn] = {
            "trail_cn": cn,
            "trail_no": first["a"].get("trail_no"),
            "name": (first["a"].get("trail_name") or "").title(),
            "admin_org": first["a"].get("admin_org"),
            "miles": round(miles, 2),
            "trail_class_min": min(classes) if classes else None,
            "trail_class_typical": max(set(classes), key=classes.count) if classes else None,
            "grade": max(weighted_grade, key=weighted_grade.get) if weighted_grade else None,
            "surface": first["a"].get("trail_surface"),
            "national_trail": first["a"].get("national_trail_designation") in (2, 3),
            "uses": ";".join(uses),
            "start_lat": first["s"][1], "start_lon": first["s"][0],
            "end_lat": rs[-1]["e"][1] if rs[-1]["e"] else None,
            "end_lon": rs[-1]["e"][0] if rs[-1]["e"] else None,
        }
    rows = sorted(trails.values(), key=lambda t: t["trail_cn"])
    with OUT.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return len(rows)


def main() -> None:
    collect()
    n = aggregate()
    print(f"wrote {n} trails -> {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
