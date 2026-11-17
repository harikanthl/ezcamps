#!/usr/bin/env python3
"""Writes compositions/sNN.html and index.html from SCENES. Edit timings here, rerun."""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# id, dur, gradient top, bottom, kicker, headline, sub, videos [(file, start_in_scene, dur, media_start, rate)], punch (t, focusY, scale) or None
SCENES = [
 ("s1", 8.3, "#5eead4", "#2f9bff", "", "640 million acres. Yours.", "America's public land. Most of us never spend a night on it.", [("map", 0, 8.3, 0, 1.0)], None),
 ("s2", 2.1, "#ffb347", "#ff5f8f", "", "A year on your land", "This year, take your kid.", [("map", 0, 2.1, 8.3, 1.0)], None),
 ("s3", 11.8, "#ffd166", "#ff7a45", "Spring · Moab, Utah", "Can I camp here?", "Ask. Then long-press the map to see whose land it is.", [("chat", 0, 6.9, 2.5, 1.7), ("land", 6.9, 4.9, 2.3, 1.0)], (8.7, 0.70, 1.4)),
 ("s4", 9.6, "#7dd3fc", "#22c55e", "Summer · Kenai River, Alaska", "First salmon", "Sockeye, moose, live river flow, and Alaska's license rules.", [("m_water", 0, 3.0, 2.5, 1.3), ("fish", 3.0, 6.6, 6.5, 1.0)], None),
 ("s5", 7.1, "#ffb347", "#c2410c", "Fall · Arkansas duck country", "First duck season", "What's been seen on the lake, and the rules for hunting at your side.", [("duck", 0, 7.1, 0, 1.0)], None),
 ("s6", 6.1, "#60a5fa", "#a855f7", "Winter · Quartzsite, Arizona", "Desert stars", "Free BLM land, and tonight's low before you leave.", [("m_winter", 0, 2.6, 2.5, 1.3), ("winter", 2.6, 3.5, 1.2, 1.2)], None),
 ("s7", 5.1, "#c084fc", "#ff8a1f", "", "Plan it. Pack it.", "A camp at the end of every day's drive, and the gear you already own.", [("ai", 0, 2.9, 0, 2.5), ("gear", 2.9, 2.2, 0, 1.2)], None),
 ("s8", 3.5, "#a3e635", "#10b981", "", "29,105 campsites", "All 50 states. Satellite, topo, forest roads, rivers and public lands.", [("m_sat", 0, 0.9, 1.5, 1.3), ("m_topo", 0.9, 0.9, 3, 1.3), ("m_lands", 1.8, 0.9, 4, 1.3), ("m_water", 2.7, 0.8, 5, 1.3)], None),
]
END = ("end", 6.4)
W, H = 1920, 1080

FONT = """@font-face{font-family:'Anton';src:url('assets/fonts/Anton-Regular.ttf') format('truetype');}"""

