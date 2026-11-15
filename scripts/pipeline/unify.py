"""
Build the canonical `campsites` table from the per-source tables in campsites.db.

Called by scripts/build_db.py after the raw tables are loaded. For every site it:
  * fixes coordinates (US longitudes missing their minus sign; drops 0/NULL coords)
  * assigns a state from its coordinates (Census boundaries, data/boundaries/us_states.json)
  * parses free/fee and amenities into one shape
  * merges the same place listed by several sources (NPS > Recreation.gov > USFS > BLM > OSM)

Stdlib only. Ratings scraped from Recreation.gov's search API are deliberately NOT copied
into this table (see data/README.md).
"""

from __future__ import annotations

import html
import json
import math
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

PRIORITY = {"nps": 5, "ridb": 4, "usfs": 3, "blm": 2, "osm": 1}
LICENSE = {"nps": "public-domain", "ridb": "public-domain", "blm": "public-domain",
           "usfs": "cc-by-4.0", "osm": "odbl"}

# Territories not in the Census 20m state file: (code, lat_min, lat_max, lon_min, lon_max)
TERRITORY_BOXES = [
    ("GU", 13.2, 13.7, 144.6, 145.0),
    ("MP", 14.0, 20.6, 144.8, 146.1),
    ("AS", -14.6, -11.0, -171.2, -168.1),
    ("VI", 17.6, 18.5, -65.1, -64.5),
]

MONEY = re.compile(r"\$\s?(\d+(?:\.\d{1,2})?)")
FREE_WORDS = re.compile(r"\b(free|no fees?|no charge|none)\b|\$0(?:\.00)?\b", re.I)
TAG = re.compile(r"<[^>]+>")
GENERIC = {"campground", "campgrounds", "camp", "camping", "site", "sites", "area", "rv", "park",
           "the", "and", "of", "group", "loop", "recreation", "dispersed", "cg", "primitive"}


# ---------------------------------------------------------------- text helpers
def strip_html(text: str | None) -> str | None:
    if not text:
        return None
    t = html.unescape(TAG.sub(" ", text))
    t = re.sub(r"\s+", " ", t).strip()
    return t or None


def parse_fee(text: str | None) -> tuple[bool | None, str | None]:
    """(free, fee_label) from free text like '$10 for campsite, $5 extra vehicle'."""
    t = strip_html(text)
    if not t:
        return None, None
    amounts = [float(a) for a in MONEY.findall(t)]
    paid = [a for a in amounts if a > 0]
    if paid:
        return False, f"${paid[0]:g}"  # first amount is almost always the per-site fee
    if FREE_WORDS.search(t):
        return True, None
    return None, None


def tidy_caps(name: str) -> str:
    """'BOUNTIFUL PEAK CAMPGROUND (UT)' -> 'Bountiful Peak Campground (UT)'. Keeps short codes."""
    small = {"and", "of", "the", "at", "on", "in", "to"}
    words = []
    for i, w in enumerate(name.split()):
        core = w.strip("()")
        if len(core) <= 3 and core.isalpha() and core in {"US", "NF", "NRA", "BLM", "RV", "CG", "OHV", "KOA", "UT", "AZ", "CA", "CO", "NM", "NV", "ID", "WY", "MT", "OR", "WA"}:
            words.append(w)
        elif i > 0 and w.lower() in small:
            words.append(w.lower())
        else:
            words.append(w.capitalize() if not w.startswith("(") else "(" + w[1:].capitalize())
    return " ".join(words)


def name_tokens(name: str | None) -> set[str]:
    words = re.findall(r"[a-z0-9]+", (name or "").lower())
    return {w for w in words if w not in GENERIC and len(w) > 1}


# ---------------------------------------------------------------- geometry
class StateLocator:
    def __init__(self, boundaries: Path):
        raw = json.loads(boundaries.read_text())["states"]
        self.states = []
        for code, rings in raw.items():
            xs = [p[0] for r in rings for p in r]
            ys = [p[1] for r in rings for p in r]
            self.states.append((code, min(xs), max(xs), min(ys), max(ys), rings))

    @staticmethod
    def _inside(x: float, y: float, rings) -> bool:
        inside = False
        for ring in rings:  # even-odd across all rings handles holes and islands
            j = len(ring) - 1
            for i in range(len(ring)):
                xi, yi = ring[i]
                xj, yj = ring[j]
                if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                    inside = not inside
                j = i
        return inside

    def locate(self, lat: float, lon: float, snap_deg: float = 0.15) -> str | None:
        for code, la, lb, ya, yb in TERRITORY_BOXES:
            if la <= lat <= lb and ya <= lon <= yb:
                return code
        for code, x0, x1, y0, y1, rings in self.states:
            if x0 <= lon <= x1 and y0 <= lat <= y1 and self._inside(lon, lat, rings):
                return code
        # Beach and lakeshore sites often sit just outside the generalized coastline.
        best, best_d = None, snap_deg
        for code, x0, x1, y0, y1, rings in self.states:
            if not (x0 - snap_deg <= lon <= x1 + snap_deg and y0 - snap_deg <= lat <= y1 + snap_deg):
                continue
            for ring in rings:
                for px, py in ring:
                    d = math.hypot((px - lon) * math.cos(math.radians(lat)), py - lat)
                    if d < best_d:
                        best, best_d = code, d
        return best


