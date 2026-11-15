# CampSitesUSA — Master Data Catalog

_Compiled 2026-11-15 from live endpoints and operator documentation. Counts are snapshots, not guarantees. Before shipping, re-check licenses and endpoint terms._

This catalog covers four things:

1. **Where the data lives** — 78 sources across federal, state, local, community and commercial.
2. **What each source actually gives you** — fields, coverage, access, license, refresh rate.
3. **What we already pulled** — reproducible CSVs/JSON in `data/`.
4. **How to combine it** — a unified `Site` schema, licensing rules, and a build order.

Companion docs:

- [`FREECAMPSITES.md`](FREECAMPSITES.md) — deep dive on freecampsites.net's schema, endpoint and terms.
- [`STATE-PARKS.md`](STATE-PARKS.md) — all 50 state park systems with verified links and reservation platforms.
- [`PARKS.md`](PARKS.md) — all 475 National Park System units, grouped by state.
- [`FREE-CAMPING-RULES.md`](FREE-CAMPING-RULES.md) — federal/state rules, stay limits, fire restrictions, overnight parking.
- [`API-NOTES.md`](API-NOTES.md) — verified endpoints, page limits, quirks and etiquette.
- [`RESEARCH.md`](RESEARCH.md) — product/feature research and architecture.

---

## 1. What we already have

| Dataset | Rows | File | License |
|---|---:|---|---|
| Recreation.gov camping listings (national) | **7,549** | `data/recreation_gov_camping.csv` / `.jsonl` | Public listing data; API unofficial — check terms |
| Recreation.gov campgrounds only | **4,523** | filtered from above | same |
| NPS park units | **475** | `data/nps_parks.csv` | Public domain |
| NPS campgrounds | **665** | `data/nps_campgrounds.csv` | Public domain |
| NPS alerts | **622** | `data/nps_alerts.csv` | Public domain |
| NPS things to do | **3,576** | `data/nps_things_to_do.csv` | Public domain |
| NPS visitor centers | **714** | `data/nps_visitor_centers.csv` | Public domain |
| NPS webcams | **287** | `data/nps_webcams.csv` | Public domain |
| BLM camping points | **539** | `data/blm_camping.csv` | Public domain |
| USFS recreation opportunities | **14,211** | `data/usfs_recreation_sites.csv` | CC BY 4.0 |
| OSM campsites (US) | **23,843** | `data/osm_camp_sites.csv` | ODbL 1.0 |
| OSM dump stations | **1,697** | `data/osm_dump_stations.csv` | ODbL 1.0 |
| OSM rest areas | **2,477** | `data/osm_rest_areas.csv` | ODbL 1.0 |
| State park systems | **50** | `data/state_park_systems.csv` | Links to official sources |
| Source registry | **78 sources** | `data/sources.json` | — |
| Unified SQLite database | all of the above | `data/campsites.db` | mixed; see per-row `license` |

Recreation.gov agency mix at snapshot:

| Agency | Listings |
|---|---:|
| USDA Forest Service | 3,440 |
| Bureau of Land Management | 1,598 |
| US Army Corps of Engineers | 1,248 |
| National Park Service | 776 |
| Bureau of Reclamation | 201 |
| Fish & Wildlife Service | 121 |
| State/local/other partners | ~165 |

Recreation.gov coverage by state (top): California 980, Oregon 689, Utah 674, Colorado 486, Idaho 458, Montana 373, Arizona 319, Washington 304. **49 states + DC + a few territories** are represented; Delaware has no Recreation.gov camping listings in this snapshot. State values are a mix of full names and abbreviations (`ID`, `Saint John`), so normalize before joining.

The unified `all_campsites` view contains **39,270 rows**:

| Source | Rows |
|---|---:|
| OpenStreetMap (US campsites) | 23,843 |
| USFS (camping, horse, OHV, trailheads) | 7,947 |
| Recreation.gov (campgrounds + rec areas) | 6,276 |
| NPS campgrounds | 665 |
| BLM camping | 539 |

OSM and USFS records have no state field; derive `state_code` from coordinates (MapKit/CLLocation or a state polygon join) before filtering by state.

---

## 2. The unified `Site` schema

Every source maps into one record. This is the contract the app and the pipeline should share.

