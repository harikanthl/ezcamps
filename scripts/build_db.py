#!/usr/bin/env python3
"""
Build data/campsites.db from the collected CSVs.

Creates one table per source, a raw `all_campsites` view, and the canonical
`campsites` table (state assigned from coordinates, coordinates fixed, fees and
amenities parsed, duplicates across sources merged; see scripts/pipeline/unify.py).
Numeric columns are inferred; empty strings become NULL.

Usage: python3 scripts/build_db.py
"""

from __future__ import annotations

import csv
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DB = DATA / "campsites.db"

sys.path.insert(0, str(ROOT / "scripts" / "pipeline"))
from unify import build_campsites  # noqa: E402
from activities import build_activities  # noqa: E402

# Only index columns people actually filter or join on. Indexing every column
# (including long descriptions) more than doubled the file size.
INDEXED = {"id", "source_id", "recareaid", "osm_id", "park_code", "park_codes", "entity_type",
           "markeractivitygroup", "state", "states", "latitude", "longitude"}

TABLES = {
    "recreation_gov": "recreation_gov_camping.csv",
    "nps_parks": "nps_parks.csv",
    "nps_campgrounds": "nps_campgrounds.csv",
    "blm_camping": "blm_camping.csv",
    "usfs_recreation": "usfs_recreation_sites.csv",
    "osm_camp_sites": "osm_camp_sites.csv",
    "osm_dump_stations": "osm_dump_stations.csv",
    "osm_rest_areas": "osm_rest_areas.csv",
    "nps_alerts": "nps_alerts.csv",
    "nps_things_to_do": "nps_things_to_do.csv",
    "nps_visitor_centers": "nps_visitor_centers.csv",
    "nps_webcams": "nps_webcams.csv",
    "state_park_systems": "state_park_systems.csv",
}

NUMERIC_HINTS = (
    "latitude", "longitude", "price_", "campsites_count", "accessible_campsites_count",
    "max_vehicle_length", "average_rating", "rating_count", "cell_coverage_score",
    "total_sites", "tent_only_sites", "rv_only_sites", "group_sites", "horse_sites",
    "electrical_hookups", "walk_boat_sites", "other_sites", "reservable_sites",
    "first_come_first_serve_sites", "rv_max_length_ft", "trailer_max_length_ft",
    "recareaid", "source_id", "id",
)


def infer_type(column: str, values: list[str]) -> str:
    if column.lower() in NUMERIC_HINTS or column.lower().endswith("_id"):
        return "REAL"
    sample = [v for v in values if v not in ("", None)][:200]
    if sample:
        try:
            for v in sample:
                float(v)
            return "REAL"
        except ValueError:
            pass
    return "TEXT"


def clean(value: str):
    if value is None or value == "":
        return None
    return value


def load_table(conn: sqlite3.Connection, name: str, path: Path) -> int:
    with path.open() as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
        fields = reader.fieldnames or []
    if not rows:
        return 0
    cols = {f: infer_type(f, [r[f] for r in rows]) for f in fields}
    col_sql = ", ".join(f'"{c}" {t}' for c, t in cols.items())
    conn.execute(f'DROP TABLE IF EXISTS "{name}"')
    conn.execute(f'CREATE TABLE "{name}" ({col_sql})')
    placeholders = ", ".join("?" for _ in fields)
    conn.executemany(
        f'INSERT INTO "{name}" VALUES ({placeholders})',
        [[clean(r[f]) for f in fields] for r in rows],
    )
    for c in (f for f in fields if f.lower() in INDEXED):
        conn.execute(f'CREATE INDEX IF NOT EXISTS "idx_{name}_{c}" ON "{name}"("{c}")')
    return len(rows)


def build_state_lookup(conn: sqlite3.Connection) -> None:
    states = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"),
        ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
        ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"),
        ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"),
        ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"),
        ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"),
        ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
        ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"),
        ("SC", "South Carolina"), ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"),
        ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
        ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
        ("PR", "Puerto Rico"), ("VI", "Virgin Islands"), ("GU", "Guam"),
        ("AS", "American Samoa"), ("MP", "Northern Mariana Islands"), ("VI", "Saint John"),
    ]
    conn.execute("DROP TABLE IF EXISTS state_lookup")
    conn.execute("CREATE TABLE state_lookup (code TEXT, name TEXT)")
    conn.executemany("INSERT INTO state_lookup VALUES (?, ?)", states)


def build_normalized_view(conn: sqlite3.Connection) -> None:
    """Add a state_code column on top of the mixed-name source data."""
    conn.executescript(
        """
        DROP VIEW IF EXISTS all_campsites_norm;
        CREATE VIEW all_campsites_norm AS
        SELECT c.*,
               COALESCE(
                   (SELECT l.code FROM state_lookup l
                    WHERE lower(l.name) = lower(trim(c.state)) LIMIT 1),
                   CASE WHEN upper(trim(c.state)) IN (SELECT code FROM state_lookup)
                        THEN upper(trim(c.state)) END
               ) AS state_code
        FROM all_campsites c;
        """
    )