def fix_coords(lat, lon) -> tuple[float, float] | None:
    if lat is None or lon is None:
        return None
    lat, lon = float(lat), float(lon)
    if lat == 0 or lon == 0:
        return None
    pacific = lat < 25 and lon > 140          # Guam / Northern Mariana Islands
    aleutians = lat > 50 and lon > 170        # Alaska west of the antimeridian
    if lon > 0 and not pacific and not aleutians:
        lon = -lon                            # common data-entry error: missing minus sign
    return lat, lon


def dist_m(a_lat, a_lon, b_lat, b_lon) -> float:
    k = math.pi / 180
    x = (b_lon - a_lon) * k * math.cos((a_lat + b_lat) * k / 2)
    return 6371000 * math.hypot(x, (b_lat - a_lat) * k)


# ---------------------------------------------------------------- per-source readers
def site(**kw) -> dict:
    base = dict(free=None, fee=None, reservable=False, agency=None, url=None, phone=None,
                description=None, amenities=set(), max_rig_ft=None, opening_hours=None,
                stay_limit=None, capacity=None, cell=None)
    base.update(kw)
    return base


CELL = {"Yes - year round": "year-round", "Yes - seasonal": "seasonal", "No": "none"}


def from_nps(raw_json: Path) -> list[dict]:
    out = []
    for c in json.loads(raw_json.read_text())["data"]:
        am = c.get("amenities") or {}
        a = set()
        if any(w in s for s in am.get("toilets", []) for w in ("Flush", "Vault", "Portable")):
            a.add("toilets")
        if any(s.startswith("Yes") for s in am.get("potableWater", [])):
            a.add("water")
        if any(s.startswith("Yes") for s in am.get("showers", [])):
            a.add("showers")
        if str(am.get("dumpStation", "")).startswith("Yes"):
            a.add("dump")
        sites_ = c.get("campsites") or {}
        if float(sites_.get("electricalHookups") or 0) > 0:
            a.add("electric")
        if float(sites_.get("tentOnly") or 0) > 0:
            a.add("tents")
        acc = c.get("accessibility") or {}
        rv_len = float(acc.get("rvMaxLength") or 0)
        if acc.get("rvAllowed") == "1" or rv_len > 0:
            a.add("rv")
        costs = [float(f["cost"]) for f in c.get("fees") or [] if re.fullmatch(r"\d+(\.\d+)?", str(f.get("cost", "")))]
        phones = [p["phoneNumber"] for ct in [c.get("contacts") or {}] for p in ct.get("phoneNumbers", []) if p.get("phoneNumber")]
        out.append(site(
            id=f"nps:{c['id']}", source="nps", name=c.get("name"), kind="campground",
            lat=c.get("latitude") or None, lon=c.get("longitude") or None,
            free=(max(costs) == 0) if costs else None,
            fee=f"${min(costs):g}" if costs and max(costs) > 0 else None,
            reservable=bool(c.get("reservationUrl")),
            agency=f"National Park Service · {c.get('parkCode', '').upper()}",
            url=c.get("reservationUrl") or c.get("url"), phone=phones[0] if phones else None,
            description=strip_html(c.get("description")), amenities=a,
            max_rig_ft=rv_len or None, capacity=int(float(sites_.get("totalSites") or 0)) or None,
            cell=CELL.get(am.get("cellPhoneReception") or ""),
        ))
    return out


def from_ridb(conn: sqlite3.Connection) -> list[dict]:
    out = []
    q = """SELECT source_id, name, agency, latitude, longitude, reservable, price_min, price_max,
                  price_unit, max_vehicle_length_ft, equipment_allowed, campsites_count, official_url
           FROM recreation_gov WHERE entity_type = 'campground'"""
    for sid, name, agency, lat, lon, res, pmin, pmax, unit, rig, equip, cap, url in conn.execute(q):
        a = set()
        e = (equip or "").lower()
        if "tent" in e:
            a.add("tents")
        if any(w in e for w in ("rv", "trailer", "fifth wheel")):
            a.add("rv")
        fee = None
        if pmax:
            lo, hi = pmin or pmax, pmax
            # The max usually includes group sites, so show the starting price.
            fee = f"${lo:g}" + ("+" if hi > lo else "") + (f"/{unit}" if unit else "")
        out.append(site(
            id=f"ridb:{int(sid)}", source="ridb", name=name, kind="campground", lat=lat, lon=lon,
            free=(pmax == 0) if pmax is not None else None, fee=fee,
            reservable=str(res) == "True", agency=agency, url=url, amenities=a,
            max_rig_ft=rig or None, capacity=int(cap) if cap else None,
        ))
    return out


