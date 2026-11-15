# Free & Dispersed Camping Rules — A Practical Guide

_Compiled 2026-11-15. This is a product-engineering summary, not legal advice. Rules change by district, season and fire conditions. Always link the user to the current agency page._

The core product question is not "is there a pin here?" but **"am I allowed to sleep here tonight?"** That answer comes from four layers:

1. **Who owns/manages the land?** → PAD-US / BLM SMA / agency boundary
2. **Is dispersed camping allowed by default?** → agency policy
3. **Is this specific road/area open?** → MVUM, closures, fire restrictions
4. **Is there a stay limit or permit?** → district/forest order

---

## Federal agencies

| Agency | Default dispersed camping | Typical stay limit | What to check | Official source |
|---|---|---|---|---|
| **BLM** | Generally allowed on undeveloped BLM land unless closed or posted | 14 days within a 28-day period (varies by district) | District rules, fire restrictions, special recreation areas, LTVA boundaries | <https://www.blm.gov/programs/recreation/camping> |
| **USFS** | Generally allowed along forest roads/trails unless posted | 14 days (varies by forest; some 5–14) | MVUM, forest orders, free permits, fire restrictions, wilderness boundaries | <https://www.fs.usda.gov/visit/know-before-you-go/camping> |
| **NPS** | Generally **not** allowed outside designated campgrounds or backcountry zones | Designated sites only | Backcountry permit, campground reservation, closures | <https://www.nps.gov/subjects/camping/index.htm> |
| **USACE** | Designated campgrounds; some projects allow primitive camping | Varies by project | Project rules, reservoir boundaries | <https://www.usace.army.mil/Missions/Civil-Works/Recreation/> |
| **BOR** | Usually designated campgrounds | Varies | Concession rules, reservoir pages | <https://www.usbr.gov/recreation/> |
| **FWS** | Varies by refuge; often prohibited | Varies | Refuge-specific hunting/fishing/camping rules | <https://www.fws.gov/refuges/> |
| **TVA** | Designated campgrounds and some dispersed areas | Varies | TVA reservoir rules | <https://www.tva.com/environment/recreation> |

### BLM

- **Default:** dispersed camping is allowed on most undeveloped BLM land.
- **14-day rule:** the common limit is 14 days in any 28-day period, but districts differ. Some require moving 25 miles; some are 7 days.
- **Long Term Visitor Areas (LTVA):** Quartzsite, Yuma, Imperial Dam, Hot Springs and others. A seasonal permit (roughly $180) covers the season and includes water/dump/trash at some areas. Winter-only.
- **Special areas:** developed campgrounds, special recreation management areas, wilderness study areas and closed areas override the default.
- **Check:** the district office page, fire restrictions, and any temporary closure order.

### USFS

- **Default:** dispersed camping is generally allowed on National Forest System land unless posted or prohibited by a forest order.
- **MVUM is the map:** the Motor Vehicle Use Map shows which roads are open to which vehicle classes. If a road is not on the MVUM, motorized use is generally prohibited. Camping must be within the corridor allowed by the MVUM.
- **Stay limits:** commonly 14 days, but forests can set 5, 7 or 14. Some require a free dispersed-camping permit.
- **Wilderness:** no mechanized or motorized access; camping is allowed but subject to wilderness rules and permits in some areas.
- **Check:** forest order, MVUM, fire restrictions, and the local ranger district.

### NPS

- Camping is generally limited to designated campgrounds and backcountry zones.
- Backcountry camping usually requires a permit (often reservable on Recreation.gov).
- Some parks allow "primitive" camping in specific zones; rules are park-specific.
- **Do not** treat NPS land as dispersed-camping land.

### USACE / BOR / FWS / TVA

- Assume designated campgrounds only unless the project/refuge page says otherwise.
- USACE and BOR campgrounds are frequently on Recreation.gov; FWS refuges often allow hunting/fishing but not camping.
- TVA has a mix of developed campgrounds and primitive areas; check the reservoir page.

---

## State and local land

| Land type | General rule | Examples / notes |
|---|---|---|
| **State parks** | Designated campgrounds only | Reservation platforms vary; see `STATE-PARKS.md` |
| **State forests** | Varies; often dispersed allowed with a permit | Check the state forestry agency |
| **Wildlife Management Areas (WMAs)** | Varies; often allowed outside hunting season, sometimes prohibited | State fish & wildlife agency is the authority |
| **State trust land** | Often closed or permit-only | Arizona requires a recreation permit; NM/UT/CO/TX differ |
| **County/city parks** | Varies; many allow camping, many do not | Call the parks department |
| **Utility land** | Varies; some utilities run cheap campgrounds | TVA, SCE, PG&E, APS, SRP |
| **Tribal land** | Permission required | Never assume public access |