def scene(sid, dur, top, bot, kicker, head, sub, vids, punch):
    words = head.split()
    head_html = " ".join(f'<span class="w"><span id="{sid}-w{i}" class="wi">{w}</span></span>' for i, w in enumerate(words))
    vids_html = "\n".join(
        f'      <video id="{sid}-v{i}" class="clip" src="assets/{f}.mp4" data-start="{st}" data-duration="{d}" '
        f'data-media-start="{ms}" data-playback-rate="{r}" muted playsinline></video>'
        for i, (f, st, d, ms, r) in enumerate(vids))
    sub_html = f'<p id="{sid}-sub" class="sub">{sub}</p>' if sub else ""
    kick_html = f'<div id="{sid}-kick" class="kick">{kicker}</div>' if kicker else ""
    tw = []
    if kicker:
        tw.append(f'tl.fromTo("#{sid}-kick", {{clipPath: "inset(0 100% 0 0)"}}, {{clipPath: "inset(0 0% 0 0)", duration: 0.45, ease: "power3.inOut"}}, 0.05);')
    tw.append(f'tl.fromTo("#{sid} .wi", {{yPercent: 110}}, {{yPercent: 0, duration: 0.5, ease: "power4.out", stagger: 0.07}}, 0.15);')
    if sub:
        tw.append(f'tl.fromTo("#{sid}-sub", {{opacity: 0, y: 24}}, {{opacity: 1, y: 0, duration: 0.45, ease: "power3.out"}}, 0.15 + {len(words)} * 0.07 + 0.25);')
    if sid == "s1":
        tw.append(f'tl.fromTo("#{sid}-phone", {{y: 700}}, {{y: 0, duration: 0.8, ease: "power4.out"}}, 0);')
    if punch:
        t, fy, sc = punch
        tw.append(f'tl.set("#{sid}-phone", {{transformOrigin: "100% {fy*100:.0f}%"}}, 0);')
        tw.append(f'tl.fromTo("#{sid}-phone", {{scale: 1}}, {{scale: {sc}, x: -40, duration: 0.55, ease: "power3.inOut"}}, {t});')
        tw.append(f'tl.fromTo("#{sid}-text", {{opacity: 1}}, {{opacity: 0.0, duration: 0.3, ease: "power2.out"}}, {t});')
    return f"""<template>
  <style>
    {FONT}
    #root {{ position: absolute; inset: 0; overflow: hidden; }}
    #{sid}-bg {{ position: absolute; inset: 0; background: linear-gradient(165deg, {top} 0%, {bot} 100%); }}
    #{sid}-text {{ position: absolute; left: 150px; top: 0; bottom: 0; width: 820px; display: flex; flex-direction: column; justify-content: center; }}
    #{sid} .head {{ font-family: 'Anton'; font-size: 148px; line-height: 1.0; color: #fff; text-transform: uppercase; margin: 0; text-shadow: 0 6px 30px rgba(0,0,0,0.12); }}
    #{sid} .w {{ display: inline-block; overflow: hidden; vertical-align: top; padding-bottom: 6px; }}
    #{sid} .wi {{ display: inline-block; }}
    #{sid} .kick {{ font-family: 'Inter'; font-weight: 900; font-size: 34px; letter-spacing: 3px; text-transform: uppercase; color: #fff; background: rgba(0,0,0,0.16); align-self: flex-start; padding: 10px 18px; border-radius: 10px; margin-bottom: 26px; }}
    #{sid} .sub {{ font-family: 'Inter'; font-weight: 700; font-size: 40px; line-height: 1.3; color: rgba(255,255,255,0.95); margin: 28px 0 0; max-width: 760px; }}
    #{sid}-phone {{ position: absolute; left: 1150px; top: 60px; width: 444px; height: 960px; border-radius: 74px; background: #0d0d10; padding: 13px; box-shadow: 0 50px 90px rgba(40,10,0,0.30), inset 0 0 0 2px #2a2a30; }}
    #{sid}-screen {{ position: relative; width: 100%; height: 100%; border-radius: 61px; overflow: hidden; background: #fff; }}
    #{sid}-screen video {{ position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }}
  </style>
  <div id="root" data-composition-id="{sid}" data-width="{W}" data-height="{H}">
    <div id="{sid}" style="position:absolute;inset:0;">
    <div id="{sid}-bg"></div>
    <div id="{sid}-text">
      {kick_html}
      <h1 id="{sid}-head" class="head">{head_html}</h1>
      {sub_html}
    </div>
    <div id="{sid}-phone" data-layout-allow-overflow>
      <div id="{sid}-screen">
{vids_html}
      </div>
    </div>
    </div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    {chr(10).join('    ' + t for t in tw)}
    tl.set({{}}, {{}}, {dur - 0.01});
    window.__timelines["{sid}"] = tl;
  </script>
</template>
"""

