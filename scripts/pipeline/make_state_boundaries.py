#!/usr/bin/env python3
"""
Convert the Census cartographic-boundary state shapefile into a compact JSON
file that build_db.py uses to assign a state to every site (point-in-polygon).

Source (public domain, US Census Bureau):
  https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_us_state_20m.zip

Usage:
  python3 -I scripts/pipeline/make_state_boundaries.py /path/to/cb_2024_us_state_20m.shp

Writes data/boundaries/us_states.json:
  {"source": ..., "states": {"UT": [[ring], ...], ...}}  rings are [[lon, lat], ...]
Stdlib only.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "boundaries" / "us_states.json"


def read_dbf(path: Path) -> list[dict[str, str]]:
    data = path.read_bytes()
    n_records, header_len, record_len = struct.unpack("<IHH", data[4:12])
    fields, pos = [], 32
    while data[pos] != 0x0D:
        name = data[pos:pos + 11].split(b"\0")[0].decode()
        length = data[pos + 16]
        fields.append((name, length))
        pos += 32
    rows, pos = [], header_len
    for _ in range(n_records):
        rec, off = {}, pos + 1  # skip deletion flag
        for name, length in fields:
            rec[name] = data[off:off + length].decode("latin-1").strip()
            off += length
        rows.append(rec)
        pos += record_len
    return rows


def read_polygons(path: Path) -> list[list[list[tuple[float, float]]]]:
    data = path.read_bytes()
    pos, shapes = 100, []
    while pos < len(data):
        _, content_len = struct.unpack(">II", data[pos:pos + 8])
        body = data[pos + 8: pos + 8 + content_len * 2]
        pos += 8 + content_len * 2
        shape_type = struct.unpack("<i", body[:4])[0]
        if shape_type == 0:
            shapes.append([])
            continue
        if shape_type != 5:
            raise ValueError(f"expected polygon shapes, got type {shape_type}")
        n_parts, n_points = struct.unpack("<ii", body[36:44])
        parts = list(struct.unpack(f"<{n_parts}i", body[44:44 + 4 * n_parts]))
        pts_off = 44 + 4 * n_parts
        pts = [struct.unpack("<dd", body[pts_off + 16 * i: pts_off + 16 * i + 16]) for i in range(n_points)]
        parts.append(n_points)
        shapes.append([pts[parts[i]:parts[i + 1]] for i in range(n_parts)])
    return shapes


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    shp = Path(sys.argv[1])
    records = read_dbf(shp.with_suffix(".dbf"))
    shapes = read_polygons(shp)
    states = {}
    for rec, rings in zip(records, shapes):
        states[rec["STUSPS"]] = [[[round(x, 4), round(y, 4)] for x, y in ring] for ring in rings]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "source": "US Census Bureau, cartographic boundary file cb_2024_us_state_20m (public domain)",
        "states": states,
    }, separators=(",", ":")))
    print(f"wrote {OUT} ({len(states)} states, {OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
