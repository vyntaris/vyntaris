#!/usr/bin/env python3
import json
import math
import os
import re
import shutil
import subprocess
import sys
import cairo
from shapely import affinity
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "system", "lib"))
import palettes

TILT = math.radians(-17)
C = (12.0, 13.4)
RX, RY = 10.6, 3.5

class Mark:
    def __init__(self, v, gap, w_max, w_min, planet_r, planet_gap, arc=None, back=True, tip=True, centre=C):
        self.v = v
        self.centre = centre
        self.gap = gap
        self.w_max = w_max
        self.w_min = w_min
        self.planet_r = planet_r
        self.planet_gap = planet_gap
        self.arc = arc
        self.back = back
        self.tip = tip

    def width(self, t):
        return self.w_min + (self.w_max - self.w_min) * ((1 - math.cos(t)) / 2) ** 0.9

    def band(self, t0, t1, steps=240):
        ts = [t0 + (t1 - t0) * i / steps for i in range(steps + 1)]
        outer = [on_ellipse(t, self.width(t), self.centre) for t in ts]
        inner = [on_ellipse(t, -self.width(t), self.centre) for t in reversed(ts)]
        return Polygon(outer + inner).buffer(0)

    def layers(self, planet=True):
        if self.arc:
            arc_from, arc_to = self.arc
        elif planet:
            arc_from, arc_to = self.planet_gap, 2 * math.pi - self.planet_gap
        else:
            arc_from, arc_to = 0.0, 2 * math.pi
        cuts = [arc_from] + [k * math.pi for k in (1, 2) if arc_from < k * math.pi < arc_to] + [arc_to]
        front, back = [], []
        for a, b in zip(cuts, cuts[1:]):
            if math.sin((a + b) / 2) > 0:
                front.append(self.band(a, b))
            else:
                tuck = lambda t: 0.04 if abs(math.sin(t)) < 1e-9 and t not in (arc_from, arc_to) else 0
                back.append(self.band(a - tuck(a), b + tuck(b)))
        if not self.arc and not planet:
            back.append(self.band(-0.04, 0))
        front, back = unary_union(front), unary_union(back) if self.back else Polygon()

        v = self.v.difference(front.buffer(self.gap, join_style="mitre"))
        if not self.tip:
            v = keep(v, lambda g: g.centroid.y < 16)
        back = back.difference(v.buffer(self.gap, join_style="mitre"))
        out = {"back": back, "v": v, "front": front}
        if planet:
            p = Point(on_ellipse(0, 0, self.centre)).buffer(self.planet_r, 128)
            out = {k: g.difference(p.buffer(self.gap)) for k, g in out.items()}
            out["planet"] = p
        return {k: keep(g, lambda g: g.area > 0.3) for k, g in out.items()}

def on_ellipse(t, out=0.0, centre=C):
    x, y = RX * math.cos(t), RY * math.sin(t)
    nx, ny = RY * math.cos(t), RX * math.sin(t)
    k = math.hypot(nx, ny)
    x, y = x + out * nx / k, y + out * ny / k
    c, s = math.cos(TILT), math.sin(TILT)
    return (centre[0] + x * c - y * s, centre[1] + x * s + y * c)

def keep(shape, test):
    pieces = shape.geoms if shape.geom_type == "MultiPolygon" else [shape]
    return unary_union([g for g in pieces if not g.is_empty and test(g)])

FULL = Mark(
    v=unary_union([
        Polygon([(1.4, 3.4), (7.4, 3.4), (13.5, 17.0), (12.0, 21.4)]),
        Polygon([(18.6, 3.4), (22.4, 3.4), (12.0, 21.4), (11.2, 19.2)]),
    ]),
    gap=0.7, w_max=0.95, w_min=0.5, planet_r=1.9, planet_gap=math.radians(24))

SMALL = Mark(
    v=unary_union([
        Polygon([(1.0, 3.4), (7.8, 3.4), (13.6, 16.4), (12.0, 23.6)]),
        Polygon([(17.6, 3.4), (22.0, 3.4), (12.0, 23.6), (11.0, 21.0)]),
    ]),
    gap=1.35, w_max=1.4, w_min=1.0, planet_r=2.5, planet_gap=math.radians(34),
    arc=(math.radians(34), math.pi + math.radians(12)), back=False, centre=(12.0, 12.9))

