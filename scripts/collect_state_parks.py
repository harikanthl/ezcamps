#!/usr/bin/env python3
"""
Build a verified 50-state table of state park agencies and reservation platforms.

Checks each official URL (HTTP status, final URL) and scans the returned HTML
for reservation-platform fingerprints. Output is a snapshot: platforms change,
so the official URL is always the source of truth.

Output: data/state_park_systems.csv
"""

from __future__ import annotations

import csv
import re
import ssl
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0 Safari/537.36"

# state, agency, official URL, known caveat
STATES = [
    ("AL", "Alabama State Parks", "https://www.alapark.com", ""),
    ("AK", "Alaska State Parks (DNR)", "https://dnr.alaska.gov/parks/", "Public-use cabins book on a separate state system."),
    ("AZ", "Arizona State Parks & Trails", "https://azstateparks.com", ""),
    ("AR", "Arkansas State Parks", "https://www.arkansasstateparks.com", ""),
    ("CA", "California State Parks", "https://www.parks.ca.gov", "Own system: ReserveCalifornia."),
    ("CO", "Colorado Parks & Wildlife", "https://cpw.state.co.us/state-parks", ""),
    ("CT", "Connecticut State Parks (DEEP)", "https://portal.ct.gov/deep/state-parks", ""),
    ("DE", "Delaware State Parks", "https://www.destateparks.com", ""),
    ("FL", "Florida State Parks", "https://www.floridastateparks.org", ""),
    ("GA", "Georgia State Parks & Historic Sites", "https://gastateparks.org", ""),
    ("HI", "Hawaii State Parks (DLNR)", "https://dlnr.hawaii.gov/dsp/", "Some parks/cabins use separate permit systems."),
    ("ID", "Idaho State Parks & Recreation", "https://parksandrecreation.idaho.gov", ""),
    ("IL", "Illinois State Parks (DNR)", "https://dnr.illinois.gov/parks.html", ""),
    ("IN", "Indiana State Parks (DNR)", "https://www.in.gov/dnr/state-parks/", ""),
    ("IA", "Iowa State Parks (DNR)", "https://www.iowadnr.gov/places-to-go/state-parks", ""),
    ("KS", "Kansas State Parks", "https://ksoutdoors.com/State-Parks", ""),
    ("KY", "Kentucky State Parks", "https://parks.ky.gov", ""),
    ("LA", "Louisiana State Parks", "https://www.lastateparks.com", ""),
    ("ME", "Maine State Parks (DACF)", "https://www.maine.gov/dacf/parks/", ""),
    ("MD", "Maryland State Parks (DNR)", "https://dnr.maryland.gov/publiclands/Pages/stateparks.aspx", ""),
    ("MA", "Massachusetts State Parks (DCR)", "https://www.mass.gov/orgs/department-of-conservation-recreation", ""),
    ("MI", "Michigan State Parks (DNR)", "https://www.michigan.gov/dnr/places/state-parks", "Own system: midnrreservations.com."),
    ("MN", "Minnesota State Parks (DNR)", "https://www.dnr.state.mn.us/state_parks/", "Own system via US eDirect."),
    ("MS", "Mississippi State Parks (MDWFP)", "https://www.mdwfp.com/parks-destinations/", ""),
    ("MO", "Missouri State Parks", "https://mostateparks.com", ""),
    ("MT", "Montana State Parks (FWP)", "https://stateparks.mt.gov", ""),
    ("NE", "Nebraska State Parks (Game & Parks)", "https://outdoornebraska.gov/stateparks/", ""),
    ("NV", "Nevada State Parks", "https://parks.nv.gov", ""),
    ("NH", "New Hampshire State Parks", "https://www.nhstateparks.org", ""),
    ("NJ", "New Jersey State Parks (DEP)", "https://www.nj.gov/dep/parksandforests/", ""),
    ("NM", "New Mexico State Parks", "https://www.emnrd.nm.gov/spd/", ""),
    ("NY", "New York State Parks", "https://parks.ny.gov", ""),
    ("NC", "North Carolina State Parks", "https://www.ncparks.gov", ""),
    ("ND", "North Dakota Parks & Recreation", "https://www.parkrec.nd.gov", ""),
    ("OH", "Ohio State Parks (DNR)", "https://ohiodnr.gov/discover-and-learn/parks", ""),
    ("OK", "Oklahoma State Parks", "https://www.travelok.com/state-parks", ""),
    ("OR", "Oregon State Parks", "https://stateparks.oregon.gov", ""),
    ("PA", "Pennsylvania State Parks (DCNR)", "https://www.dcnr.pa.gov/StateParks/", ""),
    ("RI", "Rhode Island State Parks (DEM)", "https://riparks.com", ""),
    ("SC", "South Carolina State Parks", "https://southcarolinaparks.com", ""),
    ("SD", "South Dakota State Parks (GFP)", "https://gfp.sd.gov/state-parks/", ""),
    ("TN", "Tennessee State Parks", "https://tnstateparks.com", ""),
    ("TX", "Texas State Parks (TPWD)", "https://tpwd.texas.gov/state-parks/", ""),
    ("UT", "Utah State Parks", "https://stateparks.utah.gov", ""),
    ("VT", "Vermont State Parks", "https://vtstateparks.com", ""),
    ("VA", "Virginia State Parks (DCR)", "https://www.dcr.virginia.gov/state-parks", ""),
    ("WA", "Washington State Parks", "https://parks.wa.gov", ""),
    ("WV", "West Virginia State Parks", "https://wvstateparks.com", ""),
    ("WI", "Wisconsin State Parks (DNR)", "https://dnr.wisconsin.gov/topic/parks", ""),
    ("WY", "Wyoming State Parks & Cultural Resources", "https://wyoparks.wyo.gov", ""),
]

SIGNATURES = [
    ("reserveamerica.com", "ReserveAmerica (Aspira)"),
    ("recreation.gov", "Recreation.gov"),
    ("usedirect.com", "US eDirect"),
    ("goingtocamp.com", "GoingToCamp"),
    ("reservecalifornia.com", "ReserveCalifornia"),
    ("midnrreservations.com", "Michigan DNR (own)"),
    ("campingroadtrip.com", "Other"),
]


def check(row):
    state, agency, url, note = row
    status, final, platform = "", url, ""
    try:
        ctx = ssl.create_default_context()
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=25, context=ctx) as r:
            final = r.geturl()
            status = str(r.status)
            html = r.read(400_000).decode("utf-8", "ignore").lower()
        for needle, label in SIGNATURES:
            if needle in html:
                platform = label
                break
    except Exception as exc:  # noqa: BLE001
        status = f"ERR:{type(exc).__name__}"
    return {
        "state": state,
        "agency": agency,
        "official_url": final,
        "http_status": status,
        "reservation_platform_detected": platform,
        "notes": note,
    }


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        rows = list(pool.map(check, STATES))
    with (DATA / "state_park_systems.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    ok = sum(1 for r in rows if r["http_status"] == "200")
    print(f"wrote 50 states ({ok} returned HTTP 200, rest blocked/slow)")
    for r in rows:
        print(f"  {r['state']} {r['http_status']:>4} {r['reservation_platform_detected'] or '-':<24} {r['official_url']}")


if __name__ == "__main__":
    main()
