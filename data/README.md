# `data/` — files, sources and caveats

Snapshot date: **2026-11-15**. Counts drift; re-run the collectors in `scripts/` before relying on them.

| File | Rows | Source | License | Notes |
|---|---:|---|---|---|
| `recreation_gov_camping.csv` | 7,549 | Recreation.gov public search | Public listing data; API unofficial | 4,523 campgrounds + 1,753 rec areas + permits/tours. Flat columns for SQL/spreadsheets. |
| `recreation_gov_camping.jsonl` | 7,549 | same | same | Full normalized records, one JSON object per line. |
| `nps_parks.csv` | 475 | NPS Data API | Public domain | Park units, designations, coords, activities, topics, entrance fees. |
| `nps_campgrounds.csv` | 665 | NPS Data API | Public domain | Site counts, amenities, RV limits, reservation info. |
| `nps_alerts.csv` | 622 | NPS Data API | Public domain | Current closures, hazards, road status, fire restrictions. |
| `nps_things_to_do.csv` | 3,576 | NPS Data API | Public domain | Activities with duration, season, fees, pets, accessibility. |
| `nps_visitor_centers.csv` | 714 | NPS Data API | Public domain | Visitor centers, coordinates, passport stamp locations. |
| `nps_webcams.csv` | 287 | NPS Data API | Public domain | Park webcams with status and coordinates. |
| `nps_parks_raw.json` | 475 | NPS Data API | Public domain | Raw API payload (for re-cleaning). |
| `nps_campgrounds_raw.json` | 665 | NPS Data API | Public domain | Raw API payload. |
| `blm_camping.csv` | 539 | BLM ArcGIS (RIDB-derived) | Public domain | Stay limits, fees, activities, reservation URL, directions. |
| `usfs_recreation_sites.csv` | 14,211 | USFS EDW Recreation Opportunities | CC BY 4.0 | Campgrounds, cabins, trailheads, OHV, horse camps. Attribute USFS. |
| `osm_camp_sites.csv` | 23,843 | OpenStreetMap (Overpass) | ODbL 1.0 | US `tourism=camp_site` nodes with fee, access, capacity, water, toilets, showers, power, operator. |
| `osm_camp_sites_raw.json` | 23,843 | OpenStreetMap | ODbL 1.0 | Raw Overpass response (`out body`). |
| `osm_dump_stations.csv` | 1,697 | OpenStreetMap | ODbL 1.0 | US dump stations with fee, water, toilets, hours. |
| `osm_rest_areas.csv` | 2,477 | OpenStreetMap | ODbL 1.0 | US rest areas with toilets, water, truck parking, max stay. |
| `state_park_systems.csv` | 50 | 50 state agencies | Links; check per state | Official URL + detected reservation platform + verification status. |
| `sources.json` | 78 sources | research | — | Registry of every source, endpoint, license and refresh cadence. |
| `campsites.db` | — | all of the above | mixed | SQLite: one table per source, `all_campsites` view, `sources` table. |
| `../CampSitesUSA/Resources/sites.json` | 4,069 | OSM + RIDB + NPS pipeline | mixed; attribution string included | App bundle for UT + AZ (3,693 OSM, 303 RIDB, 73 NPS). Rebuild with `scripts/pipeline/build_sites.py`. |

## Key columns

### `recreation_gov_camping.csv`

`source_id, entity_type, name, parent_name, agency, state, city, latitude, longitude, reservable, price_min, price_max, price_unit, campsites_count, accessible_campsites_count, max_vehicle_length_ft, equipment_allowed, site_types, reserve_types, activities, average_rating, rating_count, cell_coverage_score, official_url`

- `entity_type`: `campground`, `recarea`, `facility`, `permit`, `tour`, etc.
- `campsite_max_vehicle_length` is in feet.
- `aggregate_cell_coverage` is a Recreation.gov-derived score, not bars.
- `activities` is semicolon-separated and case-normalized (deduped).

### `nps_campgrounds.csv`