### Identity
| Field | Type | Notes |
|---|---|---|
| `id` | string | `{source}:{source_id}` |
| `source` | enum | `nps`, `ridb`, `recreation_gov`, `usfs`, `blm`, `osm`, `state`, `community` |
| `source_id` | string | Native ID |
| `source_url` | string | Canonical page / deep link |
| `license` | string | `public-domain`, `cc-by-4.0`, `odbl`, `proprietary`, `permission` |
| `last_seen` | date | When the collector last confirmed the record |

### Place
| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `site_type` | enum | `developed`, `primitive`, `dispersed`, `backcountry`, `rv_park`, `private`, `cabins`, `group`, `day_use` |
| `ownership` | enum | `federal`, `state`, `county`, `city`, `tribal`, `private`, `utility`, `unknown` |
| `manager` | string | NPS, USFS, BLM, USACE, BOR, FWS, state agency, concessioner |
| `designation` | string | National Park, National Forest, Wilderness, WMA, LTVA, etc. |
| `latitude`, `longitude` | double | WGS84 |
| `state`, `county`, `city` | string | |
| `elevation_ft` | int | From 3DEP |
| `timezone` | string | |

### Access & fit
| Field | Type | Notes |
|---|---|---|
| `fee` | enum | `free`, `fee`, `donation`, `permit`, `unknown` |
| `fee_min`, `fee_max`, `fee_unit` | number/string | Per night, per vehicle, per person |
| `permit_required` | bool | Free or paid permit |
| `reservation` | enum | `none`, `recommended`, `required`, `lottery` |
| `reservation_url` | string | |
| `open_season_start`, `open_season_end` | string/date | Seasonal closures |
| `max_rig_ft` | int | RV/trailer limit |
| `max_height_ft` | int | Rarely published; derive from route |
| `road_access` | enum | `paved`, `gravel`, `dirt`, `4x4`, `boat`, `hike` |
| `stay_limit_days` | int | 14 is the common BLM/USFS default |
| `capacity` | int | Number of sites |
| `ada_sites` | int | |

### Amenities & activities
Store as normalized arrays so filters and the UI stay consistent.

`amenities[]`: `toilets`, `vault_toilet`, `flush_toilet`, `potable_water`, `showers`, `dump_station`, `electric`, `sewer`, `water_hookup`, `fire_ring`, `picnic_table`, `trash`, `camp_store`, `firewood`, `ice`, `laundry`, `playground`, `boat_ramp`, `horse_corral`, `cell_signal`, `wifi`, `pet_friendly`, `ada`.

`activities[]`: `hiking`, `biking`, `mtb`, `ohv`, `boating`, `paddling`, `fishing`, `swimming`, `climbing`, `hunting`, `horseback`, `wildlife`, `stargazing`, `skiing`, `snowmobile`, `scenic_drive`.

### Conditions (computed, not stored on the site)
`overnight_low_f`, `wind_mph`, `precip_prob`, `aqi`, `smoke_density`, `fire_distance_mi`, `fire_restriction`, `cell_coverage`, `dark_sky_score`, `sunrise`, `sunset`, `moon_phase`, `tide`, `river_flow`.

### Trust
`rating`, `rating_count`, `last_verified`, `verified_by`, `report_count`, `stale` (bool), `notes`.

---

## 3. Federal camping sources

### 3.1 Recreation.gov (the backbone)

| | |
|---|---|
| Coverage | 7,549 camping-related listings; 4,523 campgrounds; federal + state partners |
| Access | `GET https://www.recreation.gov/api/search?q=camping&size=500&start=0` |
| Auth | None |
| License | Public listing data; API is undocumented — check terms before redistribution |
| Refresh | Continuous |
| Pulled | `data/recreation_gov_camping.csv` |

The richest single national inventory. Per campground it returns capacity, accessible-site count, max vehicle length, allowed equipment, site types, reserve types, price range, rating, cell-coverage score, activities, notices, coordinates and parent area. It is **not** the supported API — RIDB is — and availability is a separate, undocumented endpoint. Use it as a cacheable snapshot, not a live dependency.

### 3.2 RIDB / Recreation Information Database

| | |
|---|---|
| Coverage | 12 federal agencies: rec areas → facilities → campsites → activities → media |
| Access | `https://ridb.recreation.gov/api/v1` |
| Auth | Free API key |
| License | Public domain |
| Refresh | Nightly |
| Key fields | `MaxVehicleLength`, `CampsiteType`, `Permissions`, `StayLimit`, `FeeDescription` |

