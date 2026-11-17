#!/usr/bin/env python3
"""Writes compositions/*.html and index.html for the ezcamp launch film. Edit the tables, rerun.

`python3 tools/build.py` writes this 16:9 project; `--vertical` writes the 9:16 one in
../launch-video-vertical, which shares this project's assets folder (symlink).

The film: a drawn US map is the home stage. The hook fills each state by its federal land share
while 640,000,000 rolls up; then each season starts on the map (the route draws from the last
place, a pin drops), the camera zooms through the pin into that season's world, the phone rises
with real app footage, and hand-drawn circles mark the fact the voiceover names.
"""
import json, os, re, sys

VERTICAL = "--vertical" in sys.argv
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), "launch-video-vertical") if VERTICAL else HERE
W, H = (1080, 1920) if VERTICAL else (1920, 1080)

MAP = json.load(open(os.path.join(HERE, "assets", "usmap.json")))   # 1600x1000 Albers USA, from tools/geo (d3-geo)
ORDER = ["moab", "kenai", "arkansas", "quartzsite"]
PLACE_STATE = {"moab": "UT", "kenai": "AK", "arkansas": "AR", "quartzsite": "AZ"}

# Federal land as a share of each state's area (Congressional Research Service, Federal Land
# Ownership: Overview and Data). Only the clearly-western states are distinguished; the rest get
# the same light tint, so the map never claims a number it doesn't show.
FED = {"NV": .80, "UT": .63, "ID": .62, "AK": .61, "OR": .53, "WY": .46, "CA": .46, "AZ": .39,
       "CO": .36, "NM": .35, "MT": .29, "WA": .28, "HI": .20}

# Geometry per format. Map box is where the 1600x1000 map sits on the stage.
if VERTICAL:
    G = dict(map=(20, 700, 1040, 650), num_top=230, num_size=150, line_top=430, line_size=54,
             text="left: 80px; top: 130px; width: 920px; justify-content: flex-start;", head=118, sub=38, subw=900,
             phone=(280, 700, 520, 1124, 15, 86), ox=0.5, dx=0, label_x=812, label_w=240,
             sil=(560, 120, 560, 560), cnt_top=150, cnt_size=190)
else:
    G = dict(map=(400, 330, 1120, 700), num_top=70, num_size=190, line_top=278, line_size=58,
             text="left: 150px; top: 0; bottom: 0; width: 820px; justify-content: center;", head=148, sub=40, subw=760,
             phone=(1150, 60, 444, 960, 13, 74), ox=1.0, dx=-40, label_x=1612, label_w=280,
             sil=(40, 520, 640, 520), cnt_top=300, cnt_size=230)

# Scene table (timings are the voiceover's pauses; see SCRIPT.md).
# season: id, dur, place, colours, kicker, headline, sub, videos, punch, callouts
#   videos: (file, start, dur, media_start, rate)
#   callouts: (t, fx, fy, rx, ry, label, until) on the phone screen in 0..1 device fractions,
#             or (t, None, fy, 0, 0, label, until) for a label beside the phone with an arrow at height fy.
SEASONS = [
 ("s3", 11.8, "moab", "#ffd166", "#ff7a45", "Spring · Moab, Utah", "Can I camp here?",
  "Ask. Then long-press the map to see whose land it is.",
  [("chat", 0, 6.9, 2.5, 1.7), ("land", 6.9, 4.9, 2.3, 1.0)], (8.7, 0.70, 1.4),
  [(4.6, 0.50, 0.86, 0.47, 0.13, "Free camps, with sources", 6.7), (9.3, 0.39, 0.57, 0.36, 0.045, "BLM land. Yes, camp here", 11.45)]),
 ("s4", 9.6, "kenai", "#7dd3fc", "#22c55e", "Summer · Kenai River, Alaska", "First salmon",
  "Sockeye, moose, live river flow, and Alaska's license rules.",
  [("m_water", 0, 3.0, 2.5, 1.3), ("fish", 3.0, 6.6, 8.8, 0.6)], None,
  [(3.5, 0.21, 0.255, 0.21, 0.03, "Sockeye: 75 sightings", 5.5), (7.4, None, 0.42, 0, 0, "Under 18? No license needed", 9.25)]),
 ("s5", 7.1, "arkansas", "#ffb347", "#c2410c", "Fall · Arkansas duck country", "First duck season",
  "What's been seen on the lake, and the rules for hunting at your side.",
  [("duck", 0, 7.1, 0, 1.0)], None,
  [(3.0, 0.21, 0.541, 0.2, 0.028, "Geese on the lake", 4.8), (5.0, 0.49, 0.84, 0.46, 0.035, "Hunting at your side", 6.75)]),
 ("s6", 6.1, "quartzsite", "#60a5fa", "#a855f7", "Winter · Quartzsite, Arizona", "Desert stars",
  "Free BLM land, and tonight's low before you leave.",
  [("m_winter", 0, 2.6, 2.5, 1.3), ("winter", 2.6, 3.5, 1.2, 1.2)], None,
  [(3.6, 0.22, 0.78, 0.18, 0.045, "57° tonight", 5.75)]),
]
SCENE_ORDER = [("s1", 8.3), ("s2", 2.1), ("s3", 11.8), ("s4", 9.6), ("s5", 7.1), ("s6", 6.1), ("s7", 5.1), ("s8", 3.5), ("end", 6.4)]
MAP_GROUND = ("#2f9bff", "#5eead4")
ACCENT = "#FFC233"   # DesignKit sunshine: drawn marks
INK = "#0d0d10"

