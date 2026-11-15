# Freecampsites.net: data model, endpoint, and how to use it

_Checked 2026-11-15. The site blocked direct requests from this build environment at the TLS layer, so the endpoint below is documented from the site's own map/app behavior and its public submission form. Verify field shapes again before writing an adapter._

## What it is

Freecampsites.net is a community directory of **free and low-cost camping** in the United States (with some Canada/Mexico coverage). Listings are user-submitted and include public land (BLM, Forest Service, NPS, USACE, state, county), private overnight spots (casinos, truck stops, retail stores), dump stations, and reviews/photos.

It is the best-known consumer index of informal camping, but it is **not an open dataset**. Treat it as a research and cross-reference source, not a bulk data feed.

## What a listing contains

The submission form is effectively the site's schema. These are the fields a contributor can provide:

| Group | Fields |
|---|---|
| Identity | Campsite name, description, street address, website, phone, email, photos (jpg/png/gif, 8 MB total) |
| Cost | Fee required (yes/no), free permit required (yes/no) |
| Ownership | Public or private, then owner type |
| Public owner types | National Park Service, Forest Service, Bureau of Land Management, Fish and Wildlife Service, Bureau of Reclamation, Corps of Engineers, State Park, State Forest, County Park, Rest Area, Other |
| Private owner types | Privately owned campground, casino, truck stop, retail store, utility company, other |
| Rig fit | Class A, Class A + toad, Class B, Class C, fifth wheel, trailer, truck camper, skoolie, passenger vehicle, pop-up trailer, bicycle, feet, motorcycle |
| Access | Paved, gravel, dirt, 4x4 |
| Capacity | 1–5, 6–15, 16–29, 30+ campsites |
| Max RV length | 15, 25, 35, 45 ft, unlimited |
| Season | Dates the site is open |
| Amenities | ADA accessible, BBQ grill, boat ramp, drinking water, dump station, electricity, fire ring, horse corral, laundry, near water, pay phone, pets welcome, picnic tables, restrooms, playground, sewer, shooting range, showers, trash cans |
| Activities | RV parking, tent camping, OHV, biking, boating, fishing, hiking, horse trails, hunting, swimming, rock climbing, water sports, wildlife viewing, winter sports |

The map/listing JSON is much smaller. It exposes:

| JSON field | Meaning |
|---|---|
| `id` | Internal listing ID (used in `#!<id>&query=sitedetails` deep links) |
| `name` | Campsite name |
| `type` | Record type, normally `campsite` |
| `type_specific.fee` | `Free`, `Fee`, etc. |
| `ratings_average` | Numeric average rating |
| `ratings_count` | Number of votes/reviews |
| `distance` | Distance from the search center (miles) |
| `latitude`, `longitude` | Coordinates |
| `city`, `county`, `region`, `country` | Reverse-geocoded location |
| `excerpt` | Short description snippet |
| `url` | Canonical detail-page URL |

## The map endpoint

The site's own map calls:

```text
GET https://freecampsites.net/wp-content/themes/freecampsites/androidApp.php?location=<place name>
Headers:
  X-Requested-With: XMLHttpRequest
  Accept: application/json
```

Example:

```text
https://freecampsites.net/wp-content/themes/freecampsites/androidApp.php?location=Bend%2C%20Oregon
```

Response shape:

```json
{
  "latitude": "44.0582",
  "longitude": "-121.3153",
  "resultList": [
    {
      "id": 169377,
      "name": "Oregon Badlands Dispersed Camping",
      "type": "campsite",
      "type_specific": { "fee": "Free" },
      "ratings_average": 3.33,
      "ratings_count": 12,
      "distance": 14.2,
      "latitude": "43.98",
      "longitude": "-121.02",
      "city": "Bend",
      "county": "Deschutes",
      "region": "Oregon",
      "country": "United States",
      "excerpt": "Dispersed camping on BLM land...",
      "url": "https://freecampsites.net/#!169377&query=sitedetails"
    }
  ]
}
```

Gotchas observed/documented by the site's users:

- The body is served as `text/html`, often with leading newlines. **Trim before `JSON.parse`.**
- `?region=<lat,lon>` returns an empty body on the old code path. Use `?location=<place>`.
- Ratings are structured (`ratings_average`, `ratings_count`); the `rating` and `table_row` fields are pre-rendered star HTML.
- Free/fee status lives in `type_specific.fee`, not at the top level.
- The site sits behind bot protection and can return HTTP/2 protocol errors or empty replies to scripted clients. Do not retry aggressively.
- Detail pages use a hash route (`#!<id>&query=sitedetails`), so server-side fetching of a "page" will not contain the listing; use the JSON endpoint or a real browser.

