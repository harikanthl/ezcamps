# CampSitesUSA

A SwiftUI + SwiftData multiplatform app for finding and planning campsites across the United States — with a focus on **open data**, **public land**, and **free/dispersed camping**.

The repo currently contains two things:

1. The native SwiftUI app (`CampSitesUSA/`, `CampSitesUSA.xcodeproj/`) — map explorer, filters, site detail, saved sites, visit ratings and trip planning.
2. A researched, reproducible **data catalog** of campsites, parks and supporting layers (`docs/`, `data/`, `scripts/`).

## Start with the catalog

| Document | What it covers |
|---|---|
| [`docs/CATALOG.md`](docs/CATALOG.md) | Master catalog: federal, state, free, private, amenities, conditions, activities, licensing, build order |
| [`docs/FREECAMPSITES.md`](docs/FREECAMPSITES.md) | freecampsites.net schema, JSON endpoint, data quality, terms and a legal integration plan |
| [`docs/STATE-PARKS.md`](docs/STATE-PARKS.md) | All 50 state park systems with verified links and reservation platforms |
| [`docs/PARKS.md`](docs/PARKS.md) | All 475 National Park System units by state, with fees and activities |
| [`docs/FREE-CAMPING-RULES.md`](docs/FREE-CAMPING-RULES.md) | BLM/USFS/NPS/state rules, stay limits, fire restrictions, overnight parking |
| [`docs/API-NOTES.md`](docs/API-NOTES.md) | Verified endpoints, page limits, quirks and scraping etiquette |
| [`data/README.md`](data/README.md) | Data dictionary for every collected file |
| [`docs/RESEARCH.md`](docs/RESEARCH.md) | Product/feature research and suggested architecture |
| [`data/sources.json`](data/sources.json) | 78 sources, machine-readable |

## Data already collected