def end_scene(dur):
    return f"""<template>
  <style>
    {FONT}
    #root {{ position: absolute; inset: 0; overflow: hidden; }}
    #end-bg {{ position: absolute; inset: 0; background: linear-gradient(165deg, #ffb347 0%, #ff5f8f 100%); }}
    #end-lock {{ position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; }}
    #end-row {{ display: flex; align-items: center; gap: 44px; }}
    #end-logo {{ width: 300px; height: 300px; border-radius: 68px; box-shadow: 0 40px 80px rgba(80,10,30,0.30); }}
    #end-word {{ font-family: 'Anton'; font-size: 230px; color: #fff; line-height: 1; letter-spacing: 1px; clip-path: inset(0 100% 0 0); }}
    #end-tag {{ font-family: 'Inter'; font-weight: 700; font-size: 52px; color: #fff; margin-top: 48px; }}
    #end-cta {{ font-family: 'Inter'; font-weight: 700; font-size: 38px; color: #ff5f3d; background: #fff; border-radius: 22px; padding: 18px 40px; margin-top: 30px; }}
  </style>
  <div id="root" data-composition-id="end" data-width="{W}" data-height="{H}">
    <div id="end-bg"></div>
    <div id="end-lock">
      <div id="end-row">
        <img id="end-logo" src="assets/logo.png" alt="ezcamp logo">
        <div id="end-word">ezcamp</div>
      </div>
      <div id="end-tag">It's your land. Go camp on it.</div>
      <div id="end-cta">Free on the App Store</div>
    </div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
    tl.fromTo("#end-logo", {{ scale: 0.2, rotation: -14, opacity: 0 }}, {{ scale: 1, rotation: 0, opacity: 1, duration: 0.7, ease: "back.out(1.6)" }}, 0.1);
    tl.fromTo("#end-word", {{ clipPath: "inset(0 100% 0 0)" }}, {{ clipPath: "inset(0 0% 0 0)", duration: 0.6, ease: "power3.inOut" }}, 0.55);
    tl.fromTo("#end-tag", {{ opacity: 0, y: 20 }}, {{ opacity: 1, y: 0, duration: 0.4, ease: "power3.out" }}, 0.25);
    tl.fromTo("#end-cta", {{ opacity: 0, y: 20 }}, {{ opacity: 1, y: 0, duration: 0.4, ease: "power3.out" }}, 3.4);
    tl.set({{}}, {{}}, {dur - 0.01});
    window.__timelines["end"] = tl;
  </script>
</template>
"""

def main():
    t = 0.0
    hosts = []
    for i, sc in enumerate(SCENES):
        sid, dur = sc[0], sc[1]
        open(f"{ROOT}/compositions/{sid}.html", "w").write(scene(*sc))
        hosts.append((sid, t, dur)); t += dur
    open(f"{ROOT}/compositions/end.html", "w").write(end_scene(END[1]))
    hosts.append(("end", t, END[1])); t += END[1]
    total = round(t, 2)
    host_html = "\n".join(
        f'      <div id="{sid}" data-composition-id="{sid}" data-composition-src="compositions/{sid}.html" data-start="{st:.2f}" '
        f'data-duration="{d}" data-track-index="1" data-track-kind="graphics" data-width="{W}" data-height="{H}"></div>'
        for sid, st, d in hosts)
    vo = f'      <audio id="vo" class="clip" src="assets/vo.mp3" data-start="0" data-duration="{total}" data-volume="1"></audio>' if os.path.exists(f"{ROOT}/assets/vo.mp3") else ""
    music = f'      <audio id="bgm" class="clip" src="assets/music.mp3" data-start="0" data-duration="{total}" data-volume="0.16"></audio>' if os.path.exists(f"{ROOT}/assets/music.mp3") else ""
    open(f"{ROOT}/index.html", "w").write(f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width={W}, height={H}" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * {{ margin: 0; padding: 0; box-sizing: border-box; }}
      html, body {{ width: {W}px; height: {H}px; overflow: hidden; background: #ff8a5c; }}
      #root {{ position: relative; width: 100%; height: 100%; }}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{total}" data-width="{W}" data-height="{H}">
{host_html}
{vo}
{music}
    </div>
    <script>
      window.__timelines = window.__timelines || {{}};
      window.__timelines["main"] = gsap.timeline({{ paused: true }});
    </script>
  </body>
</html>
""")
    print("total", total, [(h[0], round(h[1], 2)) for h in hosts])

main()
