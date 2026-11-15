"""
Build the `activities` table: things to do near campsites, each with a difficulty
(0 Easy, 1 Moderate, 2 Hard, 3 Strenuous, NULL = not a physical activity / unrated)
and a plain-language `difficulty_basis` saying where the grade came from.

Sources (all already in campsites.db or data/):
  * USFS National Forest System trails (data/usfs_trails.csv, CC BY 4.0)
      graded from trail class + typical grade + length
  * NPS things to do (public domain)
      graded from the park's own wording ("strenuous", "easy"...), else from duration
  * USFS recreation sites for non-trail activities (fishing, paddling, climbing, scenic drives...)

Called by scripts/build_db.py. Stdlib only.
"""

from __future__ import annotations

import csv
import re
import sqlite3
from pathlib import Path

LEVELS = ["Easy", "Moderate", "Hard", "Strenuous"]

SCHEMA = """
DROP TABLE IF EXISTS activities;
CREATE TABLE activities (
    id TEXT PRIMARY KEY, source TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
    difficulty INTEGER, difficulty_basis TEXT, lat REAL NOT NULL, lon REAL NOT NULL,
    miles REAL, duration TEXT, uses TEXT, place TEXT, url TEXT, description TEXT,
    license TEXT NOT NULL
);
"""

WORDS = [  # checked in order; the hardest word mentioned wins
    (3, re.compile(r"\b(strenuous|very difficult|extremely difficult|most difficult)\b", re.I)),
    (2, re.compile(r"\b(difficult|challenging|hard|steep|rugged)\b", re.I)),
    (1, re.compile(r"\b(moderate|moderately)\b", re.I)),
    (0, re.compile(r"\b(easy|flat|paved|accessible|stroll|leisurely|beginners?|family|kid-friendly)\b", re.I)),
]


def words_difficulty(text: str | None) -> int | None:
    if not text:
        return None
    for level, rx in WORDS:
        if rx.search(text):
            return level
    return None


# ---------------------------------------------------------------- USFS trails
def grade_pct(grade: str | None) -> float | None:
    """'12-20%' -> 16, '>20%' -> 25."""
    if not grade:
        return None
    nums = [float(n) for n in re.findall(r"\d+", grade)]
    if not nums:
        return None
    return 25.0 if ">" in grade or len(nums) == 1 and nums[0] >= 20 else sum(nums) / len(nums)


def trail_difficulty(cls: int | None, grade: str | None, miles: float) -> tuple[int | None, str]:
    """USFS trail class is development level (1 primitive … 5 paved), not difficulty.
    Start from class, then adjust for steepness and length."""
    parts = []
    if cls is None:
        base = None
    else:
        base = {1: 2, 2: 1, 3: 1, 4: 0, 5: 0}[cls]
        parts.append(f"trail class {cls} ({['', 'primitive', 'rough', 'developed', 'well developed', 'paved/fully developed'][cls]})")
    g = grade_pct(grade)
    if g is not None:
        parts.append(f"typical grade {grade}")
    if base is None and g is None:
        if miles <= 0:
            return None, "no grade or class data"
        base = 1
    base = base if base is not None else 1
    if g is not None:
        if g >= 15:
            base += 1
        elif g <= 5 and base > 0:
            base -= 1
    if miles >= 12:
        base += 2
    elif miles >= 7:
        base += 1
    elif miles < 1.5 and base > 0:
        base -= 1
    parts.append(f"{miles:.1f} mi")
    return max(0, min(3, base)), "Forest Service " + ", ".join(parts)


def trail_type(uses: set[str]) -> str:
    if uses & {"motorcycle", "atv", "4wd"} and "hike" not in uses:
        return "ohv"
    if "bike" in uses and "hike" not in uses:
        return "bike"
    if uses == {"horse"}:
        return "horse"
    return "hike"


def from_usfs_trails(path: Path) -> list[tuple]:
    rows = []
    if not path.exists():
        return rows
    with path.open() as fh:
        for t in csv.DictReader(fh):
            name = (t["name"] or "").strip()
            miles = float(t["miles"] or 0)
            if not name or miles < 0.2:
                continue
            uses = set(filter(None, t["uses"].split(";")))
            cls = int(t["trail_class_typical"]) if t["trail_class_typical"] else None
            diff, basis = trail_difficulty(cls, t["grade"], miles)
            if not name.lower().endswith(("trail", "trl", "loop", "route", "path")):
                name += " Trail"
            rows.append((
                f"usfs-trail:{t['trail_cn']}", "usfs", name, trail_type(uses), diff, basis,
                float(t["start_lat"]), float(t["start_lon"]), round(miles, 1), None,
                ";".join(sorted(uses)), f"Trail {t['trail_no']}" if t["trail_no"] else None,
                None, None, "cc-by-4.0",
            ))
    return rows