`park_code, name, latitude, longitude, total_sites, tent_only_sites, rv_only_sites, group_sites, horse_sites, electrical_hookups, reservable_sites, first_come_first_serve_sites, toilets, potable_water, showers, dump_station, camp_store, firewood_for_sale, ice_for_sale, laundry, cell_reception, wheelchair_access, rv_allowed, rv_max_length_ft, trailer_allowed, trailer_max_length_ft, access_roads, regulations`

- Amenity values are `yes`, `no` or `unknown`. `unknown` is common in the NPS API.
- `park_code` joins to `nps_parks.park_code`.

### `blm_camping.csv`

`source_id, name, state, latitude, longitude, stay_limit, fee_description, activities, keywords, reservation_url, blm_url, map_url, phone, email, description, directions, last_updated`

- `stay_limit` is free text (e.g., "14-day stay limit").
- `activities` and `keywords` are comma-separated BLM text.

### `usfs_recreation_sites.csv`

`recareaid, recareaname, markeractivity, markeractivitygroup, forestname, latitude, longitude, open_season_start, open_season_end, openstatus, feedescription, reservation_info, restrictions, accessibility, operational_hours, recareaurl, recareadescription`

- Filter `markeractivitygroup = "Camping & Cabins"` for campgrounds (4,864 rows).
- `feedescription` carries "No fee" / fee text.
- `restrictions` may contain HTML links.
- There is no state column. Derive state from coordinates or join to a forest-boundary layer.

### `campsites.db`

```sql
-- All normalized sites
SELECT * FROM all_campsites LIMIT 10;

-- Free/low-cost federal campgrounds in Colorado that fit a 30 ft rig
SELECT source, name, manager, price_min, max_rig_ft
FROM all_campsites
WHERE state = 'Colorado' AND (max_rig_ft IS NULL OR max_rig_ft >= 30)
ORDER BY price_min NULLS LAST
LIMIT 25;

-- Count by source
SELECT source, COUNT(*) FROM all_campsites GROUP BY source;

-- Use normalized two-letter state codes (49 states + DC/territories)
SELECT state_code, COUNT(*) FROM all_campsites_norm GROUP BY state_code ORDER BY 2 DESC;
```

## Caveats

1. **Recreation.gov search is unofficial.** It is the site's own search endpoint, not RIDB. Do not poll it aggressively, do not build availability on undocumented endpoints, and re-check terms before redistributing a bulk copy.
2. **NPS `DEMO_KEY` is rate-limited.** Get a free key for production refreshes.
3. **USFS EDW resets long connections.** The collector writes `usfs_recreation_sites.partial.jsonl` and resumes. Re-run if it stops.
4. **State park pages block bots.** A `403` in `state_park_systems.csv` means "blocked or slow from this network", not "dead link". Verify in a browser.
5. **Coordinates vary in quality.** NPS and Recreation.gov are generally good; user-submitted and geocoded records need spot checks.
6. **Nothing here is legal advice.** Camping rules come from the land manager, not from this dataset. See `docs/FREE-CAMPING-RULES.md`.

## Rebuild

```bash
export NPS_API_KEY=...
python3 scripts/collect_nps.py
python3 scripts/collect_recreation_gov.py
python3 scripts/collect_usfs.py
python3 scripts/collect_blm.py
python3 scripts/collect_osm.py
python3 scripts/clean_osm.py
python3 scripts/clean_osm_amenities.py
python3 scripts/clean_nps.py
python3 scripts/collect_state_parks.py
python3 scripts/render_state_parks.py
python3 scripts/render_parks.py
python3 scripts/build_db.py
python3 scripts/pipeline/build_sites.py --states UT AZ   # app bundle
```

NPS raw JSON is fetched separately:

```bash
curl -s "https://developer.nps.gov/api/v1/parks?limit=500&api_key=DEMO_KEY" -o data/nps_parks_raw.json
curl -s "https://developer.nps.gov/api/v1/campgrounds?limit=1000&api_key=DEMO_KEY" -o data/nps_campgrounds_raw.json
```
