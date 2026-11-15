# CampSitesUSA

A SwiftUI + SwiftData multiplatform app for finding and planning campsites across the United States — with a focus on **open data**, **public land**, and **free/dispersed camping**.

The repo currently contains two things:

1. The native app template (`CampSitesUSA/`, `CampSitesUSA.xcodeproj/`).
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
| [`data/sources.json`](data/sources.json) | 65 sources, machine-readable |

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
| State park systems | 50 | `data/state_park_systems.csv` |
| Unified database | — | `data/campsites.db` |

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
python3 scripts/collect_recreation_gov.py   # ~2 min, 16 pages
python3 scripts/collect_usfs.py             # resumable; EDW resets long connections
python3 scripts/collect_blm.py              # 539 camping points
python3 scripts/clean_nps.py                # requires data/nps_*_raw.json
python3 scripts/collect_state_parks.py
python3 scripts/render_state_parks.py
python3 scripts/build_db.py
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

The Xcode project is still the default template (`Item` + `ContentView`). The catalog is the groundwork for replacing it with `Site`, `Trip`, `NightLog`, `RigProfile` and `CommunityReport` models — see [`docs/CATALOG.md#15-field-mapping-to-the-swift-model`](docs/CATALOG.md#15-field-mapping-to-the-swift-model).