The supported, stable, public-domain option. Use it for the app's federal layer if you need a documented API and can tolerate coarser data than the Recreation.gov search snapshot. No availability.

### 3.3 NPS Data API

| | |
|---|---|
| Coverage | 475 park units, 665 campgrounds, **622 alerts**, **3,576 things to do**, 714 visitor centers, 287 webcams, passport stamps |
| Access | `https://developer.nps.gov/api/v1` |
| Auth | Free key; `DEMO_KEY` for testing |
| License | Public domain |
| Refresh | Alerts ~2 h |
| Pulled | `data/nps_parks.csv`, `nps_campgrounds.csv`, `nps_alerts.csv`, `nps_things_to_do.csv`, `nps_visitor_centers.csv`, `nps_webcams.csv` |

Park polygons are not in the API, but the park units, coordinates, activities, fees, directions, weather text and campground amenity details are. Alerts are the must-have layer for closures and fire restrictions.

### 3.4 USFS Recreation Opportunities (EDW)

| | |
|---|---|
| Coverage | 14,211 points: **4,864 camping & cabins**, 2,606 trailheads, plus OHV, horse camps, picnic sites |
| Access | ArcGIS REST / GeoJSON / CSV / Shapefile |
| License | CC BY 4.0 |
| Refresh | Nightly |
| Pulled | `data/usfs_recreation_sites.csv` |

Filter `markeractivitygroup = "Camping & Cabins"` for campgrounds. Descriptions carry fees, restrictions, season and reservation info. Pair with MVUM for dispersed-camping legality.

### 3.5 BLM National Recreation Sites & Facilities

| | |
|---|---|
| Coverage | 1,269 facilities/sites; 539 RIDB camping points |
| Access | ArcGIS REST |
| License | Public domain |
| Refresh | Periodic (`LastUpdatedDate`) |
| Pulled | `data/blm_camping.csv` |

Includes `StayLimit` (usually "14-day stay limit"), fee text, activities, reservation URL, phone/email, directions and a BLM page link. This is the best free source for BLM developed sites. There is still **no national BLM dispersed-camping polygon layer** — use PAD-US BLM ownership plus local rules.

### 3.6 USACE, BOR, FWS, TVA, military

| Source | What you get | Access | Notes |
|---|---|---|---|
| USACE | Lake/river project campgrounds, boat ramps, day use | Recreation.gov/RIDB; district GIS | 1,248 listings in the Recreation.gov snapshot |
| Bureau of Reclamation | Western reservoir recreation areas | Recreation.gov/RIDB | 201 listings |
| Fish & Wildlife Service | Refuge units, trails, hunting/fishing access | Regional ArcGIS; refuge pages | 121 listings; camping often primitive/prohibited |
| TVA | Reservoir campgrounds in the Tennessee Valley | Web/PDF guides | Often cheap/free and poorly covered elsewhere |
| Military MWR | On-base and recreation-area campgrounds | `militarycampgrounds.us` | Eligibility required; niche but loyal audience |

### 3.7 Federal land-status and route layers

| Layer | Use | Endpoint |
|---|---|---|
| PAD-US 4.1 | Owner/manager of every public parcel; the "whose land is this?" answer | `edits.nationalmap.gov/arcgis/rest/services/PAD-US/PAD_US_4_1/MapServer` |
| BLM SMA | Finer surface-management polygons in the West | BLM EGIS hub |
| USFS MVUM | Roads/trails legally open to motor vehicles; dispersed-camping corridors | `apps.fs.usda.gov/arcx/rest/services/EDW/EDW_MVUM_01/MapServer` |
| USFS Trails | Trail class, surface, allowed uses, elevation range | `.../EDW_TrailNFSPublish_01/MapServer/0` |
| Census TIGER | State/county/tribal boundaries | census.gov |
| GNIS | Official place names and coordinates | USGS |

---

## 4. State park systems

All 50 states are in [`STATE-PARKS.md`](STATE-PARKS.md) and `data/state_park_systems.csv`, with agency, official URL, HTTP verification status and the reservation platform detected from the page.

Headline patterns:

