# Gear closet research for ezcamp

Compiled 2026-11-16. Scope: photo-to-cutout "closet" apps, outdoor gear list apps, Apple on-device APIs, permissive open source, and a v1 recommendation for "My gear closet".

A note on sources: many comparison pages are written by competitors (Packstack, Indyx, Wardrowbe, MetaGear), so I relied on App Store listings, official feature pages, and repo files where I could. Prices are US App Store prices as listed in November 2026.

---

## 1. Apps in this space

### Outdoor gear apps

**Packstack** (web, iOS, Android): the strongest current gear closet app for backpackers.
- What it does well: a gear closet with weight, brand, price, category, and quantity owned, plus the total value of your kit. Items are tagged as base, worn, or consumable, with base/worn/consumable and per-category weight charts. **Kits** bundle items you always carry together so you can add them in one tap. An **over-pack warning** flags when a trip uses more of an item than you own. A **gear lifecycle** feature gives a replacement score from age, nights used, and condition. Checklist mode turns any list into a tick-off list. Read-only share links include the weight breakdown. It imports LighterPack and CSV lists, auto-fills weights from a product database, and has an MCP server so assistants can read your gear.
- Gap: the closet is text and spec driven. There is no photo-cutout closet.
- Pricing: free tier (closet, 3 lists, 1 kit). Pro is monthly, annual, or one-time, and adds unlimited lists and kits, calories and water, and multiple packs per trip.
- Sources: [packstack.io](https://packstack.io/), [App Store](https://apps.apple.com/us/app/packstack-app/id6760873801), [Packstack vs PackWizard (vendor-written)](https://www.packstack.io/learn/packstack-vs-packwizard)

**LighterPack** (web): the long-standing default for ultralight hikers.
- What it does well: a gear library you drag into lists, categories, worn and consumable flags, a pie chart, CSV import and export, item images, prices, and a share link. It is fast and dense.
- Gap: desktop-first and weak on phones. The code is GPL-2.0, so it is useful for ideas only (see section 3).
- Pricing: free.
- Sources: [lighterpack.com](https://lighterpack.com/), [GitHub](https://github.com/galenmaly/lighterpack)

**PackWizard** (web)
- What it does well: a "Gear Closet" split into **bins** so you don't scroll one long list, a large product database for autofill, weight pie charts, public lists with tags, a "pack browser" of other people's lists, and LighterPack import.
- Gap: forum users call the mobile experience poor and say the product database is hard to keep current. It uses affiliate links.
- Pricing: free to use, with affiliate revenue. No public paid tier found.
- Sources: [Backpacking Light forum thread](https://backpackinglight.com/forums/topic/new-potential-lighterpack-replacement/), [Packstack comparison (vendor-written)](https://www.packstack.io/learn/packstack-vs-packwizard)

**HikerKit, MetaGear, PackList** (newer iOS apps)
- What they do well: HikerKit stores a photo per item along with weight, brand, price, and category, and builds a separate list per trip. MetaGear shows base, pack, and total weight live. PackList is free and fully offline.
- Sources: [HikerKit](https://apps.apple.com/app/id6756064941), [MetaGear blog](https://metagear-app.pages.dev/blog/gear-list-app/), [PackList](https://apps.apple.com/us/app/id6753640568)

**GearGrams**: no current information found. The homepage returns only a title, so treat it as dormant.

**Hikeventory**: not a gear closet app. [hikeventory.com](https://hikeventory.com/) is a Dutch outdoor-deals price comparison site.

### Wardrobe apps that pioneered the photo-to-cutout closet

**Whering** (4.7 stars, about 12K ratings)
- What it does well: automatic background removal on your own photos, plus an **Enhance** step that fixes lighting and smooths creases. A catalog of over 100 million items lets you add things without taking a photo. Stats cover cost-per-wear, wear rate, colour palette, and an "Unpacked" recap of what you actually wore. It has **packing lists with smart reminders**, weather-based outfit ideas, and browsing of friends' closets.
- Weakness: reviewers say the cutout sometimes leaves background bits, the AI style and colour guesses are often wrong, and they want manual erase and restore tools.
- Pricing: free core app. Credits for AI styling cost $2.99 to $12.99, and optional supporter tiers run $0.99 to $49.99.
- Source: [App Store](https://apps.apple.com/us/app/whering-your-digital-closet/id1519461680)

**Acloset** (4.5 stars, about 5.6K ratings)
- What it does well: **single and continuous camera modes**, and the app remembers the last one you used. Snapshots are cleaned up into "store-quality" cutouts with manual edits available, and AI fills in category and colour, with a "Let AI choose" option. It also offers store and Gmail receipt import, a **Packing feature for trips** (clothes, outfits, plus non-closet items) with weather-based outfit suggestions, and wear tracking with cost-per-wear.
- Pricing: free up to 100 items. Basic is $3.99/mo or $27.99/yr, Premium is $9.99/mo or $59.99/yr, and there are coin packs.
- Sources: [App Store](https://apps.apple.com/us/app/acloset-ai-fashion-assistant/id1542311809), [Acloset support](https://www.acloset.app/support/)

**Indyx** (4.8 stars, about 1.7K ratings)
- What it does well: add items from a photo, a forwarded receipt, or a product link. "Enhance" removes the background and turns the photo into a clean flat-lay. AI tags category, subcategory, and colour. An email receipt scanner puts found items into a **Review tab for approval**, which is a good pattern for anything auto-detected. You can sort by wears and cost-per-wear, and a dashboard flags underused items. **Collections** work as packing lists: adding an outfit expands into an itemized list. Closets are private by default and can be shared.
- Pricing: $12.99/mo or $74.99/yr. Basic closet and per-item wear stats are free.
- Source: [App Store](https://apps.apple.com/us/app/-/id1599179405)

**Stylebook** (long-running iOS app)
- What it does well: the most complete capture toolkit. AI cutout works even on batches of photos, with a slider, an eraser, and **tap-to-clear** for fixes, and backgrounds can be edited after import. **Continuous Import** adds photos back to back without reopening menus. Stats include closet value, items "not used in any outfit", items "not recorded on calendar", and top 10 most and least worn. **Packing lists** have a checklist, a destination image, and an unlimited archive, and adding an outfit pulls in its items.
- Pricing: one-time purchase of about $4.99.
- Sources: [features page](https://stylebookapp.com/features.html), [App Store](https://apps.apple.com/us/app/stylebook/id335709058)

**OpenWardrobe**
- What it does well: AI-assisted photo add with no stated item limit, sharing a closet with friends, and resale value estimates.
- Pricing: free. Premium is $9.99/mo or $78/yr.
- Source: [App Store](https://apps.apple.com/us/app/id1549029468)

### Ideas worth borrowing, by theme

| Theme | Best example | Idea for ezcamp |
|---|---|---|
| Capture flow | Acloset continuous mode, Stylebook Continuous Import | A "keep shooting" camera so you can add 20 items in one session. Cut out and tag in the background. |
| Background removal | Stylebook (batch, eraser, tap-to-clear) | Automatic cutout, plus a tap-to-fix tool for when it gets it wrong. |
| Auto-categorization | Indyx Review tab, Acloset "Let AI choose" | Suggest a category and let the person confirm it. Never save a guess silently. |
| Weight tracking | Packstack, LighterPack | Base, worn, and consumable flags, a total, and a per-category chart. |
| Trip lists | Packstack kits, Stylebook outfit expands to items | "Kits" such as a Kitchen bin or a Sleep system that expand into their items. |
| Owned vs packed | Packstack over-pack warning | Warn when a list needs 4 sleeping pads and you own 2. |
| Used stats | Indyx and Whering cost-per-wear, Stylebook least worn | Nights used per item, cost per night, and a "haven't used in a year" shelf. |
| Lifecycle | Packstack replacement score | Expected-life benchmarks by category (MIT data, see section 3). |
| Sharing | Packstack read-only link, Indyx private by default | Private by default, with a share card image or link for a trip's list. |
| Checklist UX | Stylebook checklist, Packstack checklist mode | Tap to pack, and show progress. |

---

## 2. Apple on-device APIs

ezcamp's deployment target is iOS 26.2, so everything below except the iOS 27 items works without availability checks.

### Subject lifting (background removal)

**VisionKit `ImageAnalysisInteraction`** (iOS 16+). This is the system "lift subject" behaviour from Photos. Set `preferredInteractionTypes = [.imageSubject]`, run `ImageAnalyzer.analyze(_:configuration:)`, then read `subjects`, `subject(at:)`, `highlightedSubjects`, and `image(for:)`, which returns a `UIImage` with the background removed. It gives you the familiar long-press-to-lift glow for free.
- [ImageAnalysisInteraction](https://developer.apple.com/documentation/visionkit/imageanalysisinteraction)
- [WWDC23 "Lift subjects from images in your app"](https://developer.apple.com/videos/play/wwdc2023/10176/)

**Vision `GenerateForegroundInstanceMaskRequest`** (Swift API, iOS 18+; the older `VNGenerateForegroundInstanceMaskRequest` is iOS 17+). This is the headless pipeline. It returns an `InstanceMaskObservation` with **one instance per object**, so you can generate a masked image per instance, cropped to its content. Use it to cut out in the background without any UI, and to split a photo of several items into separate cutouts. It is class-agnostic, so it works on tents, stoves, and boots, not only people and pets.
- [GenerateForegroundInstanceMaskRequest](https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest)
- [InstanceMaskObservation](https://developer.apple.com/documentation/vision/instancemaskobservation)
- [VNGenerateForegroundInstanceMaskRequest](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)

**New in iOS 27 (WWDC26 session 237): tap-to-segment.** `GenerateIterativeSegmentationRequest(seed: point)` segments the object under a tap. You refine it with `addIncludedPoint(_:)` and with excluded points, and the demo also shows boxes, lassos, and scribbles. The model downloads on demand, so check `assetStatus` and call `downloadAssets`. This is the right tool for a "fix the cutout" editor, gated with `if #available(iOS 27, *)`.
- [WWDC26 "What's new in image understanding"](https://developer.apple.com/videos/play/wwdc2026/237/)

**iOS 26 Vision additions** (WWDC25) don't touch segmentation: `RecognizeDocumentsRequest` and `DetectLensSmudgeRequest`. Smudge detection is a cheap quality check before capture ("wipe your lens").
- [DetectLensSmudgeRequest](https://developer.apple.com/documentation/vision/detectlenssmudgerequest)
- [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)
- [WWDC25 session 272](https://developer.apple.com/videos/play/wwdc2025/272/)

### Auto-categorizing items

**Vision `ClassifyImageRequest`** (iOS 18+, or `VNClassifyImageRequest` on earlier versions). This is Apple's built-in taxonomy of roughly 1,300 labels; check `supportedIdentifiers` for the exact list. It runs on every device, fast and on-device. Map its labels to ezcamp categories with a small lookup table (for example "tent" to Shelter, "backpack" to Packs, "lantern" or "flashlight" to Lighting). Run it on the cutout, not the full photo, for better accuracy.
- [ClassifyImageRequest](https://developer.apple.com/documentation/vision/classifyimagerequest)

**Foundation Models image input** (iOS 27, Apple Intelligence devices only). `Prompt { "…"; Attachment(image) }`, and `session.respond(generating: GearGuess.self)` should give a typed `@Generable` result with name, category, and an "is this worn" guess. Image arguments also work in tool calling through `ImageReference`. The context window is 4K tokens on device, and images draw from the same budget. Use this as an upgrade over `ClassifyImageRequest` where available, and keep Vision as the fallback.
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [WWDC26 "What's new in the Foundation Models framework" (241)](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 image understanding (237)](https://developer.apple.com/videos/play/wwdc2026/237/)
- Caveat: Apple's pages confirm `Attachment(image)` and `ImageReference`. Whether every image prompt runs fully on device was not stated explicitly. Verify in the Xcode 27 SDK.

**Other useful pieces**
- `GenerateObjectnessBasedSaliencyImageRequest` for auto-cropping a thumbnail.
- `RecognizeTextRequest` to read a brand or model name off a label or tag, which can pre-fill the name.
- `VNDetectBarcodesRequest` or the Foundation Models `BarcodeReaderTool` to scan a UPC on the box.

---

## 3. Open source (licenses checked in the repo itself)

Licenses were checked by fetching the LICENSE file from each repo on 2026-11-16. Stars and last push come from the GitHub API on the same date.

### Permissive and reusable

| Repo | License (verified) | Stars | Last push | What is reusable |
|---|---|---|---|---|
| [Packstack-Tech/packstack-api](https://github.com/Packstack-Tech/packstack-api) | MIT (LICENSE: "MIT License, Copyright (c) 2024 Packstack") | 6 | 2026-11-13 | The best data model reference. `app/utils/gear_lifecycle.py` has a ready **category taxonomy with expected lifespan per category** (Shelter 5 yr/300 nights, Pack, Sleep System, Footwear 500 mi, Clothing, Cookware, Electronics, Water System, Tools, First Aid, Safety, Camera, Climbing, Toiletries, Miscellaneous) and condition scores (new, good, fair, worn). `item_category.py` has the shared-vs-user category design, `overpack.py` the owned-vs-packed check, `pack_weight.py` and `weight.py` the base/worn/consumable weight math and units. |
| [Packstack-Tech/packstack](https://github.com/Packstack-Tech/packstack) | Apache-2.0 (LICENSE.txt) | 90 | 2023-03-06 | The older web UI. List builder and weight chart UX patterns. Stale. |
| [pigmonkey/django-geartracker](https://github.com/pigmonkey/django-geartracker) | BSD-3-Clause (LICENSE) | 3 | 2013-05-25 | A small, clean model: Category, then Type, then Item (make, model, grams, acquired date, size, image, related items, archived), and List or ListItem with quantity and carry type, plus trip dates and location. A good minimal schema to copy. |
| [jimothyGator/packlist](https://github.com/jimothyGator/packlist) | MIT (LICENSE.txt) | 7 | 2016-05-24 | A plain-text DSL for gear lists with unit-aware weights (g, kg, oz, lb). Its idea of a master list copied per trip is worth noting. |
| [lkellar/trips](https://github.com/lkellar/trips) | MIT (LICENSE) | 4 | 2022-07-25 | A SwiftUI packing list app with a template, trip, and checklist flow. Small, and Swift. |
| [kamil-kucharski/vestiq](https://github.com/kamil-kucharski/vestiq) | MIT (LICENSE) | 9 | 2026-11-07 | An Android (Kotlin) private wardrobe app: local-only storage, a versioned backup file, and an on-device stylist. Useful for the privacy and backup pattern, not the code. |
| [paladini/lighterpack-mcp](https://github.com/paladini/lighterpack-mcp) | MIT (per GitHub API) | 3 | 2026-11 | Shows how an assistant can read and write gear lists. Relevant to Ask ezcamp. |
| [danielgatis/rembg](https://github.com/danielgatis/rembg) | MIT (per GitHub API) | 25.5K | 2026-11-06 | Server-side background removal. Not needed on iPhone, since Vision does this on device. |

### Not permissive (ideas only, don't copy code)
- [galenmaly/lighterpack](https://github.com/galenmaly/lighterpack): GPL-2.0, 817 stars, active (pushed 2026-10-21). Its CSV format is the de facto import standard, so supporting **LighterPack CSV import** is worth doing. Reading a file format is fine. Copying their code is not.
- [PackRat-AI/PackRat](https://github.com/PackRat-AI/PackRat): the README says GPL-3.0, but there is no LICENSE file at the root. 36 stars, very active.
- [Columbia19/Camping-Checklist](https://github.com/Columbia19/Camping-Checklist): CC-BY-SA-4.0 (share-alike). It is a car-camping checklist taxonomy, but share-alike makes bundling it awkward. Use it only as a cross-check against your own cited packing.json.

Nothing open source yet does a photo-cutout gear closet for camping. That is open ground.

---

## 4. Recommendation: "My gear closet" v1

ezcamp already generates cited pack lists by activity, nights, people, and forecast (`Models/PackList.swift` plus `Resources/packing.json`). The closet's job is to turn "you need a headlamp" into "**your** Petzl headlamp, packed".

### v1 feature set
1. **Snap to add, continuous.** A camera that keeps shooting. Each shot is cut out on device with `GenerateForegroundInstanceMaskRequest` and saved as both the original and a cutout PNG with transparency. A photo-library picker sits beside it. If the photo has no clear subject, keep the original photo with a soft rounded frame rather than a broken cutout.
2. **Suggested category, person confirms.** `ClassifyImageRequest` on the cutout, mapped to about 15 camping categories seeded from Packstack's MIT list and adapted for car camping (Shelter, Sleep, Kitchen, Water, Lighting, Clothing, Footwear, Packs and bags, Tools, First aid, Safety, Navigation, Fishing, Hunting, Fun and comfort). On iOS 27 devices with Apple Intelligence, use Foundation Models with a `@Generable` guess for name and category. New items land in a small "Review" tray, following the Indyx pattern, so nothing auto-tagged is saved silently.
3. **The closet view.** Stickers on shelves grouped by category, with search and filter by activity. Tap a sticker for details: name, brand, quantity owned, weight, base/worn/consumable, notes, and acquired date.
4. **Weight with its basis shown.** Weight is optional. When it is present, show where it came from ("weighed by you" or "maker's listed weight"), which fits ezcamp's trust rule. Show trip totals only when most items have a weight, and say how many are missing.
5. **Closet-aware pack lists.** Each generic line in the existing smart list (for example "Headlamp, NPS source") matches closet items by category and keyword. The line becomes **"Have it"** with your sticker, **"Need it"**, or **"Pick one"** when you own several. Keep the existing source citation on the line. Show an owned-vs-needed warning, following Packstack's over-pack check ("List needs 4 sleeping pads, you own 2").
6. **Kits.** Group items you always bring together (Kitchen bin, Sleep system). A kit adds to a list in one tap.
7. **Pack checklist.** Tap a sticker to mark it packed, with a progress ring, saved per trip on the existing Trips screen.
8. **Used stats, light.** After a trip, mark what you actually used. Each item tracks nights used and a "last used" date, and there is a "Didn't use on your last 3 trips" shelf. Skip cost-per-wear in v1. It needs prices most people won't enter.
9. **Private and on device.** Store with SwiftData and the image files locally, and back them up through iCloud later. Sharing is a rendered image of the pack (stickers laid out), not an account system.
10. **Import.** Accept LighterPack CSV so ultralight users can bring their weights in.

### 3 delightful touches that set it apart
1. **"Gear explosion" capture.** Lay your gear on the floor the way hikers do for "what's in my pack" photos. Take one picture, and `GenerateForegroundInstanceMaskRequest` splits every instance into its own sticker at once, each auto-categorized into the Review tray. No closet or gear app does multi-item capture today. It turns a 30-minute chore into one shot.
2. **Peel-and-pack physics.** Cutouts get a white die-cut sticker border and a soft shadow. Long-press lifts a sticker (the VisionKit lift feel), and dragging it onto a backpack or tote at the bottom of the screen packs it, with a gentle drop haptic and the bag's weight gauge ticking up. Packing becomes satisfying rather than a chore, which fits the bright, lively palette.
3. **The cited "gap check" for this site.** When you open a campsite, the closet answers "Are you ready for this place?" in a short list. It is built from the forecast low, the site's bear storage rule, and the activities, and every line shows its source. Example: "Bear canister: needed here (NPS food storage order). You don't own one. Your 30°F bag: OK for Friday's low of 34°F (forecast)." Generic list apps can't do this. It uses data ezcamp already has.

### Build notes
- Data model sketch: `GearItem(id, name, brand?, category, quantity, weightGrams?, weightSource {weighed, listed, unknown}, carry {base, worn, consumable}, activities: Set<PackActivity>, photoOriginal, photoCutout?, condition, acquired?, nightsUsed, lastUsed?, notes)`, `GearKit(id, name, items)`, `TripPack(tripID, entries: [(itemID, qty, packed: Bool, used: Bool?)])`.
- Store cutouts as HEIC with alpha (or PNG) at about 1024 px on the long edge, plus a small thumbnail for the grid.
- Run Vision work off the main actor and show the original photo immediately, so the shutter never waits on segmentation.