USFS_CAMPING = {"Campground Camping", "Dispersed Camping", "Group Camping", "RV Camping",
                "Horse Camping", "OHV Camping"}


def from_usfs(conn: sqlite3.Connection) -> list[dict]:
    by_id: dict[int, dict] = {}
    q = """SELECT recareaid, recareaname, markeractivity, forestname, latitude, longitude,
                  open_season_start, open_season_end, feedescription, reservation_info,
                  recareaurl, recareadescription
           FROM usfs_recreation"""
    for rid, name, act, forest, lat, lon, s0, s1, fee_t, res, url, desc in conn.execute(q):
        if act not in USFS_CAMPING or rid is None:
            continue
        rid = int(rid)
        s = by_id.get(rid)
        if s is None:
            free, fee = parse_fee(fee_t)
            season = f"{s0} – {s1}" if s0 and s1 else None
            s = by_id[rid] = site(
                id=f"usfs:{rid}", source="usfs", name=name, kind="dispersed", lat=lat, lon=lon,
                free=free, fee=fee, reservable=bool(strip_html(res)),
                agency=f"USDA Forest Service · {forest}" if forest else "USDA Forest Service",
                url=url, description=strip_html(desc), opening_hours=season, activities=set(),
            )
        s["activities"].add(act)
    for s in by_id.values():
        acts = s.pop("activities")
        if acts != {"Dispersed Camping"}:
            s["kind"] = "campground"
        if "RV Camping" in acts:
            s["amenities"].add("rv")
    return list(by_id.values())


def from_blm(conn: sqlite3.Connection) -> list[dict]:
    out = []
    q = """SELECT source_id, name, latitude, longitude, stay_limit, fee_description,
                  reservation_url, blm_url, phone, description FROM blm_camping"""
    for sid, name, lat, lon, stay, fee_t, res_url, url, phone, desc in conn.execute(q):
        free, fee = parse_fee(fee_t)
        developed = re.search(r"campground|rv park|recreation site|\bcg\b", name or "", re.I)
        out.append(site(
            id=f"blm:{int(sid)}", source="blm", name=name,
            kind="campground" if developed or fee else "dispersed", lat=lat, lon=lon,
            free=free, fee=fee, reservable=bool(res_url), agency="Bureau of Land Management",
            url=url or res_url, phone=phone, description=strip_html(desc),
            stay_limit=strip_html(stay),
        ))
    return out


def from_osm(conn: sqlite3.Connection) -> list[dict]:
    out = []
    q = """SELECT osm_type, osm_id, name, camp_site, fee, fee_raw, access, capacity, max_stay,
                  opening_hours, operator, latitude, longitude, toilets, drinking_water, shower,
                  power_supply, dump_station, picnic_table, fire_pit, website, phone, description
           FROM osm_camp_sites"""
    for (otype, oid, name, cs, fee, fee_raw, access, cap, max_stay, hours, operator, lat, lon,
         toilets, water, shower, power, dump, picnic, fire, web, phone, desc) in conn.execute(q):
        if access in ("private", "no"):
            continue
        a = set()
        if toilets in ("yes", "vault", "pit", "flush"):
            a.add("toilets")
        if water in ("yes", "seasonal", "pump"):
            a.add("water")
        if shower in ("yes", "hot", "fee", "seasonal"):
            a.add("showers")
        if power not in (None, "no"):
            a.add("electric")
        if dump in ("yes", "customers", "seasonal"):
            a.add("dump")
        if picnic == "yes":
            a.add("picnic_table")
        if fire == "yes":
            a.add("fire_ring")
        informal = not name and not operator and fee != "fee"
        if cs in ("serviced", "deluxe", "standard"):
            kind = "campground"
        elif informal or (cs == "basic" and fee == "free") or re.search(r"dispersed|boondock", name or "", re.I):
            kind = "dispersed"
        else:
            kind = "campground"
        fee_label = fee_raw if fee_raw and re.match(r"[$\d]", fee_raw) else None
        out.append(site(
            id=f"osm:{otype[0]}{int(oid)}", source="osm",
            name=name or ("Dispersed site" if kind == "dispersed" else "Unnamed campsite"),
            kind=kind, lat=lat, lon=lon,
            free=True if fee == "free" else False if fee == "fee" else None, fee=fee_label,
            agency=operator, url=web, phone=phone, description=strip_html(desc), amenities=a,
            opening_hours=hours, stay_limit=max_stay,
            capacity=int(cap) if cap and str(cap).isdigit() else None,
            unnamed=not name,
        ))
    return out