- **ReserveAmerica (Aspira)** is the dominant state-park booking platform — detected in DE, IA, MT, NH, NM, NC, OR, PA, TX and many more.
- **California** runs its own `ReserveCalifornia`.
- **Washington** uses `GoingToCamp`.
- **Arizona** and **Minnesota** use `US eDirect`.
- **Michigan** runs `midnrreservations.com`.
- Several states (e.g., Alaska cabins, Hawaii permits) run separate systems for cabins/permits.
- There is **no national state-park API**. Build per-state adapters or deep-link.

State-level data worth collecting per state:

- Park and campground names, coordinates, season, fees
- Site types (tent, RV, cabin, yurt, group)
- Hookups, showers, dump station, water
- Pet and quiet-hour rules
- Out-of-state surcharges
- Reservation window and cancellation policy
- Dispersed/WMA camping rules (often on the fish & wildlife agency, not parks)

---

## 5. Free, dispersed and community camping

### 5.1 The landscape

| Source | Coverage | License | Use |
|---|---|---|---|
| **freecampsites.net** | Tens of thousands of user-submitted free/cheap sites, dump stations, reviews | No open license | Research + deep links only; see `FREECAMPSITES.md` |
| **iOverlander** | Worldwide community overnight spots, water, dump, propane, mechanics | No open license | Deep links / partnership |
| **Campendium** | Public/private campgrounds, free sites, cell signal | Proprietary | Deep links; best cell-signal reviews |
| **The Dyrt** | Public/private/dispersed, reviews, photos, availability | Proprietary | Partnership only |
| **AllStays** | RV parks, free overnight, rest areas, dump, Walmarts, truck stops | Proprietary | Reference |
| **RV Parky** | RV parks, free overnight, dump | Proprietary | Reference |
| **OvernightRVParking** | Verified free overnight parking policies | Paid | Reference |
| **OpenStreetMap** | 23,843 US `tourism=camp_site` nodes; `basic`/`fee=no` subset | ODbL | **Primary open free-site layer** |

### 5.2 The legal free-camping rules that matter

These are the rules a "can I camp here?" feature must encode. Always show the source and a "verify with the ranger" disclaimer.

| Land type | Default | Typical limit | Notes |
|---|---|---|---|
| BLM | Dispersed camping generally allowed on undeveloped land | 14 days in a 28-day period (varies by district) | Some districts require a permit; some areas closed |
| USFS | Dispersed camping generally allowed along roads/trails unless posted | 14 days (varies by forest) | MVUM determines where vehicles may go; some forests require a free permit |
| NPS | Generally **not** allowed outside designated campgrounds/backcountry | Designated sites only | Backcountry permit often required |
| USACE | Designated campgrounds only | Varies | Some projects allow primitive camping |
| FWS | Varies by refuge; often prohibited | Varies | Check refuge-specific rules |
| State parks | Designated campgrounds only | Varies | |
| State forests / WMAs | Varies widely | Often 1–14 days | Some require a permit or prohibit camping during hunting season |
| State trust land | Often prohibited or permit-only | Varies | Arizona, New Mexico, Utah, Colorado differ |
| Tribal land | Permit required | Varies | Never assume access |
| Private land | Permission required | — | |

Special programs:

- **BLM LTVA** (Long Term Visitor Areas, mostly Arizona/California): seasonal permit, ~$180 for the season, includes water/dump/trash at some areas.
- **Free dispersed-camping permits**: some national forests require a free permit (e.g., certain Colorado forests).
- **California campfire permit**: required for stoves/campfires on many public lands.
- **Arizona State Trust Land recreation permit**: required for access.
- **Fire restrictions**: often supersede camping rules entirely.

### 5.3 OSM queries worth precomputing

```overpassql
// Free campsites
node["tourism"="camp_site"]["fee"="no"](bbox);
way["tourism"="camp_site"]["fee"="no"](bbox);

// Basic/primitive sites
node["tourism"="camp_site"]["camp_site"~"basic|primitive"](bbox);

// Dump stations
node["amenity"="sanitary_dump_station"](bbox);
way["amenity"="sanitary_dump_station"](bbox);

// Drinking water, showers, laundry, propane
node["amenity"="drinking_water"](bbox);
node["amenity"="shower"](bbox);
node["shop"="laundry"](bbox);
node["shop"="gas"]["fuel:propane"="yes"](bbox);

// Rest areas
way["highway"="rest_area"](bbox);
```

