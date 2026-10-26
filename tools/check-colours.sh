#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
colours=(mauve teal "#514f6a" "#a07ce8" "#ff0000" "#00ff88" "#123456" "#fedcba" "#808080" "#000000" "#ffffff"
         "#655891" "#e5c890" "#04a5e5")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

js_cases='
for (const flavor of ["mocha", "latte"])
    for (const c of COLOURS) {
        const a = accent(palettes[flavor], c);
        out.push([flavor, c, a, isCustom(c) ? partnerOf(a) : "-"].join(" "));
    }'
list="$(printf '"%s",' "${colours[@]}")"
if command -v node >/dev/null; then
    js="$(node -e '
const src = require("fs").readFileSync("config/quickshell/config/Palettes.js", "utf8").replace(/^\..*$/mg, "");
const out = [], COLOURS = ['"$list"'];
new Function("out", "COLOURS", src + process.argv[1])(out, COLOURS);
console.log(out.join("\n"));' "$js_cases")"
else
    cat > "$tmp/check.qml" <<QML
import QtQuick
import "file://$PWD/config/quickshell/config/Palettes.js" as P
QtObject {
    Component.onCompleted: {
        const out = [], COLOURS = [$list], palettes = P.palettes, accent = P.accent, partnerOf = P.partnerOf, isCustom = P.isCustom;
        $js_cases
        for (const line of out) console.log("JS " + line);
        Qt.quit();
    }
}
QML
    js="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml "$tmp/check.qml" 2>&1 | sed -n 's/^.*JS //p')"
fi

lua="$(cd config/hypr && lua5.4 - "${colours[@]}" <<'LUA'
package.path = "./?.lua;" .. package.path
local palettes, colors = require("lib.palettes"), require("lib.colors")
for _, flavor in ipairs({ "mocha", "latte" }) do
    for _, c in ipairs(arg) do print(flavor .. " " .. c .. " #" .. colors.accent(palettes[flavor], c)) end
end
LUA
)"

py="$(python3 - "${colours[@]}" <<'PY'
import sys
sys.path.insert(0, "system/lib")
import palettes
for flavor in ("mocha", "latte"):
    for c in sys.argv[1:]:
        a, partner = palettes.accent(palettes.palette(flavor), c)
        print(flavor, c, a, partner if palettes.HEX.fullmatch(c) else "-")
PY
)"

rs="$(cd rust && cargo run -q --release -p vyntaris-core --bin vyntaris-colours -- "${colours[@]}")"

bad=0
[ -n "$js" ] || { echo "the JavaScript didn't run"; exit 1; }
[ "$js" = "$py" ] || { echo "JavaScript (<) and Python (>) differ:"; diff <(echo "$js") <(echo "$py") || true; bad=1; }
[ "$js" = "$rs" ] || { echo "JavaScript (<) and Rust (>) differ:"; diff <(echo "$js") <(echo "$rs") || true; bad=1; }
[ "$(cut -d' ' -f1-3 <<<"$js")" = "$lua" ] ||
    { echo "JavaScript (<) and Lua (>) differ:"; diff <(cut -d' ' -f1-3 <<<"$js") <(echo "$lua") || true; bad=1; }
[ "$bad" = 0 ] && echo "accents are fitted alike in JavaScript, Lua, Python and Rust ($(wc -l <<<"$js") cases)"
exit "$bad"