# ---------------------------------------------------------------- merge
def merge(sites: list[dict]) -> list[dict]:
    """Collapse the same place listed by several sources. Higher-priority sources win;
    lower ones contribute amenities and fill blank fields."""
    cell = 0.005  # ~500 m grid
    grid: dict[tuple[int, int], list[dict]] = defaultdict(list)
    kept = []
    sites.sort(key=lambda s: -PRIORITY[s["source"]])
    for s in sites:
        gx, gy = int(s["lon"] / cell), int(s["lat"] / cell)
        tokens = name_tokens(s["name"]) if not s.get("unnamed") else set()
        match = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for k in grid[(gx + dx, gy + dy)]:
                    d = dist_m(s["lat"], s["lon"], k["lat"], k["lon"])
                    kt = k["_tokens"]
                    similar = bool(tokens and kt) and len(tokens & kt) / len(tokens | kt) >= 0.5
                    if k["source"] == s["source"]:
                        # Same source: only obvious re-listings (same name, same spot).
                        if d < 50 and similar:
                            match = k
                            break
                        continue
                    if d < 150 or (d < 500 and similar):
                        match = k
                        break
                if match:
                    break
            if match:
                break
        if match:
            match["amenities"] |= s["amenities"]
            match["also_in"].append(s["id"])
            for f in ("free", "fee", "url", "phone", "description", "max_rig_ft",
                      "opening_hours", "stay_limit", "capacity", "cell"):
                if match[f] is None and s[f] is not None:
                    match[f] = s[f]
            if match["kind"] == "campground" and s["kind"] == "dispersed" and match["source"] == "osm":
                match["kind"] = "dispersed"
            continue
        s["_tokens"] = tokens
        s["also_in"] = []
        grid[(gx, gy)].append(s)
        kept.append(s)
    return kept


SCHEMA = """
DROP TABLE IF EXISTS campsites;
CREATE TABLE campsites (
    id TEXT PRIMARY KEY, source TEXT NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL,
    lat REAL NOT NULL, lon REAL NOT NULL, state TEXT,
    free INTEGER, fee TEXT, reservable INTEGER NOT NULL,
    agency TEXT, url TEXT, phone TEXT, description TEXT,
    amenities TEXT NOT NULL, max_rig_ft REAL, opening_hours TEXT, stay_limit TEXT,
    capacity INTEGER, also_in TEXT NOT NULL, license TEXT NOT NULL,
    cell TEXT  -- official cell reception note (NPS): 'year-round' | 'seasonal' | 'none'
);
"""


def build_campsites(conn: sqlite3.Connection, data_dir: Path) -> dict[str, int]:
    locator = StateLocator(data_dir / "boundaries" / "us_states.json")
    raw: list[dict] = []
    if (data_dir / "nps_campgrounds_raw.json").exists():
        raw += from_nps(data_dir / "nps_campgrounds_raw.json")
    raw += from_ridb(conn) + from_usfs(conn) + from_blm(conn) + from_osm(conn)

    stats = defaultdict(int)
    located = []
    for s in raw:
        fixed = fix_coords(s["lat"], s["lon"])
        if fixed is None:
            stats["dropped_no_coords"] += 1
            continue
        if fixed[1] != float(s["lon"]):
            stats["fixed_longitude"] += 1
        s["lat"], s["lon"] = round(fixed[0], 6), round(fixed[1], 6)
        s["state"] = locator.locate(*fixed)
        if s["state"] is None:
            stats["dropped_outside_us"] += 1
            continue
        if not s["name"]:
            s["name"] = "Unnamed campsite"
        elif s["name"].isupper():
            s["name"] = tidy_caps(s["name"])
        located.append(s)

    kept = merge(located)
    stats["merged_duplicates"] = len(located) - len(kept)
    conn.executescript(SCHEMA)
    conn.executemany(
        "INSERT INTO campsites VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [(s["id"], s["source"], s["name"], s["kind"], s["lat"], s["lon"], s["state"],
          None if s["free"] is None else int(s["free"]), s["fee"], int(bool(s["reservable"])),
          s["agency"], s["url"], s["phone"], s["description"],
          json.dumps(sorted(s["amenities"])), s["max_rig_ft"], s["opening_hours"], s["stay_limit"],
          s["capacity"], json.dumps(s["also_in"]), LICENSE[s["source"]], s["cell"]) for s in kept],
    )
    conn.executescript("""
        CREATE INDEX idx_campsites_state ON campsites(state);
        CREATE INDEX idx_campsites_kind ON campsites(kind);
        CREATE INDEX idx_campsites_source ON campsites(source);
        CREATE INDEX idx_campsites_latlon ON campsites(lat, lon);
    """)
    stats["campsites"] = len(kept)
    return dict(stats)
