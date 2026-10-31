#!/usr/bin/env python3
# The shared controls stay usable without a mouse, and a button with only an icon has a name.
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config"
SHELL = CONFIG / "quickshell"
# Each of these takes the keyboard itself, directly or through PressArea.
CONTROLS = ["AccentSwatch", "Button", "ChipButton", "Choice", "HeaderButton", "IconButton", "PickList",
            "QuickTile", "RoundToggle", "SideNav", "Slider", "Switch", "TileSurface"]
bad = 0

for name in CONTROLS:
    text = (SHELL / "components" / f"{name}.qml").read_text()
    if "PressArea" not in text and "activeFocusOnTab" not in text:
        print(f"   FAIL  {name} can't be reached with Tab")
        bad = 1
    if re.search(r"\bMouseArea\s*\{", text) and name not in ("Slider", "Choice"):
        print(f"   FAIL  {name} has a MouseArea the keyboard can't use: use PressArea")
        bad = 1

files = [f for d in ("quickshell", "installer", "greeter") for f in (CONFIG / d).rglob("*.qml")]
for f in files:
    text = f.read_text()
    for m in re.finditer(r"\b(IconButton|HeaderButton)\s*\{", text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        if not re.search(r"\blabel:", text[m.end():i]):
            print(f"   FAIL  {f.relative_to(ROOT)}: a {m.group(1)} without a label")
            bad = 1
    for m in re.finditer(r"Theme\.fontSize(?:Small)? - [0-9]", text):
        print(f"   FAIL  {f.relative_to(ROOT)}: {m.group(0)}: text below the smallest size")
        bad = 1

if not bad:
    print(f"controls: {len(CONTROLS)} take the keyboard, and every icon button in {len(files)} files has a name")
sys.exit(bad)
