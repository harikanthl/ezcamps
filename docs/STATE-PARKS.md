# State Park Systems — 50-State Directory

_Generated from `data/state_park_systems.csv` on 2026-11-15. Re-run `scripts/collect_state_parks.py` then `scripts/render_state_parks.py` to refresh._

**50 states** · **31 returned HTTP 200** from this build environment. Most of the rest return 403 to scripted clients but are valid official sites. Always treat the official URL as the source of truth.

## Reservation platform summary

| Platform | States detected |
|---|---:|
| No fingerprint | 19 |
| ReserveAmerica (Aspira) | 9 |
| US eDirect | 1 |
| ReserveCalifornia | 1 |
| GoingToCamp | 1 |

> Detection is a best-effort scan of each homepage for platform fingerprints. `No fingerprint` means the fetched page did not expose a platform string — not that no reservation system exists. Blocked pages are excluded from this summary. Several states run separate systems for cabins, permits or lotteries.

## Directory

| State | Agency | Official site | Site status | Reservation platform detected | Notes |
|---|---|---|---|---|---|
| **AL** | Alabama State Parks | <https://www.alapark.com> | 200 OK | — |  |
| **AK** | Alaska State Parks (DNR) | <https://dnr.alaska.gov/parks/> | 200 OK | — | Public-use cabins book on a separate state system. |
| **AZ** | Arizona State Parks & Trails | <https://azstateparks.com> | 200 OK | US eDirect |  |
| **AR** | Arkansas State Parks | <https://www.arkansasstateparks.com> | blocked/slow: HTTPError | — |  |
| **CA** | California State Parks | <https://www.parks.ca.gov> | 200 OK | ReserveCalifornia | Own system: ReserveCalifornia. |
| **CO** | Colorado Parks & Wildlife | <https://cpw.state.co.us/state-parks> | 200 OK | — |  |
| **CT** | Connecticut State Parks (DEEP) | <https://portal.ct.gov/deep/state-parks> | 200 OK | — |  |
| **DE** | Delaware State Parks | <https://www.destateparks.com> | 200 OK | ReserveAmerica (Aspira) |  |
| **FL** | Florida State Parks | <https://www.floridastateparks.org> | 200 OK | — |  |
| **GA** | Georgia State Parks & Historic Sites | <https://gastateparks.org> | blocked/slow: HTTPError | — |  |
| **HI** | Hawaii State Parks (DLNR) | <https://dlnr.hawaii.gov/dsp/> | blocked/slow: HTTPError | — | Some parks/cabins use separate permit systems. |
| **ID** | Idaho State Parks & Recreation | <https://parksandrecreation.idaho.gov> | 200 OK | — |  |
| **IL** | Illinois State Parks (DNR) | <https://dnr.illinois.gov/parks.html> | 200 OK | — |  |
| **IN** | Indiana State Parks (DNR) | <https://www.in.gov/dnr/state-parks/> | blocked/slow: URLError | — |  |
| **IA** | Iowa State Parks (DNR) | <https://www.iowadnr.gov/places-go/state-parks> | 200 OK | ReserveAmerica (Aspira) |  |
| **KS** | Kansas State Parks | <https://ksoutdoors.com/State-Parks> | blocked/slow: HTTPError | — |  |
| **KY** | Kentucky State Parks | <https://parks.ky.gov> | 200 OK | — |  |
| **LA** | Louisiana State Parks | <https://www.lastateparks.com> | blocked/slow: HTTPError | — |  |
| **ME** | Maine State Parks (DACF) | <https://www.maine.gov/dacf/parks/> | 202 | — |  |
| **MD** | Maryland State Parks (DNR) | <https://dnr.maryland.gov/publiclands/Pages/stateparks.aspx> | blocked/slow: HTTPError | — |  |
| **MA** | Massachusetts State Parks (DCR) | <https://www.mass.gov/orgs/department-of-conservation-recreation> | blocked/slow: HTTPError | — |  |
| **MI** | Michigan State Parks (DNR) | <https://www.michigan.gov/dnr/places/state-parks> | blocked/slow: HTTPError | — | Own system: midnrreservations.com. |
| **MN** | Minnesota State Parks (DNR) | <https://www.dnr.state.mn.us/state_parks/> | blocked/slow: HTTPError | — | Own system via US eDirect. |
| **MS** | Mississippi State Parks (MDWFP) | <https://www.mdwfp.com/parks-destinations> | 200 OK | — |  |
| **MO** | Missouri State Parks | <https://mostateparks.com> | blocked/slow: HTTPError | — |  |
| **MT** | Montana State Parks (FWP) | <https://fwp.mt.gov/stateparks/> | 200 OK | ReserveAmerica (Aspira) |  |
| **NE** | Nebraska State Parks (Game & Parks) | <https://outdoornebraska.gov/stateparks/> | blocked/slow: HTTPError | — |  |
| **NV** | Nevada State Parks | <https://parks.nv.gov> | 200 OK | — |  |
| **NH** | New Hampshire State Parks | <https://www.nhstateparks.org> | 200 OK | ReserveAmerica (Aspira) |  |
| **NJ** | New Jersey State Parks (DEP) | <https://www.nj.gov/dep/parksandforests/> | 200 OK | — |  |
| **NM** | New Mexico State Parks | <https://www.emnrd.nm.gov/spd/> | 200 OK | ReserveAmerica (Aspira) |  |
| **NY** | New York State Parks | <https://parks.ny.gov> | blocked/slow: HTTPError | — |  |
| **NC** | North Carolina State Parks | <https://www.ncparks.gov> | 200 OK | ReserveAmerica (Aspira) |  |
| **ND** | North Dakota Parks & Recreation | <https://www.parkrec.nd.gov> | 200 OK | — |  |
| **OH** | Ohio State Parks (DNR) | <https://ohiodnr.gov/discover-and-learn/parks> | 200 OK | — |  |
| **OK** | Oklahoma State Parks | <https://www.travelok.com/state-parks> | 200 OK | — |  |
| **OR** | Oregon State Parks | <https://stateparks.oregon.gov> | 200 OK | ReserveAmerica (Aspira) |  |
| **PA** | Pennsylvania State Parks (DCNR) | <https://www.pa.gov/agencies/dcnr> | 200 OK | ReserveAmerica (Aspira) |  |
| **RI** | Rhode Island State Parks (DEM) | <https://riparks.com> | blocked/slow: HTTPError | — |  |
| **SC** | South Carolina State Parks | <https://southcarolinaparks.com> | blocked/slow: URLError | — |  |
| **SD** | South Dakota State Parks (GFP) | <https://gfp.sd.gov/parks/> | 200 OK | — |  |
| **TN** | Tennessee State Parks | <https://tnstateparks.com> | 200 OK | — |  |
| **TX** | Texas State Parks (TPWD) | <https://tpwd.texas.gov/state-parks/> | 200 OK | ReserveAmerica (Aspira) |  |
| **UT** | Utah State Parks | <https://stateparks.utah.gov> | blocked/slow: HTTPError | — |  |
| **VT** | Vermont State Parks | <https://www.vtstateparks.com/> | 200 OK | — |  |
| **VA** | Virginia State Parks (DCR) | <https://www.dcr.virginia.gov/state-parks> | blocked/slow: HTTPError | — |  |
| **WA** | Washington State Parks | <https://parks.wa.gov> | 200 OK | GoingToCamp |  |
| **WV** | West Virginia State Parks | <https://wvstateparks.com> | 200 OK | — |  |
| **WI** | Wisconsin State Parks (DNR) | <https://dnr.wisconsin.gov/topic/parks> | blocked/slow: URLError | — |  |
| **WY** | Wyoming State Parks & Cultural Resources | <https://wyoparks.wyo.gov> | 200 OK | — |  |

## What to collect per state

For each state park system, the useful fields are:

- Park and campground names, coordinates, season and fees
- Site types: tent, RV, cabin, yurt, group, equestrian
- Hookups, showers, dump station, potable water, cell signal
- Pet rules, quiet hours, generator hours, fire rules
- Out-of-state surcharges and discount passes
- Reservation window, cancellation policy and lottery parks
- Dispersed/WMA camping rules (often a different agency)

## Highest-value states to adapt first

Ranked by inventory, camping culture and Recreation.gov/ReserveAmerica coverage:

1. California — 980 Recreation.gov listings; own ReserveCalifornia system
2. Oregon — 689 listings; ReserveAmerica
3. Utah — 674 listings; ReserveAmerica
4. Colorado — 486 listings; mixed platforms
5. Idaho — 458 listings; large dispersed-camping culture
6. Montana — 373 listings; ReserveAmerica
7. Arizona — 319 listings; snowbird/LTVA market
8. Washington — 304 listings; GoingToCamp
9. Texas — large state park system; ReserveAmerica
10. Florida — large snowbird/coastal market; ReserveAmerica