def build_view(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP VIEW IF EXISTS all_campsites;
        CREATE VIEW all_campsites AS
        SELECT
            'recreation_gov' AS source,
            CAST(source_id AS TEXT) AS source_id,
            name,
            CASE WHEN entity_type = 'campground' THEN 'developed' ELSE 'recreation_area' END AS site_type,
            agency AS manager,
            state,
            city,
            CAST(latitude AS REAL) AS latitude,
            CAST(longitude AS REAL) AS longitude,
            price_min, price_max, price_unit,
            CAST(campsites_count AS INTEGER) AS capacity,
            CAST(max_vehicle_length_ft AS INTEGER) AS max_rig_ft,
            equipment_allowed AS equipment,
            reservable,
            average_rating AS rating,
            rating_count,
            official_url AS source_url,
            'check' AS license
        FROM recreation_gov
        WHERE entity_type IN ('campground', 'recarea')

        UNION ALL
        SELECT
            'nps', id, name, 'developed', 'National Park Service',
            (SELECT states FROM nps_parks WHERE nps_parks.park_code = nps_campgrounds.park_code),
            NULL, CAST(latitude AS REAL), CAST(longitude AS REAL),
            NULL, NULL, NULL,
            CAST(total_sites AS INTEGER), CAST(rv_max_length_ft AS INTEGER),
            NULL, NULL, NULL, NULL, url, 'public-domain'
        FROM nps_campgrounds

        UNION ALL
        SELECT
            'blm', CAST(source_id AS TEXT), name, 'dispersed', 'Bureau of Land Management',
            state, NULL, CAST(latitude AS REAL), CAST(longitude AS REAL),
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, blm_url, 'public-domain'
        FROM blm_camping

        UNION ALL
        SELECT
            'usfs', CAST(recareaid AS TEXT), recareaname,
            CASE
                WHEN markeractivitygroup = 'Camping & Cabins' THEN 'developed'
                WHEN markeractivity = 'Trailhead' THEN 'trailhead'
                ELSE 'recreation_site'
            END,
            'USDA Forest Service', NULL, NULL,
            CAST(latitude AS REAL), CAST(longitude AS REAL),
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, recareaurl, 'cc-by-4.0'
        FROM usfs_recreation
        WHERE markeractivitygroup IN ('Camping & Cabins', 'Horse Riding & Camping', 'OHV Riding & Camping', 'Trailhead')

        UNION ALL
        SELECT
            'osm', osm_type || '/' || CAST(osm_id AS TEXT), name,
            CASE camp_site
                WHEN 'serviced' THEN 'developed'
                WHEN 'deluxe' THEN 'developed'
                WHEN 'standard' THEN 'primitive'
                WHEN 'basic' THEN 'primitive'
                ELSE 'dispersed'
            END,
            operator, NULL, NULL,
            CAST(latitude AS REAL), CAST(longitude AS REAL),
            CASE WHEN fee = 'free' THEN 0 END, NULL, NULL,
            CAST(capacity AS INTEGER), NULL, NULL, NULL, NULL, NULL, osm_url, 'odbl'
        FROM osm_camp_sites;
        """
    )


def main() -> None:
    if DB.exists():
        DB.unlink()
    conn = sqlite3.connect(DB)
    counts = {}
    for table, filename in TABLES.items():
        path = DATA / filename
        if not path.exists():
            print(f"skip {table}: {filename} not collected yet")
            continue
        counts[table] = load_table(conn, table, path)
    # The normalized view references these even when a collector has not run yet.
    conn.execute(
        """CREATE TABLE IF NOT EXISTS usfs_recreation (
            recareaid REAL, recareaname TEXT, markeractivity TEXT, markeractivitygroup TEXT,
            forestname TEXT, latitude REAL, longitude REAL, recareaurl TEXT
        )"""
    )
    conn.execute(
        """CREATE TABLE IF NOT EXISTS osm_camp_sites (
            osm_type TEXT, osm_id REAL, name TEXT, camp_site TEXT, fee TEXT,
            operator TEXT, latitude REAL, longitude REAL, capacity TEXT, osm_url TEXT
        )"""
    )
    build_view(conn)
    build_state_lookup(conn)
    build_normalized_view(conn)

    if (DATA / "sources.json").exists():
        sources = json.loads((DATA / "sources.json").read_text())["sources"]
        conn.execute("DROP TABLE IF EXISTS sources")
        conn.execute(
            """CREATE TABLE sources (
                id TEXT PRIMARY KEY, name TEXT, category TEXT, operator TEXT,
                coverage TEXT, access TEXT, endpoint TEXT, auth TEXT, license TEXT,
                redistributable TEXT, update_frequency TEXT, key_fields TEXT,
                url TEXT, notes TEXT
            )"""
        )
        for s in sources:
            conn.execute(
                "INSERT INTO sources VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                [
                    s.get("id"), s.get("name"), s.get("category"), s.get("operator"),
                    s.get("coverage"), s.get("access"), s.get("endpoint"), s.get("auth"),
                    s.get("license"), s.get("redistributable"), s.get("update"),
                    json.dumps(s.get("key_fields", [])), s.get("url"), s.get("notes"),
                ],
            )
        counts["sources"] = len(sources)

    unify_stats = build_campsites(conn, DATA)
    unify_stats |= build_activities(conn, DATA)

    conn.commit()
    total = conn.execute("SELECT COUNT(*) FROM all_campsites").fetchone()[0]
    conn.execute("VACUUM")
    conn.close()

    for table, n in counts.items():
        print(f"  {table:24} {n:>6} rows")
    print(f"  {'all_campsites (view)':24} {total:>6} rows")
    for k, v in unify_stats.items():
        print(f"  campsites: {k:22} {v:>6}")
    print(f"wrote {DB}")


if __name__ == "__main__":
    main()