---

## 6. Private and commercial camping

| Platform | Inventory | Access | Notes |
|---|---|---|---|
| **Hipcamp** | Private land: farms, ranches, vineyards, glamping | Partner API | Dominant private-land marketplace; scraping violates terms |
| **KOA** | ~500 franchised campgrounds | Web/app | Consistent amenities; no public API |
| **Good Sam** | RV parks + ratings + discounts | Web/app | Ratings and trip planning |
| **Thousand Trails** | Membership campground network | Membership | Not a general inventory |
| **Harvest Hosts / Boondockers Welcome** | Member stays at farms, wineries, businesses, private hosts | Paid membership | Partnership only |
| **Passport America** | Discount RV parks (50% off) | Membership | Price signal |
| **Escapees** | Member parks, co-ops, boondocking community | Membership | Long-term community |
| **Dyrt/Campendium/AllStays/RV Parky** | Aggregated public + private + free | Proprietary | Deep-link or partner |

Commercial inventory is where the money is, but none of it is open. The app's honest differentiator is **open government data + OSM + first-party reports**, with deep links to booking platforms.

---

## 7. Amenities and services along the way

| Need | Best open source | Backup | Fields |
|---|---|---|---|
| Dump stations | OSM `amenity=sanitary_dump_station` | Sanidumps, state DOT lists | fee, potable water, hours, season |
| Drinking water | OSM `amenity=drinking_water` | NPS/USFS facility data | potable, seasonal |
| Showers | OSM `amenity=shower` | Campground amenity data | fee, private/public |
| Laundry | OSM `shop=laundry` | — | hours, coin/card |
| Propane | OSM `fuel:propane=yes` | — | refill vs exchange |
| Fuel | OSM `amenity=fuel` | — | diesel, hours |
| Groceries | OSM `shop=supermarket` | — | — |
| Rest areas | OSM `highway=rest_area` | State DOT lists | toilets, water, overnight policy |
| Cell signal | FCC mobile broadband | Campendium reviews | carrier, tech, down/up |
| WiFi | OSM `internet_access=wlan` | Campground data | free/paid |
| RV repair | OSM `shop=car_repair` | — | RV-specific |
| Medical | OSM `amenity=hospital`/`clinic` | — | 24h, ER |

**Rest-area overnighting** is state- and site-specific. Some states allow it, some prohibit it, and some allow it only at certain sites. Never infer from a single tag; store the policy source.

Snapshot in this repo: **1,697 dump stations** and **2,477 rest areas** from OSM (`data/osm_dump_stations.csv`, `data/osm_rest_areas.csv`).

---

## 8. Conditions, safety and the "night score"

| Layer | Source | Endpoint | License |
|---|---|---|---|
| Forecast / overnight low / wind | NWS | `api.weather.gov` | Public domain |
| Global forecast fallback | Open-Meteo | `api.open-meteo.com` | CC BY 4.0 |
| Wildfire perimeters | NIFC WFIGS | ArcGIS REST | Public domain |
| Smoke plumes | NOAA HMS | Shapefile/KML | Public domain |
| AQI | AirNow | REST (key) | Public domain |
| Fire restrictions | USFS/BLM pages | web | Public domain |
| Road closures / chain controls | State 511 | varies | varies |
| Elevation / grade | USGS 3DEP | ImageServer | Public domain |
| River flow | USGS NWIS | REST | Public domain |
| Tides | NOAA CO-OPS | REST | Public domain |
| Snowpack | NRCS SNOTEL | REST | Public domain |
| Flood zones | FEMA NFHL | ArcGIS | Public domain |
| Aurora | NOAA SWPC | JSON | Public domain |
| Light pollution | VIIRS | GeoTIFF | Public domain |
| Moon phase | computed | — | — |

A defensible **Night Score** combines: overnight low, wind, precipitation probability, AQI/smoke, distance to active fire, fire restriction level, cell coverage, dark-sky radiance, elevation and (for coast) tide. Show the inputs, not just a number.

---

## 9. Activities near camp