### State trust land examples

- **Arizona:** State Trust Land requires a recreation permit for most access; camping is restricted. <https://www.azland.gov/>
- **New Mexico:** State Trust Land camping requires a permit; some areas are leased. <https://www.nmstatelands.org/>
- **Utah:** SITLA land is generally closed to recreation unless a lease/easement says otherwise. <https://trustlands.utah.gov/>
- **Colorado:** State Land Board land is generally not open to public recreation. <https://www.colorado.gov/trustlands>
- **Texas:** General Land Office land varies; much is leased. <https://www.glo.texas.gov/>

---

## Fire, closures and seasons

Fire restrictions can close dispersed camping entirely, even where camping is normally allowed.

| Layer | Source |
|---|---|
| USFS fire restrictions | <https://www.fs.usda.gov/visit/know-before-you-go/fire> |
| BLM fire restrictions | <https://www.blm.gov/programs/fire-and-aviation/fire-restrictions> |
| NPS alerts/closures | `https://developer.nps.gov/api/v1/alerts` |
| Active fires | <https://www.nifc.gov/fire-information> |
| Smoke/AQI | <https://www.airnow.gov/> |
| Statewide fire bans | State forestry or emergency management |

Seasonal issues to encode:

- **Snow:** high-country roads close; SNOTEL and 511 cameras help.
- **Monsoon:** flash floods in the Southwest; FEMA flood zones + NWS alerts.
- **Hurricane season:** Gulf/Atlantic coast, June–November.
- **Hunting season:** WMAs and some state forests close or restrict camping.
- **Spring mud:** many forest roads are seasonally closed to protect them.

---

## Overnight parking (not camping)

These are parking/lodging fallbacks, not campsites. Policies are local and change.

| Place | General policy | Verify |
|---|---|---|
| **Walmart** | Corporate defers to store/local law; many allow one night, some cities prohibit | Call the store |
| **Cracker Barrel** | Many stores allow one night in an RV | Call the store |
| **Truck stops** (Pilot, Love's, TA/Petro) | Often allow overnight; amenities are the draw | Ask the desk |
| **Casinos** | Many allow overnight RV parking; some charge | Call the casino |
| **Rest areas** | State- and site-specific; some prohibit overnight | State DOT |
| **Cabela's / Bass Pro** | Many allow overnight | Call the store |
| **Elks / Moose lodges** | Members often may stay | Lodge policy |

Never present any of these as guaranteed. A "call ahead" prompt is part of the feature, not a disclaimer afterthought.

---

## Leave No Trace (encode in the app)

- Camp at least **200 ft** from water, trails and roads where required.
- Pack out all trash; do not bury it.
- Use a portable toilet or dig a cathole **6–8 inches deep**, 200 ft from water.
- Keep campfires small; use existing rings; check restrictions.
- Do not cut standing trees or branches.
- Store food properly; respect wildlife.
- Leave gates as you found them.
- Respect other visitors and quiet hours.

---

## A defensible "Can I camp here?" answer

Return one of:

- **Likely yes** — public land, agency allows dispersed camping, no closure, within stay limit.
- **Yes, with a permit** — permit required; show how to get it.
- **Designated sites only** — NPS/USACE/state park pattern.
- **Likely no** — private, tribal, state trust, closed area, or fire closure.
- **Unknown — check with the ranger** — missing ownership or conflicting data.

Always show:

1. The land manager and parcel name (from PAD-US).
2. The rule source and date.
3. The nearest ranger district phone number.
4. A "report a problem" link.

Never show a bare green "allowed" pin on land you cannot prove is public.

---

## Sources

- BLM camping: <https://www.blm.gov/programs/recreation/camping>
- BLM LTVA: <https://www.blm.gov/programs/recreation/permits-and-passes/long-term-visitor-areas>
- USFS camping: <https://www.fs.usda.gov/visit/know-before-you-go/camping>
- USFS MVUM: <https://www.fs.usda.gov/visit/maps>
- NPS camping: <https://www.nps.gov/subjects/camping/index.htm>
- USACE recreation: <https://www.usace.army.mil/Missions/Civil-Works/Recreation/>
- FWS refuges: <https://www.fws.gov/refuges/>
- PAD-US: <https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download>
- Leave No Trace: <https://lnt.org/>