FONT = "@font-face{font-family:'Anton';src:url('assets/fonts/Anton-Regular.ttf') format('truetype');}"


# ---------- map pieces ----------

def state_bbox(code):
    nums = list(map(float, re.findall(r"-?\d+\.?\d*", MAP["states"][code])))
    xs, ys = nums[0::2], nums[1::2]
    return min(xs), min(ys), max(xs), max(ys)

def arc(a, b):
    (x1, y1), (x2, y2) = MAP["places"][a], MAP["places"][b]
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    dx, dy = x2 - x1, y2 - y1
    lift = 0.28 * (dx * dx + dy * dy) ** 0.5
    n = (dx * dx + dy * dy) ** 0.5 or 1
    cx, cy = mx + (dy / n) * lift * (-1 if dx > 0 else 1), my - abs(dx / n) * lift
    return f"M{x1},{y1} Q{cx:.1f},{cy:.1f} {x2},{y2}"

def map_svg(sid, fills=True, upto=None, new=None, all_pins=False):
    """The US map. `upto`: places already visited (route drawn solid). `new`: the place this scene adds."""
    st = []
    for code, d in MAP["states"].items():
        share = FED.get(code, 0.04) if fills else 0
        op = 0.10 + share * 0.80 if fills else 0.10
        st.append(f'<path id="{sid}-st-{code}" class="st" d="{d}" fill="#ffffff" fill-opacity="{op:.2f}" '
                  f'stroke="#ffffff" stroke-opacity="0.75" stroke-width="1.4" pathLength="1"/>')
    route = []
    visited = upto or []
    for i in range(1, len(visited)):
        route.append(f'<path class="rt" d="{arc(visited[i-1], visited[i])}" fill="none" stroke="{ACCENT}" stroke-width="5" stroke-linecap="round"/>')
    if new and visited:
        route.append(f'<path id="{sid}-seg" d="{arc(visited[-1], new)}" fill="none" stroke="{ACCENT}" stroke-width="6" '
                     f'stroke-linecap="round" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/>')
    pins = []
    show = ORDER if all_pins else visited + ([new] if new else [])
    for p in show:
        x, y = MAP["places"][p]
        pid = f"{sid}-pin-{p}"
        pins.append(f'<g id="{pid}" transform="translate({x},{y})"><g class="pin">'
                    f'<path d="M0,0 C-14,-22 -22,-30 -22,-42 A22,22 0 1 1 22,-42 C22,-30 14,-22 0,0 Z" fill="{ACCENT}" stroke="{INK}" stroke-width="3"/>'
                    f'<circle cx="0" cy="-42" r="8" fill="{INK}"/></g></g>')
    mx, my, mw, mh = G["map"]
    return (f'<svg id="{sid}-map" class="usmap" viewBox="0 0 1600 1000" style="position:absolute;left:{mx}px;top:{my}px;width:{mw}px;height:{mh}px;overflow:visible">'
            f'<g id="{sid}-states">{"".join(st)}</g><g>{"".join(route)}</g><g>{"".join(pins)}</g></svg>')

def map_point(place):
    mx, my, mw, mh = G["map"]
    x, y = MAP["places"][place]
    return mx + x * mw / 1600, my + y * mh / 1000

def ground(sid, top, bot, extra=""):
    return f'<div id="{sid}-bg" style="position:absolute;inset:0;background:linear-gradient(165deg,{top} 0%,{bot} 100%);{extra}"></div>'


# ---------- shared CSS ----------