def transform(shape, fit):
    s, dx, dy = fit
    return affinity.translate(affinity.scale(shape, s, s, origin=(0, 0)), dx, dy)

def centred_fit(shape, margin):
    minx, miny, maxx, maxy = shape.bounds
    s = (24 - 2 * margin) / max(maxx - minx, maxy - miny)
    return s, 12 - (minx + maxx) / 2 * s, 12 - (miny + maxy) / 2 * s

def coverage(shape, px):
    surf = cairo.ImageSurface(cairo.FORMAT_A8, px, px)
    cr = cairo.Context(surf)
    cr.scale(px / 24, px / 24)
    trace(cr, shape)
    cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
    cr.fill()
    surf.flush()
    data, stride = surf.get_data(), surf.get_stride()
    return [data[y * stride + x] / 255 for y in range(px) for x in range(px)]

def grid_fit(shape, margin=0.35):
    base = centred_fit(shape, margin)
    minx, miny, maxx, maxy = shape.bounds
    best = None
    for i in range(6):
        s = base[0] * (1 - 0.012 * i)
        w, h = (maxx - minx) * s, (maxy - miny) * s
        x0, y0 = 12 - (minx + maxx) / 2 * s, 12 - (miny + maxy) / 2 * s
        for ox in range(-6, 7):
            for oy in range(-6, 7):
                dx, dy = ox / 10, oy / 10
                if abs(dx) > (24 - 2 * margin - w) / 2 or abs(dy) > (24 - 2 * margin - h) / 2:
                    continue
                placed = transform(shape, (s, x0 + dx, y0 + dy))
                blur = sum(wt * sum(a * (1 - a) for a in coverage(placed, px)) / px
                           for px, wt in ((20, 1.0), (18, 0.4), (16, 0.4), (40, 0.25)))
                if best is None or blur < best[0]:
                    best = (blur, (s, x0 + dx, y0 + dy))
    return best[1]

def trace(cr, shape):
    for p in (shape.geoms if shape.geom_type == "MultiPolygon" else [shape]):
        for ring in [p.exterior, *p.interiors]:
            pts = list(ring.coords)[:-1]
            cr.move_to(*pts[0])
            for pt in pts[1:]:
                cr.line_to(*pt)
            cr.close_path()

def path(shape, digits=3):
    if shape.is_empty:
        return ""
    shape = shape.simplify(0.004 if digits > 2 else 0.012)
    n = lambda v: f"{v:.{digits}f}".rstrip("0").rstrip(".")
    ring = lambda coords: "M" + "L".join(f"{n(x)} {n(y)}" for x, y in list(coords)[:-1]) + "z"
    polys = shape.geoms if shape.geom_type == "MultiPolygon" else [shape]
    return "".join(ring(p.exterior.coords) + "".join(ring(i.coords) for i in p.interiors) for p in polys)

full = FULL.layers(planet=True)
fit = centred_fit(unary_union(list(full.values())), 0.7)
full = {k: transform(g, fit) for k, g in full.items()}
ring = FULL.layers(planet=False)
ring["hide"] = ring["v"].buffer(FULL.gap, join_style="mitre")
ring = {k: transform(g, fit) for k, g in ring.items()}
s, dx, dy = fit
px, py = on_ellipse(0)
orbit = {
    "cx": round(C[0] * s + dx, 4), "cy": round(C[1] * s + dy, 4),
    "rx": round(RX * s, 4), "ry": round(RY * s, 4), "tilt": round(math.degrees(TILT), 3),
    "width": [round(FULL.w_min * s, 4), round(FULL.w_max * s, 4)],
    "planet": {"x": round(px * s + dx, 4), "y": round(py * s + dy, 4), "r": round(FULL.planet_r * s, 4)},
}

small = unary_union(list(SMALL.layers(planet=True).values()))
small = transform(small, grid_fit(small))

PARTNERS = {
    "rosewater": "pink", "flamingo": "pink", "pink": "mauve", "mauve": "blue", "red": "peach",
    "maroon": "peach", "peach": "red", "yellow": "peach", "green": "teal", "teal": "sapphire",
    "sky": "blue", "sapphire": "blue", "blue": "mauve", "lavender": "mauve",
}

