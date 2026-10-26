#!/usr/bin/env python3
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "config/quickshell/modules/settings"
ISLAND = ROOT / "config/quickshell/modules/island"
PANELS = {"night": "NightView.qml", "game": "GameModeView.qml"}
INDEX = SETTINGS / "SettingsIndex.js"
BEGIN = "var rows = ["
END = "];"

def page_rows():
    rows, problems = {}, []
    for f in sorted((SETTINGS / "pages").glob("*Page.qml")):
        text = f.read_text()
        page = re.search(r'\bpageId:\s*"([^"]+)"', text)
        if not page:
            continue
        titles = []
        for m in re.finditer(r"\bSettingsRow\s*\{", text):
            head = text[m.end():].split("{", 1)[0]
            t = re.search(r'\btitle:\s*(?:Tr\.t\()?("(?:[^"\\]|\\.)*")', head)
            if t:
                titles.append(json.loads(t.group(1)))
            else:
                line = text.count("\n", 0, m.start()) + 1
                problems.append(f"{f.relative_to(ROOT)}:{line}: a SettingsRow without a written-out title")
        rows[page.group(1)] = titles
    for page, view in PANELS.items():
        text = (ISLAND / view).read_text()
        titles = []
        for m in re.finditer(r"\bRow_\s*\{", text):
            head = text[m.end():].split("{", 1)[0]
            t = re.search(r'\btext:\s*(?:Tr\.t\()?("(?:[^"\\]|\\.)*")', head)
            if t:
                titles.append(json.loads(t.group(1)))
            else:
                line = text.count("\n", 0, m.start()) + 1
                problems.append(f"{(ISLAND / view).relative_to(ROOT)}:{line}: a Row_ without a written-out text")
        rows[page] = titles
    return rows, problems

def block(order, rows):
    lines = [BEGIN]
    for page in order:
        for title in rows.get(page, []):
            lines.append(f"    {{ page: {json.dumps(page)}, title: {json.dumps(title, ensure_ascii=False)} }},")
    lines += [END]
    return "\n".join(lines)

def main():
    text = INDEX.read_text()
    order = re.findall(r'\{\s*id:\s*"([^"]+)"', text.split(BEGIN)[0])
    rows, problems = page_rows()
    for page in rows:
        if page not in order:
            problems.append(f"page {page!r} isn't in SettingsIndex.js's pages")
    for page in order:
        if page not in rows:
            problems.append(f"SettingsIndex.js lists page {page!r}, which no pages/*Page.qml has")
    start = text.find(BEGIN)
    end = text.find(END, start) if start >= 0 else -1
    if start < 0 or end < 0:
        problems.append(f"SettingsIndex.js lacks the {BEGIN!r} … {END!r} block")
    for p in problems:
        print(p)
    if problems:
        return 1
    new = text[:start] + block(order, rows) + text[end + len(END):]
    if new == text:
        print(f"settings index: {sum(len(r) for r in rows.values())} settings on {len(order)} pages, up to date")
        return 0
    if "--write" in sys.argv:
        INDEX.write_text(new)
        print("settings index rewritten")
        return 0
    import difflib
    sys.stdout.writelines(difflib.unified_diff(text.splitlines(True), new.splitlines(True), "index", "pages"))
    print("the settings index differs from the pages: run tools/settings-index.py --write")
    return 1

if __name__ == "__main__":
    sys.exit(main())