| Activity | Open data | Difficulty signal |
|---|---|---|
| Hiking | USFS Trails, NPS trails, USGS National Digital Trails, OSM | Trail Class 1–5; gain/length score |
| MTB | USFS trails, OSM `mtb:scale` | `mtb:scale` 0–6 |
| OHV | USFS MVUM, state OHV maps | Vehicle class + season |
| Paddling | American Whitewater, USGS NWIS, OSM waterway tags | Class I–VI; flow range |
| Fishing | State fish & wildlife, USGS, NPS | Species, season, stocking |
| Boating | USACE, state, OSM `leisure=marina` | Ramp, motor restrictions |
| Climbing | OSM `climbing=*`; Mountain Project (closed) | Grade systems |
| Horseback | USFS horse camps, OSM | Corrals, trailer access |
| Hunting | State wildlife agencies | Season, WMA rules |
| Skiing/snowmobile | USFS, state, resort pages | Trail difficulty, snow depth |
| Stargazing | NPS, DarkSky International, VIIRS | Bortle/radiance |
| Wildlife | NPS/FWS, eBird (API) | Season, hotspot |
| Scenic drives | USFS/NPS byways, OSM | Paved/unpaved, season |

Difficulty scoring when no official grade exists (documented in `RESEARCH.md`): `sqrt(2 × elevation_gain_ft × miles)`, bucketed Easy/Moderate/Hard/Strenuous, with altitude and surface adjustments. Always label which method was used.

---

## 10. Availability and booking

| System | Coverage | Access | Recommendation |
|---|---|---|---|
| Recreation.gov | Federal + partners | Undocumented availability endpoints | Deep-link in v1; partner API later |
| Campflare | Recreation.gov availability/alerts | Commercial API | Best supported option |
| ReserveAmerica (Aspira) | Many state parks | No public API | Deep-link state storefronts |
| ReserveCalifornia | California | No public API | Deep-link |
| GoingToCamp | WA + others | No public API | Deep-link |
| US eDirect | AZ, MN + others | No public API | Deep-link |

Availability is the most fragile layer. Do **not** build a product on undocumented endpoints without a fallback. Start with "check availability" deep links, then add a paid/partner feed for the top corridors.

---

## 11. Licensing matrix

| License | Sources | What you can do | What you must do |
|---|---|---|---|
| **Public domain** | NPS, RIDB, BLM, USACE, BOR, FWS, NOAA, USGS, FCC, FEMA, Census | Store, transform, redistribute | No attribution legally required; cite anyway |
| **CC BY 4.0** | USFS EDW | Store, transform, redistribute | Attribute USDA Forest Service |
| **ODbL 1.0** | OpenStreetMap, Protomaps data | Store, transform, redistribute | Attribute OSM; share-alike on derived databases; keep open |
| **CC0** | Wikidata | Anything | None |
| **CC BY-SA** | Wikipedia text, your community reports (proposed) | Store, transform, redistribute | Attribute + share-alike |
| **Proprietary** | freecampsites, iOverlander, Campendium, Dyrt, Hipcamp, AllStays, KOA, ReserveAmerica | Deep-link, manual reference | Do not scrape or redistribute |
| **Unofficial/public listing** | Recreation.gov search | Cache a snapshot | Check terms; avoid bulk redistribution; no availability polling |

**Rule of thumb:** if a source is proprietary, link out; if it is public domain or CC BY, ingest it; if it is ODbL, isolate it in its own derived database so the share-alike obligation is contained.

---

## 12. What is still missing (and how to get it)

| Gap | Why it matters | Plan |
|---|---|---|
| **National BLM dispersed-camping polygons** | The #1 boondocking question | PAD-US BLM ownership + district rules; publish a "likely allowed" score, not a legal yes |
| **State trust land rules** | Common in AZ/NM/UT/CO | Per-state land office pages; manual rules table |
| **Tribal land access** | Often mistaken for public land | BIA/Census tribal boundaries + "permission required" |
| **County/city parks** | Huge long-tail of cheap sites | Per-county open data + OSM; community submissions |
| **Utility company campgrounds** | Cheap sites in the Southeast/West | Per-utility pages (TVA, SCE, PG&E, etc.) |
| **WMA camping rules** | Hunting-season closures | State fish & wildlife agencies |
| **Reliable cell signal** | Remote work + safety | FCC + community reports; label as estimate |
| **Availability** | Booking conversion | Campflare/partner, then deep links |
| **Last-verified dates** | Stale listings are the biggest trust killer | First-party reports with expiry (e.g., 12 months) |
| **Accessibility detail** | Underserved and high-value | NPS/RIDB ADA fields + first-party reports |
| **Road difficulty** | RVs get stuck | MVUM + 3DEP grade + community reports |

