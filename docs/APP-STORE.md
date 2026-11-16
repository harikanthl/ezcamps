# ezcamp: App Store submission

Status as of 2026-11-16. Release build for a device compiles with no warnings.

## Done in the project

- Bundle ID `com.harikanthlingutla.CampSitesUSA`, display name **ezcamp**, version 1.0 (build 1), iPhone only, iOS 26.2.
- App icon (light, dark, tinted).
- Privacy manifest `CampSitesUSA/PrivacyInfo.xcprivacy`: no tracking; collects User ID and Other User Content (shared ratings only, app functionality); UserDefaults reason CA92.1.
- `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), so no export compliance questions.
- Permission strings: location (when in use), camera, microphone, add to Photos.
- Sign in with Apple entitlement; account deletion in Settings (deletes everything shared).
- Every testing aid is behind `#if DEBUG` (launch arguments only).
- Privacy policy: https://harikanth.site/ezcamp/privacy · Support: https://harikanth.site/ezcamp/support

## Blockers before you submit

1. **Sign in with Apple token revocation.** Guideline 5.1.1(v) expects apps with Sign in with Apple to revoke the token when an account is deleted. Needs a Sign in with Apple key (.p8) and its Key ID from the developer account; then the Worker calls Apple's `/auth/revoke`.
2. **NPS key.** Rotate the leaked key and set it on the Worker (`npx wrangler secret put NPS_API_KEY` in `server/ratings`), or park alerts show "not available".
3. **Test on a real iPhone:** Sign in with Apple, rating sync, camera, gear cut-outs (Vision can't run in the Simulator), Ask ezcamp with a real model (on-device and with a key), trip reel save to Photos.
4. **Screenshots** at 6.9" (iPhone 17 Pro Max, 1320×2868). Boot a 17 Pro Max simulator and use the debug launch arguments (README) for clean screens: map with 3D pins, site card with Safety, Fishing & hunting, Ask ezcamp, pack list, trip reel, gear closet.
5. **Decide the price** (free, or paid tier) before creating the app record.

## App Store Connect: privacy answers

- Data used to track you: none.
- Data linked to you: **User ID** and **Other User Content**, only if the person signs in to share ratings; purpose App Functionality.
- Location: used on the device only (nearby sites, verified ratings), not collected.
- Photos, videos, gear photos: stay on the device, not collected.
- Chat with a cloud provider: sent to the provider the person chose with their own key; the developer receives nothing. (Third-party data handling by a provider the user configured; describe in the policy, which is done.)

## Draft listing

**Name:** ezcamp: Campsites & Trips
**Subtitle:** Free camping, safety, trip reels
**Promotional text:** Ask anything about where to camp tonight. Every answer shows its source.

**Description:**
Find a campsite you can trust before you drive out.

ezcamp maps 29,105 campsites across all 50 states from open public data: the National Park Service, Recreation.gov, the Forest Service, BLM and OpenStreetMap. Spots without details stay hidden until you zoom in, so the map shows places you can actually judge.

• Ask ezcamp: chat over the map. "Free camps near Moab with water?" The answer comes from ezcamp's data, with sources, and the map follows along. Works with Apple Intelligence on your iPhone, or your own Claude or OpenAI key.
• Can I camp here? Long-press anywhere to see who manages the land and the usual rules, plus Forest Service road access.
• Tonight's conditions: overnight lows, wind, rain, smoke and wildfires within 50 miles.
• Safety heads-up: what campers reported, park alerts, the nearest hospital and police or ranger station, and county context from FBI data.
• Fishing & hunting: fish and game recorded nearby, live river flow, and license rules for every state.
• Pack lists: water, food and gear for hiking, biking, fishing or hunting, sized to the forecast. Every line cites its source.
• My gear: photograph your gear and it becomes cut-out stickers on shelves, ready to tick off when you pack.
• Road trips: a camp at the end of every day's drive, free sites first.
• Trip reels: your route, every camp by day, and your photos, ready to share with family. Want music on the beat, captions and a YouTube cut too? Open it in ezReels.
• Ratings you can trust: ratings logged at the campsite are marked verified and count double.

No ads, no tracking.

**Keywords:** camping,campsite,boondocking,dispersed,BLM,national park,RV,road trip,hiking,fishing,hunting,packing list
**Category:** Travel (secondary: Navigation)
**Age rating:** 4+ (no objectionable content; user ratings are moderated by reports).

## Reviewer notes (draft)

- No account needed. Sign in with Apple is only for sharing ratings; Settings › Shared ratings has Delete account.
- Ask ezcamp uses Apple's on-device model on devices with Apple Intelligence; elsewhere it asks for the user's own API key (Settings › AI). No key is needed to use the rest of the app.
- Long-press the map to try "Can I camp here?".
