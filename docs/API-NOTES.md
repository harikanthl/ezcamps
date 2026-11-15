# Collection Notes & Endpoint Quirks

_What actually worked on 2026-11-15, and what broke. Useful before writing another collector._

## Verified working

| Endpoint | Result | Notes |
|---|---|---|
| `developer.nps.gov/api/v1/parks?limit=500` | 475 parks | `DEMO_KEY` works but is rate-limited |
| `developer.nps.gov/api/v1/campgrounds?limit=1000` | 665 campgrounds | Amenities often `[]` = unknown |
| `developer.nps.gov/api/v1/alerts` | 622 alerts | Refresh roughly every 2 hours |
| `developer.nps.gov/api/v1/thingstodo` | 3,576 items | Great activity enrichment |
| `developer.nps.gov/api/v1/visitorcenters` | 714 | |
| `developer.nps.gov/api/v1/webcams` | 287 | |
| `recreation.gov/api/search?q=camping&size=500` | 7,549 unique | 16 pages; 500 is the max page size |
| `apps.fs.usda.gov/.../EDW_RecreationOpportunities_01/MapServer/0` | 14,211 points | Nightly; resets long connections |
| `gis.blm.gov/.../BLM_Natl_Recreation_Sites_Facilities/MapServer/2` | 539 camping points | Layer 0 = 1,269 facilities/sites |
| `developer.nps.gov` + `ridb.recreation.gov` | — | RIDB needs a real key; `DEMO_KEY` returns 401 |
| `edits.nationalmap.gov/.../PAD-US/PAD_US_4_1/MapServer` | — | Reachable; large polygons, use bbox/state queries |

## Recreation.gov search

```text
GET https://www.recreation.gov/api/search?q=camping&size=500&start=0
```

- `size` max is **500**; larger values are ignored/capped.
- `q=camping` → **7,559** results, but only **7,549 unique** by `entity_id` (duplicates across pages).
- `q=camping&fq=entity_type:campground` → **4,523** campgrounds.
- `q=&entity_type=campground` → total **10,000** (capped), so it is not a reliable "all" count.
- `q=*` → 0; do not use.
- Response fields vary by `entity_type`. Campgrounds have capacity, equipment, price, ratings; rec areas have `campgrounds_count`, `permits_count`, `official_site_url`; permits/tours lack most place fields.
- `price_range` is an object: `{amount_min, amount_max, per_unit}`. No-price listings return null, not 0.
- `activities` and equipment names arrive with inconsistent casing (`Camping` vs `CAMPING`). Normalize and dedupe.
- `links` is sometimes null. `official_site_url` is present on rec areas and some facilities.
- No API key. Be polite: one pass, cache the result, do not run this on a schedule more than daily.
- **Availability is a different endpoint** and is undocumented. Do not poll it.

## USFS EDW

- Service root: `https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RecreationOpportunities_01/MapServer`
- Layer 0 = Recreation Opportunities, 25 fields, 14,211 records.
- `resultRecordCount=1000` worked once, then the server reset the connection on page 2. **Use 500** and persist each page.
- The collector now writes `data/usfs_recreation_sites.partial.jsonl` and resumes by line count.
- `markeractivitygroup` values: `Camping & Cabins`, `Horse Riding & Camping`, `OHV Riding & Camping`, `Trailhead`, `Hiking`, `Fishing`, `Hunting`, `Water Activities`, `Winter Sports`, etc.
- Descriptions are HTML; strip tags for display but keep a sanitized HTML field if you want links.
- MVUM: `.../EDW_MVUM_01/MapServer`; Trails: `.../EDW_TrailNFSPublish_01/MapServer/0`.

## BLM

- Service: `https://gis.blm.gov/natl/rest/services/recreation/BLM_Natl_Recreation_Sites_Facilities/MapServer`
- Layer 2 = RIDB camping (539). Layer 0 = all recreation facilities/sites (1,269).
- `StayLimit` is free text and sometimes HTML-escaped.
- Coordinates are strings; cast to float.
- `LastUpdatedDate` is a useful freshness signal.
- There is no national BLM dispersed-camping polygon layer.

## NPS

- `DEMO_KEY` works for parks/campgrounds but will throttle under repeated calls. Get a key.
- The collector reads `NPS_API_KEY` from the environment. Never hard-code it; `docs/keys.md` is gitignored.
- Counts at snapshot: 475 parks, 665 campgrounds, **622 alerts**, **3,576 things to do**, 714 visitor centers, 287 webcams.
- Thingstodo records do **not** have a numeric difficulty field. Use duration, season, activities, accessibility and tags, then blend with trail data.
- `latitude`/`longitude` are **strings**.
- `states` is a comma-separated string, sometimes multiple states.
- Park `activities` and `topics` are arrays of `{id, name}`.
- Campground amenities return `[]` for unknown — do not render as "no".
- `reservations` is often `null`; use `reservationUrl` / `reservationInfo`.
- Park boundaries are not in the API. Use agency boundary layers or PAD-US.

## freecampsites.net

- Direct HTTPS requests from this network fail with `ERR_HTTP2_PROTOCOL_ERROR` / empty reply, even with a browser User-Agent and HTTP/1.1. The site is behind bot protection.
- The internal map endpoint is:
  `https://freecampsites.net/wp-content/themes/freecampsites/androidApp.php?location=<place>`
- Response is `text/html` with leading newlines; trim before `JSON.parse`.
- `?region=<lat,lon>` returns an empty body; use `?location=<place>`.
- Detail pages are hash routes (`#!<id>&query=sitedetails`), so server-side HTML fetches do not contain the listing.
- Do not scrape or republish. See `docs/FREECAMPSITES.md`.

## State park pages

- Many state sites return **403** to scripted clients (Arkansas, Georgia, Hawaii, Maryland, Massachusetts, Michigan, Minnesota, Missouri, Nebraska, New York, South Carolina, Utah, Virginia, Wisconsin, Wyoming) even with a browser UA.
- A 403 means "blocked from this network", not a bad URL. Verify in a browser before changing the table.
- `http://` → `https://` redirects are common; use the effective URL.
- Reservation platform fingerprints are best-effort. Some states load the booking widget client-side, so the homepage HTML may not contain the platform string even when they use ReserveAmerica.
- Better approach for production: use a real browser (Playwright) or a search-engine result, and store `verified_at`.

## PAD-US / ESRI

- PAD-US 4.1 MapServer: `https://edits.nationalmap.gov/arcgis/rest/services/PAD-US/PAD_US_4_1/MapServer`
- Query with a state filter or bbox; nationwide polygon dumps are large.
- For offline, convert to PMTiles with `tippecanoe` or `ogr2ogr` + `pmtiles`.
- ESRI services often return `wkid: 102100` (Web Mercator). Request `outSR=4326` if you need WGS84.

## General etiquette

- Set a descriptive `User-Agent` with contact info.
- Cache aggressively; use `If-None-Match` / `If-Modified-Since` where supported.
- Back off on 429/5xx with exponential jitter.
- Never run nationwide scrapes against a site that does not offer an API.
- Store `retrieved_at` and `source_url` with every row.
- Re-check licenses quarterly; government terms and platform ownership change.