| Dataset | Rows | File |
|---|---:|---|
| Recreation.gov camping listings | 7,549 | `data/recreation_gov_camping.csv` |
| NPS park units | 475 | `data/nps_parks.csv` |
| NPS campgrounds | 665 | `data/nps_campgrounds.csv` |
| NPS alerts | 622 | `data/nps_alerts.csv` |
| NPS things to do | 3,576 | `data/nps_things_to_do.csv` |
| BLM camping points | 539 | `data/blm_camping.csv` |
| USFS recreation opportunities | 14,211 | `data/usfs_recreation_sites.csv` |
| OSM campsites (US) | 23,843 | `data/osm_camp_sites.csv` |
| OSM dump stations | 1,697 | `data/osm_dump_stations.csv` |
| OSM rest areas | 2,477 | `data/osm_rest_areas.csv` |
| State park systems | 50 | `data/state_park_systems.csv` |
| Unified database | — | `data/campsites.db`: not in git; download with `python3 -I scripts/fetch_db.py` ([data releases](https://github.com/harikanthl/ezcamps/releases)) |

The SQLite database has one table per source plus an `all_campsites` view with a shared schema:

```sql
SELECT source, name, state, latitude, longitude, capacity, max_rig_ft
FROM all_campsites
WHERE state = 'Colorado' AND max_rig_ft >= 30
ORDER BY rating DESC
LIMIT 20;
```

## Rebuild the data

```bash
export NPS_API_KEY=...                      # or leave unset for DEMO_KEY
python3 scripts/collect_nps.py              # alerts, things to do, visitor centers, webcams
python3 scripts/collect_recreation_gov.py   # ~2 min, 16 pages
python3 scripts/collect_usfs.py             # resumable; EDW resets long connections
python3 scripts/collect_blm.py              # 539 camping points
python3 scripts/collect_osm.py              # Overpass: campsites, dump stations, rest areas
python3 scripts/clean_osm.py                # normalize campsites
python3 scripts/clean_osm_amenities.py      # normalize dump stations + rest areas
python3 scripts/clean_nps.py                # requires data/nps_*_raw.json
python3 scripts/collect_state_parks.py
python3 scripts/render_state_parks.py
python3 scripts/build_db.py
python3 -I scripts/publish_db.py            # publish data/campsites.db as a data-YYYY-MM-DD release

# App bundle: exports the canonical `campsites` table (all states) to CampSitesUSA/Resources/sites.json
python3 -I scripts/pipeline/export_app.py
```

NPS raw files were fetched with the public API (`DEMO_KEY`); for production, get a free key at <https://developer.nps.gov/signup>.

## Licensing

The collectors respect source licenses at the data level, but **not every source can be redistributed**:

- **Public domain:** NPS, RIDB, BLM, USACE, BOR, FWS, NOAA, USGS, FCC, FEMA, Census.
- **CC BY 4.0:** USFS EDW (attribute).
- **ODbL:** OpenStreetMap (attribute + share-alike).
- **Proprietary:** freecampsites.net, iOverlander, Campendium, The Dyrt, Hipcamp, AllStays, KOA, ReserveAmerica — **link out, do not scrape**.

See [`docs/CATALOG.md#11-licensing-matrix`](docs/CATALOG.md#11-licensing-matrix) for the full matrix.

## App status

The app is implemented as a SwiftUI + SwiftData multiplatform project:

- **Explore** — MapKit map with clustered pins, free/type/amenity filters and search. Dispersed sites are hidden until the Dispersed chip is tapped, and bare placeholder points (no name, fee or amenities) only appear when zoomed in to ~25 km.
- **Map styles** — Standard (Apple, 3D terrain, nature landmarks such as parks, beaches, trailheads and climbing areas; no shops or restaurants), Satellite, and **Topo** (USGS The National Map: contour lines, peak elevations, streams, springs, falls, glaciers, forest roads and trails).
- **Public lands + "Can I camp here?"** — toggleable land-manager overlay (BLM Surface Management Agency tiles, public domain) with a legend. Long-press anywhere to look up the manager (BLM, USFS, NPS, state, tribal, private…) and get a likely yes / check rules / likely no answer with the usual rules.
- **Site detail** — fee/price label, amenities, agency, source attribution, links and phone.
- **Things to do nearby** — trails and activities within 25 mi of each site, ranked easiest first (Easy / Moderate / Hard / Strenuous) with a filter per level. Every grade says where it came from: Forest Service trail class + grade + length, the park's own wording, or an estimate from duration. Built by `scripts/pipeline/activities.py` from USFS trails (`scripts/collect_usfs_trails.py`), NPS things-to-do and USFS recreation sites.
- **Saved** — SwiftData-backed saved sites.
- **Visits** — 1–5 star ratings, quick tags, notes, and location-verified check-ins (`Visit.verifyRadius = 500 m`) as the seed for trusted community ratings.
- **Trips** — plan From → To with a daily driving budget; overnight camps are suggested along the route (even days, named camps, free first). Day-by-day itinerary with swap/add/reorder, slow or seasonal road warnings, and **nearest gas, groceries and hospital** for every camp (Apple Maps search; also shown on the trip map with the Services toggle).
- **Plan with AI** — describe a trip in plain words ("SF to Moab via Zion, 5 nights, free sites, under 3 h a day"). The model only extracts from / via / to / dates / nights / driving limit; ezcamps' planner builds the route and picks real camps from its own data, after you confirm what it understood. Runs on Apple's on-device model (Foundation Models) or **any model you bring a key for** (Anthropic, OpenAI, Gemini, xAI, OpenRouter, custom OpenAI-compatible), with your own model IDs. Falls back to a pattern reader when no model is available.
- **Settings › AI** — per-feature model picker, BYOK keys in the Keychain (this device only), custom model IDs per provider, model catalog from the Operator catalog worker (`catalog.operatorok.com/provider-models`, ETag-cached, snapshot bundled).
- **Night conditions** — on every site card and trip night: overnight low, wind and rain chance (NWS, 7 days), active weather alerts (NWS), wildfires within 50 mi that aren't fully contained (NIFC WFIGS), and overnight smoke / AQI (Open-Meteo air-quality model). No keys needed.
- **Forest roads (MVUM)** — USFS Motor Vehicle Use Map layer (roads and motorized trails, with route numbers, from zoom 10) and a legend with the official swatches. In national forests, *Can I camp here?* also names the nearest forest road with its vehicle access, open dates and surface.
- **Gear tips** — contextual “Pack for this” cards on site cards and trips (freezing or bitter-cold nights, rain, smoke, off-grid nights, no signal, no water) linking to REI and Backcountry searches. Affiliate parameters live in `GearLinks.affiliateParams` (empty for now; the disclosure appears once set). Can be turned off in Settings.
- **Map controls** — locate-me and a **reset to all-US view** button.
- **Cell signal** — official NPS reception notes plus per-carrier signal reports from your visits (AT&T, Verizon, T-Mobile, Other). FCC per-carrier coverage is planned once an FCC Public Data API token is available.

The bundled `CampSitesUSA/Resources/sites.json` contains **29,105 sites in all 50 states, DC and territories** (21,271 OSM, 4,071 Recreation.gov, 2,595 USFS, 656 NPS, 512 BLM), exported by [`scripts/pipeline/export_app.py`](scripts/pipeline/export_app.py) from the `campsites` table in `data/campsites.db`. That table is built by [`scripts/pipeline/unify.py`](scripts/pipeline/unify.py): state from coordinates, coordinate fixes, parsed fees and amenities, and duplicates across sources merged. The suggested national models (`Site`, `Trip`, `NightLog`, `RigProfile`, `CommunityReport`) are mapped in [`docs/CATALOG.md#15-field-mapping-to-the-swift-model`](docs/CATALOG.md#15-field-mapping-to-the-swift-model).
