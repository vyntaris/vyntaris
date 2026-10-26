#!/usr/bin/env python3
import concurrent.futures
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONS = ROOT / "config/quickshell/components/Icons.js"
OUT = ROOT / "config/quickshell/components/MaterialIcons.js"
CDN = "https://cdn.jsdelivr.net/npm/@material-symbols/svg-400@0.40.2/rounded/{}.svg"

def fetch(name):
    try:
        text = urllib.request.urlopen(CDN.format(name), timeout=30).read().decode()
    except urllib.error.HTTPError:
        return name, None
    return name, re.search(r"<svg[^>]*>(.*)</svg>", text, re.S).group(1).strip()

def main():
    block = re.search(r"var material = \{(.*?)\n\};", ICONS.read_text(), re.S).group(1)
    block = re.sub(r"//[^\n]*", "", block).replace("base:", "").replace("levels:", "")
    names = set(re.findall(r'"([a-z0-9_]+)"', re.sub(r'^\s*"[a-z0-9-]+":', "", block, flags=re.M))) | {"close"}
    wanted = sorted(names | {n + "-fill" for n in names})
    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        found = dict(pool.map(fetch, wanted))
    missing = [n for n in sorted(names) if not found.get(n)]
    if missing:
        sys.exit("not in Material Symbols: " + ", ".join(missing))
    lines = ["// Made by tools/make-icons.py from Google's Material Symbols, Rounded (Apache 2.0): the icons Icons.js names.",
             ".pragma library", "", "var paths = {"]
    lines += [f"    {json.dumps(k)}: {json.dumps(v)}," for k, v in sorted(found.items()) if v]
    lines += ["};", ""]
    OUT.write_text("\n".join(lines))
    print(f"{sum(1 for v in found.values() if v)} icons into {OUT.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
