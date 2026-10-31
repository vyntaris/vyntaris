#!/usr/bin/env python3
# Every palette and accent reads: the same sums as Palettes.js and Theme.qml, checked against WCAG AA.
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "config/quickshell/config/Palettes.js").read_text()
PALETTES = {name: dict(re.findall(r'(\w+): "(#[0-9a-f]{6})"', body))
            for name, body in re.findall(r"(latte|frappe|macchiato|mocha): \{(.*?)\}", SOURCE, re.S)}
ACCENTS = re.search(r"accentChoices = \[(.*?)\]", SOURCE).group(1).replace('"', "").replace(" ", "").split(",")


def luminance(c):
    def lin(v):
        v = int(v, 16) / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[1:3]) + 0.7152 * lin(c[3:5]) + 0.0722 * lin(c[5:7])


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def mix(a, b, t):
    # JavaScript's Math.round: halves go up, not to the even number.
    return "#" + "".join(f"{int(int(a[i:i + 2], 16) + (int(b[i:i + 2], 16) - int(a[i:i + 2], 16)) * t + 0.5):02x}" for i in (1, 3, 5))


def ensure(color, background, ratio, towards):
    for step in range(51):
        c = mix(color, towards, step * 0.02)
        if contrast(c, background) >= ratio:
            return c
    return towards


def settled(fill):
    if contrast("#ffffff", fill) >= 4.5 or contrast("#11111b", fill) >= 4.5:
        return fill
    return ensure(fill, "#ffffff", 4.5, "#000000")


def readable_on(fill, light, dark):
    if contrast(light, fill) >= 4.5:
        return light
    return "#ffffff" if contrast("#ffffff", fill) >= contrast(dark, fill) else dark


bad = 0


def check(label, ratio, need):
    global bad
    if ratio < need:
        print(f"   FAIL  {label}: {ratio:.2f}, needs {need}")
        bad = 1


for name, pal in PALETTES.items():
    dark = name != "latte"
    worst = mix(pal["base"] if dark else pal["crust"], pal["text"], 0.06)
    for high in (False, True):
        text_ratio = 7 if high else 4.5
        towards = ("#ffffff" if dark else "#000000") if high else pal["text"]
        where = f"{name}{' high contrast' if high else ''}"
        for token in ("subtext1", "subtext0", "overlay2", "overlay1", "overlay0", "green", "red", "peach"):
            check(f"{where} {token} as text", contrast(ensure(pal[token], worst, text_ratio, towards), worst), text_ratio)
        edge = ensure(pal["overlay0"], worst, 4.5 if high else 3, towards)
        check(f"{where} a control's edge", contrast(edge, worst), 3)
        for accent in ACCENTS:
            check(f"{where} {accent} as text", contrast(ensure(pal[accent], worst, text_ratio, towards), worst), text_ratio)
    light, darkest = pal["base"], PALETTES["mocha"]["crust"]
    for accent in ACCENTS:
        fill = settled(pal[accent])
        check(f"{name} text on {accent}", contrast(readable_on(fill, light, darkest), fill), 4.5)
    # Colours a wallpaper can give: the hue is free, the saturation and lightness are fitted.
    for hue in range(0, 360, 15):
        h, s, l = hue / 60, 0.8, 0.77 if dark else 0.6
        c = (1 - abs(2 * l - 1)) * s
        x = c * (1 - abs(h % 2 - 1))
        rgb = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(h)]
        fill = settled("#" + "".join(f"{round((v + l - c / 2) * 255):02x}" for v in rgb))
        check(f"{name} text on a wallpaper accent, hue {hue}", contrast(readable_on(fill, light, darkest), fill), 4.5)

if not bad:
    print(f"contrast: {len(PALETTES)} palettes, {len(ACCENTS)} accents and wallpaper hues all read")
sys.exit(bad)