---

## 13. Recommended ingestion order

### Tier 1 — ship the map (2–3 weeks)
1. **NPS** parks + campgrounds + alerts.
2. **Recreation.gov snapshot** (campgrounds + rec areas) for capacity, price, rig fit.
3. **USFS Recreation Opportunities** filtered to camping/cabins.
4. **BLM camping** with stay limits.
5. **OSM** free sites + dump/water/showers/rest areas.
6. **PAD-US** public-land overlay.

### Tier 2 — trust and planning (3–6 weeks)
7. **NWS** forecasts + alerts.
8. **NIFC** fires + **AirNow** AQI.
9. **USFS MVUM** for dispersed-camping legality.
10. **State park** links and top-10 state adapters.
11. **3DEP** elevation and trail difficulty.

### Tier 3 — differentiation (6–12 weeks)
12. **First-party community reports** (CC BY-SA): photos, road condition, "site was full", cell signal.
13. **Night Score** and **route corridor search**.
14. **Availability deep links**, then partner API.
15. **Offline packs** (PMTiles + SQLite) per state.

---

## 14. Refresh schedule

| Cadence | Sources |
|---|---|
| Real time / hourly | NWS, AirNow, NIFC, USGS NWIS, NOAA tides |
| Daily | Recreation.gov snapshot, USFS EDW, BLM, NPS alerts |
| Weekly | OSM extracts, state park pages |
| Monthly | PAD-US, MVUM, FCC, VIIRS |
| Quarterly | Licenses, endpoint terms, state reservation platforms |
| Annually | Dataset versions (PAD-US, TIGER, GNIS) |

---

## 15. Field mapping to the Swift model

The app already ships `Site`, `SavedSite`, `Visit`, `Trip` and `TripStop` in `CampSitesUSA/Models/`. The fuller national schema suggested by this catalog is:

```swift
@Model final class Site {
    @Attribute(.unique) var id: String
    var source: String
    var sourceID: String
    var name: String
    var siteType: String
    var ownership: String
    var manager: String?
    var latitude: Double
    var longitude: Double
    var state: String?
    var county: String?
    var fee: String?
    var feeMin: Double?
    var feeMax: Double?
    var maxRigFeet: Int?
    var stayLimitDays: Int?
    var roadAccess: String?
    var amenities: [String]
    var activities: [String]
    var openSeasonStart: String?
    var openSeasonEnd: String?
    var reservationURL: String?
    var sourceURL: String
    var license: String
    var rating: Double?
    var ratingCount: Int?
    var lastVerified: Date?
}

@Model final class Trip { var name: String; var start: Date; var stops: [Site] }
@Model final class NightLog { var site: Site?; var date: Date; var lowF: Double?; var notes: String }
@Model final class RigProfile { var lengthFeet: Double; var heightFeet: Double; var fourWD: Bool; var needsHookups: Bool }
@Model final class CommunityReport { var site: Site?; var date: Date; var roadCondition: String; var crowdLevel: String; var cellCarrier: String; var signalBars: Int; var photo: Data? }
```

The catalog CSVs are the seed data. A build step can import them into a bundled SQLite/JSON store, and the app can sync refreshed deltas later.

---

## 16. Verification checklist before launch

- [ ] Re-check every license and terms page (they change).
- [ ] Confirm Recreation.gov search is still permitted for your use; get written guidance if bulk redistribution.
- [ ] Get a real NPS API key and a RIDB key; remove `DEMO_KEY`.
- [ ] Validate coordinates for a random sample of 50 sites against satellite imagery.
- [ ] Confirm BLM stay limits by district for your launch region.
- [ ] Confirm state-park reservation platforms for your launch states.
- [ ] Add "source" and "last verified" to every UI surface.
- [ ] Add a stale-record policy (hide or flag after 12 months).
- [ ] Test offline packs with airplane mode.
- [ ] Add a "report a problem / closed" path for users.

---

## Source registry

The full machine-readable list — 78 sources with endpoint/link, auth, license, refresh rate, key fields and notes — is in [`../data/sources.json`](../data/sources.json). Pull requests that add a source should add it there and, if it is ingested, a collector in `scripts/`.