data = {
    "small": path(small, 2),
    "full": {k: path(g) for k, g in full.items() if k != "planet"},
    "ring": {k: path(g) for k, g in ring.items()},
    "orbit": orbit,
    "partners": PARTNERS,
}
with open(f"{REPO}/config/quickshell/components/LogoShape.js", "w") as f:
    f.write(".pragma library\n\n// The Vyntaris mark in a 24 x 24 box, made by tools/make-logo.py; drawn by Logo.qml and the boot splash\n")
    f.write("var shape = " + json.dumps(data, indent=1) + ";\n")
print("config/quickshell/components/LogoShape.js")

icons = f"{REPO}/config/quickshell/components/Icons.js"
src = open(icons).read()
src = re.sub(r'("vyntaris": \[\n\s*\{ fill: true, e: true, d: ")[^"]*(")', lambda m: m.group(1) + data["small"] + m.group(2), src)
open(icons, "w").write(src)
print("config/quickshell/components/Icons.js")

def mix(a, b, t):
    return palettes.hexcode(palettes.mix(a, b, t))

def full_svg(accent, partner, base, glow=True):
    p = orbit["planet"]
    x0 = orbit["cx"] - orbit["rx"]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -2 28 28"><defs>
<linearGradient id="v" x1="2" y1="3" x2="20" y2="21" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{mix(accent, "#ffffff", 0.2)}"/><stop offset="1" stop-color="{partner}"/></linearGradient>
<linearGradient id="f" x1="{x0:.2f}" y1="0" x2="{p["x"]:.2f}" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{mix(partner, base, 0.2)}"/><stop offset="0.55" stop-color="{accent}"/><stop offset="1" stop-color="{mix(accent, "#ffffff", 0.5)}"/></linearGradient>
<linearGradient id="b" x1="{x0:.2f}" y1="0" x2="{p["x"]:.2f}" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{mix(partner, base, 0.2)}"/><stop offset="1" stop-color="{mix(accent, base, 0.5)}"/></linearGradient>
<radialGradient id="p" cx="{p["x"] - p["r"] * 0.35:.3f}" cy="{p["y"] - p["r"] * 0.4:.3f}" r="{p["r"] * 1.35:.3f}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffffff"/><stop offset="0.35" stop-color="{mix(accent, "#ffffff", 0.5)}"/><stop offset="1" stop-color="{accent}"/></radialGradient>
<radialGradient id="g" cx="{p["x"]:.3f}" cy="{p["y"]:.3f}" r="{p["r"] * 2.4:.3f}" gradientUnits="userSpaceOnUse"><stop offset="0.3" stop-color="{accent}" stop-opacity="0.45"/><stop offset="1" stop-color="{accent}" stop-opacity="0"/></radialGradient>
</defs><path fill="url(#b)" d="{data["full"]["back"]}"/><path fill="url(#v)" d="{data["full"]["v"]}"/><path fill="url(#f)" d="{data["full"]["front"]}"/>{f'<circle cx="{p["x"]}" cy="{p["y"]}" r="{p["r"] * 2.4:.3f}" fill="url(#g)"/>' if glow else ""}<circle cx="{p["x"]}" cy="{p["y"]}" r="{p["r"]}" fill="url(#p)"/></svg>
'''

MOCHA = palettes.palette("mocha")
ACCENT, PARTNER, BASE = MOCHA["mauve"], MOCHA[PARTNERS["mauve"]], MOCHA["base"]
with open(f"{REPO}/system/vyntaris-logo.svg", "w") as f:
    f.write(full_svg(ACCENT, PARTNER, BASE))
print("system/vyntaris-logo.svg")
with open(f"{REPO}/system/vyntaris-logo-symbolic.svg", "w") as f:
    f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="{ACCENT}" fill-rule="evenodd" d="{data["small"]}"/></svg>\n')
print("system/vyntaris-logo-symbolic.svg")

if shutil.which("rsvg-convert"):
    subprocess.run(["rsvg-convert", "-w", "600", "-h", "600", "-o", f"{REPO}/config/fastfetch/pngs/logo.png"],
                   input=full_svg(ACCENT, PARTNER, BASE, glow=False).encode(), check=True)
    print("config/fastfetch/pngs/logo.png")