## Other layers on the site

- **Dump stations** — a separate nearby layer, toggled independently of campsites.
- **Trip planner** — add stops, route optimization, avoid highways/tolls/ferries, round trips.
- **Favorites** — client-side, with optional sync.
- **Reviews, photos, submissions, blog posts, videos** — community content attached to listings.
- **Pre-cache** — the web app caches nearby listings for offline use; there is no public offline export.

## Data quality

The site itself warns that:

- Listing status and prices change over time and many records are stale.
- Some listings are marked as "research data" and are known to be inaccurate.
- Amenity data is incomplete; real sites often have more or fewer features.
- Free camping legality depends on current land-manager rules, fire restrictions and closures.

Practical implication: **never present a freecampsites.net record as authoritative.** Show the source, the last-verified date if available, and a link to the land manager.

## Licensing and permitted use

There is **no open license** on the listings. They are user-submitted content owned/curated by the site. The terms of use and `robots.txt` govern access. In practice:

- **Do not** scrape, bulk-download, or redistribute the database.
- **Do not** mirror listing text or photos into an app without permission.
- **Do** deep-link to detail pages when you want to show a specific site.
- **Do** use the site manually for research and verification.
- **Do** contact the site about bulk data submissions/partnerships; it publishes a bulk-upload template and invites data contributions: <https://freecampsites.net/bulk-data-submissions/>.
- **Best long-term path:** build your own openly licensed community reports (CC BY-SA) and optionally contribute corrections upstream.

This is consistent with the existing project decision in `docs/RESEARCH.md`: combine open government data + OSM + first-party community reports, and do not scrape freecampsites.net or iOverlander.

## How to use it in CampSitesUSA without violating terms

1. **Link-out layer.** When a user searches a corridor, query your own open inventory first; offer a "More free spots on Freecampsites.net" deep link for the map area or place.
2. **Manual verification queue.** When an OSM/BLM/USFS record is ambiguous, a human can check freecampsites.net and record only the *fact* (e.g., "BLM land, 14-day limit") with a citation, not copy the listing.
3. **Entity matching.** Match by rounded coordinates + normalized name to detect duplicates in your own dataset; do not import the site's descriptions or photos.
4. **Partnership.** If bulk data is essential, ask for written permission and agree on attribution, refresh cadence and redistribution limits.

## Adapter contract (if permission is granted)

If you later get permission, normalize each record to the project's unified `Site` schema:

```json
{
  "source": "freecampsites",
  "source_id": "169377",
  "name": "Oregon Badlands Dispersed Camping",
  "site_type": "dispersed",
  "ownership": "public",
  "manager": "BLM",
  "fee": "free",
  "permit_required": false,
  "latitude": 43.98,
  "longitude": -121.02,
  "state": "OR",
  "county": "Deschutes",
  "max_rig_ft": null,
  "road_access": null,
  "amenities": [],
  "activities": [],
  "open_season": null,
  "stay_limit_days": null,
  "rating": 3.33,
  "rating_count": 12,
  "last_verified": null,
  "source_url": "https://freecampsites.net/#!169377&query=sitedetails",
  "license": "used-with-permission"
}
```

Keep `source_url` and `license` on every row, and make deletions/updates propagate on refresh.

## Alternatives with clearer licensing

| Need | Better-licensed option |
|---|---|
| Free/informal sites | OpenStreetMap `tourism=camp_site` + `fee=no` (ODbL) |
| BLM camping with stay limits | BLM National Recreation Sites & Facilities (public domain) |
| USFS campgrounds and trailheads | USFS EDW Recreation Opportunities (CC BY 4.0) |
| Federal campground inventory + prices | Recreation.gov search snapshot (check terms) / RIDB (public domain) |
| Community reviews and cell signal | Your own CC BY-SA reports; link out to Campendium/The Dyrt |
| Dump stations, water, showers | OSM (`amenity=sanitary_dump_station`, `drinking_water`, `shower`) |

## Sources

- Freecampsites.net: <https://freecampsites.net/>
- Submission guidelines: <https://freecampsites.net/submission-guidelines#campsites>
- Bulk data submissions: <https://freecampsites.net/bulk-data-submissions/>
- FAQ: <https://freecampsites.net/faq/>
