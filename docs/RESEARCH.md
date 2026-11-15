# CampSitesUSA: Research and Feature Ideas

_Research done 2026-11-15. Check API terms and dataset versions again before building on them._

## 1. Starting point

- The repo is a new **SwiftUI + SwiftData multiplatform app**: iOS 26.2, macOS and visionOS targets. (This section describes the starting point; the app has since been implemented — see the README for current status.) That makes this a **native Apple app**, which shapes how much of opengeos we can reuse (see §3).
- **freecampsites.net is still online.** Its data comes from users and has no open license, and the same goes for iOverlander. We should not scrape either one. We get our advantage by combining **open government data** with **OSM** and **our own openly licensed community reports**.

## 2. Data sources (free or public)

### Campgrounds and sites
| Source | What it gives | Access | License |
|---|---|---|---|
| **RIDB / Recreation.gov API** (`ridb.recreation.gov/api/v1`) | Recreation areas, then facilities, then individual campsites from 12 federal agencies: site type, max vehicle length, equipment allowed, accessibility, coordinates, reservable or not | Free API key, read-only | Public domain |
| **NPS Data API** (`developer.nps.gov/api/v1`) | Parks, campgrounds, **alerts and closures** (refreshed every ~2 hours), things to do, visitor centers, webcams, passport stamp locations, fees and passes | Free API key | Public domain |
| **USFS EDW: Recreation Opportunities and RecSites** | Point locations of campgrounds and activities on Forest Service land, updated daily | ArcGIS REST, GeoJSON, CSV, Shapefile | CC BY 4.0 |
| **OpenStreetMap** `tourism=camp_site`, `camp_site=basic`, `fee=no`, `amenity=sanitary_dump_station`, `drinking_water`, `shower`, `fuel` + propane | Many free and informal spots, plus dump stations, water and showers | Overpass API or Geofabrik extracts | ODbL (share-alike) |

### "Is it legal to camp here?" (the key free-camping layer)
| Source | Use |
|---|---|
| **PAD-US 4.1 (USGS)** | Land ownership and manager for every public parcel in the US (BLM, USFS, NPS, state, and so on). Comes as a geodatabase, so we convert it to PMTiles ourselves |
| **USFS MVUM roads and trails** | Motor Vehicle Use Maps. The symbology marks roads where **dispersed camping is allowed along the corridor**. CC BY 4.0, available as GeoJSON or Shapefile |
| **BLM Surface Management Agency and eplanning layers** | There is **no national BLM dispersed-camping layer**, only per-field-office layers. PAD-US "BLM land" plus the default BLM 14-day rule is the practical proxy |

### Conditions on the night you camp
| Source | Use |
|---|---|
| **NWS API** (`api.weather.gov`) | Forecast, overnight lows, alerts. Free, no key (needs a User-Agent header) |
| **NIFC WFIGS** | Active wildfire perimeters and incidents |
| **AirNow** + **NOAA HMS smoke** | Air quality index and smoke plumes |
| **FCC National Broadband Map (mobile)** | Cell coverage by carrier (for "will I have signal?") |
| **NASA Black Marble / VIIRS** | Light pollution, for a dark-sky score |
| **USGS 3DEP** | Elevation, which helps estimate overnight lows and road grade |

### Availability (handle with care)
- Recreation.gov availability is **not in RIDB**. It lives behind undocumented endpoints, and scraping them can break their terms of service. **Campflare** sells a commercial API that covers this. Recommendation: deep-link to Recreation.gov for v1 and consider a paid partner later.

## 3. opengeos: what we can actually reuse

Most opengeos projects are **Python (notebooks, analysis)** or **web JS (MapLibre GL JS)**. None of them drop straight into a SwiftUI app, but they are a good fit for the **data pipeline**:

| Repo | How we'd use it |
|---|---|
| **leafmap** (MIT) | Notebooks for pulling, cleaning and previewing PAD-US, MVUM, RIDB and OSM data, and exporting it |
| **geospatial-data-catalogs**, **aws-open-data-geo** | Finding more datasets (fire, smoke, DEM, night lights) that are already hosted in cloud-native formats |
| **GeoLibre** (MIT; Tauri + MapLibre + DuckDB-WASM) | Quick visual QA of our PMTiles and GeoParquet outputs before they ship. It also has an iOS app, handy for checking data on a phone |
| **maplibre-gl-components / layer-control / storymaps** | Useful only if we later build a **web companion** (shareable trip pages, a "trip story" scrollytelling page) |
| **lidar**, **whitebox** | Optional. Terrain analysis for a "flat spot" score or road grade |

**Our stack:** Python pipeline (leafmap, GeoPandas, DuckDB) → `tippecanoe` → **PMTiles** on a CDN (for example Cloudflare R2) → the app renders them.

### Map engine for the app
- **MapKit (SwiftUI `Map`)**: native, free, gives routing with ETAs. Weak points are custom vector overlays (like the public-land polygons) and offline use.
- **MapLibre Native iOS + PMTiles**: reads local PMTiles directly through `pmtiles://`, gives true offline region packs, and lets us style our own public-lands and MVUM layers. Costs more integration work in SwiftUI.
- **Recommendation:** use **MapLibre Native for the map** (offline public-land layers are the core of the product) and **MapKit's `MKDirections` for routing** in v1. Later, add **Valhalla or GraphHopper** for RV-aware routing that accounts for height, length and unpaved roads.

## 4. Feature ideas

### Core (MVP)
1. **Unified map**: federal campgrounds (RIDB), NPS campgrounds, USFS sites and free OSM sites on one map. Filters: free, reservable, RV length, tent only, water, toilets, dump station.
2. **"Can I camp here?" tap test**: long-press anywhere to see the land manager (PAD-US), MVUM corridor status, stay limit, active fire restrictions and NPS alerts. Answers *likely yes / no / check with ranger*, with sources shown.
3. **Public-lands overlay**: BLM, USFS, NPS, state and private land shaded by color. This is the single most useful layer for boondockers.
4. **Offline region packs**: download a state's tiles and site data before losing signal.
5. **Trips (SwiftData)**: saved spots, multi-stop itineraries, notes, nights logged.

### Ratings you can trust
- **Built so far:** people rate a site 1–5 with quick tags (Quiet, Good cell signal, Rough road…) and notes. A rating is **Verified visit** if the phone was within 500 m of the site when it was logged. Ratings are stored on the phone (SwiftData `Visit`).
- **Next (needs the server):**
  - Sync ratings to the Cloudflare Worker + D1 backend, with Sign in with Apple.
  - Weight verified visits higher and decay old ratings, so "Rough road (2 weeks ago)" outranks a 3-year-old review.
  - Show "N verified campers" alongside the average.
  - Rate-limit to one rating per site per night, and let people report abuse.

### Activities near each spot, ranked by difficulty
- **What to show:** for any campsite, list hikes, MTB rides, paddling, climbing, fishing, swimming, scenic drives, OHV routes and ranger programs within a chosen radius or drive time. Sort by difficulty (Easy, Moderate, Hard, Strenuous), distance from camp, duration and season.
- **Where the data comes from:**
  - **NPS `/thingstodo`**: curated activities per park with duration, season, fees, pets and reservations. Its difficulty field needs checking, and we fill it in from trail data when it's missing.
  - **RIDB `/activities`** for recreation areas and facilities, and the **USFS Recreation Opportunities** activity points.
  - **Trails:** USFS National Forest System Trails (EDW), with *Trail Class 1–5* as a ready-made difficulty grade. Also NPS public trails, the USGS National Digital Trails dataset, and OSM `highway=path` tagged with `sac_scale`, `mtb:scale` and `trail_visibility`.
  - **Water:** OSM `canoe`/`whitewater` tags, plus USGS water services for live river flow ("is it runnable today?").