# ---------------------------------------------------------------- NPS things to do
NPS_TYPES = [  # first match on the activities list wins
    ("hike", ("hiking", "hike", "walking", "walk ", "backpacking", "running", "trail")),
    ("climb", ("climbing", "mountaineering", "bouldering", "canyoneering")),
    ("paddle", ("kayaking", "canoeing", "paddling", "boating", "tubing", "rafting", "stand up paddle")),
    ("bike", ("biking", "cycling")),
    ("swim", ("swimming", "snorkeling")),
    ("fish", ("fishing",)),
    ("horse", ("horse",)),
    ("snow", ("skiing", "snowshoeing", "snow")),
    ("scenic", ("scenic driving", "auto and atv", "stargazing", "wildlife watching", "birdwatching", "photography")),
    ("program", ("guided tours", "ranger", "junior ranger", "living history", "museum", "hands-on", "theater", "arts and culture")),
]
PHYSICAL = {"hike", "climb", "paddle", "bike", "swim", "horse", "snow"}


def duration_hours(text: str | None) -> float | None:
    if not text:
        return None
    nums = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", text)]
    if not nums:
        return None
    mid = (min(nums) + max(nums)) / 2  # "1-3 Hours" -> 2 h; the top of a range overstates effort
    t = text.lower()
    if "minute" in t:
        return mid / 60
    if "day" in t:
        return mid * 8
    return mid


def from_nps(conn: sqlite3.Connection) -> list[tuple]:
    rows = []
    q = """SELECT id, title, activities, duration, season, latitude, longitude, short_description,
                  url, park_codes FROM nps_things_to_do WHERE latitude IS NOT NULL AND longitude IS NOT NULL"""
    for aid, title, acts, duration, season, lat, lon, desc, url, parks in conn.execute(q):
        a = f"{acts or ''} {title or ''}".lower()
        typ = next((t for t, keys in NPS_TYPES if any(k in a for k in keys)), "other")
        diff = words_difficulty(f"{title} {desc}")
        basis = "described by the park" if diff is not None else None
        if diff is None and typ in PHYSICAL:
            h = duration_hours(duration)
            if h is not None:
                diff = 0 if h <= 1 else 1 if h <= 3 else 2 if h <= 6 else 3
                basis = f"estimated from duration ({duration})"
        rows.append((
            f"nps-todo:{aid}", "nps", title, typ, diff, basis, float(lat), float(lon), None,
            duration, None, (parks or "").upper().replace(";", ", ") or None, url, desc, "public-domain",
        ))
    return rows


# ---------------------------------------------------------------- USFS rec sites (non-trail)
USFS_TYPES = {
    "Lake and Pond Fishing": "fish", "River and Stream Fishing": "fish", "Fishing": "fish",
    "Boating - Non-Motorized": "paddle", "Boating - Motorized": "boat", "Swimming": "swim",
    "Mountain Climbing": "climb", "Rock Climbing": "climb", "Scenic Driving": "scenic",
    "Viewing Scenery": "scenic", "Viewing Wildlife": "scenic", "Interpretive Areas": "program",
    "OHV Trail Riding": "ohv", "OHV Road Riding": "ohv", "OHV Open Area Riding": "ohv",
    "Mountain Biking": "bike", "Horse Riding": "horse", "Hot Springs": "swim",
}


def from_usfs_sites(conn: sqlite3.Connection) -> list[tuple]:
    rows, seen = [], set()
    q = """SELECT recareaid, recareaname, markeractivity, forestname, latitude, longitude,
                  recareaurl, recareadescription FROM usfs_recreation"""
    for rid, name, act, forest, lat, lon, url, desc in conn.execute(q):
        typ = USFS_TYPES.get(act)
        if not typ or rid is None or lat is None or (rid, typ) in seen:
            continue
        seen.add((rid, typ))
        clean = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", desc or "")).strip() or None
        diff = words_difficulty(clean) if typ in PHYSICAL else None
        rows.append((
            f"usfs-site:{int(rid)}:{typ}", "usfs", name, typ, diff,
            "described by the Forest Service" if diff is not None else None,
            float(lat), float(lon), None, None, None, forest, url,
            clean[:600] if clean else None, "cc-by-4.0",
        ))
    return rows


def build_activities(conn: sqlite3.Connection, data_dir: Path) -> dict[str, int]:
    rows = from_usfs_trails(data_dir / "usfs_trails.csv") + from_nps(conn) + from_usfs_sites(conn)
    conn.executescript(SCHEMA)
    conn.executemany(f"INSERT OR IGNORE INTO activities VALUES ({','.join('?' * 15)})", rows)
    conn.executescript("""
        CREATE INDEX idx_activities_latlon ON activities(lat, lon);
        CREATE INDEX idx_activities_type ON activities(type);
        CREATE INDEX idx_activities_difficulty ON activities(difficulty);
    """)
    n = conn.execute("SELECT COUNT(*) FROM activities").fetchone()[0]
    return {"activities": n}
