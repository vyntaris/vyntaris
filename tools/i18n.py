#!/usr/bin/env python3
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHELL = ROOT / "config/quickshell"
I18N = SHELL / "i18n"
CALL = re.compile(r'Tr\.[tf]\(\s*"((?:[^"\\]|\\.)*)"')
SHOWN = [SHELL / "modules/settings/SettingsIndex.js", SHELL / "components/BarStyles.js"]
STEPS = re.compile(r'readonly property var pages: \[([^\]]*)\]')
FIELD = re.compile(r'\b(?:label|title):\s*"((?:[^"\\]|\\.)*)"')
RUST = re.compile(r'\b(?:tr\(|trf!\()\s*"((?:[^"\\]|\\.)*)"')

def rust_text(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)

SCRIPTS = re.compile(r'(?<![-\w])T "((?:[^"\\]|\\.)*)"')
TELL = re.compile(r'\btell\(\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"')
COMMANDS = re.compile(r'(?:\b(?:title|name):\s*|\btr\(\s*)"((?:[^"\\]|\\.)*)"')

def texts():
    out = set()
    for f in sorted([*SHELL.rglob("*.qml"), *(ROOT / "config/installer").rglob("*.qml"), *(ROOT / "config/greeter").rglob("*.qml")]):
        if f.name == "Tr.qml":
            continue
        for m in CALL.finditer(f.read_text(errors="ignore")):
            out.add(json.loads(f'"{m.group(1)}"'))
    for f in SHOWN:
        out.update(json.loads(f'"{m.group(1)}"') for m in FIELD.finditer(f.read_text()))
    steps = STEPS.search((ROOT / "config/installer/shell.qml").read_text())
    out.update(re.findall(r'"([^"]+)"', steps.group(1)) if steps else [])
    for f in sorted((ROOT / "rust").glob("*/*/src/*.rs")):
        if f.name in ("report.rs", "tests.rs"):
            continue
        text = f.read_text()
        out.update(rust_text(m.group(1)) for m in RUST.finditer(text))
        sections = re.search(r"const SECTIONS[^=]*= &\[(.*?)\];", text, re.S)
        if sections:
            out.update(re.findall(r'\("[^"]*", "([^"]+)"', sections.group(1)))
    search = (SHELL / "modules/island/Search.js").read_text()
    out.update(json.loads(f'"{m.group(1)}"') for m in COMMANDS.finditer(search))
    for f in [*sorted((SHELL / "scripts").glob("*.sh")), *sorted((ROOT / "system/bin").iterdir()), *sorted((ROOT / "system/gaming").glob("*.sh"))]:
        out.update(m.group(1) for m in SCRIPTS.finditer(f.read_text(errors="ignore")))
    for m in TELL.finditer((ROOT / "config/hypr/hyprland.lua").read_text()):
        out.update(m.groups())
    return out

def main():
    keys = texts()
    if sys.argv[1:2] == ["missing"]:
        lang = sys.argv[2]
        have = json.loads((I18N / f"{lang}.json").read_text()) if (I18N / f"{lang}.json").exists() else {}
        print(json.dumps({k: "" for k in sorted(keys - have.keys())}, ensure_ascii=False, indent=2))
        return 0
    bad = 0
    print(f"{len(keys)} texts in the shell")
    for f in sorted(I18N.glob("*.json")):
        try:
            d = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            print(f"   FAIL  {f.name}: {e}")
            bad = 1
            continue
        stale = sorted(set(d) - keys)
        empty = sorted(k for k, v in d.items() if not isinstance(v, str) or not v.strip())
        done = len(keys & {k for k, v in d.items() if isinstance(v, str) and v.strip()})
        print(f"   {'ok  ' if not stale else 'FAIL'}  {f.stem}: {done} of {len(keys)} ({100 * done // max(1, len(keys))} %)"
              + (f", {len(stale)} no longer in the shell: {stale[:3]}" if stale else "")
              + (f", {len(empty)} empty" if empty else ""))
        bad |= bool(stale)
    return bad

if __name__ == "__main__":
    sys.exit(main())