- **How to compute difficulty when no grade exists:** take trail length and elevation gain from a **USGS 3DEP** DEM sampled along the line, apply a Shenandoah-style score `sqrt(2 × gain_ft × miles)`, and bucket the result. Adjust for altitude and surface. Blend it with official grades where they exist, and always show which one we used.
- **Personalization:** a "my level" setting (fitness, kids, dog, accessible only) re-ranks the list. A "Day plan" picks one activity a day for a multi-night stay.
- **Pipeline note:** precompute an activity-to-site index (activities within 10/25 mi of each site) offline and ship it inside the region packs, so it works without signal.

### Planning
6. **Route corridor search**: "show free camps within 15 mi of my route, about every 250 mi of driving", with a daily driving budget.
7. **Night score per site**: overnight low, wind, AQI and smoke, fire distance, cell signal for your carrier, dark-sky rating, elevation.
8. **Rig profile**: rig length, height, 4x4 or 2WD, generator. Hides sites that won't fit (RIDB max vehicle length) and warns about rough roads.
9. **Stay-limit tracker**: automatically counts nights per district against the BLM/USFS 14-day rule.
10. **Closures and alerts feed**: NPS alerts plus a tracked list of dispersed-camping closures, which are growing in 2026.

### Delight
11. **Natural-language search with on-device Apple Foundation Models**: "quiet free spot near Moab with shade and Verizon signal" becomes structured filters. It runs privately and works offline.
12. **NPS passport and pass tracker**: parks visited, passport stamp locations, and whether an America the Beautiful pass pays off for the planned trip.
13. **Open community reports**: photos, road condition, "site was full", licensed **CC BY-SA**, with optional upstream edits to OSM. This is the honest counter to closed databases like iOverlander.
14. **Services along the way**: dump stations, potable water, showers, propane and laundromats (OSM).
15. **Later**: Recreation.gov cancellation alerts (through a partner), CarPlay, a visionOS 3D terrain preview of a site, a web trip-sharing page built on opengeos MapLibre plugins.

## 5. Suggested architecture

```
[Pipeline: Python, runs nightly]
  RIDB, NPS, USFS EDW, OSM, PAD-US, MVUM
    → normalize to one "Site" schema (GeoParquet)
    → tippecanoe → PMTiles (sites, public lands, MVUM), per state
    → upload to CDN

[Thin API: Cloudflare Worker]
  - holds the RIDB and NPS keys, caches responses
  - live layers: NWS, NIFC fires, AirNow
  - community reports (D1/R2)

[SwiftUI app]
  - MapLibre Native (PMTiles, offline) + MapKit routing
  - SwiftData: Trip, SavedSite, NightLog, RigProfile
  - Foundation Models: natural-language search
```

## 6. Open questions
- iPhone first, or iPhone + Mac + visionOS from day one? The template targets all three.
- Free forever, or a paid tier for offline packs and alerts?
- Are community reports in v1, or do we start read-only from open data?

## Sources
- RIDB: https://catalog.data.gov/dataset/recreation-information-database-ridb-58364 · https://ridb.recreation.gov/docs
- NPS API: https://www.nps.gov/subjects/digital/nps-data-api.htm · https://www.nps.gov/subjects/developer/changelog.htm
- PAD-US: https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download
- USFS Recreation Opportunities: https://catalog.data.gov/dataset/recreation-opportunities-feature-layer
- USFS MVUM: https://catalog.data.gov/dataset/mvum-symbology-motor-vehicle-use-map-trails
- BLM eplanning example: https://eplanning.blm.gov/arcgis/rest/services/Hosted/BLM_LHFO_SpecialRecreationManagementZone/FeatureServer/layers
- Campflare (availability data): https://docs-v2.campflare.com/campgrounds/data
- Closures tracker: https://www.thewaywardhome.com/places-closing-to-campers/
- MapLibre PMTiles on native: https://maplibre.org/flutter-maplibre-gl/advanced/pmtiles/
- opengeos: https://github.com/opengeos · https://github.com/opengeos/GeoLibre · https://github.com/opengeos/leafmap
