#!/usr/bin/env python3
# The settings' defaults are written down in more than one language (the shell's QML, Hyprland's Lua, the greeter, the
# Rust helper that writes greeter.json, the boot splash). This checks every copy against the shell's Config.qml.
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def value(raw):
    raw = raw.strip().rstrip(",")
    if raw in ("true", "false"):
        return raw == "true"
    if re.fullmatch(r'"[^"]*"', raw):
        return raw[1:-1]
    try:
        return float(raw)
    except ValueError:
        return None


def shell():
    """{group: {key: default}} from the JsonAdapter in Config.qml."""
    text = (ROOT / "config/quickshell/config/Config.qml").read_text()
    out, group = {}, None
    for line in text.splitlines():
        m = re.match(r"\s*property JsonObject (\w+): JsonObject \{", line)
        if m:
            group = m.group(1)
            out[group] = {}
            continue
        m = re.match(r"\s*property (?:string|int|real|bool) (\w+): (.+)$", line)
        if group and m and value(m.group(2)) is not None:
            out[group][m.group(1)] = value(m.group(2))
        if re.match(r"\s{12}\}", line):
            group = None
    return out


def lua():
    text = (ROOT / "config/hypr/lib/settings.lua").read_text()
    body = text[text.index("local defaults = {"):]
    body = body[:body.index("\n}\n")]
    out = {}
    for m in re.finditer(r"(\w+)\s*=\s*\{([^{}]*)\}", body):
        out[m.group(1)] = {k: value(v) for k, v in re.findall(r'(\w+)\s*=\s*("[^"]*"|[\w.]+)', m.group(2))}
    return out


def greeter():
    """The greeter's own fallbacks, by the shell's names."""
    text = (ROOT / "config/greeter/config/Config.qml").read_text()
    names = {"font": "fontFamily", "monoFont": "monoFamily", "barHeight": "height"}
    out = {}
    for key, raw in re.findall(r"root\.cfg\.(\w+) (?:\|\||\?\?) (\"[^\"]*\"|[\w.]+)", text):
        out[names.get(key, key)] = value(raw)
    return out


def rust_greeter():
    text = (ROOT / "rust/tools/json/src/main.rs").read_text()
    return {k: value(v) for k, v in re.findall(r'or\(\w, "(\w+)", json!\(("[^"]*"|[\w.]+)\)\)', text)}


def splash():
    text = (ROOT / "system/plymouth/make-theme.sh").read_text()
    m = re.search(r'flavor="\$\{2:-(\w+)\}"; accent="\$\{3:-(\w+)\}"', text)
    return {"flavor": m.group(1), "accent": m.group(2)} if m else {}


def main():
    s = shell()
    flat = {}
    for group in ("theme", "bar", "accessibility", "apps", "input", "windows"):
        for k, v in s.get(group, {}).items():
            flat.setdefault(k, (group, v))
    bad = []

    def compare(where, have, group=None):
        for k, v in have.items():
            if v is None:
                continue
            want = s.get(group, {}).get(k) if group else flat.get(k, (None, None))[1]
            if want is not None and want != v:
                bad.append(f"{where}: {k} is {v!r}, the shell's is {want!r}")

    for group, keys in lua().items():
        compare("hypr/lib/settings.lua", keys, group)
    compare("greeter/config/Config.qml", greeter())
    compare("rust/tools/json (greeter.json)", rust_greeter())
    compare("plymouth/make-theme.sh", splash(), "theme")
    for b in bad:
        print("   FAIL  " + b)
    print(f"defaults: {'all the same' if not bad else str(len(bad)) + ' differ'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