def base_css(sid):
    px, py, pw, ph, pad, rad = G["phone"]
    return f"""
    {FONT}
    #root {{ position: absolute; inset: 0; overflow: hidden; }}
    #{sid} .big {{ font-family: 'Anton'; color: #fff; text-transform: uppercase; line-height: 1; margin: 0; text-shadow: 0 6px 30px rgba(0,0,0,0.14); }}
    #{sid} .w {{ display: inline-block; }}
    #{sid}-text {{ position: absolute; {G['text']} display: flex; flex-direction: column; }}
    #{sid} .head {{ font-size: {G['head']}px; }}
    #{sid} .kick {{ font-family: 'Inter'; font-weight: 900; font-size: 34px; letter-spacing: 3px; text-transform: uppercase; color: #fff; background: rgba(0,0,0,0.18); align-self: flex-start; padding: 10px 18px; border-radius: 10px; margin-bottom: 26px; }}
    #{sid} .sub {{ font-family: 'Inter'; font-weight: 700; font-size: {G['sub']}px; line-height: 1.3; color: rgba(255,255,255,0.96); margin: 28px 0 0; max-width: {G['subw']}px; }}
    #{sid}-phone {{ position: absolute; left: {px}px; top: {py}px; width: {pw}px; height: {ph}px; border-radius: {rad}px; padding: {pad}px; background: {INK}; box-shadow: 0 50px 90px rgba(40,10,0,0.30), inset 0 0 0 2px #2a2a30; }}
    #{sid}-screen {{ position: relative; width: 100%; height: 100%; border-radius: {rad - pad}px; overflow: hidden; background: #fff; }}
    #{sid}-screen video {{ position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }}
    #{sid} .lbl {{ position: absolute; font-family: 'Anton'; font-size: 40px; line-height: 1.05; color: {INK}; background: {ACCENT}; padding: 10px 16px 12px; border-radius: 12px; text-transform: uppercase; box-shadow: 0 14px 30px rgba(0,0,0,0.22); }}
"""

def videos_html(sid, vids):
    return "\n".join(
        f'<video id="{sid}-v{i}" class="clip" src="assets/{f}.mp4" data-start="{st}" data-duration="{d}" '
        f'data-media-start="{ms}" data-playback-rate="{r}" muted playsinline></video>'
        for i, (f, st, d, ms, r) in enumerate(vids))

def words(sid, key, text, cls=""):
    return " ".join(f'<span class="w {cls}" id="{sid}-{key}{i}">{w}</span>' for i, w in enumerate(text.split()))

def screen_xy(fx, fy):
    px, py, pw, ph, pad, _ = G["phone"]
    sx, sy, sw, sh = px + pad, py + pad, pw - 2 * pad, ph - 2 * pad
    scale = max(sw / 1206, sh / 2622)
    vw = 1206 * scale
    return sx + (sw - vw) / 2 + fx * vw, sy + fy * sh, vw, sh

def punch_xy(x, y, punch):
    """Where a stage point on the phone lands after the punch-in."""
    if not punch:
        return x, y
    _, fy, sc = punch
    px, py, pw, ph, _, _ = G["phone"]
    ox, oy = px + pw * G["ox"], py + ph * fy
    return ox + (x - ox) * sc + G["dx"], oy + (y - oy) * sc

def callouts_html(sid, callouts, punch):
    """Hand-drawn marks: an ellipse drawn around the fact, a curved arrow to a label beside the phone."""
    svg, labels, tw = [], [], []
    for i, (t, fx, fy, rx, ry, text, until) in enumerate(callouts):
        after_punch = punch and t >= punch[0]
        lx = G["label_x"]
        if fx is not None:
            cx, cy, vw, sh = screen_xy(fx, fy)
            erx, ery = rx * vw, ry * sh
            if after_punch:
                cx, cy = punch_xy(cx, cy, punch)
                erx, ery = erx * punch[2], ery * punch[2]
            # A slightly open, tilted loop reads as drawn by hand.
            svg.append(f'<ellipse id="{sid}-c{i}" cx="{cx:.0f}" cy="{cy:.0f}" rx="{erx + 14:.0f}" ry="{ery + 12:.0f}" '
                       f'transform="rotate(-3 {cx:.0f} {cy:.0f})" fill="none" stroke="{ACCENT}" stroke-width="7" stroke-linecap="round" '
                       f'pathLength="1" stroke-dasharray="1.04 1" stroke-dashoffset="1.04"/>')
            tx, ty = cx + erx + 14, cy
        else:
            _, cy, _, _ = screen_xy(0.5, fy)
            px, py, pw, ph, _, _ = G["phone"]
            tx, ty = px + pw - 8, cy
        ly = max(40, min(H - 170, ty - 110))
        ax, ay = lx - 6, ly + 34
        svg.append(f'<path id="{sid}-a{i}" d="M{ax:.0f},{ay:.0f} Q{(ax + tx) / 2 + 10:.0f},{min(ay, ty) - 40:.0f} {tx + 6:.0f},{ty:.0f}" fill="none" '
                   f'stroke="{ACCENT}" stroke-width="6" stroke-linecap="round" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/>')
        labels.append(f'<div id="{sid}-l{i}" class="lbl" style="left:{lx}px;top:{ly:.0f}px;max-width:{G["label_w"]}px">{text}</div>')
        if fx is not None:
            tw.append(f'tl.to("#{sid}-c{i}", {{strokeDashoffset: 0, duration: 0.5, ease: "power2.inOut"}}, {t});')
            tw.append(f'tl.to("#{sid}-a{i}", {{strokeDashoffset: 0, duration: 0.35, ease: "power2.out"}}, {t + 0.4});')
            lt = t + 0.6
        else:
            tw.append(f'tl.to("#{sid}-a{i}", {{strokeDashoffset: 0, duration: 0.4, ease: "power2.out"}}, {t});')
            lt = t + 0.25
        tw.append(f'tl.fromTo("#{sid}-l{i}", {{opacity: 0, scale: 0.6, rotation: -6}}, {{opacity: 1, scale: 1, rotation: -2, duration: 0.45, ease: "back.out(2)"}}, {lt});')
        gone = f"#{sid}-l{i}, #{sid}-a{i}" + (f", #{sid}-c{i}" if fx is not None else "")
        tw.append(f'tl.to("{gone}", {{opacity: 0, filter: "blur(6px)", duration: 0.2, ease: "power2.in"}}, {until - 0.2:.2f});')
    out = (f'<svg id="{sid}-marks" style="position:absolute;left:0;top:0;width:{W}px;height:{H}px;overflow:visible" viewBox="0 0 {W} {H}">{"".join(svg)}</svg>'
           + "".join(labels))
    return out, tw

