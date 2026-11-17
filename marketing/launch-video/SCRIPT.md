# ezcamp launch video — "A Year on Your Land" (voiceover)

One take in ElevenLabs → `assets/vo.mp3`. ~60–65 s. Scenes are re-timed to the real audio.

| Scene | Picture (real app footage) | Line |
|---|---|---|
| s1 | US map | Every American owns a share of six hundred and forty million acres of public land. Most of us never spend a single night on it. |
| s2 | Title: A year on your land | So this year, take your kid. |
| s3 Spring | Ask ezcamp near Moab; long-press → BLM "Likely yes" | Spring, just outside Moab. Ask ezcamp where you can camp tonight. It answers from real public data. Long-press the map. Bureau of Land Management. Yes, you can camp here. |
| s4 Summer | Kenai River (rivers layer); Russian River card: sockeye, Chinook, moose, AK license from 18 | Summer, on Alaska's Kenai River. Sockeye running, moose on the trail, and the river's flow, live. He doesn't even need a license yet. |
| s5 Fall | Merrisach Lake, AR: geese, bufflehead; AR supervised-hunting rule, duck stamp | Fall, in Arkansas duck country. Geese on the lake, and the rules for his first season, hunting at your side. |
| s6 Winter | La Posa LTVA, Quartzsite (BLM): 57° tonight, clear | Winter, in Quartzsite. Desert stars on BLM land, and tonight's low before you leave. |
| s7 | Plan with AI (Claude): Denver → Moab; gear shelf | Plan the drive, with a camp at the end of every day. Pack from the gear you already own. |
| s8 | Satellite Arches, topo Grand Teton, forest roads Sedona, rivers Kenai | Twenty-nine thousand campsites. All fifty states. |
| end | Logo | It's your land. Go camp on it. ezcamp. Free on the App Store. |

Sources: 640M acres — Congressional Research Service, *Federal Land Ownership: Overview and Data*. Species — iNaturalist research-grade sightings via ezcamp. Licenses — ezcamp `licenses.json`.

Gear photos (Wikimedia Commons, CC BY / BY-SA / CC0): Backpacking_Tent.jpg, JetBoil-camping-stove-under-cooking-pot.jpg, Enbrighten_LED_Camping_Lantern.jpg, Fishing_rod_&_reel_Mahamaya_Lake_(01).jpg, Hiking_boots.jpg, Altra trail running shoe Lone Peak side view.jpg, Quadcopter_camera_drone_in_flight.jpg, Hunting_rifle_02.png, Tropical_Rucksack_3.JPG.

## Audio (local only, git-ignored)

- `assets/vo.mp3`: ElevenLabs, voice "Brittney – Social Media Voice" (stability 50, similarity 75), 58.4 s. Scene cuts in `tools/build.py` are timed to its pauses.
- `assets/music.mp3`: "Dreaming Big" (Mixkit licence: free for commercial use, no attribution), from the vireeel catalogue (`mixkit-31`, `https://app.vireeel.com/v1/public/<r2_key>`). Cut from 0:08 for 60 s with a 1.2 s fade-in and a 3 s fade-out; played at volume 0.16 under the voice.
- Screen recordings in `assets/*.mp4` come from the "ezcamps iPhone" simulator via `simctl recordVideo` and are re-encoded to 30 fps CFR.