def wrap(sid, css, body, tw, dur):
    return f"""<template>
  <style>{base_css(sid)}{css}
  </style>
  <div id="root" data-composition-id="{sid}" data-width="{W}" data-height="{H}">
    <div id="{sid}" style="position:absolute;inset:0;" data-layout-allow-overflow data-layout-allow-overlap>
{body}
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


# ---------- scenes ----------

def hook(sid="s1", dur=8.3):
    """640,000,000 rolls up while the states draw on and fill by their public-land share."""
    order = sorted(MAP["states"], key=lambda c: -FED.get(c, 0.04))
    nt, ns, lt, ls = G["num_top"], G["num_size"], G["line_top"], G["line_size"]
    body = f"""
      {ground(sid, *MAP_GROUND)}
      {map_svg(sid, fills=True)}
      <div id="{sid}-num" class="big" style="position:absolute;left:0;right:0;top:{nt}px;text-align:center;font-size:{ns}px">0</div>
      <div id="{sid}-l1" class="big" style="position:absolute;left:0;right:0;top:{lt}px;text-align:center;font-size:{ls}px">{words(sid, 'a', 'acres of public land. Yours.')}</div>
      <div id="{sid}-l2" style="position:absolute;left:60px;right:60px;top:{lt + 6}px;text-align:center;font-family:Inter;font-weight:800;font-size:{ls - 12}px;color:#fff">{words(sid, 'b', 'Most of us never spend a night on it.')}</div>
      <div style="position:absolute;right:40px;bottom:26px;font-family:Inter;font-weight:600;font-size:20px;color:rgba(255,255,255,0.85)">Shade: federal land share by state · Congressional Research Service</div>"""
    tw = [f'tl.fromTo("#{sid} .st", {{strokeDasharray: "1 1", strokeDashoffset: 1, fillOpacity: 0}}, {{strokeDashoffset: 0, duration: 1.1, ease: "power2.inOut", stagger: {{each: 0.012, from: "start"}}}}, 0);']
    for i, code in enumerate(order):
        share = FED.get(code, 0.04)
        tw.append(f'tl.to("#{sid}-st-{code}", {{fillOpacity: {0.10 + share * 0.80:.2f}, duration: 0.5, ease: "power2.out"}}, {0.9 + i * 0.045:.3f});')
    tw += [f'const n = {{ v: 0 }}; const el = document.querySelector("#{sid}-num");',
           f'tl.to(n, {{ v: 640000000, duration: 2.9, ease: "power3.out", onUpdate: () => {{ el.textContent = Math.round(n.v).toLocaleString("en-US"); }} }}, 0.35);',
           f'tl.fromTo("#{sid}-num", {{scale: 0.82, filter: "blur(10px)"}}, {{scale: 1, filter: "blur(0px)", duration: 0.7, ease: "expo.out"}}, 0.35);',
           f'tl.fromTo("#{sid}-l1 .w", {{opacity: 0, y: 40, filter: "blur(8px)"}}, {{opacity: 1, y: 0, filter: "blur(0px)", duration: 0.35, ease: "expo.out", stagger: 0.08}}, 1.6);',
           f'tl.to("#{sid}-l1 .w", {{opacity: 0, filter: "blur(8px)", duration: 0.2, ease: "power2.in", stagger: 0.03}}, 5.05);',
           f'tl.fromTo("#{sid}-l2 .w", {{opacity: 0, filter: "blur(8px)"}}, {{opacity: 1, filter: "blur(0px)", duration: 0.16, ease: "power2.out", stagger: 0.09}}, 5.35);',
           # The eastern states fade back, leaving the West bright: where the land is.
           f'tl.to("#{sid}-map", {{scale: 1.06, transformOrigin: "30% 50%", duration: 2.4, ease: "power2.inOut"}}, 5.6);']
    css = f"#{sid}-l2 .w {{ opacity: 0; }}"
    return wrap(sid, css, body, tw, dur)

def preview(sid="s2", dur=2.1):
    """A year on your land: the four stops pop in order and a dotted route ties them together."""
    seasons = ["Spring", "Summer", "Fall", "Winter"]
    tags = []
    for i, p in enumerate(ORDER):
        x, y = map_point(p)
        tags.append(f'<div id="{sid}-t{i}" style="position:absolute;left:{x + 18:.0f}px;top:{y - 80:.0f}px;font-family:Inter;font-weight:900;font-size:26px;letter-spacing:2px;color:{INK};background:#fff;padding:6px 12px;border-radius:8px;text-transform:uppercase">{seasons[i]}</div>')
    nt, ns, lt, ls = G["num_top"], G["num_size"], G["line_top"], G["line_size"]
    route = " ".join(arc(ORDER[i], ORDER[i + 1]) for i in range(3))
    mx, my, mw, mh = G["map"]
    body = f"""
      {ground(sid, *MAP_GROUND)}
      {map_svg(sid, fills=True, all_pins=True)}
      <svg style="position:absolute;left:{mx}px;top:{my}px;width:{mw}px;height:{mh}px;overflow:visible" viewBox="0 0 1600 1000">
        <path id="{sid}-route" d="{route}" fill="none" stroke="{ACCENT}" stroke-width="6" stroke-linecap="round" stroke-dasharray="0.012 0.012" pathLength="1" opacity="0.95"/>
      </svg>
      {''.join(tags)}
      <div id="{sid}-h" class="big" style="position:absolute;left:0;right:0;top:{nt + 20}px;text-align:center;font-size:{int(ns * 0.62)}px">{words(sid, 'h', 'A year on your land')}</div>
      <div id="{sid}-s" style="position:absolute;left:0;right:0;top:{lt}px;text-align:center;font-family:Inter;font-weight:800;font-size:{ls - 8}px;color:#fff">This year, take your kid.</div>"""
    tw = [f'tl.fromTo("#{sid}-h .w", {{opacity: 0, scale: 1.5, filter: "blur(10px)"}}, {{opacity: 1, scale: 1, filter: "blur(0px)", duration: 0.28, ease: "expo.out", stagger: 0.07}}, 0.0);',
          f'tl.fromTo("#{sid}-s", {{opacity: 0, filter: "blur(8px)"}}, {{opacity: 1, filter: "blur(0px)", duration: 0.2}}, 0.55);',
          f'tl.fromTo("#{sid}-route", {{clipPath: "inset(0 100% 0 0)"}}, {{clipPath: "inset(0 0% 0 0)", duration: 1.2, ease: "power2.inOut"}}, 0.2);']
    for i, p in enumerate(ORDER):
        tw.append(f'tl.fromTo("#{sid}-pin-{p} .pin", {{scale: 0, transformOrigin: "50% 100%"}}, {{scale: 1, duration: 0.4, ease: "back.out(2.2)"}}, {0.25 + i * 0.28:.2f});')
        tw.append(f'tl.fromTo("#{sid}-t{i}", {{opacity: 0, x: -14}}, {{opacity: 1, x: 0, duration: 0.25, ease: "expo.out"}}, {0.35 + i * 0.28:.2f});')
    return wrap(sid, "", body, tw, dur)

def season(sid, dur, place, top, bot, kicker, head, sub, vids, punch, callouts):
    i = ORDER.index(place)
    visited = ORDER[:i]
    px, py = map_point(place)
    mx, my, mw, mh = G["map"]
    ox, oy = (px - mx) / mw * 100, (py - my) / mh * 100
    k_season, k_place = kicker.split(" · ")
    nt, ns, lt, ls = G["num_top"], G["num_size"], G["line_top"], G["line_size"]
    # A giant outline of the state behind the season's world, drawn on as we arrive.
    code = PLACE_STATE[place]
    x0, y0, x1, y1 = state_bbox(code)
    sx, sy, sw, sh = G["sil"]
    marks, mtw = callouts_html(sid, callouts, punch)
    pfx = f"#{sid}-phone"
    body = f"""
      <div id="{sid}-mapworld" style="position:absolute;inset:0">
        {ground(sid + '-m', *MAP_GROUND)}
        <div id="{sid}-cam" style="position:absolute;inset:0">{map_svg(sid, fills=True, upto=visited, new=place)}</div>
        <div id="{sid}-ks" class="big" style="position:absolute;left:0;right:0;top:{nt}px;text-align:center;font-size:{ns}px">{k_season}</div>
        <div id="{sid}-kp" style="position:absolute;left:0;right:0;top:{lt}px;text-align:center;font-family:Inter;font-weight:900;font-size:{ls - 10}px;letter-spacing:4px;color:#fff;text-transform:uppercase">{k_place}</div>
      </div>
      <div id="{sid}-world" style="position:absolute;inset:0;opacity:0">
        {ground(sid, top, bot)}
        <svg style="position:absolute;left:{sx}px;top:{sy}px;width:{sw}px;height:{sh}px;overflow:visible" viewBox="{x0 - 4} {y0 - 4} {x1 - x0 + 8} {y1 - y0 + 8}">
          <path id="{sid}-sil" d="{MAP['states'][code]}" fill="#ffffff" fill-opacity="0.07" stroke="#ffffff" stroke-opacity="0.45" stroke-width="{(x1 - x0) / 220:.2f}" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/>
        </svg>
        <div id="{sid}-text">
          <div id="{sid}-kick" class="kick">{kicker}</div>
          <h1 id="{sid}-head" class="big head">{words(sid, 'w', head)}</h1>
          <p id="{sid}-sub" class="sub">{sub}</p>
        </div>
        <div id="{sid}-phone">
          <div id="{sid}-screen">
{videos_html(sid, vids)}
          </div>
        </div>
        {marks}
      </div>"""
    tw = [
        # Map: the route draws from the last stop, the pin drops, the camera pushes in and zooms through.
        f'tl.fromTo("#{sid}-ks", {{opacity: 0, scale: 1.4, filter: "blur(10px)"}}, {{opacity: 1, scale: 1, filter: "blur(0px)", duration: 0.3, ease: "expo.out"}}, 0.0);',
        f'tl.fromTo("#{sid}-kp", {{opacity: 0, scale: 1.25}}, {{opacity: 1, scale: 1, duration: 0.5, ease: "expo.out"}}, 0.15);',
        (f'tl.to("#{sid}-seg", {{strokeDashoffset: 0, duration: 0.8, ease: "power2.inOut"}}, 0.05);' if visited else ""),
        f'tl.fromTo("#{sid}-pin-{place} .pin", {{scale: 0, transformOrigin: "50% 100%"}}, {{scale: 1, duration: 0.45, ease: "back.out(2.4)"}}, {0.75 if visited else 0.2});',
        f'tl.set("#{sid}-cam", {{transformOrigin: "{px:.0f}px {py:.0f}px"}}, 0);',
        f'tl.to("#{sid}-cam", {{scale: 2.3, duration: 1.05, ease: "power2.inOut"}}, 0.3);',
        f'tl.to("#{sid}-ks, #{sid}-kp", {{opacity: 0, filter: "blur(8px)", duration: 0.18, ease: "power2.in"}}, 1.25);',
        f'tl.to("#{sid}-cam", {{scale: 16, duration: 0.42, ease: "power3.in"}}, 1.35);',
        f'tl.to("#{sid}-mapworld", {{opacity: 0, duration: 0.2, ease: "power1.in"}}, 1.57);',
        f'tl.to("#{sid}-world", {{opacity: 1, duration: 0.22, ease: "power1.out"}}, 1.52);',
        # World: the state outline draws, the phone rises, the words land.
        f'tl.to("#{sid}-sil", {{strokeDashoffset: 0, duration: 1.2, ease: "power2.inOut"}}, 1.6);',
        f'tl.fromTo("{pfx}", {{y: {H}, rotation: 6}}, {{y: 0, rotation: 0, duration: 0.85, ease: "expo.out"}}, 1.55);',
        f'tl.fromTo("#{sid}-kick", {{clipPath: "inset(0 100% 0 0)"}}, {{clipPath: "inset(0 0% 0 0)", duration: 0.4, ease: "power3.inOut"}}, 1.7);',
        f'tl.fromTo("#{sid}-head .w", {{opacity: 0, filter: "blur(10px)"}}, {{opacity: 1, filter: "blur(0px)", duration: 0.16, ease: "power2.out", stagger: 0.08}}, 1.85);',
        f'tl.fromTo("#{sid}-sub", {{opacity: 0, filter: "blur(8px)"}}, {{opacity: 1, filter: "blur(0px)", duration: 0.25}}, 2.35);',
    ]
    if punch:
        t, fy, sc = punch
        tw += [f'tl.set("{pfx}", {{transformOrigin: "{G["ox"] * 100:.0f}% {fy * 100:.0f}%"}}, 0);',
               f'tl.to("{pfx}", {{scale: {sc}, x: {G["dx"]}, duration: 0.55, ease: "power3.inOut"}}, {t});',
               f'tl.to("#{sid}-text", {{opacity: 0, filter: "blur(8px)", duration: 0.25, ease: "power2.in"}}, {t});']
    tw += mtw
    # Exit: everything blurs out together; the next scene opens on the map.
    tw.append(f'tl.to("#{sid}-world", {{opacity: 0, scale: 0.94, filter: "blur(12px)", duration: 0.28, ease: "power2.in"}}, {dur - 0.3:.2f});')
    tw = [t for t in tw if t]
    return wrap(sid, "", body, tw, dur)

def plan(sid="s7", dur=5.1):
    vids = [("ai", 0, 2.9, 0, 2.5), ("gear", 2.9, 2.2, 0, 1.2)]
    marks, mtw = callouts_html(sid, [(1.2, 0.5, 0.21, 0.46, 0.12, "A camp every night", 2.75), (3.4, 0.5, 0.42, 0.46, 0.11, "Your gear, cut out", 4.75)], None)
    body = f"""
      {ground(sid, '#c084fc', '#ff8a1f')}
      <div id="{sid}-text">
        <h1 id="{sid}-head" class="big head">{words(sid, 'w', 'Plan it.')}<br>{words(sid, 'x', 'Pack it.')}</h1>
        <p id="{sid}-sub" class="sub">A camp at the end of every day's drive, and the gear you already own.</p>
      </div>
      <div id="{sid}-phone"><div id="{sid}-screen">
{videos_html(sid, vids)}
      </div></div>
      {marks}"""
    tw = [f'tl.fromTo("#{sid}-phone", {{x: {W}, filter: "blur(14px)"}}, {{x: 0, filter: "blur(0px)", duration: 0.5, ease: "expo.out"}}, 0);',
          f'tl.fromTo("#{sid}-head .w", {{opacity: 0, x: -60, filter: "blur(10px)"}}, {{opacity: 1, x: 0, filter: "blur(0px)", duration: 0.3, ease: "expo.out", stagger: 0.09}}, 0.1);',
          f'tl.fromTo("#{sid}-sub", {{opacity: 0}}, {{opacity: 1, duration: 0.3}}, 0.6);',
          # The gear beat: the phone swings and the second clip lands.
          f'tl.fromTo("#{sid}-phone", {{rotationY: 0}}, {{rotationY: 0, duration: 0.01}}, 2.85);',
          f'tl.fromTo("#{sid}-screen", {{filter: "blur(0px)"}}, {{filter: "blur(10px)", duration: 0.1, yoyo: true, repeat: 1, ease: "power1.inOut"}}, 2.8);',
          f'tl.to("#{sid}-phone, #{sid}-text, #{sid}-marks, #{sid} .lbl", {{x: -{W}, filter: "blur(14px)", duration: 0.3, ease: "power3.in"}}, {dur - 0.3:.2f});'] + mtw
    return wrap(sid, "", body, tw, dur)

def count(sid="s8", dur=3.5):
    vids = [("m_sat", 0, 0.9, 1.5, 1.3), ("m_topo", 0.9, 0.9, 3, 1.3), ("m_lands", 1.8, 0.9, 4, 1.3), ("m_water", 2.7, 0.8, 5, 1.3)]
    layers = ["Satellite", "Topo", "Forest roads", "Rivers & lakes"]
    roll = "".join(f'<div class="ro">{l}</div>' for l in layers)
    if VERTICAL:
        num_pos, roll_pos = "left:0;right:0;top:150px;text-align:center", "left:0;right:0;top:400px;text-align:center"
    else:
        num_pos, roll_pos = "left:150px;top:300px", "left:150px;top:560px"
    body = f"""
      {ground(sid, '#a3e635', '#10b981')}
      <div id="{sid}-num" class="big" style="position:absolute;{num_pos};font-size:{G['cnt_size']}px">0</div>
      <div class="big" style="position:absolute;{num_pos.replace('300px','300px')};margin-top:{G['cnt_size'] + 10}px;font-size:{int(G['cnt_size'] * 0.33)}px">campsites · all 50 states</div>
      <div id="{sid}-rollbox" style="position:absolute;{roll_pos};margin-top:{int(G['cnt_size'] * 0.5)}px;height:70px;overflow:hidden">
        <div id="{sid}-roll" style="font-family:Inter;font-weight:900;font-size:54px;line-height:70px;color:{INK};text-transform:uppercase">{roll}</div>
      </div>
      <div id="{sid}-phone"><div id="{sid}-screen">
{videos_html(sid, vids)}
      </div></div>"""
    tw = [f'const n = {{ v: 0 }}; const el = document.querySelector("#{sid}-num");',
          f'tl.to(n, {{ v: 29105, duration: 1.4, ease: "power3.out", onUpdate: () => {{ el.textContent = Math.round(n.v).toLocaleString("en-US"); }} }}, 0.05);',
          f'tl.fromTo("#{sid}-phone", {{y: {H}}}, {{y: 0, duration: 0.5, ease: "expo.out"}}, 0);']
    for i in range(1, 4):
        tw.append(f'tl.to("#{sid}-roll", {{y: {-70 * i}, duration: 0.18, ease: "power3.inOut"}}, {0.9 * i - 0.09:.2f});')
    tw.append(f'tl.to("#{sid}-phone", {{y: {H}, duration: 0.3, ease: "power3.in"}}, {dur - 0.3:.2f});')
    return wrap(sid, "", body, tw, dur)

def end(sid="end", dur=6.4):
    colours = ["#ffd166", "#22c55e", "#c2410c", "#a855f7"]
    dots = "".join(f'<div id="{sid}-d{i}" style="position:absolute;left:{W / 2 - 22:.0f}px;top:{H / 2 - 160:.0f}px;width:44px;height:44px;border-radius:50%;background:{c};border:4px solid #fff"></div>' for i, c in enumerate(colours))
    starts = [(-700, -500), (700, -500), (-700, 500), (700, 500)] if not VERTICAL else [(-500, -800), (500, -800), (-500, 800), (500, 800)]
    direction = "column" if VERTICAL else "row"
    body = f"""
      {ground(sid, '#ffb347', '#ff5f8f')}
      {dots}
      <div id="{sid}-lock" style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
        <div style="display:flex;align-items:center;gap:44px;flex-direction:{direction}">
          <img id="{sid}-logo" src="assets/logo.png" alt="ezcamp logo" style="width:300px;height:300px;border-radius:68px;box-shadow:0 40px 80px rgba(80,10,30,0.30)">
          <div id="{sid}-word" class="big" style="font-size:{200 if VERTICAL else 230}px;text-transform:none;clip-path:inset(0 100% 0 0)">ezcamp</div>
        </div>
        <div id="{sid}-tag" style="font-family:Inter;font-weight:800;font-size:{48 if VERTICAL else 56}px;color:#fff;margin-top:44px">{words(sid, 't', "It's your land. Go camp on it.")}</div>
        <div id="{sid}-cta" style="font-family:Inter;font-weight:800;font-size:40px;color:#ff5f3d;background:#fff;border-radius:22px;padding:18px 42px;margin-top:30px">Free on the App Store</div>
      </div>"""
    tw = []
    for i, (x, y) in enumerate(starts):
        tw.append(f'tl.fromTo("#{sid}-d{i}", {{x: {x}, y: {y}, scale: 1}}, {{x: 0, y: 0, duration: 0.45, ease: "power3.in"}}, {i * 0.04:.2f});')
    tw += [f'tl.to("#{sid}-d0, #{sid}-d1, #{sid}-d2, #{sid}-d3", {{scale: 0, duration: 0.12}}, 0.58);',
           f'tl.fromTo("#{sid}-logo", {{scale: 0.1, rotation: -20, opacity: 0}}, {{scale: 1, rotation: 0, opacity: 1, duration: 0.7, ease: "back.out(1.8)"}}, 0.55);',
           f'tl.fromTo("#{sid}-tag .w", {{opacity: 0, filter: "blur(8px)"}}, {{opacity: 1, filter: "blur(0px)", duration: 0.16, stagger: 0.12}}, 0.3);',
           f'tl.to("#{sid}-word", {{clipPath: "inset(0 0% 0 0)", duration: 0.6, ease: "power3.inOut"}}, 0.95);',
           f'tl.fromTo("#{sid}-cta", {{opacity: 0, scale: 0.7}}, {{opacity: 1, scale: 1, duration: 0.45, ease: "back.out(2)"}}, 3.4);']
    css = f"#{sid}-tag .w {{ opacity: 0; }}"
    return wrap(sid, css, body, tw, dur)


def main():
    os.makedirs(f"{ROOT}/compositions", exist_ok=True)
    files = {"s1": hook(), "s2": preview(), "s7": plan(), "s8": count(), "end": end()}
    for row in SEASONS:
        files[row[0]] = season(*row)
    t, hosts = 0.0, []
    for sid, d in SCENE_ORDER:
        open(f"{ROOT}/compositions/{sid}.html", "w").write(files[sid])
        hosts.append((sid, t, d)); t += d
    total = round(t, 2)
    host_html = "\n".join(
        f'      <div id="{sid}" data-composition-id="{sid}" data-composition-src="compositions/{sid}.html" data-start="{st:.2f}" '
        f'data-duration="{d}" data-track-index="1" data-track-kind="graphics" data-width="{W}" data-height="{H}"></div>'
        for sid, st, d in hosts)
    has = lambda f: os.path.exists(f"{HERE}/assets/{f}")
    vo = f'      <audio id="vo" class="clip" src="assets/vo.mp3" data-start="0" data-duration="{total}" data-volume="1"></audio>' if has("vo.mp3") else ""
    music = f'      <audio id="bgm" class="clip" src="assets/music.mp3" data-start="0" data-duration="{total}" data-volume="0.16"></audio>' if has("music.mp3") else ""
    open(f"{ROOT}/index.html", "w").write(f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width={W}, height={H}" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * {{ margin: 0; padding: 0; box-sizing: border-box; }}
      html, body {{ width: {W}px; height: {H}px; overflow: hidden; background: #2f9bff; }}
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
    print("total", total, "vertical" if VERTICAL else "landscape")

main()
